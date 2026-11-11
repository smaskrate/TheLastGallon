require "support/fixtures"
require "TLG/Integration/Containers"
-- Generators and Vehicles register their installers through Boot, which
-- hooks the game's Events as it loads; a stand-in for these requires only
-- (as test_fuel_reads does).
local savedEvents = Events
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
require "TLG/Integration/Generators"
require "TLG/Integration/Vehicles"
Events = savedEvents
local I, World, E = TLG.Integration, TLG.World, TLG.Domain.EngineEffects

-- Stand-ins for the game calls the engine effects make: global ModData and
-- the clock, single-player authority (isServer false, isClient false), the
-- sandbox and the item scripts. Installed for one case and removed again.
local GLOBALS = { "ModData", "getGameTime", "isServer", "isClient", "SandboxVars", "getScriptManager" }

local function fakeGame(oneIn)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = 100, store = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    isServer = function() return false end
    isClient = function() return false end
    SandboxVars = { TheLastGallon = { VehicleStalls = true }, CarGasConsumption = 1, GeneratorFuelConsumption = 1 }
    local item = {}
    function item:getConditionLowerChance() return oneIn or 30 end
    getScriptManager = function()
        local sm = {}
        function sm:FindItem(name) return name == "Base.Generator" and item or nil end
        return sm
    end
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 190, hourOfDay = 9 }, {}
    -- Fuel the mod did not see comes in at a fixed baseline (test_fuel_reads).
    local untracked = I.Containers.untrackedDeg
    I.Containers.untrackedDeg = function() return 0.07 end
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
        I.Containers.untrackedDeg = untracked
    end
    return g
end

local function inGame(oneIn, fn)
    local g = fakeGame(oneIn)
    local ok, err = pcall(fn, g)
    g.restore()
    if not ok then error(err, 0) end
end

local function record(id, q, deg)
    local total = 0
    for _, v in pairs(q) do total = total + v end
    return { v = 1, id = id, rev = 1, t = 100, q = q, deg = deg, stab = 0, mic = 0, cond = 1, prov = {} }, total
end

-- A running car: its tank holds `q` as recorded, its engine has power 1000,
-- quality 80 and a stored loudness of 37. setEngineFeature stores loudness
-- times 0.37037036, as the game does (BC VehicleEngine.setFeatures).
local function car(q, deg)
    local side, litres = record("V1", q, deg)
    local x = { litres = litres, running = true, stalls = 0, power = 1000, quality = 80, loudness = 37,
        sets = 0, engineSends = 0, conditionSends = 0, cond = 100, tankMd = { tlg = side }, engineMd = {} }
    local tank, engine = {}, {}
    function tank:getContainerContentAmount() return x.litres end
    function tank:getContainerCapacity() return 50 end
    function tank:getModData() return x.tankMd end
    function engine:getModData() return x.engineMd end
    function engine:getCondition() return x.cond end
    function engine:setCondition(c) x.cond = math.max(0, math.min(100, c)) end
    function x:getPartById(id)
        if id == "GasTank" then return tank elseif id == "Engine" then return engine end
        return nil
    end
    function x:getId() return 7 end
    function x:getScriptName() return "Base.CarNormal" end
    function x:isEngineRunning() return self.running end
    function x:engineDoStalling() self.stalls, self.running = self.stalls + 1, false end
    function x:getEnginePower() return self.power end
    function x:getEngineQuality() return self.quality end
    function x:getEngineLoudness() return self.loudness end
    function x:setEngineFeature(qq, l, p)
        self.sets = self.sets + 1
        self.quality = math.max(0, math.min(100, qq))
        self.loudness = math.floor(l * 0.37037036)
        self.power = p
    end
    function x:transmitEngine() self.engineSends = self.engineSends + 1 end
    function x:transmitPartCondition() self.conditionSends = self.conditionSends + 1 end
    x.tank, x.engine = tank, engine
    return x
end

local NEVER = { next = function() return 0.99 end }
local ALWAYS = { next = function() return 0 end }

-- Stale petrol: 2.6 of the stock engine's 3.5, power 0.8514, wear 1.7429.
local STALE = { { gasoline = 10 }, { gasoline = 2.6 } }
-- 3 L of diesel in 8 L: a spark engine does not fire on it (D-037).
local D37 = { { gasoline = 5, diesel = 3 }, { gasoline = 0, diesel = 0 } }

