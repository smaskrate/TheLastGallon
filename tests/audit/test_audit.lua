-- Security audit tests (2026-11-05): what the mod's authority code does with
-- requests a modified client can send. Game objects are mocks
-- (tests/audit/mocks.lua): these results describe the mod's logic alone; the
-- engine's part (what a client can send, what the server applies) is shown
-- by the multiplayer harness case (TLGHarness/AuditCases.lua) and by the
-- bytecode notes in docs/security-audit-2026-11-05.md.
-- Run: tools\run-tests.ps1 -Entry tests/audit/run_audit.lua
require "audit/mocks"
require "TLG/Authority/Handlers"
require "TLG/Authority/MachineHandlers"
require "TLG/Authority/ConversionHandlers"
-- These tests move petrol from pumps into petrol cars. Since 0.2.0 about one
-- pump in four is drawn as diesel from the world's seed (D-036), and the
-- pump->car case drew one: diesel into a petrol car is refused as
-- incompatible. As in the multiplayer harness (MPServer.lua), no pump here
-- gives diesel.
require "TLG/Domain/WorldInit"
TLG.Domain.WorldInit.STATION_DIESEL_SHARE = 0

local M = AUD
local H = TLG.Authority.Handlers
local S, C, G, V = TLG.Integration.Stations, TLG.Integration.Containers, TLG.Integration.Generators,
    TLG.Integration.Vehicles
local Supply = TLG.Domain.Supply

local function pumpAt(x, y, units)
    local sq = M.square(x, y, 0)
    return sq:add(M.object("IsoObject", { piped = units }))
end

local function generatorAt(x, y, fuel)
    local sq = M.square(x, y, 0)
    return sq:add(M.object("IsoGenerator", { fuel = fuel or 0, maxFuel = 10 }))
end

local function refFor(obj, kind) return TLG.Authority.Resolver.refForObject(obj, kind) end

local nextReq = 0
local function rid()
    nextReq = nextReq + 1
    return "aud-" .. nextReq
end

M.ensureWorld()

------------------------------------------------------------------------------
-- AUD-1 (V-02): "status" had no reach check; every other command has one.
-- After the fix it answers within reach (a vehicle also from a seat in it)
-- and refuses from afar, as sample and treat do.
------------------------------------------------------------------------------
T.case("audit V-02 fixed: status refuses a vehicle out of reach, answers at the cap and from a seat", function()
    local v = M.vehicle(7, 100, 100, 40, 20)
    local far = M.player("far", M.square(150, 150, 0))
    local idsBefore = TLG.World.server().nextId
    local r = H.dispatch(far, "status", { requestId = rid(), target = { kind = "vehicle", id = 7 } })
    T.eq(r.ok, false, "status out of reach")
    T.eq(r.reason, "no_access")
    T.eq(r.detail, "not_at_fuel_cap")
    T.eq(r.total, nil, "no fuel figures in a refusal")
    T.eq(r.evaluation, nil, "no engine evaluation in a refusal")
    T.eq(TLG.World.server().nextId, idsBefore, "a refused status creates no record")
    local s = H.dispatch(far, "sample", { requestId = rid(), target = { kind = "vehicle", id = 7 }, method = "visual" })
    T.eq(s.reason, "no_access")
    local tr = H.dispatch(far, "treat", { requestId = rid(), target = { kind = "vehicle", id = 7 }, op = "seal" })
    T.eq(tr.reason, "no_access")
    -- The legitimate reads still work: beside the cap, and seated in the car.
    local atCap = M.player("atcap", M.square(101, 100, 0))
    local ok1 = H.dispatch(atCap, "status", { requestId = rid(), target = { kind = "vehicle", id = 7 } })
    T.ok(ok1.ok, "status at the cap: " .. tostring(ok1.reason))
    T.near(ok1.total, 20, 1e-6)
    T.ok(ok1.evaluation ~= nil and ok1.evaluation.grade ~= nil, "the engine's evaluation is returned")
    local seated = M.player("driver", M.square(130, 130, 0))
    seated.getVehicle = function() return v end
    local ok2 = H.dispatch(seated, "status", { requestId = rid(), target = { kind = "vehicle", id = 7 } })
    T.ok(ok2.ok, "status from a seat: " .. tostring(ok2.reason))
    -- A seat is for reading only: sample and treat still need the cap.
    local s2 = H.dispatch(seated, "sample", { requestId = rid(), target = { kind = "vehicle", id = 7 }, method = "visual" })
    T.eq(s2.reason, "no_access")
    -- A seat in another car does not count.
    local other = M.vehicle(17, 300, 300, 40, 5)
    local elsewhere = M.player("elsewhere", M.square(300, 301, 0))
    elsewhere.getVehicle = function() return other end
    local r3 = H.dispatch(elsewhere, "status", { requestId = rid(), target = { kind = "vehicle", id = 7 } })
    T.eq(r3.reason, "no_access")
end)

T.case("audit V-02 fixed: status refuses a pump and a generator out of reach, answers beside them", function()
    local pump = pumpAt(10, 10, 4000)
    local gen = generatorAt(12, 12, 6)
    local far = M.player("far2", M.square(60, 60, 0))
    local r = H.dispatch(far, "status", { requestId = rid(), target = refFor(pump, "pump") })
    T.eq(r.reason, "no_access", "pump status out of reach")
    T.eq(r.total, nil)
    local g = H.dispatch(far, "status", { requestId = rid(), target = refFor(gen, "generator") })
    T.eq(g.reason, "no_access", "generator status out of reach")
    T.eq(g.total, nil)
    local near = M.player("near2", M.square(11, 11, 0))
    local rp = H.dispatch(near, "status", { requestId = rid(), target = refFor(pump, "pump") })
    T.ok(rp.ok, "pump status beside it: " .. tostring(rp.reason))
    T.ok(rp.total > 3990, "reservoir litres returned")
    local rg = H.dispatch(near, "status", { requestId = rid(), target = refFor(gen, "generator") })
    T.ok(rg.ok, "generator status beside it: " .. tostring(rg.reason))
    T.near(rg.total, 6, 1e-6)
    -- Not changed (hardening left open): an unknown id still answers
    -- unknown_target, so whether a vehicle id exists can still be told.
    local none = H.dispatch(far, "status", { requestId = rid(), target = { kind = "vehicle", id = 999 } })
    T.eq(none.reason, "unknown_target")
end)

