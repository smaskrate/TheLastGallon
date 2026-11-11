require "support/fixtures"
require "TLG/Integration/Containers"
-- As test_engine_effects: the adapters register installers through Boot.
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Integration/Generators"
require "TLG/Integration/Vehicles"
Events = savedEvents
local I, World, E = TLG.Integration, TLG.World, TLG.Domain.EngineEffects

-- Wrong fuel's damage as the adapters apply it (D-037): the condition a
-- refused start costs, the exhaust, the sudden failure, and the sandbox
-- option that switches it all off.
local GLOBALS = { "ModData", "getGameTime", "isServer", "isClient", "SandboxVars", "getScriptManager" }

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
    SandboxVars = { TheLastGallon = { VehicleStalls = true }, CarGasConsumption = 1, GeneratorFuelConsumption = 1 }
    local item = {}
    function item:getConditionLowerChance() return 30 end
    getScriptManager = function()
        local sm = {}
        function sm:FindItem() return item end
        return sm
    end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 9 }, {}
    local V, G, N = I.Vehicles, I.Generators, TLG.Notify
    local keep = { V.attemptRoll, V.failRoll, G.attemptRoll, G.failRoll, N.send }
    local notes = {}
    N.send = function(player, key, fuel) notes[#notes + 1] = { player = player, key = key, fuel = fuel } end
    local ok, err = pcall(fn, notes)
    V.attemptRoll, V.failRoll, G.attemptRoll, G.failRoll, N.send = keep[1], keep[2], keep[3], keep[4], keep[5]
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local function record(id, q)
    local deg, total = {}, 0
    for k, v in pairs(q) do deg[k], total = 0, total + v end
    return { v = 1, id = id, rev = 1, t = 100, q = q, deg = deg, stab = 0, mic = 0, cond = 1, prov = {} }, total
end

-- A running car with an engine, a battery and an exhaust.
local function car(q, script)
    local side, litres = record("V1", q)
    local x = { litres = litres, running = true, stalls = 0, power = 1000, cond = 100, muffler = 100, charge = 1,
        sends = {}, tankMd = { tlg = side }, engineMd = {}, mufflerMd = {}, hasMuffler = true }
    local function part(name, getC, setC, md)
        local p = { name = name }
        function p:getCondition() return getC() end
        function p:setCondition(c) setC(math.max(0, math.min(100, c))) end
        function p:getModData() return md end
        return p
    end
    local tank = part("GasTank", function() return 100 end, function() end, x.tankMd)
    function tank:getContainerContentAmount() return x.litres end
    function tank:getContainerCapacity() return 50 end
    local engine = part("Engine", function() return x.cond end, function(c) x.cond = c end, x.engineMd)
    local muffler = part("Muffler", function() return x.muffler end, function(c) x.muffler = c end, x.mufflerMd)
    function muffler:getInventoryItem() return x.hasMuffler and {} or nil end
    local cell = {}
    function cell:getCurrentUsesFloat() return x.charge end
    function cell:setCurrentUsesFloat(v) x.charge = v end
    local battery = part("Battery", function() return 100 end, function() end, {})
    function battery:getInventoryItem() return cell end
    function x:getPartById(id)
        if id == "GasTank" then return tank elseif id == "Engine" then return engine
        elseif id == "Muffler" then return muffler elseif id == "Battery" then return battery end
        return nil
    end
    function x:getId() return 9 end
    function x:getScriptName() return script or "Base.CarNormal" end
    function x:isEngineRunning() return self.running end
    function x:engineDoStalling() self.stalls, self.running = self.stalls + 1, false end
    function x:getEnginePower() return self.power end
    function x:getEngineQuality() return 80 end
    function x:getEngineLoudness() return 37 end
    function x:setEngineFeature(_, _, p) self.power = p end
    function x:transmitEngine() end
    function x:transmitPartCondition(p) self.sends[#self.sends + 1] = p.name end
    function x:transmitPartUsedDelta(p) self.sends[#self.sends + 1] = p.name .. ":charge" end
    function x:getDriver() return "the driver" end
    return x
end

local function generator(q, itemType)
    local side, litres = record("G1", q)
    local x = { fuel = litres, cond = 100, md = { tlg = side, generatorFullType = itemType } }
    function x:getFuel() return self.fuel end
    function x:getMaxFuel() return 10 end
    function x:getModData() return self.md end
    function x:getCondition() return self.cond end
    function x:setCondition(c) self.cond = math.max(0, math.min(100, c)) end
    function x:getGeneratorItemType() return itemType or "Base.Generator" end
    function x:isActivated() return true end
    return x
end

local NEVER = { next = function() return 0.99 end }

T.case("wrong fuel damage: a start refused by diesel in a petrol car costs engine condition and battery", function()
    inGame(function(notes)
        local V = I.Vehicles
        local x = car({ gasoline = 6, diesel = 4 })
        local e = V.evaluate(x)
        T.ok(not e.compatible and e.attemptDamage ~= nil)
        local asked
        V.attemptRoll = function(min, max) asked = { min, max }; return 2 end
        T.eq(V.attemptDamage(x, e, "p1"), 2)
        T.eq(asked[1], 1); T.eq(asked[2], 2)
        T.eq(x.cond, 98)
        T.near(x.charge, 1 - V.ATTEMPT_BATTERY, 1e-12)
        T.eq(x.sends[1], "Engine"); T.eq(x.sends[2], "Battery:charge")
        T.eq(#notes, 1); T.eq(notes[1].player, "p1"); T.eq(notes[1].key, "IGUI_TLG_Note_StartDamage")
        T.eq(notes[1].fuel, "diesel")
        -- The engine never goes below 0.
        x.cond = 1
        V.attemptDamage(x, e, "p1")
        T.eq(x.cond, 0)
    end)
end)

T.case("wrong fuel damage: other refused starts cost nothing", function()
    inGame(function(notes)
        local V = I.Vehicles
        V.attemptRoll = function() return 2 end
        -- Stale petrol past the engine's limit: refused, no damage.
        local x = car({ gasoline = 10 })
        x.tankMd.tlg.deg.gasoline = 3.6
        local e = V.evaluate(x)
        T.ok(not e.compatible and e.attemptDamage == nil)
        T.eq(V.attemptDamage(x, e, "p1"), 0)
        -- Petrol in a diesel that lost its start roll: it would have run.
        x = car({ diesel = 6, gasoline = 4 }, "Base.VanAmbulance")
        World.get().dieselVehicles = true
        e = V.evaluate(x)
        T.ok(e.compatible and e.harmful and e.startFactor < 1)
        T.eq(V.attemptDamage(x, e, "p1"), 0)
        T.eq(x.cond, 100); T.eq(x.charge, 1); T.eq(#notes, 0)
        T.eq(V.attemptDamage(x, nil, "p1"), 0)
    end)
end)

T.case("wrong fuel damage: diesel in a running petrol engine wears the engine and the exhaust by the litre", function()
    inGame(function()
        local V = I.Vehicles
        V.failRoll = function() return 0 end
        -- 20 % diesel: wear factor 6, exhaust 0.5 a litre, no failure chance.
        local x = car({ gasoline = 8, diesel = 2 })
        V.applyEffects(x, NEVER)
        x.litres = 6
        V.applyEffects(x, NEVER)
        -- 4 L at (6 - 1) x 0.15 = 3 points; the exhaust 4 x 0.5 = 2 points.
        T.eq(x.cond, 97); T.eq(x.muffler, 98)
        T.ok(x.running, "no failure in this band, whatever the draw")
        x.litres = 5
        V.applyEffects(x, NEVER)
        T.near(x.engineMd.tlgWear, 0.75, 1e-9); T.near(x.mufflerMd.tlgWear, 0.5, 1e-9)
        T.eq(x.muffler, 98, "half a point carried")
        -- No exhaust fitted: only the engine wears.
        local y = car({ gasoline = 8, diesel = 2 })
        y.hasMuffler = false
        V.applyEffects(y, NEVER)
        y.litres = 6
        V.applyEffects(y, NEVER)
        T.eq(y.cond, 97); T.eq(y.muffler, 100)
    end)
end)

T.case("wrong fuel damage: a diesel on petrol can fail; the draw is against the litres burned", function()
    inGame(function(notes)
        local V = I.Vehicles
        World.get().dieselVehicles = true
        local x = car({ gasoline = 10 }, "Base.VanAmbulance")
        local e = V.evaluate(x)
        T.ok(e.compatible and e.failureChance == 0.02)
        local odds = E.failureOdds(0.02, 2)
        -- A draw just above the odds for 2 L: it runs on, with wear 15.
        V.failRoll = function() return odds + 1e-6 end
        V.applyEffects(x, NEVER)
        x.litres = 8
        V.applyEffects(x, NEVER)
        T.ok(x.running); T.eq(x.stalls, 0)
        T.eq(x.cond, 100 - 4, "2 L x 14 x 0.15 = 4.2 points")
        -- Just below: the engine is dead and stops, and the driver is told.
        V.failRoll = function() return odds - 1e-6 end
        x.litres = 6
        V.applyEffects(x, NEVER)
        T.eq(x.cond, 0); T.ok(not x.running); T.eq(x.stalls, 1)
        T.eq(#notes, 1); T.eq(notes[1].key, "IGUI_TLG_Note_EngineFailed")
        T.eq(notes[1].player, "the driver"); T.eq(notes[1].fuel, "gasoline")
    end)
end)

T.case("wrong fuel damage: with the stall option off a car runs on fuel that would not start it, and pays", function()
    inGame(function()
        local V = I.Vehicles
        SandboxVars.TheLastGallon.VehicleStalls = false
        V.failRoll = function() return 0.99 end
        local x = car({ gasoline = 6, diesel = 4 })
        V.applyEffects(x, { next = function() return 0 end })
        x.litres = 8
        V.applyEffects(x, { next = function() return 0 end })
        T.ok(x.running); T.eq(x.stalls, 0)
        T.eq(x.power, 500, "the power floor")
        T.eq(x.cond, 100 - 2, "2 L x 9 x 0.15 = 2.7 points")
        T.eq(x.muffler, 98, "2 L x 1.0")
    end)
end)

T.case("wrong fuel damage: the sandbox option off brings back the plain block", function()
    inGame(function(notes)
        local V = I.Vehicles
        SandboxVars.TheLastGallon.WrongFuelDamage = false
        T.eq(V.wrongFuelDamageEnabled(), false)
        World.get().dieselVehicles = true
        local x = car({ gasoline = 10 }, "Base.VanAmbulance")
        local e = V.evaluate(x)
        T.ok(not e.compatible and not e.harmful and e.wearFactor == 1)
        V.attemptRoll = function() return 2 end
        T.eq(V.attemptDamage(x, e, "p1"), 0)
        V.failRoll = function() return 0 end
        V.applyEffects(x, NEVER)
        T.eq(x.stalls, 1, "it stalls, as a blocked fuel always did")
        T.eq(x.cond, 100); T.eq(#notes, 0)
        SandboxVars.TheLastGallon.WrongFuelDamage = nil
        T.eq(V.wrongFuelDamageEnabled(), true, "on unless switched off")
    end)
end)

T.case("wrong fuel damage: a generator pays for a refused start and can fail on what it burned", function()
    inGame(function(notes)
        local G = I.Generators
        -- A petrol generator with 40 % diesel does not start.
        local x = generator({ gasoline = 3, diesel = 2 })
        local e = G.evaluate(x)
        T.ok(not e.compatible and e.attemptDamage ~= nil)
        G.attemptRoll = function() return 1 end
        T.eq(G.attemptDamage(x, e, "p2"), 1)
        T.eq(x.cond, 99); T.eq(notes[1].key, "IGUI_TLG_Note_StartDamage"); T.eq(notes[1].fuel, "diesel")
        -- The Diesel Generator on petrol runs: 15 times the wear factor.
        local d = generator({ gasoline = 5 }, "TLG.DieselGenerator")
        T.eq(G.profile(d), "generator_ci_bio")
        e = G.evaluate(d)
        T.ok(e.compatible and e.harmful and e.failureChance == 0.02)
        T.eq(G.attemptDamage(d, e, "p2"), 0, "a lost start roll costs nothing")
        local perLitre = E.generatorWearPerLitre(30, 1)
        G.failRoll = function() return 0.99 end
        d.fuel = 4
        T.eq(G.chargeWear(d), math.floor(14 * perLitre + 1e-9), "1 L at factor 15")
        T.eq(d.cond, 100 - math.floor(14 * perLitre + 1e-9))
        -- The next litre fails it: condition 0, which switches it off.
        local before = d.cond
        G.failRoll = function() return 0 end
        d.fuel = 3
        T.ok(G.chargeWear(d) >= before, "all that was left")
        T.eq(d.cond, 0)
        -- The same litres are not drawn for twice.
        d.cond = 50
        T.eq(G.chargeWear(d), 0)
        T.eq(d.cond, 50)
    end)
end)
