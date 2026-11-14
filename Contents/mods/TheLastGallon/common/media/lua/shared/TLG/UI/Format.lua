-- Player-facing text for inspection/treatment results. Uses translation keys
-- (Translate/<lang>/IG_UI.json); `tr` defaults to getText so tests can pass
-- a stub. Unknown condition is always shown as unknown, never as bad.
TLG.UI = TLG.UI or {}
TLG.UI.Format = TLG.UI.Format or {}
local Fmt = TLG.UI.Format

local function tr(key, ...)
    if Fmt.translate then return Fmt.translate(key, ...) end
    return getText(key, ...)
end

Fmt.GRADE_KEYS = {
    good = "IGUI_TLG_Grade_Good", weathered = "IGUI_TLG_Grade_Weathered", poor = "IGUI_TLG_Grade_Poor",
    unsuitable = "IGUI_TLG_Grade_Unsuitable", empty = "IGUI_TLG_Grade_Empty",
}
Fmt.REASON_KEYS = {
    aged = "IGUI_TLG_Reason_Aged", degraded = "IGUI_TLG_Reason_Degraded", water = "IGUI_TLG_Reason_Water",
    phase_separated = "IGUI_TLG_Reason_PhaseSeparated", sediment = "IGUI_TLG_Reason_Sediment",
    microbial = "IGUI_TLG_Reason_Microbial", incompatible_fuel = "IGUI_TLG_Reason_Incompatible",
    cold_start = "IGUI_TLG_Reason_ColdStart", gelling = "IGUI_TLG_Reason_Gelling", empty = "IGUI_TLG_Grade_Empty",
}
Fmt.FAILURE_KEYS = {
    needs_sample_kit = "IGUI_TLG_Fail_NeedsKit", needs_stabilizer = "IGUI_TLG_Fail_NeedsStabilizer",
    needs_filter = "IGUI_TLG_Fail_NeedsFilter", no_free_water = "IGUI_TLG_Fail_NoFreeWater",
    already_saturated = "IGUI_TLG_Fail_Saturated", not_sealable = "IGUI_TLG_Fail_NotSealable",
    not_empty = "IGUI_TLG_Fail_NotEmpty", no_access = "IGUI_TLG_Fail_NoAccess", stale = "IGUI_TLG_Fail_Stale",
    incompatible = "IGUI_TLG_Fail_Incompatible",
    -- The gas feed (D-040).
    gas_generator = "IGUI_TLG_Fail_GasGenerator", not_gas_generator = "IGUI_TLG_Fail_NotGasGenerator",
    tank_connected = "IGUI_TLG_Fail_TankConnected", no_tank = "IGUI_TLG_Fail_NoTank",
    no_propane_tank = "IGUI_TLG_Fail_NoPropaneTank", not_drained = "IGUI_TLG_Fail_NotDrained",
    -- Refusals every menu can get. A code without a key here or in the
    -- menu's own list is shown as it is (IGUI_TLG_Fail_Generic): those are
    -- malformed requests, which a menu never sends.
    unknown_target = "IGUI_TLG_Fail_Gone", no_vehicle = "IGUI_TLG_Fail_Gone", no_generator = "IGUI_TLG_Fail_Gone",
    no_engine = "IGUI_TLG_Fail_NoEngine", empty = "IGUI_TLG_Fail_Empty",
    source_not_fuel = "IGUI_TLG_Fail_NotFuel", destination_not_fuel = "IGUI_TLG_Fail_NotFuel",
    commit_failed = "IGUI_TLG_Fail_CommitFailed", future_schema = "IGUI_TLG_Fail_FutureSchema",
}

local function pct(x) return string.format("%.1f%%", (x or 0) * 100) end

function Fmt.componentName(id)
    return tr("IGUI_TLG_Fuel_" .. id)
end