------------------------------------------------------------------------------
-- AUD-3: "transfer" accepts any pair of endpoints; no power, no action.
------------------------------------------------------------------------------
T.case("audit: transfer moves pump fuel into a car and a can with no power check and no timed action", function()
    local pump = pumpAt(20, 20, 1000)
    local v = M.vehicle(8, 21, 21, 40, 0)
    local p = M.player("pumper", M.square(21, 22, 0))
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, {}))
    local r = H.dispatch(p, "transfer", { requestId = rid(), source = refFor(pump, "pump"),
        destination = { kind = "vehicle", id = 8 }, amount = 10 })
    T.ok(r.ok, "pump->car: " .. tostring(r.reason) .. " " .. tostring(r.detail))
    T.near(r.moved, 10, 1e-6)
    T.near(v.parts.GasTank.amount, 10, 1e-6, "native tank set by the mod")
    T.eq(pump.piped, 990, "pump units lowered")
    -- Bounded only by the destination's room: one request fills the tank.
    local r2 = H.dispatch(p, "transfer", { requestId = rid(), source = refFor(pump, "pump"),
        destination = { kind = "vehicle", id = 8 }, amount = 100000 })
    T.ok(r2.ok, tostring(r2.reason))
    T.near(v.parts.GasTank.amount, 40, 1e-6)
    local r3 = H.dispatch(p, "transfer", { requestId = rid(), source = refFor(pump, "pump"),
        destination = { kind = "item", id = can:getID() }, amount = 5 })
    T.ok(r3.ok, "pump->can: " .. tostring(r3.reason))
    T.near(can.fc:getAmount(), 5, 1e-6, "the can's native fluids set by the mod")
    -- The same request id again is answered from the ledger, nothing moves.
    local again = H.dispatch(p, "transfer", { requestId = "aud-" .. nextReq, source = refFor(pump, "pump"),
        destination = { kind = "item", id = can:getID() }, amount = 5 })
    T.ok(again.duplicate, "replay flagged")
    T.near(can.fc:getAmount(), 5, 1e-6)
end)

T.case("audit: transfer drains a generator and siphons a car from beside them, whoever placed them", function()
    local gen = generatorAt(30, 30, 8)
    local v = M.vehicle(9, 33, 30, 40, 30)
    local p = M.player("thief", M.square(31, 31, 0))
    local can = p.inv:AddItem(M.item("Base.JerryCan", 20, {}))
    local r = H.dispatch(p, "transfer", { requestId = rid(), source = refFor(gen, "generator"),
        destination = { kind = "item", id = can:getID() }, amount = 100 })
    T.ok(r.ok, "generator->can: " .. tostring(r.reason))
    T.near(gen.fuel, 0, 1e-6, "generator emptied")
    local far = M.player("thief2", M.square(31, 31, 0))
    local s = H.dispatch(far, "transfer", { requestId = rid(), source = { kind = "vehicle", id = 9 },
        destination = { kind = "item", id = can:getID() }, amount = 5 })
    T.eq(s.reason, "no_access_source", "a car needs the player at its filler cap")
    local near = M.player("thief3", M.square(33, 31, 0))
    local can2 = near.inv:AddItem(M.item("Base.JerryCan", 20, {}))
    local s2 = H.dispatch(near, "transfer", { requestId = rid(), source = { kind = "vehicle", id = 9 },
        destination = { kind = "item", id = can2:getID() }, amount = 100 })
    T.ok(s2.ok, "car->can at the cap: " .. tostring(s2.reason))
    T.near(v.parts.GasTank.amount, 10, 1e-6, "20 L siphoned at once")
end)

------------------------------------------------------------------------------
-- AUD-5: infinite station: the record drains while the pump does not, and
-- the vanilla take-fuel wrapper then takes the delivered litres away.
------------------------------------------------------------------------------
T.case("audit: with FuelStationGasInfinite the reservoir record is drained by transfers while units stay", function()
    SandboxVars.FuelStationGasInfinite = true
    local pump = pumpAt(40, 40, 500)
    local p = M.player("infinite", M.square(41, 41, 0))
    local moved, n = 0, 0
    while n < 80 do
        n = n + 1
        local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, {}))
        local r = H.dispatch(p, "transfer", { requestId = rid(), source = refFor(pump, "pump"),
            destination = { kind = "item", id = can:getID() }, amount = 10 })
        if not r.ok then break end
        moved = moved + r.moved
    end
    local rec, status = S.read(pump, true)
    T.eq(status, "infinite")
    T.ok(Supply.total(rec) < 1e-6, "record drained: " .. tostring(Supply.total(rec)))
    T.eq(pump.piped, 500, "units untouched (infinite)")
    T.ok(moved > 490, "litres moved " .. tostring(moved))
    SandboxVars.FuelStationGasInfinite = false
end)

T.case("audit: a vanilla pump->can dispense on a drained reservoir record loses the delivered petrol", function()
    SandboxVars.FuelStationGasInfinite = true
    -- Vanilla's action, as the station adapter wraps it (Stations.install).
    ISTakeFuel = { new = function(class, character, fuelStation, petrolCan)
        return setmetatable({ character = character, fuelStation = fuelStation, petrolCan = petrolCan }, { __index = class })
    end, complete = function(self) return true end, stop = function() end, serverStop = function() end }
    S.install()
    local pump = pumpAt(50, 50, 500)
    local p = M.player("victim", M.square(51, 51, 0))
    -- The reservoir record already drained (by transfers, as above).
    local drained = S.read(pump, true)
    drained.q = {}
    S.write(pump, drained)
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, {}))
    local action = ISTakeFuel:new(p, pump, can)
    T.ok(action.tlgPumpBefore ~= nil, "the wrapper took its snapshot")
    -- Vanilla dispenses 5 L of Petrol into the can during the action.
    can.fc:addFluid(Fluid.Petrol, 5)
    T.near(can.fc:getAmount(), 5, 1e-6)
    action:complete()
    T.near(can.fc:getAmount(), 0, 1e-6, "the settle wrote the empty record's composition over the can: petrol gone")
    SandboxVars.FuelStationGasInfinite = false
