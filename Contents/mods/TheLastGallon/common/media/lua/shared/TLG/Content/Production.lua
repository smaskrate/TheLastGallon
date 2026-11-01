-- Machines, recipes and converters for production chains (docs/balance.md).
-- Chemistry is abstract and game-facing; numbers are design values.
require "TLG/Domain/Production/Process"
require "TLG/Content/Fuels"
local R, Process = TLG.Registry, TLG.Domain.Process

------------------------------------------------------------------------------
-- Converters (versioned with the recipes that use them)
------------------------------------------------------------------------------

-- Fermentation: sugar equivalent + water -> wash (water + dissolved ethanol).
-- frac < 1 is used for aborted batches (partial conversion).
Process.converters.ferment = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local sugar = inputs.sugar_eq or 0
    local water = inputs.water or 0
    local consistency = 1 + 0.01 * (skill or 0)
    local ethanol = sugar * p.ethanolYieldLPerKg * eff * consistency * frac
    local outputs = { water = water }
    if ethanol > 0 then outputs.ethanol = ethanol end
    local leftover = sugar * (1 - frac)
    if leftover > 1e-9 then outputs.sugar_eq = leftover end
    local by = {}
    if sugar >= p.starterMinSugarKg and frac >= 1 then by.yeast_starter = 1 end
    return { outputs = outputs, byproducts = by, props = { deg = { ethanol = 0 } } }
end

-- Distillation: wash -> hydrous ethanol (purity by still and skill) + stillage.
Process.converters.distill = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    -- Only the processed fraction is distilled; an aborted batch returns the
    -- untouched remainder of the wash with the distillate (conservation).
    local eth = (inputs.ethanol or 0) * frac
    local water = (inputs.water or 0) * frac
    local sugar = (inputs.sugar_eq or 0) * frac
    local recovered = eth * m.recovery * eff
    local purity = math.min(p.maxPurity, m.purity + 0.004 * (skill or 0))
    local waterOut = math.min(water, recovered * (1 - purity) / purity)
    local outputs = {}
    if recovered > 0 then outputs.ethanol = recovered end
    if waterOut > 0 then outputs.water = waterOut end
    if frac < 1 then
        local restEth = (inputs.ethanol or 0) - eth
        local restWater = (inputs.water or 0) - water
        local restSugar = (inputs.sugar_eq or 0) - sugar
        if restEth > 0 then outputs.ethanol = (outputs.ethanol or 0) + restEth end
        if restWater > 0 then outputs.water = (outputs.water or 0) + restWater end
        if restSugar > 0 then outputs.sugar_eq = restSugar end
    end
    local stillage = (eth - recovered) + (water - waterOut) + sugar
    -- rest: the part of `outputs` that is undistilled wash (an aborted batch
    -- keeps only the spirit, Process.abort).
    local rest = nil
    if frac < 1 then
        rest = { ethanol = (inputs.ethanol or 0) - eth, water = (inputs.water or 0) - water,
            sugar_eq = (inputs.sugar_eq or 0) - sugar }
    end
    return { outputs = outputs, byproducts = { stillage = stillage }, props = { deg = { ethanol = 0 } }, rest = rest }
end

-- Drying with quicklime: removes water from hydrous ethanol.
Process.converters.dry = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local eth = inputs.ethanol or 0
    local water = inputs.water or 0
    local capacity = (inputs.quicklime_kg or 0) * p.waterPerKgLime
    local removed = math.min(water - eth * p.targetWater, capacity) * frac
    removed = math.max(0, removed)
    local outputs = { ethanol = eth }
    if water - removed > 1e-9 then outputs.water = water - removed end
    return { outputs = outputs, byproducts = { spent_lime = (inputs.quicklime_kg or 0) + removed }, props = { deg = { ethanol = 0 } } }
end

------------------------------------------------------------------------------
-- Machines (asset ids refer to docs/asset-audit.csv)
------------------------------------------------------------------------------
R.define("machine", {
    id = "fermenter_barrel", kind = "fermenter", capacity = 160, outputCapacity = 160, thermal = "sheltered",
    wearPerBatch = 0.01, asset = "A04",
})
R.define("machine", {
    id = "pot_still", kind = "still", capacity = 60, outputCapacity = 20, thermal = "sheltered",
    throughputLph = 8, recovery = 0.88, purity = 0.80, wearPerBatch = 0.02, asset = "A03",
    firebox = { capacityKg = 30, kwhPerKg = 4.2, efficiency = 0.45 },
})
R.define("machine", {
    id = "reflux_still", kind = "still", capacity = 120, outputCapacity = 40, thermal = "sheltered",
    throughputLph = 12, recovery = 0.92, purity = 0.94, wearPerBatch = 0.015, asset = "A03",
    firebox = { capacityKg = 50, kwhPerKg = 4.2, efficiency = 0.55 },
})
R.define("machine", {
    id = "drying_column", kind = "dryer", capacity = 40, outputCapacity = 40, thermal = "sheltered",
    wearPerBatch = 0.005, asset = "A03",
})

------------------------------------------------------------------------------
-- Recipes. `makes` marks the stages that make the result: an aborted batch
-- keeps the share of those done (Process.abort), so preparing and heating up
-- make nothing.
------------------------------------------------------------------------------
R.define("recipe", {
    id = "ethanol_ferment", version = 1, machines = { "fermenter_barrel" }, converter = "ferment",
    inputs = { sugar_eq = { min = 2, max = 30 }, water = { min = 8, max = 130 } },
    consumables = { yeast = 1 },
    stages = {
        { id = "prepare", hours = 1, labor = true },
        { id = "ferment", hours = 96, tempMin = 8, tempMax = 38, slowBelow = 18, slowAbove = 32, slowRate = 0.4,
            maxPauseHours = 72, makes = true },
    },
    params = { ethanolYieldLPerKg = 0.55, starterMinSugarKg = 5 },
})
R.define("recipe", {
    id = "ethanol_distill", version = 1, machines = { "pot_still", "reflux_still" }, converter = "distill",
    inputs = { ethanol = { min = 0, max = 30 }, water = { min = 1, max = 120 }, sugar_eq = { min = 0, max = 30 } },
    stages = {
        { id = "heat_up", hours = 1, heatKW = 6 },
        { id = "distill", hoursFrom = "throughputLph", minHours = 1, heatKW = 6, makes = true },
    },
    params = { maxPurity = 0.96 },
})
R.define("recipe", {
    id = "ethanol_dry", version = 1, machines = { "drying_column" }, converter = "dry",
    inputs = { ethanol = { min = 1, max = 40 }, water = { min = 0, max = 10 }, quicklime_kg = { min = 0.2, max = 10 } },
    stages = { { id = "dry", hours = 12, makes = true } },
    params = { waterPerKgLime = 0.3, targetWater = 0.005 },
})

R.define("fuel", { id = "quicklime_kg", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "yeast_starter", phase = "solid", role = "product" })
R.define("fuel", { id = "spent_lime", phase = "solid", role = "product" })

return true