-- "12.30 L": an amount of a material in its unit (docs/contracts.md:
-- liquids in litres, solids in kilograms, gases in cubic metres), from the
-- material's phase in the registry. A material the registry does not know
-- and the yeast starter, which is counted, get the bare number. Always two
-- decimals: with an optional third parameter for the places, the call
-- without it inside a concatenation (Fmt.amounts below) raised "invalid
-- option to 'format'" on the game's Lua VM, where the same call on its own
-- did not (tools/run-tests.ps1, 2026-11-14).
local AMOUNT_KEYS = { liquid = "IGUI_TLG_Amount_L", solid = "IGUI_TLG_Amount_kg", gas = "IGUI_TLG_Amount_m3" }

function Fmt.amount(id, x)
    local number = string.format("%.2f", tonumber(x) or 0)
    local def = TLG.Registry.get("fuel", id)
    local key = def and id ~= "yeast_starter" and AMOUNT_KEYS[def.phase]
    if key then return tr(key, number) end
    return number
end

-- "Water 29.67 L, Stillage 0.40 kg": the materials of a table, by id.
function Fmt.amounts(t)
    local parts = {}
    for _, id in ipairs(TLG.Tables.sortedKeys(t or {})) do
        parts[#parts + 1] = Fmt.componentName(id) .. " " .. Fmt.amount(id, t[id])
    end
    return table.concat(parts, ", ")
end

-- A length of game time: "40 min" under an hour, "3.5 h" under ten hours,
-- "17 h" under two days, then "2 d 10 h".
function Fmt.duration(hours)
    local h = math.max(0, tonumber(hours) or 0)
    if h < 1 then return tr("IGUI_TLG_Dur_Min", tostring(math.max(1, math.floor(h * 60 + 0.5)))) end
    if h < 10 then return tr("IGUI_TLG_Dur_Hours", string.format("%.1f", h)) end
    local whole = math.floor(h + 0.5)
    if whole < 48 then return tr("IGUI_TLG_Dur_Hours", tostring(whole)) end
    return tr("IGUI_TLG_Dur_Days", tostring(math.floor(whole / 24)), tostring(whole - math.floor(whole / 24) * 24))
end

-- How long ago, in game time: "just now", minutes, hours, then days.
function Fmt.ago(hours)
    local h = math.max(0, hours or 0)
    if h < 1 / 60 then return tr("IGUI_TLG_Ago_Now") end
    if h < 1 then
        local m = math.floor(h * 60)
        return m == 1 and tr("IGUI_TLG_Ago_Minute") or tr("IGUI_TLG_Ago_Minutes", tostring(m))
    end
    if h < 24 then
        local n = math.floor(h)
        return n == 1 and tr("IGUI_TLG_Ago_Hour") or tr("IGUI_TLG_Ago_Hours", tostring(n))
    end
    local d = math.floor(h / 24)
    return d == 1 and tr("IGUI_TLG_Ago_Day") or tr("IGUI_TLG_Ago_Days", tostring(d))
end

-- The engine a tank feeds, by its profile: "Engine: stock diesel engine".
function Fmt.engine(profile)
    if profile == nil then return nil end
    return tr("IGUI_TLG_EngineIs", tr("IGUI_TLG_Profile_" .. tostring(profile)))
end

-- What one test's result means for that engine (the authority's `verdict`):
-- headed as the sample's, since a test misses what is below its precision.
function Fmt.verdict(v)
    if v == nil then return nil end
    return tr("IGUI_TLG_VerdictTitle") .. " <LINE> " .. Fmt.evaluation(v)
end

