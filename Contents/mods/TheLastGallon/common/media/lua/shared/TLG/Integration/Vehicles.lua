-- Adapter: vehicle fuel tank (VehiclePart "GasTank").
--
--   quantity owner     native part content amount (float litres)
--   composition owner  TLG sidecar (part modData "tlg")
--   consumption owner  native engine (Java); TLG never subtracts fuel
--   replication        vehicle:transmitPartModData(part)
--   reconciliation     native decrease (driving, idling, siphoning by code TLG
--                      did not see) leaves proportionally; unknown increase is
--                      untracked inflow at the pessimistic baseline (D-006)
--   effects            start/stall/power from ConsumerService; applied through
--                      per-instance engine controls only (G09 verified RT-SP;
--                      start gate and stall NOT RUN)
--   runtime status     refuel, siphon and idle-burn reconciliation verified
--                      RT-SP 2026-10-31
--
-- Vanilla actions mutate the tank incrementally in update() on the
-- authoritative side and finish in complete() (SRC ISAddGasolineToVehicle.lua),
-- so hooks snapshot at construction and settle once at complete/stop.
require "TLG/Integration/Containers"
require "TLG/Boot"

TLG.Integration.Vehicles = TLG.Integration.Vehicles or {}
local V = TLG.Integration.Vehicles
local C, Native, World = TLG.Integration.Containers, TLG.Integration.Native, TLG.World
local Supply, Mixing, Aging, Tx, Consumers = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging,
    TLG.Authority.Transactions, TLG.Domain.Consumers
local Tables = TLG.Tables

V.SIDECAR = "tlg"
V.DEFAULT_PROFILE = "engine_si_stock"

function V.tank(vehicle)
    return vehicle and vehicle:getPartById("GasTank") or nil
end

function V.keyOf(vehicle)
    return "veh:" .. tostring(vehicle:getSqlId()) .. ":" .. tostring(vehicle:getScriptName())
end

-- Stock profile of this engine (before any conversion).
function V.baseProfile(vehicle)
    local engine = vehicle:getPartById("Engine")
    local md = engine and engine:getModData().tlg
    return (md and md.profile) or V.DEFAULT_PROFILE
end

-- Effective profile: a Commissioned conversion for this exact engine wins
-- (ConversionService.effectiveProfile), otherwise the stock profile.
function V.profile(vehicle)
    local CD = TLG.Integration.ConversionDevices
    if CD then
        local md = CD.vehicleStore(vehicle)
        if md and md[CD.KEY] then
            local device = CD.describeVehicle(vehicle, false)
            local p = CD.effective(md, device)
            if p then return p end
        end
    end
    return V.baseProfile(vehicle)
end

function V.read(vehicle, persist)
    local part = V.tank(vehicle)
    if part == nil then return nil, "no_tank" end
    local amount = part:getContainerContentAmount()
    local cap = part:getContainerCapacity()
    local raw = part:getModData()[V.SIDECAR]
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", raw)
    if raw ~= nil and side == nil then return nil, schemaStatus end
    if side == nil then
        local rec
        if amount <= 1e-6 then
            rec = Supply.new({ storage = "vehicle_tank", cap = cap, t = World.now() })
        else
            rec = World.baseline(V.keyOf(vehicle), { storage = "vehicle_tank", cap = cap, q = { gasoline = amount } })
        end
        rec.cap = cap
        if persist then rec.id = World.newId("V") end
        return rec, "initialized"
    end
    local rec = Supply.new({ storage = "vehicle_tank", cap = cap, t = side.t, cond = side.cond, stab = side.stab,
        mic = side.mic, label = side.label })
    rec.id, rec.rev = side.id, side.rev or 0
    for id, q in pairs(side.q or {}) do rec.q[id] = q end
    for id, d in pairs(side.deg or {}) do rec.deg[id] = d end
    rec.prov = Tables.deepCopy(side.prov or {})
    local primary = Supply.primary(rec) or "gasoline"
    local base = { deg = 0, mic = 0 }
    if amount > Supply.total(rec) + 1e-4 then base.deg = C.untrackedDeg() end
    -- Native stores floats; tolerate float precision before calling it a change.
    if math.abs(amount - Supply.total(rec)) <= 1e-4 then return rec, "ok" end
    local out, info = Tx.reconcile(rec, { total = amount }, base, primary)
    out.cap = cap
    return out, "reconciled", info
end

function V.writeSidecar(vehicle, rec)
    local part = V.tank(vehicle)
    local side = { v = C.SCHEMA }
    for _, f in ipairs({ "id", "rev", "deg", "stab", "mic", "t", "cond", "label", "prov", "q" }) do
        side[f] = Tables.deepCopy(rec[f])
    end
    part:getModData()[V.SIDECAR] = side
    vehicle:transmitPartModData(part)
