require "support/fixtures"
-- The Fuel entry of a vehicle's or a generator's tank, what its dialogs
-- say, and the line in the game's Generator Info window (client UI, UX
-- review R5). The Fuel menu loads the pour action, which derives from a
-- class of the game: the stand-in of tests/integration/test_mp_actions.lua,
-- whose case runs the class whichever file loaded it first, and which is
-- therefore left in place as the game leaves its own. The menus register
-- game events and the window is a game class: stand-ins for the load.
__TLG_SOURCES["TimedActions/ISBaseTimedAction"] = __TLG_SOURCES["TimedActions/ISBaseTimedAction"] or [[
    ISBaseTimedAction = {}
    ISBaseTimedAction.__index = ISBaseTimedAction
    function ISBaseTimedAction:derive(type)
        local o = setmetatable({}, self)
        self.__index = self
        o.Type = type
        return o
    end
    function ISBaseTimedAction.new(self, character)
        local o = setmetatable({}, self)
        self.__index = self
        o.character = character
        return o
    end
]]
local savedEvents, realRequire, savedWindow = Events, require, ISGeneratorInfoWindow
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require = function(name)
    if name == "ISUI/ISGeneratorInfoWindow" then
        -- The game's text: the long one of the window, the short one of the tooltip.
        ISGeneratorInfoWindow = { getRichText = function(_, displayStats) return displayStats and "game text" or "short" end }
        return true
    end
    return realRequire(name)
end
require "TLG/UI/FuelContextMenu"
require "TLG/UI/GeneratorInfo"
require = realRequire
local Window = ISGeneratorInfoWindow
ISGeneratorInfoWindow, Events = savedWindow, savedEvents
local Menu, Info, Fmt, G = TLG.UI.FuelMenu, TLG.UI.GeneratorInfo, TLG.UI.Format, TLG.Integration.Generators

local function bracket(key, ...)
    local args = { ... }
    return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
end

local function has(text, part) return string.find(text, part, 1, true) ~= nil end

local GLOBALS = { "instanceof", "getCore", "getCell", "JoypadState", "IsoObjectPicker", "getMouseXScaled", "getMouseYScaled",
    "getSpecificPlayer", "getText", "ISContextMenu", "ISWorldObjectContextMenu", "isServer", "isClient", "getTimestampMs" }

