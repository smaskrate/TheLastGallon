-- Wood gas content (spec §10). A gasifier turns prepared, dry solid wood fuel
-- into an operating stream of producer gas (woodgas, Nm3). The gas is never a
-- liquid and is never stored: it fills a small buffer inside the gasifier and
-- the engine draws from it. TLG.Domain.Gas.Gasifier runs the hopper, warm-up,
-- buffer, filter loading and service; stationary and vehicle gasifiers are
-- machine variants of one recipe and one converter. Numbers are design
-- values (docs/balance.md); chemistry is abstract.
--
-- The recipe exists for load validation (eligible feed, per-load bounds,
-- hopper capacity through Process.plan), for previews (Process.plan's
-- expected gas for a load) and to version the converter. It is marked
-- `stream = true`: running it as a Process batch would bypass the buffer
-- (see the shared-module notes in the report).
require "TLG/Domain/Production/Process"
require "TLG/Content/Fuels"
require "TLG/Domain/Gas"
local R, Process, Tables = TLG.Registry, TLG.Domain.Process, TLG.Tables

-- Tar from gasifier filters and wood distillation (kg).
R.define("fuel", { id = "wood_tar", phase = "solid", role = "product" })

local function rho(id)
    local f = R.need("fuel", id)
    if f.phase == "solid" then return 1 end
    return f.density
end

-- Gasification of a feed table in kg (`water` = extra moisture of wet feed;
-- "firewood" itself is seasoned wood). Per kg of solid feed (params.feeds):
--   tar  = tarKgPerKg x tarMult           -> byproducts.wood_tar (filter)
--   ash  = ashKgPerKg                     -> byproducts.wood_ash (grate)
--   gas  = gasNm3PerKg x yieldMult        -> outputs.woodgas (Nm3)
--   the gasified rest (feed - tar - ash) enters the gas in proportion to
--   yieldMult; the remainder burns to drive off moisture (losses.combusted)
--   air drawn into the gas = gas mass - gasified feed in it
--   (props.external.air): producer gas is mostly air nitrogen
--   moisture leaves as condensate         -> byproducts.water
-- Wet feed, w = water / (solids + water) above wetFree:
--   yieldMult = eff x max(0, 1 - wetPenalty (w - wetFree))
--   tarMult   = 1 + wetTar (w - wetFree)   (wet feed loads the filter faster)
-- props.filterLoad = filter kg-equivalents = sum(feed x filterLoad x tarMult).
-- The converter is linear in its inputs at fixed composition, which lets the
-- gasifier runtime apply it to any slice of the hopper.
Process.converters.gasify = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local feedIds = Tables.sortedKeys(p.feeds)
    local solids, water = 0, inputs.water or 0
    for _, id in ipairs(feedIds) do solids = solids + (inputs[id] or 0) end
    local total = solids + water
    local w = 0
    if total > 0 then w = water / total end
    local wet = math.max(0, w - p.wetFree)
    local yieldMult = math.max(0, 1 - p.wetPenalty * wet) * eff
    local tarMult = 1 + p.wetTar * wet
    local gas, tar, ash, inGas, combusted, load = 0, 0, 0, 0, 0, 0
    for _, id in ipairs(feedIds) do
        local s = (inputs[id] or 0) * frac
        if s > 0 then
            local f = p.feeds[id]
            local t = s * f.tarKgPerKg * tarMult
            local a = s * f.ashKgPerKg
            local gasified = s - t - a
            gas = gas + s * f.gasNm3PerKg * yieldMult
            inGas = inGas + gasified * yieldMult
            combusted = combusted + gasified * (1 - yieldMult)
            tar, ash = tar + t, ash + a
            load = load + s * f.filterLoad * tarMult
        end
    end
    local condensate = water * frac
    local outputs, by = {}, {}
    if gas > 0 then outputs.woodgas = gas end
    if tar > 0 then by.wood_tar = tar end
    if ash > 0 then by.wood_ash = ash end
    if condensate > 0 then by.water = condensate / rho("water") end
    if frac < 1 then
        for _, id in ipairs(feedIds) do
            local left = (inputs[id] or 0) * (1 - frac)
            if left > 0 then outputs[id] = left end
        end
        local wetLeft = water * (1 - frac)
        for _, id in ipairs(Tables.sortedKeys(by)) do outputs[id] = (outputs[id] or 0) + by[id] end
        if wetLeft > 0 then outputs.water = (outputs.water or 0) + wetLeft end
        by = {}
    end
    return {
        outputs = outputs, byproducts = by,
        props = {
            losses = { combusted = combusted }, external = { air = gas * rho("woodgas") - inGas },
            filterLoad = load, moisture = w, yieldMult = yieldMult,
        },
    }
end

-- Machines. Gasifier fields (validated by TLG.Domain.Gas):
--   gasifier = true  marks the machine for the gasifier runtime and validator
--   capacity         hopper capacity, kg (solids + moisture)
--   feedKgPerHour    hopper consumption at full output
--   warmupHours      lit-to-usable-gas time; feed burns at warmupFeedFrac of
--                    full rate and its gas is flared
--   holdHours        a stopped gasifier stays hot this long, then goes out
--                    (buffer vented, warm-up needed again)
--   bufferNm3        gas held between gasifier and engine (minutes of use)
--   filterKg         filter capacity in kg-equivalents of feed (pause
--                    filter_full until serviced)
--   wearPerFilterCycle  condition lost each time the filter fills
-- `vehicle` holds the conversion costs applied by the vehicle conversion
-- adapter (spec §11): installed mass, cargo volume lost, engine power factor.
R.define("machine", {
    id = "gasifier_stationary", kind = "gasifier", gasifier = true, capacity = 120, thermal = "sheltered", asset = "A08",
    feedKgPerHour = 8, warmupHours = 0.5, warmupFeedFrac = 0.5, holdHours = 3,
    bufferNm3 = 2.0, filterKg = 400, wearPerFilterCycle = 0.01,
})
R.define("machine", {
    id = "gasifier_vehicle", kind = "gasifier", gasifier = true, capacity = 60, thermal = "outdoor", asset = "A09",
    feedKgPerHour = 15, warmupHours = 0.3, warmupFeedFrac = 0.6, holdHours = 1,
    bufferNm3 = 0.5, filterKg = 240, wearPerFilterCycle = 0.015,
    vehicle = { installedMassKg = 180, cargoLoss = 0.35, powerFactor = 0.65 },
})

R.define("recipe", {
    id = "woodgas_gasify", version = 1, machines = { "gasifier_stationary", "gasifier_vehicle" },
    converter = "gasify", stream = true,
    inputs = {
        firewood = { min = 0, max = 120 }, wood_chips_dry = { min = 0, max = 120 },
        charcoal = { min = 0, max = 120 }, water = { min = 0, max = 40 },
    },
    stages = {
        { id = "warm_up", hours = 0.5 },
        { id = "gasify", hoursFrom = "feedKgPerHour", minHours = 0.25 },
    },
    params = {
        feeds = {
            firewood = { gasNm3PerKg = 2.2, tarKgPerKg = 0.012, ashKgPerKg = 0.010, filterLoad = 1.0 },
            wood_chips_dry = { gasNm3PerKg = 2.4, tarKgPerKg = 0.010, ashKgPerKg = 0.012, filterLoad = 0.9 },
            charcoal = { gasNm3PerKg = 4.2, tarKgPerKg = 0.001, ashKgPerKg = 0.030, filterLoad = 0.3 },
        },
        wetFree = 0.05, wetPenalty = 2.5, wetTar = 4.0, wetMax = 0.30,
    },
})

return true
