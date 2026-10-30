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
require "TLG/Domain/Fuel/Supply"
require "TLG/Domain/Fuel/Inspection"
require "TLG/Domain/Balance"

TLG.Domain.Consumers = TLG.Domain.Consumers or {}
local Consumers = TLG.Domain.Consumers
local Supply, Balance = TLG.Domain.Supply, TLG.Domain.Balance
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

local function lerp(a, b, t) return a + (b - a) * Num.clamp(t, 0, 1) end

function Consumers.evaluate(profileId, s, state)
    state = state or {}
    local p = Registry.need("consumer", profileId)
    local r = { compatible = true, startFactor = 1, powerFactor = 1, wearFactor = 1, energyFactor = 1, reasons = {} }
    local function reason(code) r.reasons[#r.reasons + 1] = code end
    local total = Supply.total(s)
    local fuel = Supply.fuelTotal(s)
    if fuel <= Num.DUST then
        r.compatible = false
        r.grade = "empty"
        reason("empty")
        return r
    end

    -- Composition against the accepted list.
    local foreign, energy = 0, 0
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local f = Registry.need("fuel", id)
        if f.role ~= "contaminant" then
            local frac = s.q[id] / fuel
            local rule = p.accepts[id]
            if rule == nil then
                foreign = foreign + frac
            else
                if frac > rule.max + 1e-9 then
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

    -- Chemical condition.
    local deg = Supply.blendDeg(s)
    r.deg = deg
    if deg >= p.maxDeg then
        r.compatible = false
        r.grade = "unsuitable"
        reason("degraded")
    else
        r.grade = TLG.Domain.Inspection.grade(deg, state.previousGrade)
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
