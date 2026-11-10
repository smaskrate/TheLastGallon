-- Biodiesel content (spec §10): oils and fats -> biodiesel for the explicit
-- diesel consumer profiles. Chemistry is abstract and game-facing; numbers
-- are design values (docs/balance.md). Every processing input has a
-- renewable route, so the chain does not depend on a finite reagent:
--   oilseed --press--> plant_oil + press cake               oil_press
--   firewood --dry distillation--> methanol + charcoal, tar, liquor
--                                                          wood_retort (fire)
--   firewood --burn--> wood_ash                             ash_pit
--   wood_ash + water --leach, boil down--> lye + spent ash  lye_leacher (fire)
--   plant_oil + methanol + lye --react, settle--> crude + glycerin
--                                                          biodiesel_reactor (fire)
--   crude + wash water --wash, settle, dry--> biodiesel     biodiesel_wash_tank (fire)
-- Scavenged cooking oil (TLG.Feedstocks `oil`) is a finite shortcut into the
-- reactor; gasifier ash (TLG/Content/WoodGas) is another source of wood_ash.
--
-- Mass balance, checked for every converter by the tests:
--   inputs + props.external = outputs + byproducts + props.losses    (kg)
-- litres and Nm3 converted through FuelDefinition.density; props.losses and
-- props.external are kg. Batch quality travels as components the consumer
-- model already understands: unreacted plant_oil and leftover methanol are
-- foreign fuel, soap/catalyst residue is carried as `sediment`, water as
-- `water`; props.quality reports the fractions and a grade.
-- Seasonal behaviour: settling slows below 10 C and stalls below 0 C
-- (workshop exposure "sheltered"); biodiesel itself gels below its
-- coldLimitC in consumers that lack a fuel heater.
-- Aborted batches (frac < 1) return every material in `outputs`, because
-- Process.abort only returns outputs.
require "TLG/Domain/Production/Process"
require "TLG/Content/Fuels"
require "TLG/Content/WoodGas"
local R, Process, Tables = TLG.Registry, TLG.Domain.Process, TLG.Tables

R.define("fuel", { id = "press_cake", phase = "solid", role = "product" })
R.define("fuel", { id = "spent_ash", phase = "solid", role = "product" })

local function rho(id)
    local f = R.need("fuel", id)
    if f.phase == "solid" then return 1 end
    return f.density
end

local function fold(outputs, by)
    for _, id in ipairs(Tables.sortedKeys(by)) do outputs[id] = (outputs[id] or 0) + by[id] end
    return outputs
end

local function put(t, id, q)
    if q > 0 then t[id] = (t[id] or 0) + q end
end

------------------------------------------------------------------------------
-- Converters
------------------------------------------------------------------------------

-- Oil press: oilseed -> plant_oil (L) + press cake; residue stuck in the press
-- is an explicit loss.
Process.converters.press_oil = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local seed = inputs.oilseed or 0
    local pressed = seed * frac
    local oilFrac = math.min(p.maxOilKgPerKg, p.oilKgPerKg + p.skillOilKgPerKg * (skill or 0)) * eff
    local oilKg = pressed * oilFrac
    local residue = pressed * p.residueKgPerKg
    local outputs, by = {}, {}
    put(outputs, "plant_oil", oilKg / rho("plant_oil"))
    put(by, "press_cake", pressed - oilKg - residue)
    if frac < 1 then
        put(outputs, "oilseed", seed - pressed)
        outputs, by = fold(outputs, by), {}
    end
    return { outputs = outputs, byproducts = by,
        props = { losses = { press_residue = residue }, external = {}, oilKgPerKg = oilFrac } }
end

-- Wood retort (dry distillation): firewood -> methanol (L) + charcoal + tar +
-- liquor water; non-condensable gas is burned under the retort (loss).
Process.converters.wood_distill = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local wood = inputs.firewood or 0
    local done = wood * frac
    local methanolKg = done * p.methanolKgPerKg * (1 + p.skillMethanol * (skill or 0)) * eff
    local charcoal = done * p.charcoalKgPerKg
    local tar = done * p.tarKgPerKg
    local liquor = done * p.liquorKgPerKg
    local outputs, by = {}, {}
    put(outputs, "methanol", methanolKg / rho("methanol"))
    put(by, "charcoal", charcoal)
    put(by, "wood_tar", tar)
    put(by, "water", liquor / rho("water"))
    if frac < 1 then
        put(outputs, "firewood", wood - done)
        outputs, by = fold(outputs, by), {}
    end
    return { outputs = outputs, byproducts = by,
        props = { losses = { offgas = done - methanolKg - charcoal - tar - liquor }, external = {} } }
