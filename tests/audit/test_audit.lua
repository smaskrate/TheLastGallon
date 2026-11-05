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
-- AUD-4 (mod side): a project written into a generator's mod data is honoured.
------------------------------------------------------------------------------
T.case("audit: a Commissioned project forged in generator mod data changes the engine profile", function()
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

T.case("audit: a fuel sidecar forged in item mod data is read back as fuel condition", function()
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