-- What I know about it: each test done on this fuel, most precise first,
-- with when it was done, what it found and whether the fuel changed since;
-- a note when the container is open. For a vehicle's or a generator's tank,
-- the engine it feeds first, and under each test what it means for that
-- engine. `reply` is the authority's answer to the known command:
-- { tests = { { method, observation, ageHours, changed, verdict } }, sealed,
-- engine, tank }.
function Fmt.known(reply)
    local parts = { tr("IGUI_TLG_KnownTitle") }
    local tests = reply and reply.tests or {}
    if reply and reply.engine then parts[#parts + 1] = Fmt.engine(reply.engine) end
    if #tests == 0 then
        parts[#parts + 1] = tr("IGUI_TLG_ConditionUnknown")
        return table.concat(parts, " <LINE> <LINE> ")
    end
    for _, t in ipairs(tests) do
        local lines = { tr("IGUI_TLG_KnownTest", tr("IGUI_TLG_TestName_" .. t.method), Fmt.ago(t.ageHours)) }
        lines[#lines + 1] = Fmt.observation(t.observation, true)
        if t.changed then lines[#lines + 1] = tr("IGUI_TLG_KnownChanged") end
        if t.verdict then lines[#lines + 1] = Fmt.verdict(t.verdict) end
        parts[#parts + 1] = table.concat(lines, " <LINE> ")
    end
    if not reply.sealed and not reply.tank then parts[#parts + 1] = tr("IGUI_TLG_KnownOpen") end
    return table.concat(parts, " <LINE> <LINE> ")
end

-- One observation's findings; `noMethod` leaves out the method line (What I
-- know about it names the test above them).
function Fmt.observation(obs, noMethod)
    if obs == nil then
        return tr("IGUI_TLG_ConditionUnknown")
    end
    local lines = {}
    local grade = TLG.Domain.Inspection.grade(obs.observedDeg, nil)
    lines[#lines + 1] = tr("IGUI_TLG_Primary", Fmt.componentName(obs.primary or "gasoline"))
    lines[#lines + 1] = tr("IGUI_TLG_ConditionEstimate", tr(Fmt.GRADE_KEYS[grade] or grade),
        string.format("%.1f", obs.observedDeg), string.format("%.1f", obs.degError))
    lines[#lines + 1] = obs.waterDetected and tr("IGUI_TLG_WaterDetected", pct(obs.observedWater))
        or tr("IGUI_TLG_WaterNotDetected")
    if obs.phaseSeparated then lines[#lines + 1] = tr("IGUI_TLG_PhaseSeparated") end
    if (obs.observedSediment or 0) > 0 then lines[#lines + 1] = tr("IGUI_TLG_Sediment", pct(obs.observedSediment)) end
    if obs.composition then
        local parts = {}
        for _, id in ipairs(TLG.Tables.sortedKeys(obs.composition)) do
            parts[#parts + 1] = Fmt.componentName(id) .. " " .. pct(obs.composition[id])
        end
        lines[#lines + 1] = tr("IGUI_TLG_Composition", table.concat(parts, ", "))
    end
    if not noMethod then lines[#lines + 1] = tr("IGUI_TLG_Method_" .. (obs.method or "visual")) end
    return table.concat(lines, " <LINE> ")
end

function Fmt.evaluation(e)
    if e == nil then return "" end
    local lines = { tr(Fmt.GRADE_KEYS[e.grade] or "IGUI_TLG_Grade_Good") }
    if not e.compatible then
        lines[#lines + 1] = tr("IGUI_TLG_NotCompatible")
    elseif e.harmful then
        lines[#lines + 1] = tr("IGUI_TLG_Harmful")
    else
        lines[#lines + 1] = tr("IGUI_TLG_Compatible")
    end
    for _, r in ipairs(e.reasons or {}) do
        local key = Fmt.REASON_KEYS[r]
        local level, wrong = string.match(r, "^wrong_fuel_(%d)_(.+)$")
        if key then
            lines[#lines + 1] = "- " .. tr(key)
        elseif level then
            lines[#lines + 1] = "- " .. tr("IGUI_TLG_Reason_Wrong_" .. level, Fmt.componentName(wrong))
        elseif string.find(r, "^marginal_") then
            lines[#lines + 1] = "- " .. tr("IGUI_TLG_Reason_Marginal", Fmt.componentName(string.sub(r, 10)))
        elseif string.find(r, "^too_much_") then
            lines[#lines + 1] = "- " .. tr("IGUI_TLG_Reason_TooMuch", Fmt.componentName(string.sub(r, 10)))
        end
    end
    return table.concat(lines, " <LINE> ")
end

function Fmt.failure(reply)
    local key = Fmt.FAILURE_KEYS[reply.reason]
    if key then return tr(key) end
    return tr("IGUI_TLG_Fail_Generic", tostring(reply.reason))
end

return Fmt