end

-- Ash pit: firewood -> wood_ash; everything else leaves as flue gas.
Process.converters.burn_to_ash = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local wood = inputs.firewood or 0
    local burned = wood * frac
    local ash = burned * p.ashKgPerKg
    local outputs = {}
    put(outputs, "wood_ash", ash)
    if frac < 1 then put(outputs, "firewood", wood - burned) end
    return { outputs = outputs, byproducts = {}, props = { losses = { flue = burned - ash }, external = {} } }
end

-- Lye leacher: wood_ash + water -> lye (kg) + spent ash; the water is boiled
-- off (loss). Less than waterPerKgAsh litres per kg leaches incompletely.
Process.converters.leach_lye = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local ash = inputs.wood_ash or 0
    local water = inputs.water or 0
    local extraction = 0
    if ash > 0 then extraction = math.min(1, water / (ash * p.waterPerKgAsh)) end
    local done = ash * frac
    local lye = done * p.lyeKgPerKgAsh * extraction * eff
    local outputs, by = {}, {}
    put(outputs, "lye", lye)
    put(by, "spent_ash", done - lye)
    if frac < 1 then
        put(outputs, "wood_ash", ash - done)
        put(outputs, "water", water * (1 - frac))
        outputs, by = fold(outputs, by), {}
    end
    return { outputs = outputs, byproducts = by,
        props = { losses = { evaporated = water * frac * rho("water") }, external = {}, extraction = extraction } }
end

-- Transesterification: plant_oil + methanol + lye -> crude biodiesel +
-- glycerin. Full conversion needs methanolPerOil L and lyePerOil kg per litre
-- of oil; less of either limits conversion (unreacted oil stays in the
-- crude). Water and excess lye turn oil into soap. Glycerin is derived from
-- the mass balance of the reacting oil and methanol. Excess methanol stays in
-- the crude; a little evaporates while heating (loss). The crude is not a
-- finished fuel: its methanol and unreacted oil exceed consumer foreignMax.
Process.converters.transesterify = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local oil = inputs.plant_oil or 0
    local meth = inputs.methanol or 0
    local lye = inputs.lye or 0
    local water = inputs.water or 0
    local ratioM, ratioK = 0, 0
    if oil > 0 then
        ratioM = meth / (oil * p.methanolPerOil)
        ratioK = lye / (oil * p.lyePerOil)
    end
    local base = math.min(p.maxConversion, p.baseConversion + p.skillConversion * (skill or 0))
    local conv = math.min(1, ratioM, ratioK) * math.max(0, base - p.conditionLoss * (1 - eff))
    local soap = 0
    if oil > 0 then
        soap = p.soapBase + p.soapPerWater * (water / oil) + p.soapPerExcessLye * math.max(0, ratioK - 1)
        soap = math.min(p.maxSoap, soap)
    end
    if conv + soap > 1 then conv = 1 - soap end
    local oilConv = oil * conv * frac
    local oilSoap = oil * soap * frac
    local oilLeft = oil - oilConv - oilSoap
    local methReact = oilConv * p.methanolReactPerOil
    local vapour = math.max(0, meth * frac - methReact) * p.methanolVapour
    local methLeft = meth - methReact - vapour
    local lyeUsed = lye * frac
    local bio = oilConv * p.biodieselPerOil
    local glyKg = oilConv * rho("plant_oil") + methReact * rho("methanol") - bio * rho("biodiesel")
    local soapKg = oilSoap * rho("plant_oil") + lyeUsed
    local outputs, by = {}, {}
    put(outputs, "biodiesel", bio)
    put(outputs, "methanol", methLeft)
    put(outputs, "plant_oil", oilLeft)
    put(outputs, "sediment", soapKg / rho("sediment"))
    put(outputs, "water", water)
    put(by, "glycerin", glyKg / rho("glycerin"))
    local total = 0
    for _, id in ipairs(Tables.sortedKeys(outputs)) do total = total + outputs[id] end
    local function share(id) if total > 0 then return (outputs[id] or 0) / total end return 0 end
    local quality = { grade = "crude", conversion = conv, soap = share("sediment"), methanol = share("methanol"),
        oil = share("plant_oil"), water = share("water") }
    if frac < 1 then
        put(outputs, "lye", lye - lyeUsed)
        outputs, by = fold(outputs, by), {}
    end
    return { outputs = outputs, byproducts = by,
        props = { deg = { biodiesel = 0 }, quality = quality, external = {},
            losses = { methanol_vapour = vapour * rho("methanol") } } }