-- A character on a tile, a car that may be under the cursor, generators on
-- tiles; getText as the game's Translator with every key known.
local function world(fn)
    local saved = { translate = Fmt.translate, holdsGas = G.holdsGas, profile = G.profile, isGas = G.isGas,
        vehicleProfile = TLG.Integration.Vehicles.profile, received = TLG.World.received }
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local w = { squares = {}, picked = nil, kit = false, ms = 0 }
    local function list(t)
        return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
    end
    function w.square(x, y)
        local key = x .. "," .. y
        if w.squares[key] == nil then
            local s = { objects = {} }
            function s:getX() return x end
            function s:getY() return y end
            function s:getZ() return 0 end
            function s:getWorldObjects() return list({}) end
            function s:getObjects() return list(self.objects) end
            function s:DistToProper(o) return math.sqrt((o:getX() - x) ^ 2 + (o:getY() - y) ^ 2) end
            s.floor = { class = "IsoObject", getSquare = function() return s end, getFluidContainer = function() return nil end,
                getPipedFuelAmount = function() return 0 end, hasModData = function() return false end }
            w.squares[key] = s
        end
        return w.squares[key]
    end
    function w.generator(x, y)
        local s = w.square(x, y)
        local g = { class = "IsoGenerator", getSquare = function() return s end, getObjectIndex = function() return 1 end,
            getFluidContainer = function() return nil end, fuel = 5 }
        function g:getFuel() return self.fuel end
        s.objects[#s.objects + 1] = g
        return g
    end
    function w.car(atCap)
        local car = { class = "BaseVehicle", atCap = atCap }
        local tank = { getArea = function() return "cap" end }
        function car:getPartById(id) return id == "GasTank" and tank or nil end
        function car:isInArea() return self.atCap end
        function car:getId() return 31 end
        return car
    end
    w.at = w.square(10, 10)
    w.player = { getVehicle = function() return w.seated end, getSquare = function() return w.at end,
        getInventory = function()
            return { getFirstTypeRecurse = function(_, t) return w.kit and t == "TLG.FuelSampleKit" and {} or nil end }
        end }
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    getCore = function() return { getZoom = function() return 1 end } end
    getCell = function()
        return { getGridSquare = function(_, x, y) return w.squares[x .. "," .. y] end,
            getVehicles = function() return { toArray = function() return {} end } end }
    end
    JoypadState = nil
    IsoObjectPicker = { Instance = { PickVehicle = function() return w.picked end } }
    getMouseXScaled, getMouseYScaled = function() return 0 end, function() return 0 end
    getSpecificPlayer = function() return w.player end
    getText, Fmt.translate = bracket, bracket
    isServer, isClient = function() return false end, function() return false end
    getTimestampMs = function() return w.ms end
    local function context()
        local c = { options = {} }
        function c:addOption(name, _, fn) local o = { name = name, fn = fn }; self.options[#self.options + 1] = o; return o end
        function c:addSubMenu(option, sub) option.sub = sub end
        return c
    end
    w.context = context
    ISContextMenu = { getNew = context }
    ISWorldObjectContextMenu = { addToolTip = function() return {} end, setTest = function() return "test" end }
    G.holdsGas = function(g) return g.gas == true end
    G.isGas = function(g) return g.isGas == true end
    G.profile = function(g) return g.profile or "generator_si_stock" end
    TLG.Integration.Vehicles.profile = function(v) return v.profile or "engine_si_stock" end
    local ok, err = pcall(fn, w)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    G.isGas = saved.isGas
    Fmt.translate, G.holdsGas, G.profile, TLG.Integration.Vehicles.profile = saved.translate, saved.holdsGas, saved.profile,
        saved.vehicleProfile
    TLG.World.received = saved.received
    if not ok then error(err, 0) end
end

local function names(sub)
    local out = {}
    for _, o in ipairs(sub.options) do out[#out + 1] = o.name end
    return table.concat(out, " | ")
end

T.case("integration: the tank under the click is offered from where the authority lets it be sampled", function()
    world(function(w)
        local floor = w.at.floor
        T.ok(Menu.tankAt(0, { floor }) == nil, "nothing clicked")
        -- A car under the cursor: from its fuel cap only.
        local car = w.car(false)
        w.picked = car
        T.ok(Menu.tankAt(0, { floor }) == nil, "not at the fuel cap")
        car.atCap = true
        local t = Menu.tankAt(0, { floor })
        T.ok(t ~= nil and t.kind == "vehicle" and t.owner == car)
        T.eq(t.ref.kind, "vehicle"); T.eq(t.ref.id, 31)
        w.seated = car
        T.ok(Menu.tankAt(0, { floor }) == nil, "seated: none")
        w.seated, w.picked = nil, nil
        -- A generator: within 2.5 tiles as the authority measures them, so
        -- two tiles off on both axes (2.83) is out, though the old scan found it.
        local near, far = w.generator(12, 10), w.generator(12, 12)
        t = Menu.tankAt(0, { near })
        T.ok(t ~= nil and t.kind == "generator" and t.owner == near)
        T.eq(t.ref.kind, "generator"); T.eq(t.ref.x, 12); T.eq(t.ref.index, 1)
        T.ok(Menu.tankAt(0, { far }) == nil, "out of the authority's reach")
        near.gas = true
        T.ok(Menu.tankAt(0, { near }) == nil, "its fuel is gas: Gas is its entry")
        -- A gas generator run empty holds no gas and has no liquid either.
        near.gas, near.isGas, near.fuel = false, true, 0
        T.ok(Menu.tankAt(0, { near }) == nil, "an empty gas generator")
        near.fuel = 3
        T.ok(Menu.tankAt(0, { near }) ~= nil, "one that still holds petrol from before its conversion")
    end)
end)

T.case("integration: a tank's Fuel entry names the engine and offers the three tests", function()
    world(function(w)
        local car = w.car(true)
        car.profile = "engine_ci_stock"
        w.picked = car
        local c = w.context()
        Menu.fillWorld(0, c, { w.at.floor }, false)
        T.eq(#c.options, 1)
        T.eq(c.options[1].name, "[ContextMenu_TLG_FuelVehicle]", "its own name, not a can's Fuel entry")
        T.eq(names(c.options[1].sub), "[IGUI_TLG_EngineIs:[IGUI_TLG_Profile_engine_ci_stock]] | [ContextMenu_TLG_ShowKnown] | "
            .. "[ContextMenu_TLG_Look] | [ContextMenu_TLG_SampleKit]")
        local sub = c.options[1].sub.options
        T.ok(sub[1].fn == nil, "the engine line does nothing")
        T.ok(sub[4].notAvailable == true, "no kit carried: greyed")
        w.kit = true
        c = w.context()
        Menu.fillWorld(0, c, { w.at.floor }, false)
        T.ok(c.options[1].sub.options[4].notAvailable == nil)
        -- The menu's test call: there is something to show.
        T.eq(Menu.fillWorld(0, w.context(), { w.at.floor }, true), "test")
        -- A client of a server names the engine from its copies (D-042,
        -- amended), a vehicle's only once the world record's copy has come.
        isClient = function() return true end
        TLG.World.received = false
        c = w.context()
        Menu.fillWorld(0, c, { w.at.floor }, false)
        T.eq(names(c.options[1].sub), "[ContextMenu_TLG_ShowKnown] | [ContextMenu_TLG_Look] | [ContextMenu_TLG_SampleKit]",
            "no copy of the world record yet: no line")
        TLG.World.received = true
        c = w.context()
        Menu.fillWorld(0, c, { w.at.floor }, false)
        T.eq(names(c.options[1].sub), "[IGUI_TLG_EngineIs:[IGUI_TLG_Profile_engine_ci_stock]] | [ContextMenu_TLG_ShowKnown] | "
            .. "[ContextMenu_TLG_Look] | [ContextMenu_TLG_SampleKit]", "the copy has come")
        isClient = function() return false end
        -- A generator, and one that holds gas.
        w.picked = nil
        local gen = w.generator(11, 10)
        gen.profile = "generator_ci_bio"
        c = w.context()
        Menu.fillWorld(0, c, { gen }, false)
        T.eq(c.options[1].name, "[ContextMenu_TLG_FuelGenerator]")
        T.ok(has(names(c.options[1].sub), "[IGUI_TLG_EngineIs:[IGUI_TLG_Profile_generator_ci_bio]]"))
        -- A generator's profile is its own record's: on a client it needs no
        -- copy of the world record.
        isClient = function() return true end
        TLG.World.received = false
        c = w.context()
        Menu.fillWorld(0, c, { gen }, false)
        T.ok(has(names(c.options[1].sub), "[IGUI_TLG_EngineIs:[IGUI_TLG_Profile_generator_ci_bio]]"), "a client, no world record")
        isClient = function() return false end
        gen.gas = true
        c = w.context()
        Menu.fillWorld(0, c, { gen }, false)
        T.eq(#c.options, 0, "no Fuel entry on a gas generator")
    end)
end)

T.case("integration: a client counts the world record once the server's created one has come", function()
    local W = TLG.World
    local saved = { md = ModData, client = isClient, server = isServer, received = W.received }
    local kept = {}
    ModData = { add = function(k, d) kept[k] = d end, request = function() end }
    isServer, isClient = function() return false end, function() return true end
    local ok, err = pcall(function()
        W.requestFromServer()
        T.ok(not W.hasRecord(), "asked for, not come")
        W.onReceive("OtherMod", { v = 1 })
        T.ok(not W.hasRecord(), "another key")
        W.onReceive(W.KEY, false)
        T.ok(not W.hasRecord(), "not a table")
        W.onReceive(W.KEY, {})
        T.ok(not W.hasRecord(), "the server's table before it created the record")
        T.ok(kept[W.KEY] ~= nil, "kept as the copy all the same")
        W.onReceive(W.KEY, { v = 1, dieselVehicles = false })
        T.ok(W.hasRecord(), "a created record, here one without diesel vehicles")
        W.requestFromServer()
        T.ok(not W.hasRecord(), "asked for again: the copy before does not count")
        isClient = function() return false end
        T.ok(W.hasRecord(), "the authority always holds it")
    end)
    ModData, isClient, isServer, W.received = saved.md, saved.client, saved.server, saved.received
    if not ok then error(err, 0) end
end)

T.case("integration: a tank's dialogs name the engine and say what a kit's sample means for it", function()
    world(function()
        local obs = { observedDeg = 0.4, degError = 0.5, primary = "diesel", method = "kit", composition = { diesel = 1 } }
        local t = Menu.sampleText({ ok = true, observation = obs, engine = "engine_si_stock",
            verdict = { grade = "unsuitable", compatible = false, harmful = true, reasons = { "wrong_fuel_4_diesel" } } })
        T.ok(has(t, "[IGUI_TLG_EngineIs:[IGUI_TLG_Profile_engine_si_stock]]"), t)
        T.ok(has(t, "[IGUI_TLG_VerdictTitle] <LINE> [IGUI_TLG_Grade_Unsuitable] <LINE> [IGUI_TLG_NotCompatible]"), t)
        T.ok(has(t, "[IGUI_TLG_Reason_Wrong_4:[IGUI_TLG_Fuel_diesel]]"), t)
        -- A can's sample: as before.
        t = Menu.sampleText({ ok = true, observation = obs })
        T.ok(not has(t, "EngineIs") and not has(t, "VerdictTitle"), t)
        -- What I know about it: the engine first, also with nothing known;
        -- a tank is not "open".
        t = Fmt.known({ tests = {}, sealed = false, engine = "generator_ci_bio", tank = true })
        T.eq(t, "[IGUI_TLG_KnownTitle] <LINE> <LINE> [IGUI_TLG_EngineIs:[IGUI_TLG_Profile_generator_ci_bio]] <LINE> <LINE> "
            .. "[IGUI_TLG_ConditionUnknown]")
        t = Fmt.known({ sealed = false, engine = "engine_ci_stock", tank = true, tests = {
            { method = "kit", observation = obs, ageHours = 2, changed = false,
                verdict = { grade = "good", compatible = true, reasons = {} } },
            { method = "visual", observation = { observedDeg = 0.5, degError = 1, primary = "diesel" }, ageHours = 0 } } })
        T.ok(has(t, "[IGUI_TLG_VerdictTitle] <LINE> [IGUI_TLG_Grade_Good] <LINE> [IGUI_TLG_Compatible]"), t)
        T.ok(not has(t, "[IGUI_TLG_KnownOpen]"), "no open-container note for a tank")
        local _, count = string.gsub(t, "VerdictTitle", "")
        T.eq(count, 1, "the look has no judgement")
        T.ok(has(Fmt.known({ tests = {}, sealed = false }), "[IGUI_TLG_ConditionUnknown]"))
        T.ok(has(Fmt.known({ sealed = false, tests = { { method = "visual", observation = obs, ageHours = 0 } } }),
            "[IGUI_TLG_KnownOpen]"), "an open can still says so")
    end)
end)

T.case("integration: Generator Info says which fuel the generator takes", function()
    world(function(w)
        T.ok(Info.original ~= nil and Window.getRichText ~= Info.original, "the game's text is wrapped")
        local gen = { profile = "generator_ci_bio" }
        T.eq(Window.getRichText(gen, true),
            "[IGUI_TLG_GenFuel:[IGUI_TLG_GenFuel_generator_ci_bio]] <LINE> game text")
        T.eq(Window.getRichText(gen, false), "short", "the tooltip's short text is left alone")
        -- Asked at every frame: the profile is read again after REFRESH_MS.
        local reads = 0
        G.profile = function(g) reads = reads + 1; return g.profile end
        Info.last = nil
        for _ = 1, 50 do Window.getRichText(gen, true) end
        T.eq(reads, 1)
        gen.profile = "generator_gas"
        w.ms = Info.REFRESH_MS
        T.ok(has(Window.getRichText(gen, true), "[IGUI_TLG_GenFuel_generator_gas]"), "a conversion shows after the refresh")
        T.eq(reads, 2)
        -- Another generator is not answered from the first one's line.
        local other = { profile = "generator_si_stock" }
        T.ok(has(Window.getRichText(other, true), "[IGUI_TLG_GenFuel_generator_si_stock]"))
        -- A profile without a text, and a failing read: the game's text alone.
        getText = function(key, ...) if key == "IGUI_TLG_GenFuel_odd" then return key end return bracket(key, ...) end
        Info.last = nil
        T.eq(Window.getRichText({ profile = "odd" }, true), "game text")
        G.profile = function() error("no mod data") end
        Info.last = nil
        T.eq(Window.getRichText({}, true), "game text")
    end)
end)

-- A can's entries that drain a generator and pour into a station's
-- reservoir queue the pour action (R13): before, each sent the transfer at
-- once.
T.case("integration: Drain the generator and Pour into the station reservoir queue the timed action", function()
    world(function(w)
        local saved = { queue = ISTimedActionQueue, pane = ISInventoryPaneContextMenu, request = TLG.Net and TLG.Net.request }
        local queued, requests = {}, 0
        w.player.isTimedActionInstant = function() return false end
        ISTimedActionQueue = { add = function(action) queued[#queued + 1] = action end }
        ISInventoryPaneContextMenu = { transferIfNeeded = function(_, item) w.moved = item end }
        if TLG.Net then TLG.Net.request = function() requests = requests + 1 end end
        local ok, err = pcall(function()
            local fc = { getAmount = function() return 6 end, getFreeCapacity = function() return 4 end,
                isEmpty = function() return false end }
            local can = { getID = function() return 7 end, getWorldItem = function() return nil end,
                getFluidContainerFromSelfOrWorldItem = function() return fc end }
            local function entry(sub, key)
                for _, o in ipairs(sub.options) do
                    if o.name == bracket(key) then return o end
                end
                return nil
            end
            -- Nothing near: neither entry.
            local sub = w.context()
            Menu.addDrainOptions(w.player, sub, can)
            Menu.addPourOptions(w.player, sub, can)
            T.eq(#sub.options, 0)
            -- A generator with 3 L two tiles away: the drain, as long as its
            -- 3 L, the can's room asked for.
            local gen = w.generator(12, 10)
            gen.fuel = 3
            sub = w.context()
            Menu.addDrainOptions(w.player, sub, can)
            local drain = entry(sub, "ContextMenu_TLG_DrainGenerator")
            T.ok(drain ~= nil, "offered")
            drain.fn()
            T.eq(#queued, 1); T.eq(requests, 0, "no request sent at the click")
            local a = queued[1]
            T.eq(a.Type, "ISTLGPourFuel"); T.ok(a.item == can and w.moved == can, "the can, taken in hand")
            T.eq(a.source.kind, "generator"); T.eq(a.source.x, 12); T.eq(a.source.y, 10)
            T.ok(a.destination == nil, "a drain has no destination: the can is it")
            T.ok(a.faceObject == gen, "the generator faced")
            T.eq(a.amount, 4); T.eq(a.litres, 3); T.eq(a.experimental, false)
            -- A generator on gas, an empty one, a full can: no drain.
            gen.gas = true
            sub = w.context(); Menu.addDrainOptions(w.player, sub, can); T.eq(#sub.options, 0, "gas")
            gen.gas, gen.fuel = nil, 0
            sub = w.context(); Menu.addDrainOptions(w.player, sub, can); T.eq(#sub.options, 0, "empty")
            gen.fuel = 3
            fc.getFreeCapacity = function() return 0.01 end
            sub = w.context(); Menu.addDrainOptions(w.player, sub, can); T.eq(#sub.options, 0, "no room")
            -- A pump a tile away: the pour into its reservoir, the pump the
            -- destination and faced, what the can holds.
            local s = w.square(10, 11)
            local pump = { class = "IsoObject", getSquare = function() return s end, getObjectIndex = function() return 2 end,
                getPipedFuelAmount = function() return 100 end, hasModData = function() return false end }
            s.objects[#s.objects + 1] = pump
            sub = w.context()
            Menu.addPourOptions(w.player, sub, can)
            local pour = entry(sub, "ContextMenu_TLG_PourStation")
            T.ok(pour ~= nil, "offered")
            pour.fn()
            T.eq(#queued, 2); T.eq(requests, 0)
            a = queued[2]
            T.eq(a.destination.kind, "pump"); T.eq(a.destination.y, 11); T.eq(a.destination.index, 2)
            T.ok(a.source == nil, "a pour: the can is the source")
            T.ok(a.faceObject == pump); T.eq(a.amount, 6); T.eq(a.litres, nil)
        end)
        ISTimedActionQueue, ISInventoryPaneContextMenu = saved.queue, saved.pane
        if TLG.Net then TLG.Net.request = saved.request end
        if not ok then error(err, 0) end
    end)
end)

T.case("integration: a pour or a drain takes the nearest pump or generator, not the first one found", function()
    world(function(w)
        local saved = { queue = ISTimedActionQueue, pane = ISInventoryPaneContextMenu }
        local queued = {}
        w.player.isTimedActionInstant = function() return false end
        ISTimedActionQueue = { add = function(action) queued[#queued + 1] = action end }
        ISInventoryPaneContextMenu = { transferIfNeeded = function() end }
        local ok, err = pcall(function()
            local function pumpAt(x, y)
                local s = w.square(x, y)
                local p = { class = "IsoObject", getSquare = function() return s end, getObjectIndex = function() return 3 end,
                    getPipedFuelAmount = function() return 100 end, hasModData = function() return false end }
                s.objects[#s.objects + 1] = p
                return p
            end
            -- Launch 450's layout: a station's pumps a tile apart, the
            -- character two tiles east of the south one. The scan meets the
            -- north one first; the south one is nearer (2 tiles against 2.24).
            local north, south = pumpAt(8, 9), pumpAt(8, 10)
            T.ok(Menu.nearbyPump(w.player) == south, "the pump beside the character")
            local fc = { getAmount = function() return 2 end, getFreeCapacity = function() return 8 end,
                isEmpty = function() return false end }
            local can = { getID = function() return 9 end, getWorldItem = function() return nil end,
                getFluidContainerFromSelfOrWorldItem = function() return fc end }
            local sub = w.context()
            Menu.addPourOptions(w.player, sub, can)
            for _, o in ipairs(sub.options) do
                if o.name == bracket("ContextMenu_TLG_PourStation") then o.fn() end
            end
            T.eq(#queued, 1)
            T.eq(queued[1].destination.x, 8); T.eq(queued[1].destination.y, 10, "poured into the south pump")
            T.ok(queued[1].faceObject == south and queued[1].faceObject ~= north, "and faces it")
            -- Generators: one a tile west and two north (2.24), met first;
            -- one two tiles east (2), nearer: the drain takes it.
            local far, near = w.generator(9, 8), w.generator(12, 10)
            far.fuel, near.fuel = 3, 3
            T.ok(Menu.nearbyGenerator(w.player) == near)
            sub = w.context()
            Menu.addDrainOptions(w.player, sub, can)
            sub.options[1].fn()
            T.eq(queued[2].source.x, 12); T.ok(queued[2].faceObject == near)
            -- As near as each other: the first met, from the west.
            local west = w.generator(8, 10)
            T.ok(Menu.nearbyGenerator(w.player) == west, "two tiles west and two east: the west one")
        end)
        ISTimedActionQueue, ISInventoryPaneContextMenu = saved.queue, saved.pane
        if not ok then error(err, 0) end
    end)
end)
