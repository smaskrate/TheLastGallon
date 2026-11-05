-- Adapter: gas station pumps (IsoObject piped fuel).
-- Runtime status: pump -> can and pump -> vehicle verified RT-SP 2026-10-31
-- (1 L per unit on both paths), and on a dedicated server (RT-MP run 160);
-- the infinite sandbox setting is NOT RUN.
--
--   quantity           native pipedFuelAmount (int units in pump modData,
--                      BC IsoObject.getPipedFuelAmount); TLG convention
--                      1 unit = 1 L, fractional remainder kept in the sidecar
--   composition owner  TLG sidecar (pump modData "tlg"), storage station_ust
--   consumption owner  dispensing actions; TLG corrects the pump amount after
--                      both vanilla paths so every litre delivered removes
--                      exactly one litre (D-010):
--                        ISTakeFuel: 1 unit = 1 L, but complete() ADDS the last
--                        increment to the pump (SRC ISTakeFuel.lua:64-70)
--                        ISRefuelFromGasPump: 1 unit = 1.25 L (Vehicles.JerryCanLitres/8)
--   infinite sandbox   quantity is not corrected (pumps never run out) but the
--                      reservoir still ages and carries contamination
--   replication        transmitModData (vanilla setter does the same)
--   server copy        reads checked against the vault on a server (TLG/Authority/
--                      Vault.lua, holder "pump:x,y,z"; audit V-01)
require "TLG/Integration/Containers"
require "TLG/Integration/Vehicles"
require "TLG/Boot"
require "TLG/Authority/Vault"

TLG.Integration.Stations = TLG.Integration.Stations or {}
local S = TLG.Integration.Stations
local C, V, World = TLG.Integration.Containers, TLG.Integration.Vehicles, TLG.World
local Supply, Mixing, Aging, WorldInit = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging, TLG.Domain.WorldInit
local Tables = TLG.Tables
local Vault = TLG.Authority.Vault

S.LITRES_PER_UNIT = 1.0

-- A pump is an object with piped fuel, or one TLG already manages (restored
-- stations keep working after the original reserve is exhausted). Exhausted
-- pumps TLG never touched are recognised by the vanilla "fuelAmount" modData
-- entry (BC IsoObject.getPipedFuelAmount stores it there; key name NOT RUN).
function S.isPump(obj)
    if obj == nil then return false end
    if obj:getPipedFuelAmount() > 0 then return true end
    local md = obj:hasModData() and obj:getModData() or nil
    return md ~= nil and (md.tlg ~= nil or type(md.fuelAmount) == "number")
end

function S.keyOf(obj)
    local sq = obj:getSquare()
    return string.format("pump:%d,%d,%d", sq and sq:getX() or -1, sq and sq:getY() or -1, sq and sq:getZ() or -1)
end

local function infinite()
    return SandboxVars and SandboxVars.FuelStationGasInfinite == true
end

local function contaminationEnabled()
    local o = SandboxVars and SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.StationContamination
    return o ~= false
end

