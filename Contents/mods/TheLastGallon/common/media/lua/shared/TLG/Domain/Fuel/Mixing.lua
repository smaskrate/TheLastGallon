-- Transfers and blends (FuelService.previewTransfer / previewBlend).
--
-- Transfers are homogeneous: every component leaves the source in proportion
-- to its share. Intensive properties mix by volume:
--   deg[c]  weighted by the quantity of component c
--   stab    weighted by non-contaminant volume
--   mic     weighted by total volume
-- Both participants must already be advanced to the same world time
-- (spec §6 rule 6); the caller (authority layer) does that.
require "TLG/Domain/Fuel/Supply"

TLG.Domain.Mixing = TLG.Domain.Mixing or {}
local Mixing = TLG.Domain.Mixing
local Supply = TLG.Domain.Supply
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

Mixing.TIME_TOLERANCE = 1e-6

local function weighted(a, wa, b, wb)
    local w = wa + wb
    if w <= 0 then return 0 end
    return (a * wa + b * wb) / w
end

-- Splits `amount` off `s` homogeneously. Returns the removed parcel as a
-- component table (and mutates `s`). When the whole supply is taken, exact
-- quantities move so no residue is left by rounding.
local function split(s, amount)
    local total = Supply.total(s)
    local parcel = {}
    if amount >= total - Num.EPS then
        for _, id in ipairs(Tables.sortedKeys(s.q)) do
            parcel[id] = s.q[id]
            s.q[id] = 0
        end
        return parcel
    end
    local frac = amount / total
    for _, id in ipairs(Tables.sortedKeys(s.q)) do
        local take = s.q[id] * frac
        parcel[id] = take
        s.q[id] = s.q[id] - take
    end
    return parcel
end

-- Adds a parcel with the given intensive properties into `dst`.
local function merge(dst, parcel, props)
    local parcelFuel, parcelTotal = 0, 0
    for _, id in ipairs(Tables.sortedKeys(parcel)) do
        parcelTotal = parcelTotal + parcel[id]
        if not TLG.Domain.FuelDefs.isContaminant(id) then parcelFuel = parcelFuel + parcel[id] end
    end
    local dstFuel, dstTotal = Supply.fuelTotal(dst), Supply.total(dst)
    dst.stab = weighted(dst.stab, dstFuel, props.stab, parcelFuel)
    local dstMic = dst.mic
    if dstTotal <= Num.DUST then
        dstMic = math.max(dst.mic, dst.dirty * 0.2)
    end
    dst.mic = weighted(dstMic, dstTotal, props.mic, parcelTotal)
    for _, id in ipairs(Tables.sortedKeys(parcel)) do
        local add = parcel[id]
        if add > 0 then
            local have = dst.q[id] or 0
            local f = Registry.need("fuel", id)
            if f.aging then
                local d0 = dst.deg[id] or 0
                local d1 = props.deg[id] or 0
                dst.deg[id] = weighted(d0, have, d1, add)
            end
            dst.q[id] = have + add
        end
    end
end

-- Pure preview of moving up to `amount` from src to dst.
-- Returns { ok, reason, moved, src, dst, parcel }.
function Mixing.previewTransfer(src, dst, amount, opts)
    opts = opts or {}
    if not Num.isFinite(amount) or amount <= 0 then
        return { ok = false, reason = "invalid_amount" }
    end
    if src.id ~= nil and src.id == dst.id then
        return { ok = false, reason = "same_supply" }
    end
    if math.abs(src.t - dst.t) > Mixing.TIME_TOLERANCE then
        return { ok = false, reason = "time_mismatch" }
    end
    if src.phase ~= dst.phase then
        return { ok = false, reason = "phase_mismatch" }
    end
    local available = Supply.total(src)
    local room = Supply.free(dst)
    local moved = math.min(amount, available, room)
    if opts.maxAmount then moved = math.min(moved, opts.maxAmount) end
    local newSrc, newDst = Supply.copy(src), Supply.copy(dst)
    if moved <= Num.DUST then
        return { ok = true, moved = 0, src = newSrc, dst = newDst, parcel = {},
            reason = (room <= Num.DUST) and "destination_full" or "source_empty" }
    end
    local props = { deg = Tables.copy(src.deg), stab = src.stab, mic = src.mic }
    local parcel = split(newSrc, moved)
    merge(newDst, parcel, props)
    Supply.addProvenance(newDst, { k = "in", from = src.id, t = src.t, n = moved })
    local dust = Supply.normalize(newSrc) + Supply.normalize(newDst)
    return { ok = true, moved = moved, src = newSrc, dst = newDst, parcel = parcel, dust = dust }
end

-- Prediction of combining several (supply, amount) inputs into an empty
-- vessel with the given storage profile; used by blending UI and previews.
function Mixing.previewBlend(inputs, storageId, capacity)
    local t = inputs[1] and inputs[1].supply.t or 0
    local out = Supply.new({ storage = storageId or "unknown", cap = capacity or math.huge, t = t })
    out.cap = capacity or 1e12
    for _, input in ipairs(inputs) do
        local tmp = Supply.copy(input.supply)
        local parcel = split(tmp, math.min(input.amount, Supply.total(tmp)))
        merge(out, parcel, { deg = input.supply.deg, stab = input.supply.stab, mic = input.supply.mic })
    end
    Supply.normalize(out)
    return out
end

-- Adds quantity of unknown origin (native change TLG did not initiate) using
-- a baseline condition; never fresher than `baseline` (decision D-006).
function Mixing.addUntracked(s, component, amount, baseline)
    local out = Supply.copy(s)
    if amount <= Num.DUST then return out end
    local parcel = { [component] = amount }
    local deg = {}
    if Registry.need("fuel", component).aging then deg[component] = baseline.deg or 0 end
    merge(out, parcel, { deg = deg, stab = 0, mic = baseline.mic or 0 })
    Supply.addProvenance(out, { k = "untracked", c = component, n = amount, t = out.t })
    Supply.normalize(out)
    return out
end

-- Removes quantity proportionally (native consumption/dispensing TLG observed
-- but did not perform). Returns the new record and the removed parcel.
function Mixing.removeProportional(s, amount)
    local out = Supply.copy(s)
    amount = math.min(amount, Supply.total(out))
    if amount <= 0 then return out, {} end
    local parcel = split(out, amount)
    Supply.normalize(out)
    return out, parcel
end

return Mixing
