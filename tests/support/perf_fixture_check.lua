-- Offline check of the performance mode's biodiesel fixture loads
-- (SPHarness.lua, RT.PF.bio): the amounts RT.PF.bio.amounts works out,
-- loaded and started by the domain and brought 3 hours on, as the harness
-- loads them in game. Run it after a change to the biodiesel recipes:
--   tools/run-tests.ps1 -Entry tests/support/perf_fixture_check.lua
-- The function below must stay the same text as the harness's. Not part of
-- the suite.
loadstring(__TLG_SOURCES["support/prelude"], "support/prelude")()
loadstring(__TLG_SOURCES["support/testlib"], "support/testlib")()
require "support/fixtures"
require "TLG/Content/Biodiesel"
local P, Reg, Tables = TLG.Domain.Process, TLG.Registry, TLG.Tables

RT = { PF = { bio = { loadLogs = 11, oilL = 18,
    machines = { "wood_retort", "ash_pit", "lye_leacher", "biodiesel_reactor", "biodiesel_wash_tank" },
    recipes = { "methanol_wood_distill", "ash_burn", "lye_leach", "biodiesel_react", "biodiesel_wash" },
    feedLogs = { 3, 0, 1, 1, 1 } } } }

-- Same text as RT.PF.bio.amounts in SPHarness.lua.
function RT.PF.bio.amounts()
    local P, Reg = TLG.Domain.Process, TLG.Registry
    local wood = 9 * RT.PF.bio.loadLogs
    local burnt = P.plan("ash_burn", { firewood = wood }, P.new({ machine = "ash_pit" }))
    if not burnt.ok then return nil, "ash_burn " .. tostring(burnt.reason) end
    local leach = Reg.need("recipe", "lye_leach")
    local perKg = leach.params.waterPerKgAsh
    local ashKg = math.min(leach.inputs.wood_ash.max, burnt.expected.outputs.wood_ash, leach.inputs.water.max / perKg)
    local react = Reg.need("recipe", "biodiesel_react").params
    local oil = RT.PF.bio.oilL
    local reactIn = { plant_oil = oil, methanol = oil * react.methanolPerOil, lye = oil * react.lyePerOil }
    local reacted = P.plan("biodiesel_react", reactIn, P.new({ machine = "biodiesel_reactor" }))
    if not reacted.ok then return nil, "biodiesel_react " .. tostring(reacted.reason) end
    local wash = Reg.need("recipe", "biodiesel_wash")
    local washIn = TLG.Tables.copy(reacted.expected.outputs)
    local carried = washIn.water or 0
    washIn.water = carried + math.min((washIn.biodiesel or 0) * wash.params.washWaterPerL,
        math.max(0, wash.inputs.water.max - carried))
    return { { firewood = wood }, { firewood = wood }, { wood_ash = ashKg, water = ashKg * perKg }, reactIn, washIn }
end

local function brief(t)
    local parts = {}
    for _, k in ipairs(Tables.sortedKeys(t or {})) do parts[#parts + 1] = string.format("%s=%.4f", k, t[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local amounts, why = RT.PF.bio.amounts()
local bad = 0
if amounts == nil then
    print("AMOUNTS FAILED " .. tostring(why))
    bad = 1
else
    local env = F.env()
    for k = 1, 5 do
        local bio = RT.PF.bio
        local rec = P.new({ id = "P" .. k, machine = bio.machines[k], t = 0 })
        if bio.feedLogs[k] > 0 then
            local fed = P.addFirebox(rec, 9 * bio.feedLogs[k])
            if fed.ok then rec = fed.proc else print("FEED " .. bio.machines[k] .. " " .. tostring(fed.reason)) end
        end
        local loaded = P.load(rec, bio.recipes[k], amounts[k], 3)
        local started = loaded.ok and P.start(loaded.proc, 0) or loaded
        local line = string.format("%-20s inputs %s -> load %s", bio.machines[k], brief(amounts[k]),
            tostring(loaded.ok and "ok" or loaded.reason))
        if started.ok then
            local later = P.advance(started.proc, 3, env)
            line = line .. string.format("; started; 3 h on: state=%s pause=%s stage=%d firebox=%.2f; expected %s",
                tostring(later.state), tostring(later.pause), later.stage, later.firebox, brief(loaded.expected.outputs))
            if later.state ~= "Processing" and later.state ~= "Paused" then bad = bad + 1 end
        else
            bad = bad + 1
            line = line .. "; start " .. tostring(started.reason)
        end
        print(line)
    end
end
print(string.format("fixture loads: %d problems", bad))
if bad > 0 then __TLG_EXIT_CODE = 1 end
