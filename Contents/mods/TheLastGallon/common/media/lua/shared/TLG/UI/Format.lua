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
}

local function pct(x) return string.format("%.1f%%", (x or 0) * 100) end

function Fmt.componentName(id)
    return tr("IGUI_TLG_Fuel_" .. id)
end

function Fmt.observation(obs)
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
    lines[#lines + 1] = tr("IGUI_TLG_Method_" .. (obs.method or "visual"))
    return table.concat(lines, " <LINE> ")
end

function Fmt.evaluation(e)
    if e == nil then return "" end
    local lines = { tr(Fmt.GRADE_KEYS[e.grade] or "IGUI_TLG_Grade_Good") }
    lines[#lines + 1] = e.compatible and tr("IGUI_TLG_Compatible") or tr("IGUI_TLG_NotCompatible")
    for _, r in ipairs(e.reasons or {}) do
        local key = Fmt.REASON_KEYS[r]
        if key then
            lines[#lines + 1] = "- " .. tr(key)
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
