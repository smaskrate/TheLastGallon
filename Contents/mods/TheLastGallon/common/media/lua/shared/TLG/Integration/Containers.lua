-- Adapter: native fluid containers (inventory items and world objects).
--
--   quantity owner     native FluidContainer
--   composition owner  native fluids (Petrol, TLG_* fluids)
--   consumption owner  native (any vanilla use of the fluid)
--   sidecar            owner modData "tlg": id, rev, deg, stab, mic, t,
--                      storage, sealed, cond, dirty, label, prov and the last
--                      reconciled composition q; every record write sets the
--                      native fluids to q where they differ (C.commit)
--   replication        item: syncItemFields (a can's record the same on the
--                      client as on the server, RT-MP runs 145-171); object:
--                      transmitModData
--   server copy        on a server every read is checked against the vault
--                      (TLG/Authority/Vault.lua; audit V-01): clients can
--                      rewrite both mod data stores there
--   reconciliation     on every read: native decreases leave proportionally,
--                      unknown increases mix in at the world baseline when
--                      found, into the record advanced to then (D-006)
--
-- Lua-initiated pours go through FluidContainer.Transfer, which this adapter
-- wraps (wrappability verified RT-DS, G02) so the destination receives the
-- source's chemical condition with the moved fluid. The game's pour action,
-- which pours in slices, is followed once per pour (see the hook below).
require "TLG/Integration/Native"
require "TLG/Integration/World"
require "TLG/Authority/Transactions"
require "TLG/Content/Containers"
require "TLG/Persistence/Migrations"
require "TLG/Authority/Vault"

TLG.Integration.Containers = TLG.Integration.Containers or {}
local C = TLG.Integration.Containers
local Native, World = TLG.Integration.Native, TLG.World
local Supply, Mixing, Aging, Tx = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging, TLG.Authority.Transactions
local Tables = TLG.Tables
local Vault = TLG.Authority.Vault

C.SIDECAR = "tlg"
C.SCHEMA = 1
C.FLOAT_TOLERANCE = 1e-4
-- A record write sets the fluids to the record's composition when any
-- component differs by more than this (litres). Below C.FLOAT_TOLERANCE,
-- since the next read adopts smaller differences from the fluids and drops
-- them; above the precision of native amounts (Java floats, about 2e-6 L at
-- 20 L), since a change too small to store would make the total creep.
C.COMMIT_TOLERANCE = 1e-5

local SIDECAR_FIELDS = { "id", "rev", "deg", "stab", "mic", "t", "storage", "sealed", "cond", "dirty", "label", "prov", "q" }

-- An item lying on the ground can hold its fluid on the world object
-- instead of on the item (BC InventoryItem.getFluidContainerFromSelfOrWorldItem;
-- RT-SP 2026-10-31: a reloaded jerry can on the ground had no item container).
-- The record stays with the item either way: its modData persists with the
-- world item (same run).
function C.ownerOf(fc)
    if fc == nil then return nil end
    local owner = fc:getOwner()
    if owner == nil then return nil end
    if instanceof(owner, "InventoryItem") then return owner, "item" end
    if instanceof(owner, "IsoWorldInventoryObject") and owner:getItem() then return owner:getItem(), "item" end
    if instanceof(owner, "IsoObject") then return owner, "object" end
    return nil
end

function C.fluidOf(owner, kind)
    if kind == "item" and owner.getFluidContainerFromSelfOrWorldItem then
        return owner:getFluidContainerFromSelfOrWorldItem()
    end
    return owner:getFluidContainer()
end

function C.keyOf(owner, kind)
    if kind == "item" then return "item:" .. tostring(owner:getID()) end
    local sq = owner:getSquare()
    return string.format("obj:%d,%d,%d:%s", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1,
        tostring(owner:getObjectIndex()))
end

-- The vault's holder: the item, or the tile of the world object.
function C.holderOf(owner, kind)
    if kind == "item" then return Vault.itemHolder(owner) end
    local sq = owner:getSquare()
    return string.format("obj:%d,%d,%d", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1)
end

local function send(owner, kind)
    if kind == "object" then
        owner:transmitModData()
    elseif owner.syncItemFields then
        owner:syncItemFields()
    end
end

local function storageFor(owner, kind)
    if kind == "item" then return TLG.ContainerProfiles.forItem(owner) end
    return TLG.ContainerProfiles.forObject(owner)
end

