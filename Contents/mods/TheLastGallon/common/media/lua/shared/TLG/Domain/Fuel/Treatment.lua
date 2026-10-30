-- Storage interactions: stabilizing, filtering, water separation, cleaning,
-- sealing and repair. Each returns { ok, reason, supply, removed, used }.
-- Filtering removes only eligible contamination; nothing here lowers `deg`
-- (oxidation is not reversible by treatment, spec §7).
require "TLG/Domain/Fuel/Supply"

TLG.Domain.Treatment = TLG.Domain.Treatment or {}
local Treatment = TLG.Domain.Treatment
local Supply = TLG.Domain.Supply
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

-- One stabilizer dose treats this many litres at full strength.
Treatment.LITRES_PER_DOSE = 20
-- Stored concentration is capped; effect is already capped at 1.0 in Aging.
Treatment.MAX_STAB = 2.0

function Treatment.stabilize(s, doses)
    local out = Supply.copy(s)
    local fuel = Supply.fuelTotal(out)
    if fuel <= Num.DUST then return { ok = false, reason = "empty", supply = out } end
    if doses <= 0 then return { ok = false, reason = "invalid_amount", supply = out } end
    local room = math.max(0, Treatment.MAX_STAB - out.stab) * fuel / Treatment.LITRES_PER_DOSE
    local used = math.min(doses, room)
    if used <= 0 then return { ok = false, reason = "already_saturated", supply = out } end
    out.stab = out.stab + used * Treatment.LITRES_PER_DOSE / fuel
    return { ok = true, supply = out, used = used }
end

-- spec: { sedimentEff = 0..1, waterCapacity = litres absorbed, holdup = litres
-- of mixture retained in the filter, micReduction = 0..1 }.
function Treatment.filter(s, spec)
    local out = Supply.copy(s)
    local total = Supply.total(out)
    if total <= Num.DUST then return { ok = false, reason = "empty", supply = out } end
    local removed = {}
    local sed = out.q.sediment or 0
    if sed > 0 then
        local take = sed * (spec.sedimentEff or 0.95)
        out.q.sediment = sed - take
        removed.sediment = take
    end
    local free = Supply.freeWater(out)
    if free > 0 and (spec.waterCapacity or 0) > 0 then
        local take = math.min(free, spec.waterCapacity)
        out.q.water = out.q.water - take
        removed.water = (removed.water or 0) + take
    end
    -- Carrier holdup: the filter retains some mixture, proportionally.
    local holdup = math.min(spec.holdup or 0, Supply.total(out))
    if holdup > 0 then
        local frac = holdup / Supply.total(out)
        for _, id in ipairs(Tables.sortedKeys(out.q)) do
            local take = out.q[id] * frac
            out.q[id] = out.q[id] - take
            removed[id] = (removed[id] or 0) + take
        end
    end
    out.mic = out.mic * (1 - (spec.micReduction or 0.3))
    Supply.normalize(out)
    return { ok = true, supply = out, removed = removed }
end

-- Settle and drain. Free water leaves; in a phase-separated gasoline/ethanol
-- blend the lower phase also carries ethanol (`phaseEthanolRatio` litres of
-- ethanol per litre of free water, bounded by the ethanol present).
function Treatment.separateWater(s, phaseEthanolRatio)
    local out = Supply.copy(s)
    local free = Supply.freeWater(out)
    if free <= Num.DUST then return { ok = false, reason = "no_free_water", supply = out } end
    local removed = { water = free }
    if Supply.isPhaseSeparated(out) then
        local eth = math.min(out.q.ethanol or 0, free * (phaseEthanolRatio or 1.0))
        out.q.ethanol = out.q.ethanol - eth
        removed.ethanol = eth
    end
    out.q.water = out.q.water - free
    -- Removing ethanol lowers the water capacity; drain again until stable.
    for _ = 1, 8 do
        local extra = Supply.freeWater(out)
        if extra <= Num.DUST then break end
        out.q.water = out.q.water - extra
        removed.water = removed.water + extra
    end
    Supply.normalize(out)
    return { ok = true, supply = out, removed = removed }
end

function Treatment.clean(s)
    local out = Supply.copy(s)
    if not Supply.isEmpty(out) then return { ok = false, reason = "not_empty", supply = out } end
    out.dirty = 0
    out.mic = 0
    out.stab = 0
    return { ok = true, supply = out }
end

function Treatment.setSealed(s, sealed)
    local out = Supply.copy(s)
    local storage = Registry.need("storage", out.storage)
    if not storage.sealable then return { ok = false, reason = "not_sealable", supply = out } end
    out.sealed = sealed and true or false
    return { ok = true, supply = out }
end

-- Repair improves the vessel only: never quantity or quality.
function Treatment.repair(s, amount)
    local out = Supply.copy(s)
    if amount <= 0 then return { ok = false, reason = "invalid_amount", supply = out } end
    out.cond = Num.clamp(out.cond + amount, 0, 1)
    return { ok = true, supply = out }
end

return Treatment
