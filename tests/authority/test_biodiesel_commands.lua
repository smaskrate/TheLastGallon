require "support/fixtures"
-- The handlers' adapters register game events when they load (TLG/Boot); a
-- stand-in event list takes them (as tests/authority/test_machine_commands.lua).
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/Authority/MachineHandlers"
Events = savedEvents
local H, Machines, World, Process = TLG.Authority.Handlers, TLG.Integration.Machines, TLG.World, TLG.Domain.Process
local R = TLG.Registry

-- Stand-ins for the game calls a machine command makes (as
-- tests/authority/test_machine_commands.lua), with the two globals a load
-- from the inventory reads: the water fluid and the cooking perk.
local GLOBALS = { "ModData", "getGameTime", "getCell", "getClimateManager", "isServer", "isClient", "getWorld",
    "Fluid", "Perks" }

local function fakeGame(now)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local g = { now = now, squares = {}, store = {} }
    ModData = { getOrCreate = function(k)
        g.store[k] = g.store[k] or {}
        return g.store[k]
    end }
    local clock = {}
    function clock:getWorldAgeHours() return g.now end
    getGameTime = function() return clock end
    local cell = {}
    function cell:getGridSquare(x, y, z) return g.squares[x .. "," .. y .. "," .. z] end
    getCell = function() return cell end
    local cm, values, world = {}, {}, {}
    function cm:getAirTemperatureForSquare() return 22 end
    function cm:getTemperature() return 22 end
    function values:getDayLightLagged() return 0.5 end
    function cm:getClimateValuesCopy() return values end
    getClimateManager = function() return cm end
    function world:isHydroPowerOn() return false end
    getWorld = function() return world end
    isServer = function() return false end
    isClient = function() return false end
    Fluid = { Water = "water" }
    Perks = { Cooking = "cooking" }
    local md = World.get()
    md.v, md.calendar, md.climateLog = 1, { dayOfYear = 180, hourOfDay = 0 }, { [0] = { t = 22, rh = 0.7 } }
    -- A machine's first record takes an id from the world's counter.
    md.seed, md.nextId = 7, 1
    function g.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return g
end

