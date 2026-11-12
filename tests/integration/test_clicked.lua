require "support/fixtures"
-- What a right-click in the world is on (client UI, TLG/UI/Clicked.lua), and
-- the Workshop menu that follows it. The menus register game events when
-- they load; a stand-in event list takes them.
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/Clicked"
-- The Workshop menu loads its timed action, which derives from a class of
-- the game: a stand-in for the time of the load.
local realRequire, savedAction = require, ISBaseTimedAction
require = function(name)
    if name == "TimedActions/ISBaseTimedAction" then
        ISBaseTimedAction = ISBaseTimedAction or { derive = function() local c = {}; c.__index = c; return c end }
        return true
    end
    return realRequire(name)
end
require "TLG/UI/WorkshopMenu"
require = realRequire
ISBaseTimedAction = savedAction
Events = savedEvents
local Clicked = TLG.UI.Clicked

local GLOBALS = { "instanceof", "getCore", "getCell", "JoypadState", "IsoObjectPicker", "getMouseXScaled", "getMouseYScaled",
    "getSpecificPlayer", "getText", "ISContextMenu" }

-- A small world: squares by "x,y", each with items on the ground (at a
-- position on screen) and objects standing on it.
local function world(zoom)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local w = { squares = {}, zoom = zoom or 1, picked = nil, vehicles = {} }
    local function list(t)
        return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
    end
    function w.square(x, y)
        local key = x .. "," .. y
        if w.squares[key] == nil then
            local s = { items = {}, objects = {} }
            function s:getX() return x end
            function s:getY() return y end
            function s:getZ() return 0 end
            function s:getWorldObjects() return list(self.items) end
            function s:getObjects() return list(self.objects) end
            s.floor = { class = "IsoObject", getSquare = function() return s end }
            w.squares[key] = s
        end
        return w.squares[key]
    end
    function w.item(x, y, sx, sy, name)
        local s = w.square(x, y)
        local o = { class = "IsoWorldInventoryObject", name = name }
        function o:getSquare() return s end
        function o:getScreenPosX() return sx end
        function o:getScreenPosY() return sy end
        s.items[#s.items + 1] = o
        return o
    end
    function w.generator(x, y)
        local s = w.square(x, y)
        local g = { class = "IsoGenerator", getSquare = function() return s end, getObjectIndex = function() return 1 end,
            getGeneratorItemType = function() return "Base.Generator" end }
        s.objects[#s.objects + 1] = g
        return g
    end
    instanceof = function(o, class) return type(o) == "table" and o.class == class end
    getCore = function() return { getZoom = function() return w.zoom end } end
    getCell = function()
        return { getGridSquare = function(_, x, y) return w.squares[x .. "," .. y] end,
            getVehicles = function() return { toArray = function() return w.vehicles end } end }
    end
    JoypadState = nil
    IsoObjectPicker = { Instance = { PickVehicle = function() return w.picked end } }
    getMouseXScaled, getMouseYScaled = function() return 0 end, function() return 0 end
    function w.restore()
        for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    end
    return w
end

local function inWorld(zoom, fn)
    local w = world(zoom)
    local ok, err = pcall(fn, w)
    w.restore()
    if not ok then error(err, 0) end
end

local function names(list)
    local out = {}
    for _, o in ipairs(list) do out[#out + 1] = o.name end
    table.sort(out)
    return table.concat(out, ",")
end

T.case("clicked: an item on the ground counts when the click is within 48 pixels of it, as the game's Grab", function()
    inWorld(1, function(w)
        w.item(10, 10, 400, 300, "can")
        w.item(10, 10, 500, 300, "far on the same tile")
        w.item(11, 10, 440, 310, "near on the next tile")
        w.item(13, 10, 400, 300, "two tiles away")
        local floor = w.square(10, 10).floor
        -- A click 40 pixels from the can and 12 from the neighbour's item.
        T.eq(names(Clicked.worldItems(0, { requestX = 430, requestY = 300 }, { floor })), "can,near on the next tile")
        -- On the can: the item 100 pixels off on the same tile is not under it.
        T.eq(names(Clicked.worldItems(0, { requestX = 400, requestY = 300 }, { floor })), "can,near on the next tile")
        -- Bare ground of the same tile, 100 pixels from everything.
        T.eq(names(Clicked.worldItems(0, { requestX = 300, requestY = 380 }, { floor })), "")
        -- Exactly at the radius.
        T.eq(names(Clicked.worldItems(0, { requestX = 352, requestY = 300 }, { floor })), "can")
        T.eq(names(Clicked.worldItems(0, { requestX = 351, requestY = 300 }, { floor })), "")
    end)
end)

T.case("clicked: the radius is 48 pixels divided by the zoom", function()
    inWorld(2, function(w)
        w.item(10, 10, 400, 300, "can")
        local floor = w.square(10, 10).floor
        T.eq(names(Clicked.worldItems(0, { requestX = 424, requestY = 300 }, { floor })), "can", "24 pixels at zoom 2")
        T.eq(names(Clicked.worldItems(0, { requestX = 430, requestY = 300 }, { floor })), "", "30 pixels at zoom 2")
    end)
end)

T.case("clicked: an item handed over as clicked always counts, once", function()
    inWorld(1, function(w)
        local can = w.item(10, 10, 400, 300, "can")
        local floor = w.square(10, 10).floor
        local got = Clicked.worldItems(0, { requestX = 900, requestY = 900 }, { can, floor, can })
        T.eq(#got, 1); T.eq(got[1], can)
        got = Clicked.worldItems(0, { requestX = 400, requestY = 300 }, { can, floor })
        T.eq(#got, 1, "not twice when it is also near the click")
    end)
end)

T.case("clicked: without a click position every item of the clicked squares counts, as before", function()
    inWorld(1, function(w)
        w.item(10, 10, 400, 300, "can")
        w.item(10, 10, 470, 300, "second")
        w.item(11, 10, 440, 310, "next tile")
        local floor = w.square(10, 10).floor
        T.eq(names(Clicked.worldItems(0, {}, { floor })), "can,second", "a menu built without a position")
        T.eq(names(Clicked.worldItems(0, nil, { floor })), "can,second")
        -- A controller has no cursor, whatever the menu's position says.
        JoypadState = { players = { {} } }
        T.eq(Clicked.usesController(0), true); T.eq(Clicked.usesController(1), false)
        T.eq(names(Clicked.worldItems(0, { requestX = 900, requestY = 900 }, { floor })), "can,second")
    end)
end)

T.case("clicked: the generator is one clicked or standing on a clicked square", function()
    inWorld(1, function(w)
        local g = w.generator(10, 10)
        local here, there = w.square(10, 10).floor, w.square(14, 10).floor
        local near = function() return "the nearest" end
        T.eq(Clicked.generator(0, { g }, near), g)
        T.eq(Clicked.generator(0, { here }, near), g, "its tile clicked")
        T.eq(Clicked.generator(0, { there }, near), nil, "another tile: none, however near one stands")
        T.eq(Clicked.generator(0, {}, near), nil)
        JoypadState = { players = { {} } }
        T.eq(Clicked.generator(0, { there }, near), "the nearest", "a controller: the nearest in reach")
        T.eq(Clicked.generator(0, { here }, near), g)
    end)
end)

T.case("clicked: the vehicle is one handed over or under the cursor", function()
    inWorld(1, function(w)
        local car = { class = "BaseVehicle" }
        local floor = w.square(10, 10).floor
        local near = function() return "the nearest" end
        T.eq(Clicked.vehicle(0, { floor }, near), nil, "nothing under the cursor")
        w.picked = car
        T.eq(Clicked.vehicle(0, { floor }, near), car, "the game's own pick")
        w.picked = nil
        T.eq(Clicked.vehicle(0, { floor, car }, near), car)
        IsoObjectPicker = nil
        T.eq(Clicked.vehicle(0, { floor }, near), nil, "no picker: none, and no error")
        JoypadState = { players = { {} } }
        T.eq(Clicked.vehicle(0, { floor }, near), "the nearest")
    end)
end)

T.case("clicked: the Workshop menu shows for the clicked generator or car, not for one that is only near", function()
    inWorld(1, function(w)
        local function context()
            local c = { options = {} }
            function c:addOption(name) local o = { name = name }; self.options[#self.options + 1] = o; return o end
            function c:addSubMenu(option, sub) option.sub = sub end
            return c
        end
        ISContextMenu = { getNew = context }
        -- An argument shows after the key, so each Start entry names its
        -- conversion.
        getText = function(key, a) if a ~= nil then return key .. ":" .. tostring(a) end return key end
        -- The character stands at 10,10; a generator one tile off and a car
        -- two tiles off are both within the old menu's reach.
        local at = w.square(10, 10)
        local player = { getVehicle = function() return nil end, getSquare = function() return at end,
            DistTo = function() return 2 end }
        getSpecificPlayer = function() return player end
        local g = w.generator(11, 10)
        local car = { class = "BaseVehicle", getX = function() return 12 end, getY = function() return 10 end,
            getId = function() return 7 end, getScriptName = function() return "Base.CarNormal" end }
        w.vehicles = { car }
        local function entries(worldobjects)
            local c = context()
            TLG.UI.WorkshopMenu.fill(0, c, worldobjects, false)
            local out = {}
            for _, o in ipairs(c.options) do out[#out + 1] = o.name end
            return table.concat(out, ",")
        end
        T.eq(entries({ w.square(14, 14).floor }), "", "bare ground: nothing, though both are in reach")
        T.eq(entries({ at.floor }), "", "the character's own tile")
        T.eq(entries({ w.square(11, 10).floor }), "ContextMenu_TLG_ConvGenerator", "the generator's tile")
        T.eq(entries({ g }), "ContextMenu_TLG_ConvGenerator")
        -- 0.4.2: the generator's Start entries offer the flex conversion
        -- only; the gas one waits for its feed (D-040).
        local c = context()
        TLG.UI.WorkshopMenu.fill(0, c, { g }, false)
        local starts = {}
        for _, o in ipairs(c.options[1] and c.options[1].sub and c.options[1].sub.options or {}) do
            if string.find(o.name, "ContextMenu_TLG_ConvBegin", 1, true) then starts[#starts + 1] = o.name end
        end
        T.eq(table.concat(starts, ","), "ContextMenu_TLG_ConvBegin:IGUI_TLG_Conversion_flex_generator", "Start entries")
        w.picked = car
        T.eq(entries({ w.square(12, 10).floor }), "ContextMenu_TLG_ConvVehicle", "the car under the cursor")
        w.picked = nil
        T.eq(entries({ car }), "ContextMenu_TLG_ConvVehicle")
        T.eq(entries({ w.square(11, 10).floor, car }), "ContextMenu_TLG_ConvGenerator,ContextMenu_TLG_ConvVehicle")
        -- With a controller, as before: what is in reach.
        JoypadState = { players = { {} } }
        T.eq(entries({ w.square(14, 14).floor }), "ContextMenu_TLG_ConvGenerator,ContextMenu_TLG_ConvVehicle")
        -- Seated in a vehicle: no Workshop menu.
        JoypadState = nil
        player.getVehicle = function() return car end
        T.eq(entries({ g, car }), "")
    end)
end)