end

-- Washing and drying: wash water carries soap and methanol out of the crude
-- (wash effluent as byproduct components); the settled fuel holds wetCarry
-- L water per L, which the heated drying stage takes down to dryCarry (the
-- difference is an explicit loss). Less wash water than washWaterPerL per
-- litre removes proportionally less. Unreacted oil cannot be washed out.
-- An aborted wash returns the mix unchanged (washing is reversible mixing).
Process.converters.wash_biodiesel = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    if frac < 1 then
        return { outputs = Tables.copy(inputs), byproducts = {}, props = { losses = {}, external = {} } }
    end
    local bio = inputs.biodiesel or 0
    local oil = inputs.plant_oil or 0
    local meth = inputs.methanol or 0
    local sed = inputs.sediment or 0
    local water = inputs.water or 0
    local need = bio * p.washWaterPerL
    local suff = 1
    if need > 0 then suff = math.min(1, water / need) end
    local soapEff = math.min(p.maxSoapRemoval, p.soapRemoval + p.skillSoapRemoval * (skill or 0))
    local soapOut = sed * soapEff * suff * eff
    local methOut = meth * p.methanolRemoval * suff * eff
    local wet = math.min(water, bio * p.wetCarry)
    local final = math.min(wet, bio * p.dryCarry)
    local outputs, by = {}, {}
    put(outputs, "biodiesel", bio)
    put(outputs, "plant_oil", oil)
    put(outputs, "methanol", meth - methOut)
    put(outputs, "sediment", sed - soapOut)
    put(outputs, "water", final)
    put(by, "water", water - wet)
    put(by, "methanol", methOut)
    put(by, "sediment", soapOut)
    local total = 0
    for _, id in ipairs(Tables.sortedKeys(outputs)) do total = total + outputs[id] end
    local function share(id) if total > 0 then return (outputs[id] or 0) / total end return 0 end
    local q = { soap = share("sediment"), methanol = share("methanol"), oil = share("plant_oil"),
        water = share("water"), washed = suff }
    local foreign = q.methanol + q.oil
    if q.soap <= p.goodSoap and foreign <= p.goodForeign and q.water <= p.goodWater then
        q.grade = "good"
    elseif q.soap <= p.fairSoap and foreign <= p.fairForeign and q.water <= p.fairWater then
        q.grade = "fair"
    else
        q.grade = "poor"
    end
    return { outputs = outputs, byproducts = by,
        props = { deg = { biodiesel = 0 }, quality = q, external = {},
            losses = { dried_off = (wet - final) * rho("water") } } }
end

------------------------------------------------------------------------------
-- Machines (asset ids refer to the asset table in the implementation plan)
------------------------------------------------------------------------------
R.define("machine", {
    id = "oil_press", kind = "press", capacity = 40, outputCapacity = 20, thermal = "sheltered",
    throughputKgph = 8, wearPerBatch = 0.01, asset = "A05",
})
R.define("machine", {
    id = "wood_retort", kind = "retort", capacity = 100, outputCapacity = 10, thermal = "sheltered",
    throughputKgph = 10, wearPerBatch = 0.02, asset = "A03",
    firebox = { capacityKg = 40, kwhPerKg = 4.2, efficiency = 0.5 },
})
R.define("machine", {
    id = "ash_pit", kind = "fire_pit", capacity = 100, outputCapacity = 5, thermal = "outdoor",
    burnKgph = 20, wearPerBatch = 0.002,
})
R.define("machine", {
    id = "lye_leacher", kind = "leacher", capacity = 160, outputCapacity = 10, thermal = "sheltered",
    wearPerBatch = 0.005, asset = "A06",
    firebox = { capacityKg = 20, kwhPerKg = 4.2, efficiency = 0.4 },
})
R.define("machine", {
    id = "biodiesel_reactor", kind = "reactor", capacity = 130, outputCapacity = 130, thermal = "sheltered",
    wearPerBatch = 0.02, asset = "A06",
    firebox = { capacityKg = 20, kwhPerKg = 4.2, efficiency = 0.5 },
})
R.define("machine", {
    id = "biodiesel_wash_tank", kind = "settler", capacity = 240, outputCapacity = 130, thermal = "sheltered",
    wearPerBatch = 0.01, asset = "A06",
    firebox = { capacityKg = 10, kwhPerKg = 4.2, efficiency = 0.5 },
})

