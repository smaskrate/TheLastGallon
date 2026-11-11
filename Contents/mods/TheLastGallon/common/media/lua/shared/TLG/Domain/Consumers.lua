-- ConsumerService.evaluate(profileId, supply, operatingState)
--
-- Compatibility (which fuels an engine accepts) is separate from condition
-- (degradation, contamination) and from nominal energy (spec §6 rule 11).
-- Results are game-level factors; adapters apply only those they control:
--   compatible     can it run at all
--   grade          good | weathered | poor | unsuitable (for this consumer)
--   startFactor    multiplier on start success (0..1)
--   powerFactor    multiplier on available power (0..1)
--   wearFactor     multiplier on engine wear (>= 1)
--   energyFactor   energy per litre relative to the reference fuel
--   reasons        sorted list of reason codes for UI text
--
-- Wrong fuel (D-037): a fuel the engine is not built for, above the trace it
-- tolerates, no longer just blocks the start. The profile's `wrongFuel`
-- rules give bands by the fuel's share: the engine runs worse and wears
-- faster, and in the last band of some rules it does not start at all. An
-- accepted fuel above its `max` (ethanol in a stock petrol engine) follows
-- its rule's `over`. Extra results:
--   harmful        the engine runs, or tries to, on a fuel that damages it:
--                  a pour of it wants the player's confirmation
--   wrongFuel      the fuel that decided, wrongLevel 1 (light) to 4 (no start)
--   attemptDamage  { min, max } engine condition lost at each refused start
--   failureChance  chance of sudden engine failure for each litre burned
--   exhaustWear    exhaust condition lost for each litre burned
-- With Consumers.damageEnabled() false (the sandbox option off) none of this
-- applies and such fuel blocks the start, as before 0.3.0.
require "TLG/Domain/Fuel/Supply"
require "TLG/Domain/Fuel/Inspection"
require "TLG/Domain/Balance"

TLG.Domain.Consumers = TLG.Domain.Consumers or {}
local Consumers = TLG.Domain.Consumers
local Supply, Balance = TLG.Domain.Supply, TLG.Domain.Balance
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

local function lerp(a, b, t) return a + (b - a) * Num.clamp(t, 0, 1) end

-- The adapters point this at the sandbox option; `state.wrongFuelDamage`
-- overrides it for one evaluation.
Consumers.damageEnabled = function() return true end

local GRADE_RANK = { good = 1, weathered = 2, poor = 3, unsuitable = 4 }
local function worseGrade(a, b)
    if (GRADE_RANK[b] or 0) > (GRADE_RANK[a] or 0) then return b end
    return a
end

-- The last band whose threshold the share is above.
local function pickBand(bands, share)
    local found
    for _, b in ipairs(bands) do
        if share > b.above + 1e-9 then found = b end
    end
    return found
end

