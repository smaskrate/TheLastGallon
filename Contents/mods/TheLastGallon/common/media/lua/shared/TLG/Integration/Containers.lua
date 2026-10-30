-- Adapter: native fluid containers (inventory items and world objects).
--
--   quantity owner     native FluidContainer
--   composition owner  native fluids (Petrol, TLG_* fluids)
--   consumption owner  native (any vanilla use of the fluid)
--   sidecar            owner modData "tlg": id, rev, deg, stab, mic, t,
--                      storage, sealed, cond, dirty, label, prov and the last
--                      reconciled composition q
--   replication        item: syncItemFields (MP NOT RUN); object: transmitModData
--   reconciliation     on every read: native decreases leave proportionally,
--                      unknown increases mix in at the world baseline (D-006)
--
-- Lua-initiated pours go through FluidContainer.Transfer, which this adapter
-- wraps (wrappability verified RT-DS, G02) so the destination receives the
-- source's chemical condition with the moved fluid.
require "TLG/Integration/Native"
require "TLG/Integration/World"
require "TLG/Authority/Transactions"
require "TLG/Content/Containers"
require "TLG/Persistence/Migrations"

TLG.Integration.Containers = TLG.Integration.Containers or {}
local C = TLG.Integration.Containers
local Native, World = TLG.Integration.Native, TLG.World
local Supply, Mixing, Aging, Tx = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging, TLG.Authority.Transactions
local Tables = TLG.Tables

C.SIDECAR = "tlg"
C.SCHEMA = 1
C.FLOAT_TOLERANCE = 1e-4

local SIDECAR_FIELDS = { "id", "rev", "deg", "stab", "mic", "t", "storage", "sealed", "cond", "dirty", "label", "prov", "q" }

function C.ownerOf(fc)
    if fc == nil then return nil end
    local owner = fc:getOwner()
    if owner == nil then return nil end
    if instanceof(owner, "InventoryItem") then return owner, "item" end
    if instanceof(owner, "IsoObject") then return owner, "object" end
    return nil
end

function C.keyOf(owner, kind)
    if kind == "item" then return "item:" .. tostring(owner:getID()) end
    local sq = owner:getSquare()
    return string.format("obj:%d,%d,%d:%s", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1,
        tostring(owner:getObjectIndex()))
end

local function storageFor(owner, kind)
    if kind == "item" then return TLG.ContainerProfiles.forItem(owner) end
    return TLG.ContainerProfiles.forObject(owner)
end

-- Builds the committed record for a container; nil when it does not hold
-- TLG-tracked fuel. `persist` allows assigning ids/baselines (authority).
function C.read(owner, kind, persist)
    local fc = owner:getFluidContainer()
    if fc == nil then return nil, "no_fluid_container" end
    local comp, foreign = Native.readComposition(fc)
    if foreign > 1e-6 then return nil, "foreign_fluid" end
    local md = owner:getModData()
    -- Newer (unknown) schemas stay untouched and read-only (docs/migrations.md).
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", md[C.SIDECAR])
    if md[C.SIDECAR] ~= nil and side == nil then return nil, schemaStatus end
    local storage = storageFor(owner, kind)
    local cap = fc:getCapacity()
    if side == nil then
        local rec
        if Tables.isEmpty(comp) then
            rec = Supply.new({ storage = storage, cap = cap, t = World.now() })
        else
            rec = World.baseline(C.keyOf(owner, kind), { storage = storage, cap = cap, q = comp })
        end
        rec.cap = cap
        if persist then rec.id = World.newId("S") end
        return rec, "initialized"
    end
    local rec = Supply.new({ storage = side.storage or storage, cap = cap, t = side.t, sealed = side.sealed,
        cond = side.cond, dirty = side.dirty, stab = side.stab, mic = side.mic, label = side.label })
    rec.id, rec.rev = side.id, side.rev or 0
    for id, q in pairs(side.q or {}) do rec.q[id] = q end
    for id, d in pairs(side.deg or {}) do rec.deg[id] = d end
    rec.prov = Tables.deepCopy(side.prov or {})
    -- Native amounts are Java floats (RT-DS drift ~2.5e-7 L per transfer):
    -- differences within C.FLOAT_TOLERANCE are adopted silently.
    local maxDiff = 0
    for id, q in pairs(comp) do maxDiff = math.max(maxDiff, math.abs(q - (rec.q[id] or 0))) end
    for id, q in pairs(rec.q) do maxDiff = math.max(maxDiff, math.abs(q - (comp[id] or 0))) end
    if maxDiff <= C.FLOAT_TOLERANCE then
        rec.q = Tables.copy(comp)
        Supply.normalize(rec)
        rec.cap = cap
        return rec, "ok"
    end
    local base = { deg = 0, mic = 0 }
    for id, q in pairs(comp) do
        if q > (rec.q[id] or 0) + 1e-6 then base.deg = C.untrackedDeg(); break end
    end
    local reconciled, info = Tx.reconcile(rec, { comp = comp }, base)
    reconciled.cap = cap
    if info.added > 1e-6 then
        TLG.Log.debug("container %s: %.4f L of untracked inflow reconciled", C.keyOf(owner, kind), info.added)
    end
    return reconciled, (info.added > 1e-6 or info.removed > 1e-6) and "reconciled" or "ok"
end

-- Degradation assigned to fuel of unknown origin (untracked inflow): the
-- pessimistic baseline, cached per world day.
local untrackedCache = { day = nil, deg = 0 }
function C.untrackedDeg()
    local env = World.env()
    local day = env:dayIndex(World.now())
    if untrackedCache.day ~= day then
        local b = World.baseline("untracked", { storage = "unknown", cap = 1, q = { gasoline = 1 } })
        untrackedCache.day, untrackedCache.deg = day, b.deg.gasoline or 0
    end
    return untrackedCache.deg