end)

------------------------------------------------------------------------------
-- AUD-4 (mod side, V-01): a project written into a generator's mod data is
-- honoured where there is no server copy (single player, or a server whose
-- store did not load). On a server the vault checks it: cases at the end.
------------------------------------------------------------------------------
T.case("audit V-01 (no server copy): a Commissioned project forged in generator mod data changes the engine profile", function()
    local gen = generatorAt(70, 70, 0)
    T.eq(G.profile(gen), "generator_si_stock")
    local md = gen:getModData()
    md.tlgDeviceId, md.tlgEngineId = "AUDIT-D", "AUDIT-E"
    md.tlgConv = {
        v = 1, id = "AUDIT-C", rev = 1, conversion = "flex_generator", state = "Commissioned", t = 0,
        snap = { targetConsumerProfile = "generator_si_flex", fuelStorageChanges = {}, cargoAndWeightImpact = {},
            visualConfiguration = {}, workStages = {}, requiredModules = {}, requiredTools = {},
            reversalAndSalvageRules = {} },
        hours = {}, delivered = {}, workers = {}, credit = {}, deviceKey = "gen:AUDIT-D",
        chassis = "Base.Generator", deviceKind = "generator", engineId = "AUDIT-E",
        originalProfile = "generator_si_stock", commissionedAt = 0,
    }
    T.eq(G.profile(gen), "generator_si_flex", "no parts, no work, no skill: the forged record is enough")
    -- A profile id that does not exist makes every evaluation of it raise.
    md.tlgConv.snap.targetConsumerProfile = "no_such_profile"
    T.raises(function() G.evaluate(gen) end, "unknown id")
end)

T.case("audit V-01 (no server copy): a fuel sidecar forged in item mod data is read back as fuel condition", function()
    local p = M.player("forger", M.square(80, 80, 0))
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, { Petrol = 10 }))
    local rec = C.read(can, "item", true)
    T.ok(rec.deg.gasoline > 0, "found petrol has a baseline age: " .. tostring(rec.deg.gasoline))
    C.commit(can, "item", rec)
    can.md.tlg.deg.gasoline = 0
    can.md.tlg.stab = 2
    local again = C.read(can, "item", true)
    T.eq(again.deg.gasoline, 0)
    T.eq(again.stab, 2)
end)

------------------------------------------------------------------------------
-- Input shapes a modified client can send.
------------------------------------------------------------------------------
T.case("audit: malformed references and amounts are refused without raising", function()
    local p = M.player("fuzzer", M.square(90, 90, 0))
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, { Petrol = 5 }))
    local pump = pumpAt(90, 91, 100)
    local function tx(extra)
        local req = { requestId = rid(), source = refFor(pump, "pump"), destination = { kind = "item", id = can:getID() },
            amount = 1 }
        for k, v in pairs(extra) do req[k] = v end
        return H.dispatch(p, "transfer", req)
    end
    T.eq(tx({ amount = 0 / 0 }).reason, "invalid_amount")
    T.eq(tx({ amount = -5 }).reason, "invalid_amount")
    T.eq(tx({ amount = "5" }).reason, "invalid_amount")
    T.eq(tx({ amount = 1e9 }).reason, "invalid_amount")
    T.eq(tx({ requestId = string.rep("x", 65) }).reason, "malformed_request_id")
    T.eq(tx({ requestId = 12 }).reason, "malformed_request_id")
    T.eq(tx({ source = "pump" }).reason, "malformed_source")
    T.eq(tx({ source = { kind = "pump", x = 1 / 0, y = 91, z = 0, index = 0 } }).reason, "unknown_source")
    T.eq(tx({ source = { kind = "pump", x = 90, y = 91, z = 0, index = 7 } }).reason, "unknown_source")
    T.eq(tx({ source = { kind = "item", id = 1 / 0 } }).reason, "unknown_source")
    T.eq(tx({ destination = { kind = "vehicle", id = 0 / 0 } }).reason, "unknown_destination")
    T.eq(H.dispatch(p, "nope", { requestId = rid() }).reason, "unknown_command")
    T.eq(H.dispatch(p, "treat", { requestId = rid(), op = "rawset", target = { kind = "item", id = can:getID() } }).reason,
        "unknown_operation")
    -- A non-table args value: the dispatcher raises, which Net.lua's pcall
    -- turns into a server_error reply (the transport's responsibility).
    T.raises(function() H.dispatch(p, "treat", 5) end)
    T.eq(H.dispatch(p, "treat", "x").reason, "unknown_operation")
end)

T.case("audit: a conversion request with an unknown conversion id is refused, not raised", function()
    local gen = generatorAt(95, 95, 0)
    local p = M.player("conv", M.square(96, 96, 0))
    local r = H.dispatch(p, "conversion.begin", { requestId = rid(), device = refFor(gen, "generator"),
        conversion = "flex_rocket" })
    T.eq(r.ok, false)
    T.eq(r.reason, "unknown_conversion")
    local r2 = H.dispatch(p, "conversion.begin", { requestId = rid(), device = refFor(gen, "generator"),
        conversion = 5 })
    T.eq(r2.reason, "malformed_request")
end)

------------------------------------------------------------------------------
-- Ledger bound: an old request id runs again once 64 newer ones came.
------------------------------------------------------------------------------
T.case("audit: the per-actor ledger forgets a request after 64 later ones", function()
    local p = M.player("replayer", M.square(110, 110, 0))
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, { Petrol = 5 }))
    local target = { kind = "item", id = can:getID() }
    local first = H.dispatch(p, "sample", { requestId = "replay-0", target = target, method = "visual" })
    T.ok(first.ok)
    T.ok(H.dispatch(p, "sample", { requestId = "replay-0", target = target, method = "visual" }).duplicate)
    for i = 1, 64 do
        H.dispatch(p, "sample", { requestId = "replay-" .. i, target = target, method = "visual" })
    end
    local again = H.dispatch(p, "sample", { requestId = "replay-0", target = target, method = "visual" })
    T.eq(again.duplicate, nil, "executed again")
end)