T.case("integration: with the stall option off a running engine on fuel it cannot take keeps running", function()
    inGame(nil, function()
        local x = car(D37[1], D37[2])
        SandboxVars.TheLastGallon.VehicleStalls = false
        for _ = 1, 5 do I.Vehicles.applyEffects(x, ALWAYS) end
        T.eq(x.stalls, 0, "never stalled, however the roll fell")
        T.ok(x.running)
        T.eq(x.power, 500, "half power: a car that runs can still move")
        SandboxVars.TheLastGallon.VehicleStalls = true
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.stalls, 1, "with the option on it stalls at once")
    end)
end)

T.case("integration: poor fuel lowers a running car's power once and gives it back when it stops", function()
    inGame(nil, function()
        local x = car(STALE[1], STALE[2])
        local e = I.Vehicles.evaluate(x)
        T.ok(e.compatible and e.powerFactor < 1, string.format("power factor %.6f", e.powerFactor))
        local want = E.targetPower(1000, e.powerFactor)
        T.eq(want, 851)
        for _ = 1, 4 do I.Vehicles.applyEffects(x, NEVER) end
        T.eq(x.power, 851, "lowered once")
        T.eq(x.loudness, 37, "loudness kept through setEngineFeature")
        T.eq(x.quality, 80, "quality kept")
        T.eq(x.engineSends, 1, "sent to the clients once")
        T.eq(x.engineMd.tlgPower.base, 1000)
        x.running = false
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.power, 1000, "its own power back")
        T.eq(x.loudness, 37)
        T.eq(x.engineMd.tlgPower, nil, "nothing kept")
        local sets = x.sets
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.sets, sets, "a stopped engine the mod no longer lowers is left alone")
    end)
end)

T.case("integration: a repair while running on poor fuel becomes the car's power", function()
    inGame(nil, function()
        local x = car(STALE[1], STALE[2])
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.power, 851)
        x.power = 1200 -- VehiclePart.repair sets the script's force
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.power, 1022, "lowered from 1200")
        x.running = false
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.power, 1200)
    end)
end)

T.case("integration: a car's engine wears for each litre it burns on poor fuel", function()
    inGame(nil, function()
        local x = car(STALE[1], STALE[2])
        local wf = I.Vehicles.evaluate(x).wearFactor
        T.near(wf, 1 + 2.6 / 3.5, 1e-9)
        I.Vehicles.applyEffects(x, NEVER) -- the first minute only notes the tank
        T.eq(x.cond, 100)
        for _ = 1, 3 do
            x.litres = x.litres - 3 -- the game's burn between two minutes
            I.Vehicles.applyEffects(x, NEVER)
        end
        local due = 9 * (wf - 1) * 0.15
        T.eq(x.cond, 99, string.format("%.6f points due", due))
        T.eq(x.conditionSends, 1)
        T.near(x.engineMd.tlgWear, due - 1, 1e-9, "the rest carried")
        -- Refuelled while running: no wear, only a new reference.
        x.litres = 20
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(x.cond, 99)
        -- Twice the sandbox's car fuel use: half the wear per litre (at the
        -- blend the refuel made: the petrol came in unseen, at the baseline).
        SandboxVars.CarGasConsumption = 2
        local carry = x.engineMd.tlgWear
        x.litres = 18
        local wf2 = I.Vehicles.evaluate(x).wearFactor
        T.ok(wf2 > 1 and wf2 < wf, string.format("wear factor %.6f after the refuel", wf2))
        I.Vehicles.applyEffects(x, NEVER)
        T.near(x.engineMd.tlgWear, carry + 2 * (wf2 - 1) * 0.075, 1e-9)
        -- Stopped: the reference goes, and so nothing counts across a stop.
        x.running = false
        I.Vehicles.applyEffects(x, NEVER)
        T.eq(I.Vehicles.lastTank[7], nil)
    end)
end)

T.case("integration: good fuel costs a car neither power nor wear", function()
    inGame(nil, function()
        local x = car({ gasoline = 10 }, { gasoline = 0.2 })
        for _ = 1, 3 do
            x.litres = x.litres - 3
            I.Vehicles.applyEffects(x, NEVER)
        end
        T.eq(x.power, 1000)
        T.eq(x.sets, 0)
        T.eq(x.cond, 100)
        T.eq(x.stalls, 0)
    end)
end)