-- Reservoir record; initialises original station fuel on first contact.
function S.read(obj, persist)
    local units = obj:getPipedFuelAmount()
    local raw = Vault.guard("supply", function() return S.keyOf(obj) end, obj:getModData(), "tlg",
        function() obj:transmitModData() end)
    local side, schemaStatus = TLG.Persistence.Migrations.sidecar("supply", raw)
    if raw ~= nil and side == nil then return nil, schemaStatus end
    local litres = units * S.LITRES_PER_UNIT + ((side and side.frac) or 0)
    if side == nil then
        local key = S.keyOf(obj)
        local q = { gasoline = litres }
        if contaminationEnabled() then
            local c = WorldInit.stationContamination(World.facts(), key, litres)
            q.gasoline = litres - c.water - c.sediment
            q.water, q.sediment = c.water, c.sediment
        end
        local rec = World.baseline(key, { storage = "station_ust", cap = math.max(10000, litres), q = q,
            preAgeMax = WorldInit.MAX_STATION_PRE_AGE })
        if persist then rec.id = World.newId("R") end
        rec.frac = 0
        return rec, "initialized"
    end
    local rec = Supply.new({ storage = "station_ust", cap = side.cap or math.max(10000, litres), t = side.t,
        cond = side.cond, stab = side.stab, mic = side.mic, label = side.label })
    rec.id, rec.rev, rec.frac = side.id, side.rev or 0, side.frac or 0
    for id, q in pairs(side.q or {}) do rec.q[id] = q end
    for id, d in pairs(side.deg or {}) do rec.deg[id] = d end
    rec.prov = Tables.deepCopy(side.prov or {})
    if infinite() then return rec, "infinite" end
    if math.abs(litres - Supply.total(rec)) <= 1e-4 then return rec, "ok" end
    local base, at = { deg = 0, mic = 0 }, nil
    if litres > Supply.total(rec) then base, at = C.inflowAt() end
    local out = TLG.Authority.Transactions.reconcile(rec, { total = litres }, base, "gasoline", at)
    out.frac = rec.frac
    return out, "reconciled"
end

-- Writes sidecar and sets the native unit count (whole units; remainder kept).
function S.write(obj, rec)
    if not infinite() then
        local total = Supply.total(rec)
        local units = math.floor(total / S.LITRES_PER_UNIT + 1e-9)
        rec.frac = total - units * S.LITRES_PER_UNIT
        obj:setPipedFuelAmount(units)
    end
    S.writeSidecar(obj, rec)
end

-- The reservoir's record alone, the pump's units untouched.
function S.writeSidecar(obj, rec)
    local side = { v = C.SCHEMA, cap = rec.cap, frac = rec.frac or 0 }
    for _, f in ipairs({ "id", "rev", "deg", "stab", "mic", "t", "cond", "label", "prov", "q" }) do
        side[f] = Tables.deepCopy(rec[f])
    end
    obj:getModData().tlg = side
    Vault.put("supply", function() return S.keyOf(obj) end, side)
    obj:transmitModData()
end

-- Removes `litres` from the reservoir; returns the delivered parcel record.
local function draw(obj, before, litres)
    local now, env = World.now(), World.env()
    local res = Aging.advance(before, now, env)
    local remaining, parcel = Mixing.removeProportional(res, litres)
    remaining.rev = (res.rev or 0) + 1
    remaining.frac = before.frac
    S.write(obj, remaining)
    local p = Supply.copy(res)
    p.q = parcel
    return p
end

-- Not for a constructor: those keep vanilla's parameters (below). In
-- multiplayer a client sends a timed action's fields named as its new's
-- parameters, read from the function itself (BC NetTimedAction.set), and
-- the server calls new with them. Wrapped as function(self, ...), new
-- declared none, so the server built ISTakeFuel without its pump and the
-- fuel never moved (RT-MP run 156).
local function wrap(class, method, fn)
    local orig = class and class[method]
    if orig == nil then return false end
    class[method] = function(self, ...) return fn(orig, self, ...) end
    return true
end

