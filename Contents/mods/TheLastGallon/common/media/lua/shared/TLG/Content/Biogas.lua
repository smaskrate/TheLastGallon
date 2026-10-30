-- Biogas content (spec §10): anaerobic digestion of manure and food waste.
-- Numbers are design values (docs/balance.md); chemistry is abstract.
--
-- Batch digesters run on the shared production framework. The finished gas
-- waits in the digester until TLG.Domain.Gas.collectInto moves it into a
-- bounded gas holder (storage profile gas_holder, which leaks slowly through
-- TLG.Domain.Aging); a full holder leaves the rest in the digester
-- (OutputReady, pause output_full) and nothing is emitted twice.
--
-- Stages: load (labour) -> inoculate (startup delay while the culture
-- establishes; no gas) -> digest. Unheated digester (exposure "outdoor"):
--   below 10 C  stalls (pause too_cold) and resumes when it warms up
--   10-20 C     slow, rate 0.35
--   20-40 C     nominal (mesophilic band; durations are calibrated at the
--               30-40 C optimum, the framework has a single slow band)
--   40-50 C     slow; above 50 C stalls (too_hot)
-- The heated digester keeps the culture at about 35 C with a firebox heat
-- coil (0.4 kW): it runs in any weather while fuelled, pauses no_heat when
-- the firebox is empty, and its digest stage is shorter (300 h vs 360 h).
-- A cold digester never spoils; the batch simply waits.
--
-- Anti-exploit rules (spec: no accidental unlimited high-yield energy):
--   * digestate is a product (role "product") that no recipe accepts, so it
--     cannot be digested again (Process.plan: ineligible_digestate)
--   * manure is required in every batch (min 20 kg): it carries the culture
--     and buffers acidity; a food-waste share above 50 % sours the batch,
--     yield x max(0.3, 1 - 1.2 (share - 0.5))
--   * output per digester is bounded by batch size and minimum cycle time:
--     Biogas.capNm3PerDay() <= MAX_NM3_PER_DIGESTER_DAY (5.5 Nm3/day, about
--     118 MJ or 33 kWh of fuel per day). Respawning or bulk inputs scale only
--     with the number of digesters built, never the yield of one digester.
require "TLG/Domain/Production/Process"
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Domain/Gas"
local R, Process, Tables = TLG.Registry, TLG.Domain.Process, TLG.Tables

TLG.Content = TLG.Content or {}
TLG.Content.Biogas = TLG.Content.Biogas or {}
local Biogas = TLG.Content.Biogas

Biogas.MAX_NM3_PER_DIGESTER_DAY = 5.5
Biogas.RECIPES = { "biogas_digest", "biogas_digest_heated" }

local function rho(id)
    local f = R.need("fuel", id)
    if f.phase == "solid" then return 1 end
    return f.density
end

-- Digestion: manure + food waste (+ dilution water) -> biogas + digestate.
-- Mass balance: digestate = digested feed mass - biogas mass. An aborted
-- batch (frac < 1) returns the undigested share and the digestate in
-- `outputs`, because Process.abort only returns outputs.
Process.converters.digest = function(inputs, p, m, eff, skill, frac)
    frac = frac or 1
    local manure = inputs.manure or 0
    local food = inputs.food_waste or 0
    local water = inputs.water or 0
    local organic = manure + food
    local share = 0
    if organic > 0 then share = food / organic end
    local sour = 1
    if share > p.sourShare then
        sour = math.max(p.sourFloor, 1 - p.sourSlope * (share - p.sourShare))
    end
    local gas = (manure * p.manureYield + food * p.foodWasteYield * sour) * eff * frac
    local digested = (manure + food + water * rho("water")) * frac
    local digestate = digested - gas * rho("biogas")
    local outputs, by = {}, {}
    if gas > 0 then outputs.biogas = gas end
    if digestate > 0 then by.digestate = digestate end
    if frac < 1 then
        local keep = 1 - frac
        if manure > 0 then outputs.manure = manure * keep end
        if food > 0 then outputs.food_waste = food * keep end
        if water > 0 then outputs.water = water * keep end
        if digestate > 0 then outputs.digestate = digestate end
        by = {}
    end
    return { outputs = outputs, byproducts = by,
        props = { sour = sour, foodShare = share, losses = {}, external = {} } }
end

R.define("machine", {
    id = "biogas_digester", kind = "digester", capacity = 900, outputCapacity = 80, thermal = "outdoor",
    wearPerBatch = 0.005, asset = "A10",
})
R.define("machine", {
    id = "biogas_digester_heated", kind = "digester", capacity = 900, outputCapacity = 80, thermal = "outdoor",
    wearPerBatch = 0.008, asset = "A10",
    firebox = { capacityKg = 60, kwhPerKg = 4.2, efficiency = 0.6 },
})

local INPUTS = { manure = { min = 20, max = 900 }, food_waste = { min = 0, max = 300 }, water = { min = 0, max = 400 } }
local PARAMS = { manureYield = 0.05, foodWasteYield = 0.15, sourShare = 0.5, sourSlope = 1.2, sourFloor = 0.3 }

local function band(st)
    st.tempMin, st.slowBelow, st.slowAbove, st.tempMax, st.slowRate = 10, 20, 40, 50, 0.35
    return st
end

R.define("recipe", {
    id = "biogas_digest", version = 1, machines = { "biogas_digester" }, converter = "digest",
    inputs = Tables.deepCopy(INPUTS),
    stages = {
        { id = "load", hours = 1, labor = true },
        band({ id = "inoculate", hours = 48 }),
        band({ id = "digest", hours = 360 }),
    },
    params = Tables.deepCopy(PARAMS),
})
R.define("recipe", {
    id = "biogas_digest_heated", version = 1, machines = { "biogas_digester_heated" }, converter = "digest",
    inputs = Tables.deepCopy(INPUTS),
    stages = {
        { id = "load", hours = 1, labor = true },
        { id = "inoculate", hours = 48, heatKW = 0.4, tempMin = -25 },
        { id = "digest", hours = 300, heatKW = 0.4, tempMin = -25 },
    },
    params = Tables.deepCopy(PARAMS),
})

-- Largest biogas output per digester-day the content allows: the best batch
-- over each recipe's input bounds (10 kg grid, full condition, best skill)
-- divided by its shortest cycle (every stage at rate 1; labour stages at
-- skill 10, which Process shortens by 25 %).
function Biogas.capNm3PerDay()
    local best = 0
    for _, rid in ipairs(Biogas.RECIPES) do
        local def = R.need("recipe", rid)
        local m = R.need("machine", def.machines[1])
        local hours = 0
        for _, st in ipairs(def.stages) do
            local h = st.hours
            if st.labor then h = h * (1 - 0.025 * 10) end
            hours = hours + h
        end
        local conv = Process.converters[def.converter]
        local bm, bf = def.inputs.manure, def.inputs.food_waste
        local mostGas = 0
        local manure = bm.min
        while manure <= bm.max + 1e-9 do
            local food = bf.min
            while food <= bf.max + 1e-9 and manure + food <= m.capacity + 1e-9 do
                local out = conv({ manure = manure, food_waste = food }, def.params, m, 1, 10)
                if (out.outputs.biogas or 0) > mostGas then mostGas = out.outputs.biogas end
                food = food + 10
            end
            manure = manure + 10
        end
        local rate = mostGas / hours * 24
        if rate > best then best = rate end
    end
    return best
end

return Biogas