end

-- Endpoint for TLG-initiated transfers: TLG sets the native amount too.
function V.endpoint(vehicle)
    local ep = { key = V.keyOf(vehicle), consumer = V.profile(vehicle) }
    function ep:canAccess(player)
        local part = V.tank(vehicle)
        if part and player and vehicle:isInArea(part:getArea(), player) then return true end
        return false, "not_at_fuel_cap"
    end
    function ep:read() return (V.read(vehicle, true)) end
    function ep:write(rec)
        local part = V.tank(vehicle)
        part:setContainerContentAmount(Supply.total(rec))
        V.writeSidecar(vehicle, rec)
        return true
    end
    return ep
end

------------------------------------------------------------------------------
-- Hooks on vanilla actions
------------------------------------------------------------------------------
local function settleIntoTank(action, srcRec, movedLitres, correctCan)
    local vehicle = action.vehicle
    if vehicle == nil or movedLitres <= 1e-6 then return end
    local now, env = World.now(), World.env()
    local tankRec = Aging.advance((V.read(vehicle, true)), now, env)
    -- The native tank already contains the litres; the sidecar view of the tank
    -- (after reconcile) attributed them as untracked. Rebuild from the
    -- pre-action tank record instead.
    local before = Aging.advance(action.tlgTankBefore, now, env)
    local src = Aging.advance(srcRec, now, env)
    local parcel = Supply.copy(src)
    local frac = movedLitres / math.max(1e-9, Supply.total(src))
    for id, q in pairs(parcel.q) do parcel.q[id] = q * math.min(1, frac) end
    local merged = Mixing.previewBlend({ { supply = before, amount = Supply.total(before) },
        { supply = parcel, amount = Supply.total(parcel) } }, "vehicle_tank", tankRec.cap)
    merged.id, merged.rev, merged.cap, merged.t = before.id or tankRec.id, (tankRec.rev or 0) + 1, tankRec.cap, now
    merged.prov = before.prov
    Supply.addProvenance(merged, { k = "in", from = src.id, t = now, n = movedLitres })
    V.writeSidecar(vehicle, merged)
end

local function wrap(class, method, fn)
    local orig = class[method]
    if orig == nil then return false end
    class[method] = function(self, ...) return fn(orig, self, ...) end
    return true
end

local function installAddGasoline()
    local A = ISAddGasolineToVehicle
    if A == nil then return end
    wrap(A, "new", function(orig, class, character, part, item, otherItems)
        local o = orig(class, character, part, item, otherItems)
        if World.isAuthority() and o and o.vehicle and item and item:getFluidContainer() then
            local ok = pcall(function()
                o.tlgTankBefore = V.read(o.vehicle, true)
                o.tlgCanBefore = C.read(item, "item", true)
                o.tlgTankStart = part:getContainerContentAmount()
            end)
            if not ok then o.tlgTankBefore = nil end
        end
        return o
    end)
    local function settle(self)
        if self.tlgSettled or not self.tlgTankBefore or not self.tlgCanBefore then return end
        self.tlgSettled = true
        local moved = self.part:getContainerContentAmount() - self.tlgTankStart
        local ok, err = pcall(settleIntoTank, self, self.tlgCanBefore, moved)
        if not ok then TLG.Log.error("vehicle refuel settle: %s", tostring(err)) end
    end
    wrap(A, "complete", function(orig, self) local r = orig(self); settle(self); return r end)
    wrap(A, "stop", function(orig, self) if not isClient() then settle(self) end; return orig(self) end)
    wrap(A, "serverStop", function(orig, self) local r = orig(self); settle(self); return r end)
end