-- Pump -> can (SRC ISTakeFuel.lua:97, new(character, fuelStation, petrolCan)).
local function installTakeFuel()
    local orig = ISTakeFuel and ISTakeFuel.new
    if orig == nil then return end
    ISTakeFuel.new = function(class, character, fuelStation, petrolCan)
        local o = orig(class, character, fuelStation, petrolCan)
        if World.isAuthority() and o and fuelStation and petrolCan and petrolCan:getFluidContainer() then
            pcall(function()
                o.tlgPumpBefore = S.read(fuelStation, true)
                o.tlgCanBefore = C.read(petrolCan, "item", true)
                o.tlgCanStart = petrolCan:getFluidContainer():getAmount()
            end)
        end
        return o
    end
    local function settle(self)
        if self.tlgSettled or not self.tlgPumpBefore or not self.tlgCanBefore then return end
        self.tlgSettled = true
        local ok, err = pcall(function()
            local fc = self.petrolCan:getFluidContainer()
            local delivered = fc:getAmount() - self.tlgCanStart
            if delivered <= 1e-6 then return end
            local parcel = draw(self.fuelStation, self.tlgPumpBefore, delivered)
            local can = Aging.advance(self.tlgCanBefore, World.now(), World.env())
            local merged = Mixing.previewBlend({ { supply = can, amount = Supply.total(can) },
                { supply = parcel, amount = Supply.total(parcel) } }, can.storage, can.cap)
            merged.id, merged.rev, merged.cap, merged.sealed, merged.cond = can.id, (can.rev or 0) + 1, can.cap,
                can.sealed, can.cond
            Supply.addProvenance(merged, { k = "pump", from = parcel.id, t = World.now(), n = delivered })
            -- The can's fluids become the record's: the station's water and
            -- sediment with its petrol, and the water the can's fuel took up.
            C.commit(self.petrolCan, "item", merged)
        end)
        if not ok then TLG.Log.error("pump->can settle: %s", tostring(err)) end
    end
    wrap(ISTakeFuel, "complete", function(orig, self) local r = orig(self); settle(self); return r end)
    wrap(ISTakeFuel, "stop", function(orig, self) if not isClient() then settle(self) end; return orig(self) end)
    wrap(ISTakeFuel, "serverStop", function(orig, self) local r = orig(self); settle(self); return r end)
end

-- Pump -> vehicle (SRC ISRefuelFromGasPump.lua:108, new(character, part,
-- fuelStation)).
local function installRefuelFromPump()
    local orig = ISRefuelFromGasPump and ISRefuelFromGasPump.new
    if orig == nil then return end
    ISRefuelFromGasPump.new = function(class, character, part, fuelStation)
        local o = orig(class, character, part, fuelStation)
        if World.isAuthority() and o and part and fuelStation then
            pcall(function()
                o.tlgPumpBefore = S.read(fuelStation, true)
                o.tlgTankBefore = V.read(part:getVehicle(), true)
                o.tlgTankStart = part:getContainerContentAmount()
            end)
        end
        return o
    end
    local function settle(self)
        if self.tlgSettled or not self.tlgPumpBefore or not self.tlgTankBefore then return end
        self.tlgSettled = true
        local ok, err = pcall(function()
            local delivered = self.part:getContainerContentAmount() - self.tlgTankStart
            if delivered <= 1e-6 then return end
            local parcel = draw(self.fuelStation, self.tlgPumpBefore, delivered)
            local now, env = World.now(), World.env()
            local before = Aging.advance(self.tlgTankBefore, now, env)
            local merged = Mixing.previewBlend({ { supply = before, amount = Supply.total(before) },
                { supply = parcel, amount = Supply.total(parcel) } }, "vehicle_tank", before.cap)
            merged.id, merged.rev, merged.cap = before.id, (before.rev or 0) + 1, before.cap
            Supply.addProvenance(merged, { k = "pump", from = parcel.id, t = now, n = delivered })
            V.writeSidecar(self.part:getVehicle(), merged)
        end)
        if not ok then TLG.Log.error("pump->vehicle settle: %s", tostring(err)) end
    end
    wrap(ISRefuelFromGasPump, "complete", function(orig, self) local r = orig(self); settle(self); return r end)
    wrap(ISRefuelFromGasPump, "stop", function(orig, self) if not isClient() then settle(self) end; return orig(self) end)
    wrap(ISRefuelFromGasPump, "serverStop", function(orig, self) local r = orig(self); settle(self); return r end)
end

function S.install()
    installTakeFuel()
    installRefuelFromPump()
    TLG.Log.info("station adapter installed")
end

TLG.Boot.addInstaller("stations", S.install)

return S