-- Largest difference between two compositions in any component (litres).
local function maxDifference(a, b)
    local d = 0
    for id, q in pairs(a) do d = math.max(d, math.abs(q - (b[id] or 0))) end
    for id, q in pairs(b) do d = math.max(d, math.abs(q - (a[id] or 0))) end
    return d
end

-- Builds the committed record for a container; nil when it does not hold
-- TLG-tracked fuel. `persist` allows assigning ids/baselines (authority).
-- A record with untracked inflow comes back advanced to now, any other at
-- its last write; callers advance it to now either way.
function C.read(owner, kind, persist)
    local fc = C.fluidOf(owner, kind)
    if fc == nil then return nil, "no_fluid_container" end
    local comp, foreign = Native.readComposition(fc)
    if foreign > 1e-6 then return nil, "foreign_fluid" end
    local raw = Vault.guard("supply", function() return C.holderOf(owner, kind) end, owner:getModData(), C.SIDECAR,
        function() send(owner, kind) end)
    -- Newer (unknown) schemas stay untouched and read-only (docs/migrations.md).
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", raw)
    if raw ~= nil and side == nil then return nil, schemaStatus end
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
    if maxDifference(comp, rec.q) <= C.FLOAT_TOLERANCE then
        rec.q = Tables.copy(comp)
        Supply.normalize(rec)
        rec.cap = cap
        return rec, "ok"
    end
    local base, at = { deg = 0, mic = 0 }, nil
    for id, q in pairs(comp) do
        if q > (rec.q[id] or 0) + 1e-6 then base, at = C.inflowAt(); break end
    end
    local reconciled, info = Tx.reconcile(rec, { comp = comp }, base, nil, at)
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

-- Untracked inflow mixes in when it is found: the baseline above, into the
-- record advanced to now (Tx.reconcile's `at`), so it is not aged again
-- over the time it went unseen. Returns Tx.reconcile's baseline and `at`.
function C.inflowAt()
    return { deg = C.untrackedDeg(), mic = 0 }, { now = World.now(), env = World.env() }
end

function C.writeSidecar(owner, kind, rec)
    local side = { v = C.SCHEMA }
    for _, f in ipairs(SIDECAR_FIELDS) do side[f] = Tables.deepCopy(rec[f]) end
    owner:getModData()[C.SIDECAR] = side
    Vault.put("supply", function() return C.holderOf(owner, kind) end, side)
    send(owner, kind)
end

-- Writes the record and sets the container's fluids to its composition
-- where they differ, or `always` (a write that moves litres). D-007: the
-- fluids carry the composition through every native transfer. Aging turns
-- fuel into water; written to the record alone, that water was dropped by
-- the next read, which takes the fluids as they are. Both get what the
-- container can hold (Native.holdable), so they agree; the litres stay the
-- same, as aging keeps a liquid's total. Returns false, why when the fluids
-- could not be set, the record left as it was.
function C.commit(owner, kind, rec, always)
    local held = Supply.copy(rec)
    held.q = Native.holdable(rec.q)
    Supply.normalize(held)
    local fc = C.fluidOf(owner, kind)
    if fc and (always or maxDifference(Native.readComposition(fc), held.q) > C.COMMIT_TOLERANCE) then
        local ok, why = Native.writeComposition(fc, held.q)
        if not ok then
            TLG.Log.error("container %s: fluids not set to its record: %s", C.keyOf(owner, kind), tostring(why))
            return false, why
        end
    end
    C.writeSidecar(owner, kind, held)
    return true
end

-- Endpoint for TLG-initiated transactions (moves native quantity too).
-- `readStatus` is the last read's status ("initialized": fuel the mod had
-- not recorded, given its baseline); `record` writes the record and its
-- composition, never moving litres (a look records what it finds, D-024).
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
        local rec, status = C.read(owner, kind, true)
        self.readStatus = status
        return rec
    end
    function ep:write(rec)
        return C.commit(owner, kind, rec, true)
    end
    function ep:record(rec)
        return C.commit(owner, kind, rec)
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
    C.commit(srcOwner, srcKind, newSrc)
    C.commit(dstOwner, dstKind, merged)
    return newSrc, merged
end

-- The record's revision as stored on the owner; -1 when it has none.
local function revOf(owner)
    local side = owner:getModData()[C.SIDECAR]
    return type(side) == "table" and side.rev or -1
end