------------------------------------------------------------------------------
-- Robustness: a record whose time lies far in the past costs one climate
-- segment per world day between then and now, with no bound.
------------------------------------------------------------------------------
T.case("audit: a sidecar dated 1e6 hours ago builds over 40000 climate segments on one read", function()
    local env = TLG.World.env()
    local rec = Supply.new({ storage = "jerrycan_steel", cap = 20, q = { gasoline = 10 }, t = M.now - 1e6 })
    local segs = env:segments(rec.t, M.now, "sheltered")
    T.ok(#segs > 40000, "segments: " .. tostring(#segs))
    local out = TLG.Domain.Aging.advance(rec, M.now, env)
    T.ok(out.t == M.now)
end)

------------------------------------------------------------------------------
-- AUD-2 (V-03): the world record in global ModData is sent to any client
-- that asks for it. After the fix the fields only the authority uses (seed,
-- next id, machine squares, today's climate sums) live in the server store
-- (server/TLG/Server/WorldStore.lua attaches it); here a plain table stands
-- in for the store's mod data.
------------------------------------------------------------------------------
T.case("audit V-03 fixed: the server store takes the seed, ids, machine sites and climate sums", function()
    local World, WorldInit = TLG.World, TLG.Domain.WorldInit
    local md = World.get()
    local saved = {}
    for _, f in ipairs(World.SERVER_FIELDS) do saved[f] = md[f] end
    T.ok(World.store == nil and World.server() == md, "no store yet: the fields are in the world record")
    T.ok(type(md.seed) == "number", "the world record was created with a seed")
    local key = "pump:4,5,0"
    local spec = { storage = "station_ust", cap = 10000, q = { gasoline = 1000 } }
    local before = World.baseline(key, spec)
    local cBefore = WorldInit.stationContamination(World.facts(), key, 1000)
    md.machineSites = { ["P1-1"] = { x = 1, y = 2, z = 0 } }
    md.climateAcc = { day = 1, n = 1, t = 20, rh = 0.5 }
    local seed, nextId = md.seed, md.nextId

    local store = World.attachServerStore({})
    local ok, err = pcall(function()
        -- What a client is sent (the world record) holds none of them now.
        for _, f in ipairs(World.SERVER_FIELDS) do T.eq(md[f], nil, "world record still has " .. f) end
        T.ok(World.server() == store, "World.server() is the store")
        T.eq(store.seed, seed)
        T.eq(store.nextId, nextId)
        T.eq(store.machineSites["P1-1"].x, 1)
        T.eq(store.climateAcc.t, 20)
        T.eq(store.v, World.SERVER_STORE_SCHEMA)
        -- The public fields stay public (UI previews read them).
        T.ok(md.v ~= nil and md.policy ~= nil and md.calendar ~= nil and md.balanceHistory ~= nil)
        -- Ids, baselines, station water and climate sums use the store.
        local id = World.newId("S")
        T.eq(id, string.format("S%d-%d", seed, nextId))
        T.eq(store.nextId, nextId + 1)
        T.eq(md.nextId, nil)
        local after = World.baseline(key, spec)
        T.near(after.deg.gasoline, before.deg.gasoline, 1e-12, "same seed, same baseline")
        local cAfter = WorldInit.stationContamination(World.facts(), key, 1000)
        T.near(cAfter.water, cBefore.water, 1e-12, "same seed, same station water")
        World.recordClimate()
        T.ok(store.climateAcc ~= nil and md.climateAcc == nil, "today's climate sums go to the store")
        T.ok(md.climateLog ~= nil, "the climate log stays public")
        -- A save from before the store, or written again by an older
        -- version: the store's seed wins, the next id never goes back.
        md.seed, md.nextId = 11, 50
        local merged = World.attachServerStore({ seed = 77, nextId = 3 })
        T.eq(merged.seed, 77)
        T.eq(merged.nextId, 50)
        T.eq(md.seed, nil)
        T.eq(md.nextId, nil)
        -- A world whose store file was lost gets a new seed, not nil.
        local lost = World.attachServerStore({})
        T.ok(type(lost.seed) == "number", "new seed: " .. tostring(lost.seed))
        T.eq(lost.nextId, 1)
        T.ok(type(World.newId("S")) == "string")
    end)
    World.store = nil
    for _, f in ipairs(World.SERVER_FIELDS) do md[f] = saved[f] end
    if not ok then error(err, 0) end
end)

------------------------------------------------------------------------------
-- V-01 fixed: on a server the records in client-writable mod data are
-- checked against the server copy (TLG/Authority/Vault.lua). These cases run
-- with isServer() true and a server store attached; the mocks stand in for
-- the engine (the packets themselves are the multiplayer case AUD-4).
-- A packet never edits a table in the mod data: the engine wipes the mod
-- data and builds new tables (KahluaTableImpl.load, BC 42.21), so each
-- forgery below puts a new table in place, as a packet does.
------------------------------------------------------------------------------
local Vault = TLG.Authority.Vault
local Mach = TLG.Integration.Machines

-- Runs fn(store) as a server with a fresh vault; puts the world back after.
local function asServer(fn, regenerated)
    local World = TLG.World
    local md = World.get()
    local saved = {}
    for _, f in ipairs(World.SERVER_FIELDS) do saved[f] = TLG.Tables.deepCopy(md[f]) end
    local wasServer = M.server
    M.server = true
    local store = World.attachServerStore({})
    Vault.attach(store, regenerated)
    local ok, err = pcall(fn, store)
    M.server = wasServer
    World.store = nil
    for _, f in ipairs(World.SERVER_FIELDS) do md[f] = saved[f] end
    if not ok then error(err, 0) end
end

local function canWith(litres)
    local p = M.player("vault", M.square(90, 90, 0))
    return p.inv:AddItem(M.item("Base.PetrolCan", 10, { Petrol = litres }))
end

T.case("audit V-01 fixed: a can's record rewritten, replaced or removed in its mod data is put back", function()
    asServer(function(store)
        T.ok(Vault.active(), "a server with a store keeps copies")
        T.eq(store.vault.from, store.nextId, "ids from now on are the vault's own")
        local can = canWith(10)
        local rec = C.read(can, "item", true)
        C.commit(can, "item", rec)
        local deg, stab, id = can.md.tlg.deg.gasoline, can.md.tlg.stab, can.md.tlg.id
        T.ok(deg > 0, "found petrol is aged: " .. tostring(deg))
        -- The run-1 forgery: fresher fuel and a stabilizer, same id.
        local f = TLG.Tables.deepCopy(can.md.tlg)
        f.deg.gasoline, f.stab = 0, 2
        can.md.tlg = f
        local synced = can.synced
        local again = C.read(can, "item", true)
        T.near(again.deg.gasoline, deg, 1e-12, "condition from the server copy")
        T.eq(again.stab, stab)
        T.near(can.md.tlg.deg.gasoline, deg, 1e-12, "the mod data is put back too")
        T.ok(can.synced > synced, "and sent back to the clients")
        -- A whole new record under an id the server never gave out.
        local forged = TLG.Tables.deepCopy(can.md.tlg)
        forged.id, forged.deg.gasoline = string.format("S%s-%d", store.vault.tag, store.nextId + 50), 0
        can.md.tlg = forged
        T.eq(C.read(can, "item", true).id, id, "the can's own record comes back")
        T.eq(can.md.tlg.id, id)
        -- The record removed (to have the fuel taken as untracked).
        can.md.tlg = nil
        local back, status = C.read(can, "item", true)
        T.eq(back.id, id, "a removed record comes back")
        T.eq(status, "ok")
        -- A legitimate write is the new copy: a later read finds it equal.
        back.stab = 0.25
        C.commit(can, "item", back)
        T.eq(C.read(can, "item", true).stab, 0.25)
        -- After a load from the save the mod data holds an equal, separate
        -- table: it is the record, nothing is put back.
        local restored = Vault.stats.restored
        can.md.tlg = TLG.Tables.deepCopy(can.md.tlg)
        T.eq(C.read(can, "item", true).stab, 0.25)
        T.eq(Vault.stats.restored, restored, "an equal table is taken as the record")
    end)
end)

T.case("audit V-01 fixed: a record copied onto another can moves there, and the can it left reads as untracked", function()
    asServer(function()
        local good, other = canWith(10), canWith(10)
        local rec = C.read(good, "item", true)
        rec.stab = 2
        C.commit(good, "item", rec)
        local id = good.md.tlg.id
        -- Copied onto a can the server never recorded: it moves there.
        other.md.tlg = TLG.Tables.deepCopy(good.md.tlg)
        local moved = C.read(other, "item", true)
        T.eq(moved.id, id)
        T.eq(moved.stab, 2)
        -- The can it came from no longer has it: untracked, a new record.
        local left, status = C.read(good, "item", true)
        T.eq(status, "initialized", "the copy did not double the record")
        T.ok(left.id ~= id, "new id " .. tostring(left.id))
        T.eq(good.md.tlg, nil, "the copy is dropped from its mod data")
        T.eq(left.stab, 0, "fuel taken as found, without the stabilizer")
        -- Copied onto a can with a record of its own: that one comes back.
        C.commit(good, "item", left)
        local ownId = good.md.tlg.id
        good.md.tlg = TLG.Tables.deepCopy(other.md.tlg)
        T.eq(C.read(good, "item", true).id, ownId)
    end)
end)

T.case("audit V-01 fixed: an id from before the vault is adopted once; an unknown one is dropped", function()
    asServer(function(store)
        local v = store.vault
        local legacyCan, forgedCan, foreignCan = canWith(10), canWith(10), canWith(10)
        local base = C.read(legacyCan, "item", true)
        local side = { v = 1, id = string.format("S%s-%d", v.tag, v.from - 1), rev = 3, t = base.t,
            storage = base.storage, deg = { gasoline = 0.5 }, stab = 0.1, mic = 0, q = { gasoline = 10 }, prov = {} }
        legacyCan.md.tlg = TLG.Tables.deepCopy(side)
        local adopted = C.read(legacyCan, "item", true)
        T.eq(adopted.id, side.id, "a save's record is taken as found")
        T.near(adopted.deg.gasoline, 0.5, 1e-12)
        local f2 = TLG.Tables.deepCopy(legacyCan.md.tlg)
        f2.deg.gasoline = 0
        legacyCan.md.tlg = f2
        T.near(C.read(legacyCan, "item", true).deg.gasoline, 0.5, 1e-12, "and kept from then on")
        -- n at or past the vault's start: never given out without a copy.
        forgedCan.md.tlg = TLG.Tables.deepCopy(side)
        forgedCan.md.tlg.id = string.format("S%s-%d", v.tag, v.from + 7)
        local _, status = C.read(forgedCan, "item", true)
        T.eq(status, "initialized", "forged: read as untracked fuel")
        T.eq(forgedCan.md.tlg, nil)
        -- Another seed: not this world's ids.
        foreignCan.md.tlg = TLG.Tables.deepCopy(side)
        foreignCan.md.tlg.id = "S123-1"
        T.eq(select(2, C.read(foreignCan, "item", true)), "initialized")
    end)
    -- A world whose store was lost: ids under the old seed are adopted.
    asServer(function(store)
        T.eq(store.vault.foreign, true)
        local can = canWith(10)
        can.md.tlg = { v = 1, id = "S123-1", rev = 0, t = 0, storage = "jerrycan_steel", deg = { gasoline = 0.2 },
            stab = 0, mic = 0, q = { gasoline = 10 }, prov = {} }
        T.eq(C.read(can, "item", true).id, "S123-1")
    end, true)
end)

T.case("audit V-01 fixed: a pump's and a generator's records, project and wear are kept on the server", function()
    asServer(function()
        local pump = pumpAt(95, 95, 500)
        local prec = S.read(pump, true)
        S.write(pump, prec)
        local water = pump.md.tlg.q.water
        local id = pump.md.tlg.id
        local fp = TLG.Tables.deepCopy(pump.md.tlg)
        fp.q.water, fp.q.sediment, fp.q.gasoline = 0, 0, 500
        pump.md.tlg = fp
        local sent = pump.transmitted
        local back = S.read(pump, true)
        T.near(back.q.water or 0, water or 0, 1e-12, "the station's water comes back")
        T.eq(back.id, id)
        T.ok(pump.transmitted > sent, "and is sent to the clients")

        local gen = generatorAt(97, 97, 5)
        local grec = G.read(gen, true)
        G.writeSidecar(gen, grec)
        local gmd = gen:getModData()
        local fg = TLG.Tables.deepCopy(gmd.tlg)
        fg.profile = "generator_si_flex"
        gmd.tlg = fg
        T.eq(G.baseProfile(gen), "generator_si_stock", "a profile written in alone is put back")
        -- The run-2 forgery: a Commissioned project nobody worked for.
        gmd.tlgDeviceId, gmd.tlgEngineId = "AUDIT-D", "AUDIT-E"
        gmd.tlgConv = {
            v = 1, id = "AUDIT-C", rev = 1, conversion = "flex_generator", state = "Commissioned", t = 0,
            snap = { targetConsumerProfile = "generator_si_flex", fuelStorageChanges = {}, cargoAndWeightImpact = {},
                visualConfiguration = {}, workStages = {}, requiredModules = {}, requiredTools = {},
                reversalAndSalvageRules = {} },
            hours = {}, delivered = {}, workers = {}, credit = {}, deviceKey = "gen:AUDIT-D",
            chassis = "Base.Generator", deviceKind = "generator", engineId = "AUDIT-E",
            originalProfile = "generator_si_stock", commissionedAt = 0,
        }
        T.eq(G.profile(gen), "generator_si_stock", "the forged project is dropped")
        T.eq(gmd.tlgConv, nil)
        -- A project the server wrote is kept; one rewritten is put back.
        local CD = TLG.Integration.ConversionDevices
        local proj = { v = 1, id = TLG.World.newId("C"), rev = 0, conversion = "flex_generator", state = "Planned", t = 0 }
        CD.store(gmd, gen, proj, G.keyOf(gen))
        local fc = TLG.Tables.deepCopy(gmd.tlgConv)
        fc.state = "Commissioned"
        gmd.tlgConv = fc
        T.eq(CD.project(gmd, G.keyOf(gen)).state, "Planned")
        T.eq(gmd.tlgConv.state, "Planned")
        -- Wear: the charged litres rewritten so no wear is due.
        G.chargeWear(gen)
        T.ok(gmd.tlgWear ~= nil, "wear recorded")
        local charged = gmd.tlgWear.charged
        local fw = TLG.Tables.deepCopy(gmd.tlgWear)
        fw.charged = 999
        gmd.tlgWear = fw
        G.chargeWear(gen)
        T.eq(gmd.tlgWear.charged, charged, "the wear record comes back")
    end)
end)

T.case("audit V-01 fixed: a gas generator's feed record is kept on the server (D-040)", function()
    asServer(function()
        local G, GasFeed = TLG.Integration.Generators, TLG.Domain.GasFeed
        local gen = generatorAt(96, 96, 0)
        local r = GasFeed.connect(GasFeed.new({ id = TLG.World.newId("GS"), t = 0 }), 100, 0)
        G.writeGas(gen, r.rec)
        local gmd = gen:getModData()
        local forged = TLG.Tables.deepCopy(gmd.tlgGas)
        forged.tank.uses = 5000
        gmd.tlgGas = forged
        T.eq(G.gasRecord(gen).tank.uses, 100, "a tank refilled in mod data is put back")
        T.eq(gmd.tlgGas.tank.uses, 100)
        -- A feed record nobody wrote, on a generator without one, is dropped.
        local other = generatorAt(95, 96, 0)
        other:getModData().tlgGas = { v = 1, id = "AUDIT-GS", buf = { propane = 3 }, fuel = 9,
            tank = { uses = 5000 }, t = 0 }
        T.eq(G.gasRecord(other), nil, "a forged feed record is dropped")
        T.eq(other:getModData().tlgGas, nil)
    end)
end)

T.case("audit V-01 fixed: a machine's process record rewritten in its mod data is put back", function()
    asServer(function()
        local p = M.player("brewer", M.square(99, 99, 0))
        local vessel = p.inv:AddItem(M.item("TLG.FermenterVessel"))
        local rec = Mach.read(vessel, true)
        Mach.write(vessel, rec)
        local state = rec.state
        local fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.state, fm.outputs = "OutputReady", { ethanol = 50 }
        vessel.md.tlgProc = fm
        local back = Mach.read(vessel, true)
        T.eq(back.state, state)
        T.ok(TLG.Tables.isEmpty(back.outputs), "no output to bottle")
        T.eq(vessel.md.tlgProc.state, state)
        -- The quiet writes (fire notes, kept on the server) are copies too.
        local stored = Mach.stored(vessel)
        stored.seen = 12.5
        Mach.write(vessel, stored, true)
        T.eq(Mach.read(vessel, true).seen, 12.5)
    end)
end)

-- A machine record with `hours` of readings and fire notes from hour `from`,
-- as the hourly and ten-minute passes write them: fireplace notes, "no fire"
-- notes, a campfire's and a barbecue's.
local function withHistory(rec, from, hours)
    rec.temps, rec.fires = {}, {}
    for h = from, from + hours - 1 do
        rec.temps[h] = 14 + (h % 7) * 0.371
        if h % 3 == 0 then
            rec.fires[h] = false
        else
            rec.fires[h] = { t = h + 0.83, f = 400 - h % 50, x = 1, y = 2, r = true, c = 35 }
        end
    end
    rec.fires[from + 1] = { t = from + 1.5, f = 397, x = 9, y = 0, r = false, c = 35, k = "campfire", rmax = 10 }
    rec.fires[from + 2] = { t = from + 2.5, f = 100, x = -2, y = 0, r = false, c = 25, rad = 3 }
    return rec
end

-- A table as a load gives it back: new tables throughout, each filled in the
-- reverse of the order pairs gave (a save does not keep that order).
local function reloaded(v)
    if type(v) ~= "table" then return v end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    for i = #keys, 1, -1 do out[keys[i]] = reloaded(v[keys[i]]) end
    return out
end

T.case("audit V-01 compact: a machine's readings and notes are saved as digests; rewritten ones are dropped", function()
    asServer(function(store)
        local p = M.player("brewer2", M.square(98, 99, 0))
        local vessel = p.inv:AddItem(M.item("TLG.FermenterVessel"))
        local rec = withHistory(Mach.read(vessel, true), 100, 48)
        Mach.write(vessel, rec)
        local e = store.vault.recs["process:" .. rec.id]
        T.ok(e.r.temps == nil and e.r.fires == nil, "saved without readings and notes")
        T.eq(type(e.d.temps), "number"); T.eq(type(e.d.fires), "number")
        T.ok(Vault.bytes(e, 1e9) < 2048, "under 2 KB saved")
        T.ok(Vault.bytes(rec, 1e9) > 3 * Vault.bytes(e, 1e9), "the record with two days of history is over three times that")
        -- One reading raised and another lowered as much: the readings sum
        -- to the same, the digest does not.
        local cleared = Vault.stats.cleared
        local fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.temps[110], fm.temps[111] = fm.temps[110] + 5, fm.temps[111] - 5
        vessel.md.tlgProc = fm
        local back = Mach.read(vessel, true)
        T.ok(back.temps == nil, "readings that differ are dropped")
        T.ok(Vault.same(back.fires, rec.fires), "the notes as written stay")
        T.eq(back.state, rec.state)
        T.eq(Vault.stats.cleared, cleared + 1)
        T.ok(vessel.md.tlgProc.temps == nil, "the mod data is cleared at once")
        -- A note with a field the mod never writes.
        Mach.write(vessel, withHistory(Mach.read(vessel, true), 100, 48))
        fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.fires[104].boost = 10
        vessel.md.tlgProc = fm
        back = Mach.read(vessel, true)
        T.ok(back.fires == nil and back.temps ~= nil, "notes dropped, readings kept")
        -- Another field rewritten, the history untouched: the record is put
        -- back with its readings and notes.
        local good = withHistory(Mach.read(vessel, true), 100, 48)
        Mach.write(vessel, good)
        local restored = Vault.stats.restored
        fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.outputs = { ethanol = 50 }
        vessel.md.tlgProc = fm
        back = Mach.read(vessel, true)
        T.ok(TLG.Tables.isEmpty(back.outputs), "no output to bottle")
        T.ok(Vault.same(back.temps, good.temps) and Vault.same(back.fires, good.fires), "history kept")
        T.eq(Vault.stats.restored, restored + 1)
        -- A reading added for an hour to come, and one under an hour no
        -- reading is filed under.
        fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.temps[200] = 24
        vessel.md.tlgProc = fm
        T.ok(Mach.read(vessel, true).temps == nil)
        Mach.write(vessel, withHistory(Mach.read(vessel, true), 100, 48))
        fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.temps[120.5] = 24
        vessel.md.tlgProc = fm
        T.ok(Mach.read(vessel, true).temps == nil)
        -- The passes' own writes (same table, one entry more, the oldest
        -- pruned) keep the digest current: no false alarm on the next read.
        local live = Mach.stored(vessel)
        withHistory(live, 100, 48)
        Mach.write(vessel, live, true)
        for h = 148, 160 do
            live.temps[h] = 20 + h % 5
            live.temps[h - 48] = nil
            live.fires[h] = { t = h + 0.5, f = 300, x = 1, y = 2, r = true, c = 35 }
            live.fires[h - 48] = nil
            Mach.write(vessel, live, true)
        end
        local st = Vault.stats.cleared + Vault.stats.restored
        vessel.md.tlgProc = reloaded(live)
        back = Mach.read(vessel, true)
        T.ok(Vault.same(back.temps, live.temps), "a load of the record as written reads as it is")
        T.eq(Vault.stats.cleared + Vault.stats.restored, st)
    end)
end)

T.case("audit V-01 compact: after a restart every record reads as written", function()
    asServer(function(store)
        local p = M.player("brewer3", M.square(97, 99, 0))
        local vessels, recs = {}, {}
        for i = 1, 3 do
            local vessel = p.inv:AddItem(M.item("TLG.FermenterVessel"))
            local rec = withHistory(Mach.read(vessel, true), 100 + i, 24 * i)
            Mach.write(vessel, rec)
            vessels[i], recs[i] = vessel, TLG.Tables.deepCopy(rec)
        end
        local can = canWith(12)
        C.commit(can, "item", C.read(can, "item", true))
        local canRec = TLG.Tables.deepCopy(can.md.tlg)
        -- The save and the load: the store and every mod data come back as
        -- new tables, filled in another order.
        local saved = reloaded(store)
        for i = 1, 3 do vessels[i].md.tlgProc = reloaded(vessels[i].md.tlgProc) end
        can.md.tlg = reloaded(can.md.tlg)
        Vault.attach(TLG.World.attachServerStore(saved), false)
        -- A record removed before any read since the restart comes back
        -- without its history (the table written went with the Lua state).
        vessels[3].md.tlgProc = nil
        local back = Mach.read(vessels[3], true)
        T.eq(back.id, recs[3].id); T.ok(back.temps == nil and back.fires == nil)
        local before = TLG.Tables.copy(Vault.stats)
        for i = 1, 2 do
            back = Mach.read(vessels[i], true)
            T.ok(Vault.same(back.temps, recs[i].temps) and Vault.same(back.fires, recs[i].fires), "history " .. i .. " kept")
            T.eq(back.id, recs[i].id)
        end
        C.read(can, "item", true)
        T.ok(Vault.same(can.md.tlg, canRec), "the can's record as written")
        for _, s in ipairs({ "restored", "cleared", "dropped" }) do T.eq(Vault.stats[s], before[s], s) end
        -- A reading forged after the restart is still caught.
        local fm = TLG.Tables.deepCopy(vessels[1].md.tlgProc)
        fm.temps[101] = 30
        vessels[1].md.tlgProc = fm
        T.ok(Mach.read(vessels[1], true).temps == nil)
    end)
end)

T.case("audit V-01 compact: a vault saved with whole machine records is compacted when loaded", function()
    asServer(function(store)
        local p = M.player("brewer4", M.square(96, 99, 0))
        local vessel = p.inv:AddItem(M.item("TLG.FermenterVessel"))
        local rec = withHistory(Mach.read(vessel, true), 100, 24)
        Mach.write(vessel, rec)
        -- The vault as its first version saved it: whole records, no keys.
        local k = "process:" .. rec.id
        local old = reloaded(store)
        old.vault.dk = nil
        old.vault.recs[k] = { h = store.vault.recs[k].h, r = reloaded(rec) }
        vessel.md.tlgProc = reloaded(rec)
        Vault.attach(TLG.World.attachServerStore(old), false)
        local e = old.vault.recs[k]
        T.ok(e.r.temps == nil and type(e.d.temps) == "number" and type(e.d.fires) == "number", "compacted")
        T.eq(type(old.vault.dk.w), "number")
        local st = Vault.stats.restored + Vault.stats.cleared
        local back = Mach.read(vessel, true)
        T.ok(Vault.same(back.temps, rec.temps) and Vault.same(back.fires, rec.fires))
        T.eq(Vault.stats.restored + Vault.stats.cleared, st)
    end)
end)

T.case("audit V-01 compact: a record taken as found is bounded in size and form", function()
    asServer(function(store)
        local v = store.vault
        T.ok(v.from >= 3, "ids were given out before the vault")
        local function legacyId(letter, back) return string.format("%s%s-%d", letter, v.tag, v.from - back) end
        -- A can's record from a save, padded past the bound.
        local can = canWith(10)
        local base = C.read(can, "item", true)
        can.md.tlg = { v = 1, id = legacyId("S", 1), rev = 3, t = base.t, storage = base.storage,
            deg = { gasoline = 0.5 }, stab = 0.1, mic = 0, q = { gasoline = 10 }, prov = {}, pad = string.rep("x", 9000) }
        T.eq(select(2, C.read(can, "item", true)), "initialized", "read as untracked fuel")
        -- A machine's from a save with a reading under an hour none is filed
        -- under: dropped; one as the mod writes them: taken, then kept.
        local p = M.player("brewer5", M.square(95, 99, 0))
        local vessel = p.inv:AddItem(M.item("TLG.FermenterVessel"))
        local bad = withHistory(Mach.read(vessel, false), 100, 24)
        bad.id = legacyId("P", 1)
        bad.temps[5000000] = 1
        vessel.md.tlgProc = reloaded(bad)
        T.ok(Mach.read(vessel, true).id ~= bad.id, "dropped: an idle machine")
        T.eq(vessel.md.tlgProc, nil)
        local good = withHistory(Mach.read(vessel, false), 100, 24)
        good.id = legacyId("P", 2)
        vessel.md.tlgProc = reloaded(good)
        T.eq(Mach.read(vessel, true).id, good.id, "a save's machine is taken as found")
        local fm = TLG.Tables.deepCopy(vessel.md.tlgProc)
        fm.temps[101] = 40
        vessel.md.tlgProc = fm
        T.ok(Mach.read(vessel, true).temps == nil, "and its readings are checked from then on")
        -- A generator's wear the vault never saw, padded past the bound.
        local gen = generatorAt(93, 97, 5)
        G.writeSidecar(gen, G.read(gen, true))
        local gmd = gen:getModData()
        gmd.tlgWear = { c = 0, charged = 0, pad = string.rep("x", 9000) }
        G.chargeWear(gen)
        T.ok(gmd.tlgWear == nil or gmd.tlgWear.pad == nil, "not kept")
    end)
end)

T.case("audit V-01 fixed: single player keeps no copies and drops a server's", function()
    local World = TLG.World
    local md = World.get()
    local saved = {}
    for _, f in ipairs(World.SERVER_FIELDS) do saved[f] = TLG.Tables.deepCopy(md[f]) end
    local store = World.attachServerStore({ vault = { v = 1, from = 1, tag = "1", recs = {}, holders = {} } })
    local ok, err = pcall(function()
        T.ok(not Vault.active())
        Vault.attach(store, false)
        T.eq(store.vault, nil, "a world loaded without a server drops the copies, which would go stale")
        local can = canWith(10)
        local rec = C.read(can, "item", true)
        C.commit(can, "item", rec)
        can.md.tlg.stab = 2
        T.eq(C.read(can, "item", true).stab, 2, "single player reads the mod data as found")
    end)
    World.store = nil
    for _, f in ipairs(World.SERVER_FIELDS) do md[f] = saved[f] end
    if not ok then error(err, 0) end
end)

------------------------------------------------------------------------------
-- The known command (What I know about it, 2026-11-06): read-only, answered
-- by the authority from its own player object, with status's reach. A
-- player out of reach gets no_access and nothing about the fuel.
------------------------------------------------------------------------------
T.case("audit: what I know needs the same reach as status, and tells only the asking player's own tests", function()
    M.vehicle(27, 400, 400, 40, 20)
    local far = M.player("knowfar", M.square(450, 450, 0))
    local r = H.dispatch(far, "known", { requestId = rid(), target = { kind = "vehicle", id = 27 } })
    T.eq(r.ok, false); T.eq(r.reason, "no_access")
    T.eq(r.tests, nil, "no knowledge in a refusal")
    local near = M.player("knownear", M.square(401, 400, 0))
    T.ok(H.dispatch(near, "sample", { requestId = rid(), target = { kind = "vehicle", id = 27 }, method = "visual" }).ok)
    local k = H.dispatch(near, "known", { requestId = rid(), target = { kind = "vehicle", id = 27 } })
    T.ok(k.ok, "known at the cap: " .. tostring(k.reason))
    T.eq(#k.tests, 1); T.eq(k.tests[1].method, "visual")
    -- Another player at the same cap knows nothing of the first one's look.
    local other = M.player("knowother", M.square(401, 400, 0))
    local o = H.dispatch(other, "known", { requestId = rid(), target = { kind = "vehicle", id = 27 } })
    T.ok(o.ok); T.eq(#o.tests, 0, "knowledge belongs to the player who tested")
end)

T.case("audit: what I know about a can nobody tested writes no record", function()
    local p = M.player("knowfresh", M.square(500, 500, 0))
    local can = p.inv:AddItem(M.item("Base.PetrolCan", 10, { Petrol = 4 }))
    local k = H.dispatch(p, "known", { requestId = rid(), target = { kind = "item", id = can:getID() } })
    T.ok(k.ok, "known on a fresh can: " .. tostring(k.reason))
    T.eq(#k.tests, 0, "nothing known")
    T.eq(can:getModData().tlg, nil, "no record written on the can")
    -- Not asserted: the read gives the record it builds an id (nextId moves
    -- by one), as status has always done (Containers endpoint read, persist
    -- true); the id is never written. Noted in D-034.
end)
