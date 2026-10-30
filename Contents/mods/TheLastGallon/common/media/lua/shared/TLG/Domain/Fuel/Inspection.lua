-- Inspection knowledge, kept separate from physical state (spec §5).
-- An observation records what a sample revealed at a given precision; the
-- fuel itself does not change with who inspects it.
--
-- observation = { sampledAt, precision, observedDeg, degError, observedWater,
--                 observedSediment, composition, sampledRev, method }
require "TLG/Domain/Fuel/Supply"
require "TLG/Domain/Balance"
require "TLG/Util/Rng"

TLG.Domain.Inspection = TLG.Domain.Inspection or {}
local Inspection = TLG.Domain.Inspection
local Supply, Balance = TLG.Domain.Supply, TLG.Domain.Balance
local Tables, Num = TLG.Tables, TLG.Num

-- methods: visual (look/smell), kit (sampling kit), lab (bench test).
Inspection.METHODS = {
    visual = { precision = 0.3, waterThreshold = 0.01, composition = false },
    kit = { precision = 0.7, waterThreshold = 0.001, composition = true },
    lab = { precision = 0.95, waterThreshold = 0.0002, composition = true },
}

-- precision may be raised by skill (0..1 bonus), never above 0.98.
function Inspection.sample(s, method, skillBonus, rng)
    local m = Inspection.METHODS[method] or Inspection.METHODS.visual
    local precision = math.min(0.98, m.precision + (skillBonus or 0) * 0.25)
    local trueDeg = Supply.blendDeg(s)
    local sd = (1 - precision) * 0.8
    local noise = rng and rng:normal() * sd or 0
    local observedDeg = math.max(0, trueDeg + noise)
    local total = Supply.total(s)
    local waterFrac = total > Num.DUST and Supply.freeWater(s) / total or 0
    local sedFrac = total > Num.DUST and (s.q.sediment or 0) / total or 0
    local obs = {
        sampledAt = s.t,
        sampledRev = s.rev,
        method = method,
        precision = precision,
        observedDeg = observedDeg,
        degError = sd * 2,
        observedWater = waterFrac >= m.waterThreshold and waterFrac or 0,
        waterDetected = waterFrac >= m.waterThreshold,
        observedSediment = sedFrac >= m.waterThreshold and sedFrac or 0,
        phaseSeparated = Supply.isPhaseSeparated(s) and waterFrac >= m.waterThreshold,
        primary = Supply.primary(s),
    }
    if m.composition and total > Num.DUST then
        local comp = {}
        for _, id in ipairs(Tables.sortedKeys(s.q)) do
            if not TLG.Domain.FuelDefs.isContaminant(id) then
                comp[id] = Num.roundTo(s.q[id] / total, 0.05)
            end
        end
        obs.composition = comp
    end
    return obs
end

-- Grade from a degradation value with hysteresis around thresholds:
-- moving to a worse grade needs deg >= threshold; moving back to a better
-- grade needs deg < threshold - hysteresis.
function Inspection.grade(deg, previous)
    local h = Balance.GRADE_HYSTERESIS
    local raw
    for _, g in ipairs(Balance.GRADES) do
        if deg < g.below then raw = g.id; break end
    end
    if previous == nil or previous == raw then return raw end
    local order = { good = 1, weathered = 2, poor = 3 }
    if order[raw] and order[previous] and order[raw] < order[previous] then
        for _, g in ipairs(Balance.GRADES) do
            if g.id == raw then
                if deg < g.below - h then return raw end
                return previous
            end
        end
    end
    return raw
end

-- What the player knows: "unknown" until sampled; stale samples are flagged
-- when the supply changed after sampling (revision differs).
function Inspection.knowledge(s, obs, previousGrade)
    if obs == nil then
        return { state = "unknown" }
    end
    return {
        state = (obs.sampledRev == s.rev) and "current" or "stale",
        grade = Inspection.grade(obs.observedDeg, previousGrade),
        ageHours = s.t - obs.sampledAt,
        waterDetected = obs.waterDetected,
        phaseSeparated = obs.phaseSeparated,
        precision = obs.precision,
        observation = obs,
    }
end

return Inspection