-- A generator holding `q` as recorded, condition 100, Base.Generator.
local function generator(q, deg)
    local side, litres = record("G1", q, deg)
    local x = { fuel = litres, cond = 100, md = { tlg = side } }
    function x:getFuel() return self.fuel end
    function x:getMaxFuel() return 10 end
    function x:getModData() return self.md end
    function x:getCondition() return self.cond end
    function x:setCondition(c) self.cond = math.max(0, math.min(100, c)) end
    function x:getGeneratorItemType() return "Base.Generator" end
    function x:isActivated() return true end
    return x
end

T.case("integration: a generator is charged once for each litre burned since its record was written", function()
    inGame(30, function()
        -- 3.0 of a generator's 4.0: wear factor 1.75; a litre at factor 2 is 1/3 of a point.
        local x = generator({ gasoline = 10 }, { gasoline = 3.0 })
        local perLitre = E.generatorWearPerLitre(30, 1)
        T.eq(I.Generators.chargeWear(x), 0, "nothing burned")
        x.fuel = 4
        T.eq(I.Generators.chargeWear(x), 1, "6 L: 1.5 points")
        T.eq(x.cond, 99)
        T.near(x.md.tlgWear.c, 6 * 0.75 * perLitre - 1, 1e-9)
        T.eq(I.Generators.chargeWear(x), 0, "the same litres are not charged twice")
        T.eq(x.cond, 99)
        x.fuel = 2
        T.eq(I.Generators.chargeWear(x), 1, "2 L more: 0.5 + 0.5")
        T.eq(x.cond, 98)
        x.fuel = 0
        I.Generators.chargeWear(x)
        T.near(x.md.tlgWear.c, 0.5, 1e-9, "a tank run dry still charges what it burned")
        T.eq(x.md.tlgWear.charged, 10)
    end)
end)

T.case("integration: a generator's rewritten record starts the count again; unseen fuel is not charged", function()
    inGame(30, function()
        local x = generator({ gasoline = 10 }, { gasoline = 3.0 })
        x.fuel = 7
        I.Generators.chargeWear(x)
        -- The mod writes a new record holding the tank as it is (a refuel, a look).
        local side = record("G1", { gasoline = 9 }, { gasoline = 3.0 })
        side.rev = 2
        x.md.tlg, x.fuel = side, 9
        local carry = x.md.tlgWear.c
        T.eq(I.Generators.chargeWear(x), 0)
        T.eq(x.md.tlgWear.charged, 0, "counted from the new record")
        T.near(x.md.tlgWear.c, carry, 1e-12, "the fraction kept")
        -- 2 L burned, then 3 L poured in where the mod did not see it.
        x.fuel = 7
        I.Generators.chargeWear(x)
        local c1 = x.md.tlgWear.c
        x.fuel = 10
        I.Generators.chargeWear(x)
        T.near(x.md.tlgWear.c, c1, 1e-12, "no wear for fuel coming in")
        x.fuel = 8
        I.Generators.chargeWear(x)
        T.near(x.md.tlgWear.c, c1 + 2 * 0.75 * E.generatorWearPerLitre(30, 1), 1e-9,
            "the 2 L burned after it are charged")
    end)
end)

T.case("integration: generator wear follows the item's own rate and good fuel adds none", function()
    inGame(24, function()
        local x = generator({ gasoline = 10 }, { gasoline = 3.0 })
        x.fuel = 9
        I.Generators.chargeWear(x)
        T.near(x.md.tlgWear.c, 1 * 0.75 * (1.5 / 24 / 0.15), 1e-9, "Base.Generator scripted 1 in 24 here")
        local fresh = generator({ gasoline = 10 }, { gasoline = 0.2 })
        fresh.fuel = 1
        T.eq(I.Generators.chargeWear(fresh), 0)
        T.eq(fresh.cond, 100)
    end)
end)

T.case("integration: a multiplayer client never charges generator wear", function()
    inGame(30, function()
        isClient = function() return true end
        local x = generator({ gasoline = 10 }, { gasoline = 3.0 })
        x.fuel = 1
        T.eq(I.Generators.chargeWear(x), 0)
        T.eq(x.cond, 100)
        T.eq(x.md.tlgWear, nil)
    end)
end)