function Consumers.evaluate(profileId, s, state)
    state = state or {}
    local p = Registry.need("consumer", profileId)
    local r = { compatible = true, startFactor = 1, powerFactor = 1, wearFactor = 1, energyFactor = 1, reasons = {} }
    local function reason(code) r.reasons[#r.reasons + 1] = code end
    local damage = state.wrongFuelDamage
    if damage == nil then damage = Consumers.damageEnabled() end
    local total = Supply.total(s)
    local fuel = Supply.fuelTotal(s)
    if fuel <= Num.DUST then
        r.compatible = false
        r.grade = "empty"
        reason("empty")
        return r
    end

    -- Wrong fuel: each rule sums its fuels' share and picks a band. The worst
    -- of the rules that apply decides each factor; they do not multiply. An
    -- accepted fuel past its limit (`over`) is one more such rule.
    local ruled, over, worst, coldNoStartBelow, banded = {}, {}, nil, nil, false
    local function merge(level, lead, b, wear)
        worst = worst or { level = 0, start = 1, power = 1, wear = 1, failure = 0, exhaust = 0 }
        if level > worst.level then worst.level, worst.fuel = level, lead end
        worst.start = math.min(worst.start, b.start or 1)
        worst.power = math.min(worst.power, b.power or 1)
        worst.wear = math.max(worst.wear, wear)
        worst.failure = math.max(worst.failure, b.failure or 0)
        worst.exhaust = math.max(worst.exhaust, b.exhaust or 0)
        if b.noStart then worst.noStart, worst.attempt = true, b.attempt or worst.attempt end
    end
    if damage then
        for _, id in ipairs(Tables.sortedKeys(p.accepts)) do
            local rule = p.accepts[id]
            local frac = (s.q[id] or 0) / fuel
            if rule.over and frac > rule.max + 1e-9 then
                -- Past its limit the engine still runs, lean.
                local o = rule.over
                if o.high and frac > o.high.above + 1e-9 then
                    o = o.high
                    coldNoStartBelow = o.coldBelowC
                end
                over[id] = true
                merge(o.level or 2, id, o, o.wear or 1)
                reason("too_much_" .. id)
            end
        end
    end
    if damage and p.wrongFuel then
        for _, rule in ipairs(p.wrongFuel) do
            local share, lead, leadShare = 0, nil, 0
            for _, id in ipairs(rule.fuels) do
                local f = (s.q[id] or 0) / fuel
                share = share + f
                if f > leadShare then lead, leadShare = id, f end
            end
            local band = pickBand(rule.bands, share)
            if band then
                for _, id in ipairs(rule.fuels) do ruled[id] = true end
                local wear = band.wear or 1
                for id, extra in pairs(rule.extraWear or {}) do
                    wear = wear * (1 + extra * ((s.q[id] or 0) / fuel) / share)
                end
                merge(band.level, lead, band, wear)
                banded = banded or {}
                banded[#banded + 1] = "wrong_fuel_" .. band.level .. "_" .. tostring(lead)
            end
        end
    end
    if worst then
        r.harmful, r.wrongFuel, r.wrongLevel = true, worst.fuel, worst.level
        r.startFactor = r.startFactor * worst.start
        r.powerFactor = r.powerFactor * worst.power
        r.wearFactor = r.wearFactor * worst.wear
        if worst.failure > 0 then r.failureChance = worst.failure end
        if worst.exhaust > 0 then r.exhaustWear = worst.exhaust end
        if worst.noStart then
            r.compatible = false
            r.attemptDamage = worst.attempt
        end
        for _, code in ipairs(banded or {}) do reason(code) end
    end

    -- Composition against the accepted list.
    local foreign, energy = 0, 0
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local f = Registry.need("fuel", id)
        if f.role ~= "contaminant" then
            local frac = s.q[id] / fuel
            local rule = p.accepts[id]
            if rule == nil then
                -- A wrong fuel a band already judged is not counted again.
                if not ruled[id] then foreign = foreign + frac end
            else
                if over[id] then
                    -- Judged above, with the wrong fuels.
                elseif frac > rule.max + 1e-9 then
                    r.compatible = false
                    reason("too_much_" .. id)
                elseif frac > rule.soft + 1e-9 then
                    local over = (frac - rule.soft) / math.max(1e-9, rule.max - rule.soft)
                    r.startFactor = r.startFactor * lerp(1, 0.6, over)
                    r.powerFactor = r.powerFactor * lerp(1, 0.85, over)
                    r.wearFactor = r.wearFactor * lerp(1, 1.5, over)
                    reason("marginal_" .. id)
                end
            end
            energy = energy + frac * (f.energyMJ or 0)
        end
    end
    if foreign > p.foreignMax + 1e-9 then
        r.compatible = false
        reason("incompatible_fuel")
    end
    local ref = Registry.need("fuel", p.referenceFuel)
    r.energyFactor = energy / ref.energyMJ
    -- Fuel-specific power derate (e.g. wood gas), weighted by fuel share.
    if p.derate then
        local loss = 0
        for _, id in ipairs(Tables.sortedKeys(p.derate)) do
            loss = loss + ((s.q[id] or 0) / fuel) * (1 - p.derate[id])
        end
        if loss > 0 then
            r.powerFactor = r.powerFactor * (1 - loss)
            reason("derated")
        end
    end

    -- Chemical condition.
    local deg = Supply.blendDeg(s)
    r.deg = deg
    if deg >= p.maxDeg then
        r.compatible = false
        r.grade = "unsuitable"
        reason("degraded")
    else
        r.grade = TLG.Domain.Inspection.grade(deg, state.previousGrade)
        -- Fuel that harms the engine is never "good" for it.
        if r.harmful then r.grade = worseGrade(r.grade, (r.wrongLevel or 1) >= 2 and "poor" or "weathered") end
        local t = deg / p.maxDeg
        if deg >= 1 then
            r.startFactor = r.startFactor * lerp(1, 0.55, (deg - 1) / math.max(1e-9, p.maxDeg - 1))
            r.powerFactor = r.powerFactor * lerp(1, 0.8, t)
            r.wearFactor = r.wearFactor * lerp(1, 2.0, t)
            reason("aged")
        end
    end

    -- Contamination.
    local freeWater = Supply.freeWater(s) / total
    if Supply.isPhaseSeparated(s) and p.ignition == "spark" then
        r.compatible = false
        reason("phase_separated")
    elseif freeWater > p.waterMax then
        r.startFactor = r.startFactor * 0.5
        r.powerFactor = r.powerFactor * 0.85
        reason("water")
        if freeWater > p.waterMax * 5 then
            r.compatible = false
        end
    end
    local sediment = (s.q.sediment or 0) / total
    if sediment > p.sedimentMax then
        r.powerFactor = r.powerFactor * 0.85
        r.wearFactor = r.wearFactor * 1.5
        reason("sediment")
    end
    if s.mic > 0.5 then
        r.powerFactor = r.powerFactor * 0.9
        reason("microbial")
    end

    -- Cold behaviour.
    local ambient = state.ambientC
    if ambient ~= nil then
        if coldNoStartBelow and ambient < coldNoStartBelow then
            r.startFactor = 0
            reason("cold_start")
        end
        if p.coldStart and (s.q[p.coldStart.fuel] or 0) / fuel > p.coldStart.above and ambient < p.coldStart.belowC then
            r.startFactor = r.startFactor * lerp(0.9, 0.3, (p.coldStart.belowC - ambient) / 15)
            reason("cold_start")
        end
        for _, id in ipairs(Tables.sortedKeys(s.q)) do
            local f = Registry.need("fuel", id)
            if f.coldLimitC and ambient < f.coldLimitC and s.q[id] / fuel > 0.2 and not p.fuelHeater then
                r.startFactor = r.startFactor * 0.3
                r.powerFactor = r.powerFactor * 0.7
                reason("gelling")
                break
            end
        end
    end

    if not r.compatible then
        r.startFactor = 0
        r.powerFactor = 0
        if r.grade ~= "unsuitable" then r.grade = "unsuitable" end
    end
    r.reasons = Tables.sort(r.reasons)
    return r
end

return Consumers