local function square(g, x, y)
    local sq = { x = x, y = y, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return 0 end
    function sq:isInARoom() return true end
    local list = {}
    function list:size() return #sq.objs end
    function list:get(i) return sq.objs[i + 1] end
    function sq:getWorldObjects() return list end
    g.squares[x .. "," .. y .. ",0"] = sq
    return sq
end

-- A machine item lying on `sq` (machines are items on the ground, D-015).
local ids = 100
local function machine(fullType, sq, rec)
    ids = ids + 1
    local item, wi, md, id = {}, {}, { tlgProc = rec }, ids
    function wi:getSquare() return sq end
    function wi:getItem() return item end
    function item:getFullType() return fullType end
    function item:getModData() return md end
    function item:getWorldItem() return wi end
    function item:getID() return id end
    sq.objs[#sq.objs + 1] = wi
    return item
end

-- A machine's record with a finished batch of `outputs` waiting in it.
local function finished(machineId, outputs)
    local p = Process.new({ id = "F-" .. machineId, machine = machineId, t = 2 })
    p.state, p.outputs = "OutputReady", outputs
    return p
end

-- The requesting player and what they carry.
local function player()
    local p, inv = { items = {} }, {}
    local bag = {}
    function bag:Remove(item)
        for i = #p.items, 1, -1 do
            if p.items[i] == item then table.remove(p.items, i) end
        end
    end
    function inv:getAllEvalRecurse(pred)
        local found, list = {}, {}
        for _, it in ipairs(p.items) do
            if pred(it) then found[#found + 1] = it end
        end
        function list:size() return #found end
        function list:get(i) return found[i + 1] end
        return list
    end
    function inv:getItemWithIDRecursiv() return nil end
    function inv:getFirstTypeRecurse() return nil end
    function inv:AddItem(fullType) return p:give(fullType) end
    function p:getInventory() return inv end
    function p:getUsername() return "tester" end
    function p:getSquare() return nil end
    function p:getPerkLevel() return 0 end
    -- An item of `fullType`; `left` is the share of a food item not yet used.
    function p:give(fullType, left)
        ids = ids + 1
        local item, id = {}, ids
        function item:getFullType() return fullType end
        function item:getID() return id end
        function item:getContainer() return bag end
        function item:getFluidContainer() return nil end
        if left then
            function item:getBaseHunger() return -0.3 end
            function item:getHungChange() return -0.3 * left end
        end
        p.items[#p.items + 1] = item
        return item
    end
    -- A container of clean water.
    function p:giveWater(litres)
        local item, fc = p:give("Base.BucketEmpty"), { amount = litres }
        function fc:isEmpty() return self.amount <= 0 end
        function fc:isPureFluid(f) return f == Fluid.Water end
        function fc:getAmount() return self.amount end
        function fc:adjustAmount(a) self.amount = a end
        function item:getFluidContainer() return fc end
        function item:syncItemFields() end
        return fc
    end
    function p:count(fullType)
        local n = 0
        for _, it in ipairs(p.items) do
            if it:getFullType() == fullType then n = n + 1 end
        end
        return n
    end
    return p
end

local requests = 0
local function req(item, extra)
    requests = requests + 1
    local args = { requestId = "biodiesel-" .. requests, target = Machines.refFor(item) }
    for k, v in pairs(extra or {}) do args[k] = v end
    return args
end

local function inGame(fn)
    local g = fakeGame(2)
    local ok, err = pcall(fn, g)
    g.restore()
    if not ok then error(err, 0) end
end

local function rec(item) return item:getModData().tlgProc end

-- A reactor with a finished retort (methanol) and leacher (lye) beside it.
local function reactorSite(g, methanolL, lyeKg)
    local retort = machine("TLG.WoodRetort", square(g, 1, 1), finished("wood_retort", { methanol = methanolL }))
    local leacher = machine("TLG.LyeLeacher", square(g, 2, 1), finished("lye_leacher", { lye = lyeKg }))
    local reactor = machine("TLG.BiodieselReactor", square(g, 1, 2), nil)
    return reactor, retort, leacher
end

T.case("biodiesel: the reactor takes oil from the inventory and methanol and lye from the machines beside it", function()
    inGame(function(g)
        local reactor, retort, leacher = reactorSite(g, 10, 2)
        local p = player()
        for _ = 1, 30 do p:give("Base.OilVegetable") end
        local recipe = R.need("recipe", "biodiesel_react").params
        local r = H.commands["machine.load"](p, req(reactor))
        T.eq(r.ok, true, tostring(r.reason))
        T.eq(r.state, "Processing")
        T.near(r.oilL, 27, 1e-9, "30 bottles of 0.9 L")
        T.near(r.methanolL, 27 * recipe.methanolPerOil, 1e-9, "methanol in the recipe's ratio")
        T.near(r.lyeKg, 27 * recipe.lyePerOil, 1e-9, "lye in the recipe's ratio")
        T.eq(p:count("Base.OilVegetable"), 0, "the bottles are used")
        T.near(rec(retort).outputs.methanol, 10 - r.methanolL, 1e-9, "the rest of the methanol stays in the retort")
        T.eq(rec(retort).state, "OutputReady")
        T.near(rec(leacher).outputs.lye, 2 - r.lyeKg, 1e-9, "the rest of the lye stays in the leacher")
        -- The same request again is answered from the ledger: nothing more is taken.
        local again = H.commands["machine.load"](p, { requestId = r.requestId, target = Machines.refFor(reactor) })
        T.eq(again.duplicate, true)
        T.near(rec(retort).outputs.methanol, 10 - r.methanolL, 1e-9)
    end)
end)

T.case("biodiesel: the retort's methanol limits the oil taken; a part-used bottle counts for what is left", function()
    inGame(function(g)
        local recipe = R.need("recipe", "biodiesel_react").params
        -- Methanol for 6 L of oil: six bottles fit (5.4 L), a seventh does not,
        -- and the half bottle (0.45 L) does.
        local reactor, retort = reactorSite(g, 6 * recipe.methanolPerOil, 2)
        local p = player()
        for _ = 1, 10 do p:give("Base.OilVegetable") end
        p:give("Base.OilVegetable", 0.5)
        local r = H.commands["machine.load"](p, req(reactor))
        T.eq(r.ok, true, tostring(r.reason))
        T.near(r.oilL, 5.85, 1e-9)
        T.eq(p:count("Base.OilVegetable"), 4, "four full bottles left")
        T.near(rec(retort).outputs.methanol, (6 - 5.85) * recipe.methanolPerOil, 1e-9)
    end)
end)

T.case("biodiesel: a reactor load that cannot be made takes nothing", function()
    inGame(function(g)
        local reactor, retort, leacher = reactorSite(g, 10, 2)
        local p = player()
        for _ = 1, 3 do p:give("Base.OilVegetable") end
        local r = H.commands["machine.load"](p, req(reactor))
        T.eq(r.ok, false)
        T.eq(r.reason, "not_enough_plant_oil", "2.7 L is under the 5 L a batch needs")
        T.near(r.oilAvailableL, 2.7, 1e-9)
        T.eq(p:count("Base.OilVegetable"), 3)
        T.near(rec(retort).outputs.methanol, 10, 1e-9)
        T.near(rec(leacher).outputs.lye, 2, 1e-9)
        T.eq(rec(reactor), nil, "the reactor's record is not written")
    end)
    inGame(function(g)
        local reactor = machine("TLG.BiodieselReactor", square(g, 1, 2), nil)
        machine("TLG.LyeLeacher", square(g, 2, 1), finished("lye_leacher", { lye = 2 }))
        T.eq(H.commands["machine.load"](player(), req(reactor)).reason, "no_ready_retort")
    end)
    inGame(function(g)
        local reactor = machine("TLG.BiodieselReactor", square(g, 1, 2), nil)
        machine("TLG.WoodRetort", square(g, 1, 1), finished("wood_retort", { methanol = 10 }))
        T.eq(H.commands["machine.load"](player(), req(reactor)).reason, "no_ready_leacher")
        -- A retort four tiles away is out of reach.
        machine("TLG.LyeLeacher", square(g, 1, 6), finished("lye_leacher", { lye = 2 }))
        T.eq(H.commands["machine.load"](player(), req(reactor)).reason, "no_ready_leacher")
    end)
end)

T.case("biodiesel: reactor, wash tank and the hours between give washed biodiesel", function()
    inGame(function(g)
        local reactor = reactorSite(g, 10, 2)
        local tank = machine("TLG.BiodieselWashTank", square(g, 2, 2), nil)
        local p = player()
        for _ = 1, 30 do p:give("Base.OilVegetable") end
        for _ = 1, 4 do p:give("Base.Firewood") end
        local water = p:giveWater(40)
        T.eq(H.commands["machine.addFuel"](p, req(reactor)).ok, true)
        local loaded = H.commands["machine.load"](p, req(reactor))
        T.eq(loaded.ok, true, tostring(loaded.reason))
        -- No crude yet: the tank has nothing to take.
        T.eq(H.commands["machine.load"](p, req(tank)).reason, "no_ready_reactor")
        -- Mixing half an hour, reacting two, settling eight.
        g.now = 2 + 10.5 + 0.01
        local s = H.commands["machine.status"](p, req(reactor))
        T.eq(s.state, "OutputReady", tostring(s.pause))
        local conversion = R.need("recipe", "biodiesel_react").params.baseConversion
        T.near(s.outputs.biodiesel, 27 * conversion, 1e-6, "the oil converted")
        -- The crude goes to the wash tank, never into a can.
        T.eq(H.commands["machine.collect"](p, req(reactor, { destination = { kind = "item", id = 1 } })).reason,
            "use_next_machine")
        for _ = 1, 2 do p:give("Base.Firewood") end
        T.eq(H.commands["machine.addFuel"](p, req(tank)).ok, true)
        local washed = H.commands["machine.load"](p, req(tank))
        T.eq(washed.ok, true, tostring(washed.reason))
        local perL = R.need("recipe", "biodiesel_wash").params.washWaterPerL
        T.near(washed.washWaterL, 27 * conversion * perL, 1e-6, "wash water for the biodiesel in the crude")
        T.near(water.amount, 40 - washed.washWaterL, 1e-6, "taken from the bucket")
        T.ok((washed.discarded.glycerin or 0) > 0, "the reactor's glycerin is thrown away")
        T.eq(rec(reactor).state, "Ready", "the reactor is empty")
        -- Washing an hour, settling a day, drying three hours.
        g.now = g.now + 28 + 0.01
        s = H.commands["machine.status"](p, req(tank))
        T.eq(s.state, "OutputReady", tostring(s.pause))
        T.near(s.outputs.biodiesel, 27 * conversion, 1e-6, "washing loses no biodiesel")
        local q = rec(tank).outProps.quality
        T.ok(q.grade == "good" or q.grade == "fair", "a batch in the recipe's ratios washes to usable fuel: " ..
            tostring(q.grade))
        T.ok(q.methanol < 0.01, "the methanol is washed out")
    end)
end)

-- Runs a loaded machine to the end of its batch and returns its status.
local function finish(g, p, item, hours)
    g.now = g.now + hours + 0.01
    return H.commands["machine.status"](p, req(item))
end

T.case("biodiesel: firewood through the retort gives methanol, and its charcoal with the last of it", function()
    inGame(function(g)
        local retort = machine("TLG.WoodRetort", square(g, 1, 1), nil)
        local leacher = machine("TLG.LyeLeacher", square(g, 2, 1), finished("lye_leacher", { lye = 2 }))
        local reactor = machine("TLG.BiodieselReactor", square(g, 1, 2), nil)
        local p = player()
        -- 12 logs: 108 kg. The retort takes 11 (99 kg of the 100 it holds);
        -- the last one feeds the firebox.
        for _ = 1, 12 do p:give("Base.Log") end
        local r = H.commands["machine.load"](p, req(retort))
        T.eq(r.ok, true, tostring(r.reason))
        T.near(r.woodKg, 99, 1e-9)
        T.eq(p:count("Base.Log"), 1)
        T.eq(H.commands["machine.addFuel"](p, req(retort)).ok, true)
        -- Heating up 1.5 h, carbonizing 99 kg at 10 kg/h, cooling 6 h. One
        -- log does not last: the firebox is fed again when it stops.
        local s = finish(g, p, retort, 1.5 + 9.9 + 6)
        T.eq(s.pause, "no_heat", "9 kg of wood is not enough heat")
        for _ = 1, 3 do p:give("Base.Log") end
        T.eq(H.commands["machine.addFuel"](p, req(retort)).ok, true)
        s = finish(g, p, retort, 1.5 + 9.9 + 6)
        T.eq(s.state, "OutputReady", tostring(s.pause))
        local params = R.need("recipe", "methanol_wood_distill").params
        local methanol = 99 * params.methanolKgPerKg / R.need("fuel", "methanol").density
        T.near(s.outputs.methanol, methanol, 1e-6)
        -- 5.01 L of methanol covers 33.4 L of oil: 37 bottles (33.3 L) fit,
        -- which leaves a little in the retort, and its charcoal with it.
        for _ = 1, 40 do p:give("Base.OilVegetable") end
        local first = H.commands["machine.load"](p, req(reactor))
        T.eq(first.ok, true, tostring(first.reason))
        T.near(first.oilL, 33.3, 1e-9)
        T.eq(first.charcoal, 0, "methanol is left: the retort is not empty")
        T.eq(p:count("Base.Charcoal"), 0)
        T.eq(rec(retort).state, "OutputReady")
        T.near(rec(leacher).outputs.lye, 2 - first.lyeKg, 1e-9)
    end)
    inGame(function(g)
        -- A retort holding exactly what 6 bottles need is emptied by the load.
        local recipe = R.need("recipe", "biodiesel_react").params
        local full = finished("wood_retort", { methanol = 5.4 * recipe.methanolPerOil })
        full.byproducts = { charcoal = 27.72, wood_tar = 6.93, water = 31.7 }
        local retort = machine("TLG.WoodRetort", square(g, 1, 1), full)
        machine("TLG.LyeLeacher", square(g, 2, 1), finished("lye_leacher", { lye = 2 }))
        local reactor = machine("TLG.BiodieselReactor", square(g, 1, 2), nil)
        local p = player()
        for _ = 1, 6 do p:give("Base.OilVegetable") end
        local r = H.commands["machine.load"](p, req(reactor))
        T.eq(r.ok, true, tostring(r.reason))
        T.eq(rec(retort).state, "Ready", "the retort is empty")
        T.eq(r.charcoal, 27)
        T.eq(p:count("Base.Charcoal"), 27, "its charcoal, in whole kilograms")
    end)
end)

T.case("biodiesel: firewood through the ash barrel and the leacher gives lye", function()
    inGame(function(g)
        local barrel = machine("TLG.AshBarrel", square(g, 1, 1), nil)
        local leacher = machine("TLG.LyeLeacher", square(g, 2, 1), nil)
        local p = player()
        for _ = 1, 11 do p:give("Base.Log") end
        T.eq(H.commands["machine.load"](p, req(leacher)).reason, "no_ready_ash")
        local r = H.commands["machine.load"](p, req(barrel))
        T.eq(r.ok, true, tostring(r.reason))
        T.near(r.woodKg, 99, 1e-9)
        -- Burning 99 kg at 20 kg/h, cooling 12 h.
        local s = finish(g, p, barrel, 99 / 20 + 12)
        T.eq(s.state, "OutputReady", tostring(s.pause))
        local ashKg = 99 * R.need("recipe", "ash_burn").params.ashKgPerKg
        T.near(s.outputs.wood_ash, ashKg, 1e-9)
        T.eq(H.commands["machine.collect"](p, req(barrel, { destination = { kind = "item", id = 1 } })).reason,
            "use_next_machine")
        -- No water carried: nothing is taken.
        r = H.commands["machine.load"](p, req(leacher))
        T.eq(r.reason, "not_enough_water")
        T.near(rec(barrel).outputs.wood_ash, ashKg, 1e-9)
        -- 2.5 L covers 1.25 kg of the 1.485 kg of ash; the rest stays.
        local water = p:giveWater(2.5)
        r = H.commands["machine.load"](p, req(leacher))
        T.eq(r.ok, true, tostring(r.reason))
        T.near(r.ashKg, 1.25, 1e-9)
        T.near(water.amount, 0, 1e-9)
        T.near(rec(barrel).outputs.wood_ash, ashKg - 1.25, 1e-9)
        p:give("Base.Log")
        T.eq(H.commands["machine.addFuel"](p, req(leacher)).ok, true)
        -- Leaching a day, boiling down four hours.
        s = finish(g, p, leacher, 28)
        T.eq(s.state, "OutputReady", tostring(s.pause))
        T.near(s.outputs.lye, 1.25 * R.need("recipe", "lye_leach").params.lyeKgPerKgAsh, 1e-9)
    end)
end)

T.case("biodiesel: machine.load is refused for the ethanol machines, and for a carried machine", function()
    inGame(function(g)
        local still = machine("TLG.PotStill", square(g, 1, 1), nil)
        T.eq(H.commands["machine.load"](player(), req(still)).reason, "wrong_machine")
        local reactor = reactorSite(g, 10, 2)
        function reactor:getWorldItem() return nil end
        local p = player()
        local inv = p:getInventory()
        function inv:getItemWithIDRecursiv(id) return id == reactor:getID() and reactor or nil end
        T.eq(H.commands["machine.load"](p, req(reactor)).reason, "not_placed")
    end)
end)
