require "support/fixtures"
require "TLG/Integration/Containers"
-- The adapters register installers through Boot, and the handlers load them
-- (as tests/authority/test_sample.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/Integration/Generators"
require "TLG/Integration/Vehicles"
require "TLG/Integration/Stations"
require "TLG/Authority/Handlers"
Events = savedEvents
local I, D, World = TLG.Integration, TLG.Domain, TLG.World
local H, Res = TLG.Authority.Handlers, TLG.Authority.Resolver

-- What a player learns about the fuel in a vehicle's or a generator's tank
-- and about the engine it feeds (UX review R5): the tests a can has, on the
-- tank's real endpoint; what a kit's result means for the engine; and the
-- warning when one of the game's own refuels leaves the wrong fuel in it.
local GLOBALS = { "ModData", "getGameTime", "isServer", "isClient", "SandboxVars", "Events", "ISAddFuel",
    "ISAddGasolineToVehicle", "ISTakeGasolineFromVehicle", "ISStartVehicleEngine", "ISRefuelFromGasPump", "ISTakeFuel",
    "ISTakeGenerator", "ISDropWorldItemAction", "ISUnequipAction", "ISActivateGenerator", "getClimateManager" }

local function inGame(fn)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local store = {}
    ModData = { getOrCreate = function(k)
        store[k] = store[k] or {}
        return store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return 100 end
    getGameTime = function() return clock end
    isServer = function() return false end
    isClient = function() return false end
    getClimateManager = nil
    SandboxVars = { TheLastGallon = {} }
    Events = setmetatable({}, { __index = function() return { Add = function() end } end })
    local md = World.get()
    md.v, md.calendar, md.climateLog, md.dieselVehicles = 1, { dayOfYear = 190, hourOfDay = 9 }, {}, true
    local srv = World.server()
    srv.seed, srv.nextId = srv.seed or 7, srv.nextId or 1
    local N, C, Native, Consumers = TLG.Notify, I.Containers, I.Native, D.Consumers
    local keep = { N.send, C.untrackedDeg, Native.readComposition, Native.writeComposition, Res.resolve,
        Consumers.damageEnabled }
    local notes = {}
    N.send = function(player, key, fuel) notes[#notes + 1] = { player = player, key = key, fuel = fuel } end
    C.untrackedDeg = function() return 0.07 end
    Native.readComposition = function(fc) return fc:fluids(), 0, {} end
    Native.writeComposition = function(fc, comp) fc.comp = TLG.Tables.copy(comp); return true end
    local ok, err = pcall(fn, notes)
    N.send, C.untrackedDeg, Native.readComposition, Native.writeComposition, Res.resolve, Consumers.damageEnabled =
        keep[1], keep[2], keep[3], keep[4], keep[5], keep[6]
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local function record(id, q)
    local deg = {}
    for k in pairs(q) do deg[k] = 0 end
    return { v = 1, id = id, rev = 1, t = 100, q = q, deg = deg, stab = 0, mic = 0, cond = 1, prov = {} }
end

local function total(q)
    local n = 0
    for _, v in pairs(q or {}) do n = n + v end
    return n
end

-- A parked car; `q` its tank's record (nil: fuel the mod never recorded,
-- `litres` of it). `x.atCap` says whether a player stands at the fuel cap.
local function car(q, script, litres)
    local x = { litres = litres or total(q), atCap = true, tankMd = { tlg = q and record("V1", q) or nil }, engineMd = {} }
    local tank, engine = {}, {}
    function tank:getContainerContentAmount() return x.litres end
    function tank:setContainerContentAmount(n) x.litres = n end
    function tank:getContainerCapacity() return 60 end
    function tank:getModData() return x.tankMd end
    function tank:getArea() return "TireRearLeft" end
    function tank:getVehicle() return x end
    function engine:getModData() return x.engineMd end
    x.tank = tank
    function x:getPartById(id)
        if id == "GasTank" then return tank elseif id == "Engine" then return engine end
        return nil
    end
    function x:getId() return 9 end
    function x:getSqlId() return 9 end
    function x:getScriptName() return script or "Base.CarNormal" end
    function x:isInArea() return self.atCap end
    function x:transmitPartModData() end
    return x
end

local function generator(q, itemType)
    local x = { fuel = total(q), md = { tlg = record("G1", q), generatorFullType = itemType } }
    function x:getFuel() return self.fuel end
    function x:setFuel(n) self.fuel = n end
    function x:getMaxFuel() return 10 end
    function x:getModData() return self.md end
    function x:getCondition() return 100 end
    function x:transmitModData() end
    function x:getSquare() return nil end
    function x:getGeneratorItemType() return itemType or "Base.Generator" end
    return x
end

-- A can of `q` (its record, and its native fluids).
local function can(q)
    local x = { md = { tlg = record("C1", q) } }
    local fc = {}
    function fc:getCapacity() return 20 end
    function fc:fluids() return TLG.Tables.copy(q) end
    function x:getModData() return self.md end
    function x:getFluidContainerFromSelfOrWorldItem() return fc end
    function x:getFluidContainer() return fc end
    function x:getFullType() return "Base.PetrolCan" end
    function x:getID() return 7 end
    return x
end

local function player(withKit)
    local p, md = {}, {}
    function p:getModData() return md end
    function p:getUsername() return "tester" end
    function p:getVehicle() return nil end
    function p:getInventory()
        return { getFirstTypeRecurse = function(_, t) return withKit and t == "TLG.FuelSampleKit" and {} or nil end }
    end
    return p, md
end

local function hasReason(v, code)
    for _, r in ipairs(v.reasons or {}) do
        if r == code then return true end
    end
    return false
end

T.case("integration: a tank answers a can's tests, names its engine, and a kit's result is judged for it", function()
    inGame(function()
        -- The three ways a tank's record is read: never recorded, as
        -- written, and with litres the mod did not see come in.
        local cases = {
            { name = "initialized", car = car(nil, "Base.CarNormal", 20) },
            { name = "ok", car = car({ gasoline = 20 }) },
            { name = "reconciled", car = car({ gasoline = 4 }, "Base.CarNormal", 10) },
        }
        for i, c in ipairs(cases) do
            local p, md = player(true)
            Res.resolve = function() return I.Vehicles.endpoint(c.car) end
            local target = { kind = "vehicle", id = 9 }
            local look = H.sample(p, { requestId = "tank-look-" .. i, target = target, method = "visual" })
            T.eq(look.ok, true, c.name)
            T.eq(look.engine, "engine_si_stock", c.name .. ": the engine is named")
            T.ok(look.verdict == nil, c.name .. ": a look finds no composition, so it is not judged")
            local kit = H.sample(p, { requestId = "tank-kit-" .. i, target = target, method = "kit" })
            T.eq(kit.ok, true, c.name)
            T.ok(kit.verdict ~= nil and kit.verdict.compatible == true and not kit.verdict.harmful,
                c.name .. ": petrol in a petrol engine")
            -- Filed under the id the tank's record carries from now on.
            local id = c.car.tankMd.tlg and c.car.tankMd.tlg.id
            T.ok(id ~= nil, c.name .. ": the tank has a record")
            local entry = md.tlgKnowledge[tostring(id)]
            T.ok(entry ~= nil and entry.kit == kit.observation, c.name .. ": the sample is filed under the tank's id")
            T.ok(entry.kit.verdict == nil, c.name .. ": the judgement is not kept with the observation")
            local k = H.dispatch(p, "known", { requestId = "tank-known-" .. i, target = target })
            T.eq(k.ok, true, c.name)
            T.eq(k.engine, "engine_si_stock"); T.eq(k.tank, true)
            T.eq(#k.tests, 2, c.name .. ": both tests are known")
            T.eq(k.tests[1].method, "kit")
            T.ok(k.tests[1].verdict ~= nil and k.tests[1].verdict.compatible == true, c.name)
            T.ok(k.tests[2].verdict == nil, c.name .. ": the look's stays unjudged")
        end
    end)
end)

T.case("integration: a tank is sampled from its fuel cap only, and a can's sample names no engine", function()
    inGame(function()
        local c = car({ gasoline = 20 })
        c.atCap = false
        local p = player(true)
        Res.resolve = function() return I.Vehicles.endpoint(c) end
        local r = H.sample(p, { requestId = "tank-far-1", target = { kind = "vehicle", id = 9 }, method = "visual" })
        T.eq(r.ok, false); T.eq(r.reason, "no_access")
        T.eq(H.known(p, { requestId = "tank-far-2", target = { kind = "vehicle", id = 9 } }).reason, "no_access")
        -- A can: the container endpoint has no engine (its reach is the
        -- container adapter's own matter).
        local jerry = can({ gasoline = 10 })
        Res.resolve = function()
            local ep = I.Containers.endpoint(jerry, "item")
            function ep:canAccess() return true end
            return ep
        end
        r = H.sample(p, { requestId = "tank-can-1", target = { kind = "item", id = 7 }, method = "kit" })
        T.eq(r.ok, true)
        T.ok(r.engine == nil and r.verdict == nil, "no engine, no judgement")
        local k = H.known(p, { requestId = "tank-can-2", target = { kind = "item", id = 7 } })
        T.ok(k.engine == nil and k.tank == false and k.tests[1].verdict == nil)
    end)
end)

T.case("integration: the kit's judgement follows the engine and tells no more than the sample found", function()
    inGame(function()
        local p = player(true)
        -- Diesel in a petrol car.
        local petrolCar = car({ diesel = 20 })
        Res.resolve = function() return I.Vehicles.endpoint(petrolCar) end
        local r = H.sample(p, { requestId = "tank-d-1", target = { kind = "vehicle", id = 9 }, method = "kit" })
        T.eq(r.verdict.compatible, false, "a petrol engine does not start on diesel")
        T.ok(hasReason(r.verdict, "wrong_fuel_4_diesel"), table.concat(r.verdict.reasons, ","))
        -- A diesel van, by its chassis, takes the same fuel.
        local van = car({ diesel = 20 }, "Base.PickUpVan")
        Res.resolve = function() return I.Vehicles.endpoint(van) end
        r = H.sample(p, { requestId = "tank-d-2", target = { kind = "vehicle", id = 9 }, method = "kit" })
        T.eq(r.engine, "engine_ci_stock")
        T.ok(r.verdict.compatible and not r.verdict.harmful, "diesel in a diesel")
        -- 2.4 % petrol in it harms the engine; a kit rounds shares to 5 %
        -- and does not see it, so the sample's judgement stays clean while
        -- the refuel warning, which reads the record, names the petrol.
        local trace = car({ diesel = 19.52, gasoline = 0.48 }, "Base.PickUpVan")
        Res.resolve = function() return I.Vehicles.endpoint(trace) end
        r = H.sample(p, { requestId = "tank-d-3", target = { kind = "vehicle", id = 9 }, method = "kit" })
        T.ok(r.observation.composition.gasoline == nil or r.observation.composition.gasoline == 0, "below the kit's step")
        T.ok(r.verdict.compatible and not r.verdict.harmful, "judged on what the kit found")
        T.eq(I.Vehicles.warnWrongFuel(trace, p), "gasoline", "the record has it")
        -- A generator's tank: the mod's diesel generator with petrol in it.
        local gen = generator({ gasoline = 5 }, "TLG.DieselGenerator")
        local ep = { key = "gen", consumer = I.Generators.profile(gen) }
        function ep:canAccess() return true end
        function ep:read() self.readStatus = "ok"; return (I.Generators.read(gen, true)) end
        Res.resolve = function() return ep end
        r = H.sample(p, { requestId = "tank-g-1", target = { kind = "generator" }, method = "kit" })
        T.eq(r.engine, "generator_ci_bio")
        T.ok(r.verdict.harmful == true and hasReason(r.verdict, "wrong_fuel_3_gasoline"), table.concat(r.verdict.reasons, ","))
    end)
end)

T.case("integration: the fuel as a sample describes it", function()
    local Inspection, Supply = D.Inspection, D.Supply
    T.ok(Inspection.asSupply(nil) == nil)
    T.ok(Inspection.asSupply({ observedDeg = 1, primary = "diesel" }) == nil, "a look has no composition")
    T.ok(Inspection.asSupply({ composition = { gasoline = 0 } }) == nil, "nothing found")
    local s = Inspection.asSupply({ composition = { gasoline = 0.9, ethanol = 0.1 }, observedDeg = 1.4,
        observedWater = 0.02, observedSediment = 0.01, sampledAt = 50 })
    T.near(Supply.blendDeg(s), 1.4, 1e-9, "every part at the condition estimated")
    T.near(Supply.freeWater(s) / Supply.total(s), 0.02, 1e-9, "the free water seen, past what the ethanol holds")
    T.near(s.q.sediment / Supply.total(s), 0.01, 1e-9)
    T.near(s.q.gasoline / Supply.fuelTotal(s), 0.9, 1e-9)
end)

T.case("integration: the fuel that makes a blend wrong for an engine", function()
    inGame(function()
        local Consumers = D.Consumers
        local function wrong(profile, q, damage)
            local s = F.supply({ storage = "vehicle_tank", cap = 60, q = q, t = 100 })
            local e = Consumers.evaluate(profile, s, { wrongFuelDamage = damage })
            return Consumers.wrongFuelOf(profile, s, e), e
        end
        T.ok(wrong("engine_si_stock", { gasoline = 20 }) == nil)
        T.ok(wrong("engine_si_stock", { gasoline = 18, ethanol = 2 }) == nil, "an accepted blend")
        T.eq(wrong("engine_si_stock", { gasoline = 10, diesel = 10 }), "diesel")
        T.eq(wrong("engine_si_stock", { gasoline = 10, ethanol = 10 }), "ethanol", "past its limit")
        T.eq(wrong("engine_ci_stock", { diesel = 10, gasoline = 6, ethanol = 0.2 }), "gasoline")
        T.eq(wrong("engine_ci_stock", { diesel = 10, gasoline = 6, ethanol = 4 }), "ethanol", "the harsher band decides")
        T.ok(wrong("engine_ci_stock", { diesel = 19.9, gasoline = 0.1 }) == nil, "a trace the engine tolerates")
        -- The damage option off: no band is judged, the fuel is named all the same.
        local fuel, e = wrong("engine_si_stock", { gasoline = 10, diesel = 10 }, false)
        T.ok(e.wrongFuel == nil and e.compatible == false, "blocked, without a band")
        T.eq(fuel, "diesel")
        T.eq(wrong("engine_si_stock", { gasoline = 10, ethanol = 10 }, false), "ethanol")
        T.ok(wrong("engine_ci_stock", { diesel = 19.9, gasoline = 0.1 }, false) == nil)
        -- Wet or aged fuel of the right kind is not wrong fuel.
        local s = F.supply({ storage = "vehicle_tank", cap = 60, q = { gasoline = 19, water = 1 }, deg = { gasoline = 5 }, t = 100 })
        local bad = Consumers.evaluate("engine_si_stock", s, {})
        T.eq(bad.compatible, false)
        T.ok(Consumers.wrongFuelOf("engine_si_stock", s, bad) == nil)
    end)
end)

T.case("integration: a refuel that leaves the wrong fuel in the tank tells the player who poured", function()
    inGame(function(notes)
        local V, G = I.Vehicles, I.Generators
        local who = player(false)
        T.ok(V.warnWrongFuel(car({ gasoline = 20 }), who) == nil)
        T.eq(#notes, 0, "the right fuel: nothing said")
        T.eq(V.warnWrongFuel(car({ gasoline = 10, diesel = 10 }), who), "diesel")
        T.eq(notes[1].key, "IGUI_TLG_Note_WrongInTank"); T.eq(notes[1].fuel, "diesel"); T.ok(notes[1].player == who)
        T.eq(V.warnWrongFuel(car({ diesel = 10, gasoline = 10 }, "Base.PickUpVan"), who), "gasoline")
        T.ok(V.warnWrongFuel(car({}), who) == nil, "an empty tank")
        -- The option off: the start is blocked, and the note still names the fuel.
        D.Consumers.damageEnabled = function() return false end
        T.eq(V.warnWrongFuel(car({ gasoline = 10, diesel = 10 }), who), "diesel")
        T.eq(notes[#notes].fuel, "diesel")
        D.Consumers.damageEnabled = function() return true end
        T.eq(G.warnWrongFuel(generator({ gasoline = 5 }, "TLG.DieselGenerator"), who), "gasoline")
        T.ok(G.warnWrongFuel(generator({ gasoline = 5 }, "Base.Generator"), who) == nil)
    end)
end)

-- The game's actions as far as the hooks use them: `new` keeps its
-- parameters, `complete` moves the litres.
local function action(class, fields)
    return setmetatable(fields, { __index = class })
end

T.case("integration: the game's Add Fuel, can refuel and pump refuel warn at their end, once", function()
    inGame(function(notes)
        local V, G, S = I.Vehicles, I.Generators, I.Stations
        local who = player(false)
        -- Generator: Add Fuel pours a can of petrol into a diesel generator.
        ISAddFuel = { new = function(class, character, gen, petrol)
            return action(class, { character = character, generator = gen, petrol = petrol })
        end, complete = function(self) self.generator.fuel = self.generator.fuel + 4; return true end,
            isValid = function() return true end }
        ISTakeGenerator, ISDropWorldItemAction, ISUnequipAction, ISActivateGenerator = nil, nil, nil, nil
        G.install()
        local gen = generator({ diesel = 2 }, "TLG.DieselGenerator")
        local a = ISAddFuel:new(who, gen, can({ gasoline = 4 }))
        T.eq(#notes, 0)
        a:complete()
        T.eq(#notes, 1, "told at the end of the action")
        T.eq(notes[1].key, "IGUI_TLG_Note_WrongInTank"); T.eq(notes[1].fuel, "gasoline"); T.ok(notes[1].player == who)
        T.near(gen.md.tlg.q.gasoline, 4, 1e-6, "the record has what was poured")
        -- Diesel into it: nothing said.
        local fine = generator({ diesel = 2 }, "TLG.DieselGenerator")
        ISAddFuel:new(who, fine, can({ diesel = 4 })):complete()
        T.eq(#notes, 1)

        -- Vehicle: a can of diesel into a petrol car, stopped half way.
        ISAddGasolineToVehicle = { new = function(class, character, part, item)
            return action(class, { character = character, part = part, item = item, vehicle = part:getVehicle() })
        end, complete = function(self) self.vehicle.litres = self.vehicle.litres + 10; return true end,
            stop = function(self) self.vehicle.litres = self.vehicle.litres + 5 end, serverStop = function() end }
        ISTakeGasolineFromVehicle = nil
        ISStartVehicleEngine = { complete = function() return true end }
        V.install()
        local c = car({ gasoline = 10 })
        a = ISAddGasolineToVehicle:new(who, c.tank, can({ diesel = 10 }))
        a.vehicle.litres = a.vehicle.litres + 5
        a:stop()
        T.eq(#notes, 2, "a stopped refuel has poured too")
        T.eq(notes[2].fuel, "diesel")
        a:complete()
        T.eq(#notes, 2, "settled once")
        c = car({ gasoline = 10 })
        ISAddGasolineToVehicle:new(who, c.tank, can({ gasoline = 10 })):complete()
        T.eq(#notes, 2, "petrol into a petrol car")

        -- Pump: a petrol pump fills a diesel van.
        local pump = { md = { tlg = record("P1", { gasoline = 500 }) }, litres = 500 }
        function pump:getPipedFuelAmount() return self.litres end
        function pump:setPipedFuelAmount(n) self.litres = n end
        function pump:getModData() return self.md end
        function pump:transmitModData() end
        function pump:getSquare() return nil end
        ISRefuelFromGasPump = { new = function(class, character, part, fuelStation)
            return action(class, { character = character, part = part, fuelStation = fuelStation })
        end, complete = function(self)
            local v = self.part:getVehicle()
            v.litres, self.fuelStation.litres = v.litres + 20, self.fuelStation.litres - 20
            return true
        end, stop = function() end, serverStop = function() end }
        ISTakeFuel = nil
        S.install()
        local van = car({ diesel = 20 }, "Base.PickUpVan")
        ISRefuelFromGasPump:new(who, van.tank, pump):complete()
        T.eq(#notes, 3, "told at the pump")
        T.eq(notes[3].fuel, "gasoline"); T.ok(notes[3].player == who)
        T.near(van.tankMd.tlg.q.gasoline, 20, 1e-6, "the tank's record has the pump's petrol")
    end)
end)