-- What following a pour needs, read before it: both records and the
-- source's fluids. Nil when the mod does not follow it (no owner, no fuel
-- of the mod's in the source, another fluid in the target).
local function prepare(a, b)
    local ao, ak = C.ownerOf(a)
    local bo, bk = C.ownerOf(b)
    if not ao or not bo then return nil end
    local srcRec = C.read(ao, ak, true)
    if not srcRec or Supply.isEmpty(srcRec) then return nil end
    local dstRec = C.read(bo, bk, true)
    if not dstRec then return nil end
    return { a = a, ao = ao, ak = ak, bo = bo, bk = bk, src = srcRec, dst = dstRec,
        before = Native.readComposition(a), revs = { revOf(ao), revOf(bo) } }
end

-- Follows what left the source since `prepare`. When either record was
-- written in between, the records `prepare` read are out of date: the
-- litres are left to the next read, as fuel the mod did not see arrive.
local function follow(c)
    local parcel, moved = subtract(c.before, Native.readComposition(c.a))
    if moved <= 1e-7 then return end
    if revOf(c.ao) ~= c.revs[1] or revOf(c.bo) ~= c.revs[2] then
        TLG.Log.warn("pour of %.4f L into %s not followed: a record was written during it", moved,
            C.keyOf(c.bo, c.bk))
        return
    end
    C.followNativeTransfer(c.ao, c.ak, c.src, c.bo, c.bk, c.dst, parcel)
end

-- The game's pour action (ISFluidTransferAction, used by the Transfer
-- Liquid window) pours one slice per update and the rest when it completes
-- (SRC ISFluidTransferAction.lua:29,73): about 0.02 L a slice, 190 calls
-- for 3.79 L (RT-SP run 213). Followed slice by slice, a component under
-- Native.MIN_FLUID in a slice went to the largest component of a target
-- without it, so fuel with less than about 1 % water or sediment arrived
-- without them (run 213). While the action's update or complete runs, its
-- own slices go to the game alone; the whole pour is followed once, when
-- the action completes or is stopped, from the records as they were before
-- its first slice. A multiplayer client moves nothing (SRC :25,
-- `not isClient()`); the server calls the action's complete and never its
-- update (engine-capabilities.md, timed actions on a server), so a pour
-- there is one call.
local active = nil -- { action, a, b } while an action's update or complete runs

local function transferHook(a, b, amount, ...)
    if not World.isAuthority() or a == nil or b == nil then
        return originalTransfer(a, b, amount, ...)
    end
    if active and a == active.a and b == active.b then
        local action = active.action
        if action.tlgPour == nil then
            local ok, p = pcall(prepare, a, b)
            if not ok then TLG.Log.error("pour action prepare: %s", tostring(p)) end
            action.tlgPour = ok and p or false
        end
        return originalTransfer(a, b, amount, ...)
    end
    local ok, ctxOrErr = pcall(prepare, a, b)
    local res = originalTransfer(a, b, amount, ...)
    if ok and ctxOrErr then
        local ok2, err = pcall(follow, ctxOrErr)
        if not ok2 then TLG.Log.error("transfer hook: %s", tostring(err)) end
    elseif not ok then
        TLG.Log.error("transfer hook prepare: %s", tostring(ctxOrErr))
    end
    return res
end

-- Runs one of the action's methods with its own slices left to the game.
local function asPour(orig, action, ...)
    local ok, a, b = pcall(function()
        return action.source:getFluidContainer(), action.target:getFluidContainer()
    end)
    if not ok or a == nil or b == nil then return orig(action, ...) end
    local outer = active
    active = { action = action, a = a, b = b }
    local done, res = pcall(orig, action, ...)
    active = outer
    if not done then error(res, 0) end
    return res
end

local function finishPour(action)
    local p = action.tlgPour
    action.tlgPour = false
    if p then
        local ok, err = pcall(follow, p)
        if not ok then TLG.Log.error("pour action: %s", tostring(err)) end
    end
end

-- Wraps the pour action's class (`cls`: ISFluidTransferAction in the game,
-- a stand-in in the tests).
function C.installPourAction(cls)
    local update, complete, stop = cls.update, cls.complete, cls.stop
    function cls:update(...) return asPour(update, self, ...) end
    function cls:complete(...)
        local res = asPour(complete, self, ...)
        finishPour(self)
        return res
    end
    function cls:stop(...)
        finishPour(self)
        return stop(self, ...)
    end
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
    local A = ISFluidTransferAction
    if A and A.update and A.complete and A.stop then
        C.installPourAction(A)
        TLG.Log.info("container adapter: the game's pour action followed once per pour")
    else
        TLG.Log.warn("ISFluidTransferAction not found; its pours are followed slice by slice")
    end
end

function C.originalTransfer()
    return originalTransfer or FluidContainer.Transfer
end

return C