------------------------------------------------------------------------------
-- Recipes. `makes` marks the stages that make the result (Process.abort):
-- pressing, carbonizing, burning, leaching and boiling down, reacting. The
-- reactor's mixing and settling make nothing more. Every stage of the wash
-- is marked: its converter gives the mix back unchanged until all are done.
------------------------------------------------------------------------------
local SETTLE = { tempMin = 0, slowBelow = 10, slowRate = 0.5 }
local function settle(st)
    for _, k in ipairs(Tables.sortedKeys(SETTLE)) do st[k] = SETTLE[k] end
    return st
end

R.define("recipe", {
    id = "press_oilseed", version = 1, machines = { "oil_press" }, converter = "press_oil",
    inputs = { oilseed = { min = 2, max = 40 } },
    stages = { { id = "press", hoursFrom = "throughputKgph", minHours = 0.5, labor = true, makes = true } },
    params = { oilKgPerKg = 0.30, skillOilKgPerKg = 0.003, maxOilKgPerKg = 0.33, residueKgPerKg = 0.01 },
})
R.define("recipe", {
    id = "methanol_wood_distill", version = 1, machines = { "wood_retort" }, converter = "wood_distill",
    inputs = { firewood = { min = 10, max = 100 } },
    stages = {
        { id = "heat_up", hours = 1.5, heatKW = 8 },
        { id = "carbonize", hoursFrom = "throughputKgph", minHours = 2, heatKW = 4, makes = true },
        { id = "cool_down", hours = 6 },
    },
    params = { methanolKgPerKg = 0.04, skillMethanol = 0.02, charcoalKgPerKg = 0.28, tarKgPerKg = 0.07,
        liquorKgPerKg = 0.32 },
})
R.define("recipe", {
    id = "ash_burn", version = 1, machines = { "ash_pit" }, converter = "burn_to_ash",
    inputs = { firewood = { min = 5, max = 100 } },
    stages = {
        { id = "burn", hoursFrom = "burnKgph", minHours = 1, makes = true },
        { id = "cool", hours = 12 },
    },
    params = { ashKgPerKg = 0.015 },
})
R.define("recipe", {
    id = "lye_leach", version = 1, machines = { "lye_leacher" }, converter = "leach_lye",
    inputs = { wood_ash = { min = 1, max = 40 }, water = { min = 2, max = 120 } },
    stages = {
        { id = "leach", hours = 24, makes = true },
        { id = "boil_down", hours = 4, heatKW = 3, makes = true },
    },
    params = { lyeKgPerKgAsh = 0.15, waterPerKgAsh = 2.0 },
})
R.define("recipe", {
    id = "biodiesel_react", version = 1, machines = { "biodiesel_reactor" }, converter = "transesterify",
    inputs = {
        plant_oil = { min = 5, max = 100 }, methanol = { min = 0.5, max = 25 },
        lye = { min = 0.05, max = 2 }, water = { min = 0, max = 5 },
    },
    stages = {
        { id = "mix", hours = 0.5, labor = true },
        { id = "react", hours = 2, heatKW = 3, makes = true },
        settle({ id = "settle", hours = 8 }),
    },
    params = {
        methanolPerOil = 0.15, methanolReactPerOil = 0.11, lyePerOil = 0.0125, biodieselPerOil = 1.0,
        baseConversion = 0.985, skillConversion = 0.001, maxConversion = 0.995, conditionLoss = 0.2,
        soapBase = 0.004, soapPerWater = 1.5, soapPerExcessLye = 0.02, maxSoap = 0.5, methanolVapour = 0.05,
    },
})
R.define("recipe", {
    id = "biodiesel_wash", version = 1, machines = { "biodiesel_wash_tank" }, converter = "wash_biodiesel",
    inputs = {
        biodiesel = { min = 5, max = 100 }, methanol = { min = 0, max = 25 }, plant_oil = { min = 0, max = 50 },
        sediment = { min = 0, max = 10 }, water = { min = 2, max = 120 },
    },
    stages = {
        { id = "wash", hours = 1, labor = true, makes = true },
        settle({ id = "settle", hours = 24, makes = true }),
        { id = "dry", hours = 3, heatKW = 1.5, makes = true },
    },
    params = {
        washWaterPerL = 0.3, soapRemoval = 0.92, skillSoapRemoval = 0.005, maxSoapRemoval = 0.98,
        methanolRemoval = 0.97, wetCarry = 0.004, dryCarry = 0.0005,
        goodSoap = 0.001, goodForeign = 0.015, goodWater = 0.001,
        fairSoap = 0.002, fairForeign = 0.025, fairWater = 0.0015,
    },
})

return true