end

function C.writeSidecar(owner, kind, rec)
    local side = { v = C.SCHEMA }
    for _, f in ipairs(SIDECAR_FIELDS) do side[f] = Tables.deepCopy(rec[f]) end
    owner:getModData()[C.SIDECAR] = side
    if kind == "object" then
        owner:transmitModData()
    elseif owner.syncItemFields then
        owner:syncItemFields()
    end
end

-- Endpoint for TLG-initiated transactions (moves native quantity too).
function C.endpoint(owner, kind, actor)
    local ep = { key = C.keyOf(owner, kind), owner = owner, kind = kind }
    function ep:canAccess(player)
        if kind == "item" then
            local outer = owner:getOutermostContainer()
            if outer and player and outer == player:getInventory() then return true end
            local wi = owner:getWorldItem()
            local sq = (wi and wi:getSquare()) or (outer and outer:getSourceGrid())
            if sq and player and player:getSquare() and player:getSquare():DistToProper(sq) <= 2.5 then return true end
            return false, "out_of_reach"
        end
        local sq = owner:getSquare()
        if sq and player and player:getSquare() and player:getSquare():DistToProper(sq) <= 2.5 then return true end
        return false, "out_of_reach"
    end
    function ep:read()
        local rec = C.read(owner, kind, true)
        return rec
    end
    function ep:write(rec)
        local ok, why = Native.writeComposition(owner:getFluidContainer(), rec.q)
        if not ok then return false, why end
        C.writeSidecar(owner, kind, rec)
        return true
    end
    return ep
end

------------------------------------------------------------------------------
-- FluidContainer.Transfer hook
------------------------------------------------------------------------------
local originalTransfer = nil

local function subtract(before, after)
    local parcel, total = {}, 0
    for id, q in pairs(before) do
        local d = q - (after[id] or 0)
        if d > 1e-7 then parcel[id] = d; total = total + d end
    end
    return parcel, total
end

-- Moves chemical condition along with a native transfer that already happened.
function C.followNativeTransfer(srcOwner, srcKind, srcRec, dstOwner, dstKind, dstRec, parcel)
    local now = World.now()
    local env = World.env()
    local src = Aging.advance(srcRec, now, env)
    local dst = Aging.advance(dstRec, now, env)
    -- Merge the parcel with the source's intensive properties.
    local parcelSupply = Supply.copy(src)
    parcelSupply.q = Tables.copy(parcel)
    local merged = Mixing.previewBlend({ { supply = dst, amount = Supply.total(dst) },
        { supply = parcelSupply, amount = Supply.total(parcelSupply) } }, dst.storage, dst.cap)
    merged.id, merged.rev, merged.cap, merged.t = dst.id, (dst.rev or 0) + 1, dst.cap, now
    merged.sealed, merged.cond, merged.dirty, merged.label = dst.sealed, dst.cond, dst.dirty, dst.label
    merged.prov = dst.prov
    Supply.addProvenance(merged, { k = "in", from = src.id, t = now, n = Supply.total(parcelSupply) })
    -- Source keeps its properties; native already removed the parcel.
    local newSrc = Supply.copy(src)
    for id, q in pairs(parcel) do
        newSrc.q[id] = math.max(0, (newSrc.q[id] or 0) - q)
    end
    Supply.normalize(newSrc)
    newSrc.rev = (src.rev or 0) + 1
    C.writeSidecar(srcOwner, srcKind, newSrc)
    C.writeSidecar(dstOwner, dstKind, merged)
    return newSrc, merged
end

local function transferHook(a, b, amount, ...)
    if not World.isAuthority() or a == nil or b == nil then
        return originalTransfer(a, b, amount, ...)
    end
    local ok, ctxOrErr = pcall(function()
        local ao, ak = C.ownerOf(a)
        local bo, bk = C.ownerOf(b)
        if not ao or not bo then return nil end
        local srcRec = C.read(ao, ak, true)
        if not srcRec or Supply.isEmpty(srcRec) then return nil end
        local dstRec = C.read(bo, bk, true)
        if not dstRec then return nil end
        return { ao = ao, ak = ak, bo = bo, bk = bk, src = srcRec, dst = dstRec,
            before = Native.readComposition(a) }
    end)
    local res = originalTransfer(a, b, amount, ...)
    if ok and ctxOrErr then
        local c = ctxOrErr
        local ok2, err = pcall(function()
            local after = Native.readComposition(a)
            local parcel, moved = subtract(c.before, after)
            if moved > 1e-7 then
                C.followNativeTransfer(c.ao, c.ak, c.src, c.bo, c.bk, c.dst, parcel)
            end
        end)
        if not ok2 then TLG.Log.error("transfer hook: %s", tostring(err)) end
    elseif not ok then
        TLG.Log.error("transfer hook prepare: %s", tostring(ctxOrErr))
    end
    return res
end

function C.install()
    if originalTransfer ~= nil then return end
    if FluidContainer == nil or FluidContainer.Transfer == nil then
        TLG.Log.error("FluidContainer.Transfer not found; container adapter disabled")
        return
    end
    originalTransfer = FluidContainer.Transfer
    FluidContainer.Transfer = transferHook
    TLG.Log.info("container adapter installed (FluidContainer.Transfer wrapped)")
end

function C.originalTransfer()
    return originalTransfer or FluidContainer.Transfer
end

return C