-- Siphon: vanilla adds Petrol to the can; correct the can's native fluids to
-- the tank's real composition and carry the tank's condition.
local function installTakeGasoline()
    local A = ISTakeGasolineFromVehicle
    if A == nil then return end
    wrap(A, "new", function(orig, class, character, part, item, otherItems)
        local o = orig(class, character, part, item, otherItems)
        if World.isAuthority() and o and part and item and item:getFluidContainer() then
            pcall(function()
                o.tlgVehicle = part:getVehicle()
                o.tlgTankBefore = V.read(o.tlgVehicle, true)
                o.tlgCanCompBefore = Native.readComposition(item:getFluidContainer())
                o.tlgCanBefore = C.read(item, "item", true)
                o.tlgTankStart = part:getContainerContentAmount()
            end)
        end
        return o
    end)
    local function settle(self)
        if self.tlgSettled or not self.tlgTankBefore or not self.tlgCanBefore then return end
        self.tlgSettled = true
        local ok, err = pcall(function()
            local moved = self.tlgTankStart - self.part:getContainerContentAmount()
            if moved <= 1e-6 then return end
            local now, env = World.now(), World.env()
            local tank = Aging.advance(self.tlgTankBefore, now, env)
            local remaining, parcel = Mixing.removeProportional(tank, moved)
            remaining.rev = (tank.rev or 0) + 1
            V.writeSidecar(self.tlgVehicle, remaining)
            -- Correct native can contents: previous contents + real parcel.
            local fc = self.item:getFluidContainer()
            local comp = Tables.copy(self.tlgCanCompBefore)
            for id, q in pairs(parcel) do comp[id] = (comp[id] or 0) + q end
            Native.writeComposition(fc, comp)
            local can = Aging.advance(self.tlgCanBefore, now, env)
            local p = Supply.copy(tank)
            p.q = parcel
            local merged = Mixing.previewBlend({ { supply = can, amount = Supply.total(can) },
                { supply = p, amount = moved } }, can.storage, can.cap)
            merged.id, merged.rev, merged.cap = can.id, (can.rev or 0) + 1, can.cap
            merged.sealed, merged.cond = can.sealed, can.cond
            C.writeSidecar(self.item, "item", merged)
        end)
        if not ok then TLG.Log.error("siphon settle: %s", tostring(err)) end
    end
    wrap(A, "complete", function(orig, self) local r = orig(self); settle(self); return r end)
    wrap(A, "stop", function(orig, self) if not isClient() then settle(self) end; return orig(self) end)
    wrap(A, "serverStop", function(orig, self) local r = orig(self); settle(self); return r end)
end

------------------------------------------------------------------------------
-- Engine effects (start gate and stall NOT RUN, see engine-capabilities G03)
------------------------------------------------------------------------------
V.STALL_CHANCE_PER_MINUTE = 0.04

function V.evaluate(vehicle)
    local rec = V.read(vehicle, false)
    if rec == nil then return nil end
    local ambient = nil
    pcall(function() ambient = getClimateManager():getTemperature() end)
    return Consumers.evaluate(V.profile(vehicle), rec, { ambientC = ambient })
end

-- Called every in-game minute on the authority for running vehicles.
function V.applyEffects(vehicle, rng)
    if not vehicle:isEngineRunning() then return end
    local e = V.evaluate(vehicle)
    if e == nil or e.grade == "empty" then return end
    local roll = rng and rng:next() or ZombRandFloat(0, 1)
    if not e.compatible or roll < V.STALL_CHANCE_PER_MINUTE * (1 - e.startFactor) then
        vehicle:engineDoStalling()
    end
end

-- Start gate (SRC ISStartVehicleEngine.lua:26-44 calls tryStartEngine on the
-- authoritative side): poor or incompatible fuel can make the engine crank
-- and fail through the vanilla engine state API.
V.startRoll = function() return ZombRandFloat(0, 1) end

local function vehicleStallsEnabled()
    local o = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.VehicleStalls
    return o ~= false
end

local function installStartGate()
    wrap(ISStartVehicleEngine, "complete", function(orig, self)
        local vehicle = self.character and self.character:getVehicle()
        if vehicle and World.isAuthority() and vehicleStallsEnabled() and vehicle:isDriver(self.character) then
            local part = V.tank(vehicle)
            if part and part:getContainerContentAmount() > 0 then
                local ok, e = pcall(V.evaluate, vehicle)
                if ok and e and e.grade ~= "empty" and (not e.compatible or V.startRoll() > e.startFactor) then
                    vehicle:engineDoStartingFailed()
                    TLG.Log.debug("vehicle start refused: %s", table.concat(e.reasons, ","))
                    return true
                end
            end
        end
        return orig(self)
    end)
end

function V.install()
    installAddGasoline()
    installTakeGasoline()
    installStartGate()
    Events.EveryOneMinute.Add(function()
        if not World.isAuthority() then return end
        local cell = getCell()
        if cell == nil then return end
        -- A java.util.HashSet on 42.21 (BC IsoCell.vehicles), so no get(i);
        -- iterated the way vanilla iterates Sets (SRC server/Vehicles/Vehicles.lua:1037).
        -- RT-SP 2026-10-31: get(i) raised "tried to call nil" every minute.
        for _, vehicle in ipairs(cell:getVehicles():toArray()) do
            local ok, err = pcall(V.applyEffects, vehicle)
            if not ok then TLG.Log.debug("vehicle effects: %s", tostring(err)) end
        end
    end)
    TLG.Log.info("vehicle adapter installed")
end

TLG.Boot.addInstaller("vehicles", V.install)

return V
