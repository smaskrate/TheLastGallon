require "support/fixtures"
-- The gasifier's menu (client UI, D-040): which entries it offers in each
-- state, the requests they send, and its Status text. The menu registers
-- game events when it loads; a stand-in event list takes them, the last
-- one registered for each event kept: the Gas menu's, loaded for its
-- Status text, before the gasifier's.
local savedEvents = Events
local callbacks = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) callbacks[k] = fn end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/GasMenu"
require "TLG/UI/GasifierMenu"
Events = savedEvents
local Menu, GZ, Gasifier = TLG.UI.GasifierMenu, TLG.Integration.Gasifiers, TLG.Domain.Gas.Gasifier

local function context()
    local c = { options = {} }
    function c:addOption(name, target, fn)
        local option = { name = name, onSelect = fn }
        self.options[#self.options + 1] = option
        return option
    end
    function c:addSubMenu(option, sub) option.sub = sub end
    return c
end

-- The entries of the menu built for `item`, by name: { [name] = option }.
local function entries(item)
    local c = context()
    callbacks.OnFillInventoryObjectContextMenu(0, c, { item })
    T.eq(#c.options, 1, "one root entry")
    local out = {}
    for _, o in ipairs(c.options[1].sub.options) do out[o.name] = o end
    return out, c.options[1].sub.options
end

local function withGame(fn)
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        ISContextMenu = ISContextMenu, getGameTime = getGameTime, isServer = isServer, isClient = isClient,
        request = TLG.Net.request }
    local g = { hours = 50, wood = 0, requests = {} }
    local square = { getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end }
    local item = { class = "InventoryItem", md = {} }
    function item:getFullType() return "TLG.Gasifier" end
    function item:getID() return 77 end
    function item:getModData() return self.md end
    function item:getDisplayName() return "Wood Gasifier" end
    local world = { class = "IsoWorldInventoryObject" }
    function world:getItem() return item end
    function world:getSquare() return square end
    function item:getWorldItem()
        if g.carried then return nil end
        return world
    end
    g.item = item
    instanceof = function(value, class) return type(value) == "table" and value.class == class end
    getText = function(key) return key end
    getGameTime = function() return { getWorldAgeHours = function() return g.hours end } end
    isServer = function() return false end
    isClient = function() return true end
    getSpecificPlayer = function() return { getInventory = function() return {
        getAllEvalRecurse = function() return { size = function() return g.wood end } end,
    } end } end
    ISContextMenu = { getNew = context }
    TLG.Net.request = function(command, args) g.requests[#g.requests + 1] = { command = command, args = args } end
    local ok, err = pcall(fn, g)
    instanceof, getSpecificPlayer, getText = saved.instanceof, saved.getSpecificPlayer, saved.getText
    ISContextMenu, getGameTime, isServer, isClient = saved.ISContextMenu, saved.getGameTime, saved.isServer, saved.isClient
    TLG.Net.request = saved.request
    if not ok then error(err, 0) end
end

-- A record as the authority writes it: loaded, then lit at the clock's hour.
local function record(g, kg, lit)
    local st = Gasifier.new({ id = "W-1", machine = "gasifier_stationary", t = g.hours })
    if kg > 0 then st = Gasifier.load(st, { firewood = kg }, g.hours).st end
    if lit then
        st = Gasifier.start(st, g.hours).st
        st.site = { x = 10, y = 20, z = 0 }
    end
    g.item.md.tlgGasifier = st
    return st
end

T.case("integration: the gasifier menu offers what applies in each state", function()
    withGame(function(g)
        T.eq(callbacks.OnFillInventoryObjectContextMenu, Menu.fill)
        T.eq(callbacks.OnFillWorldObjectContextMenu, Menu.fillWorld)
        -- New and empty, no wood carried: Load and Light are greyed.
        local e, list = entries(g.item)
        T.eq(list[1].name, "ContextMenu_TLG_GasifierStatus", "Status first")
        T.ok(e.ContextMenu_TLG_GasifierLoad.notAvailable, "no wood to load")
        T.ok(e.ContextMenu_TLG_GasifierLight.notAvailable, "nothing to light")
        T.eq(e.ContextMenu_TLG_GasifierPutOut, nil)
        T.eq(e.ContextMenu_TLG_GasifierService, nil)
        -- Wood carried, loaded: Light offered.
        g.wood = 2
        record(g, 20, false)
        e = entries(g.item)
        T.ok(not e.ContextMenu_TLG_GasifierLoad.notAvailable)
        T.ok(not e.ContextMenu_TLG_GasifierLight.notAvailable)
        e.ContextMenu_TLG_GasifierLight.onSelect()
        T.eq(g.requests[#g.requests].command, "gasifier.light")
        T.eq(g.requests[#g.requests].args.target.id, 77)
        T.eq(g.requests[#g.requests].args.target.x, 10)
        -- Lit: Put out instead of Light; no clean out while it burns.
        record(g, 20, true)
        e = entries(g.item)
        T.eq(e.ContextMenu_TLG_GasifierLight, nil)
        T.ok(e.ContextMenu_TLG_GasifierPutOut ~= nil)
        T.eq(e.ContextMenu_TLG_GasifierService, nil)
        -- Two hours on (the stored record lags): waiting with its gas ready,
        -- tar and ash in it: still lit, and it may be cleaned out.
        g.hours = 52
        e = entries(g.item)
        T.ok(e.ContextMenu_TLG_GasifierPutOut ~= nil)
        T.ok(e.ContextMenu_TLG_GasifierService ~= nil)
        e.ContextMenu_TLG_GasifierService.onSelect()
        T.eq(g.requests[#g.requests].command, "gasifier.service")
        -- Hours later it has gone out: Light again.
        g.hours = 60
        e = entries(g.item)
        T.ok(e.ContextMenu_TLG_GasifierLight ~= nil and not e.ContextMenu_TLG_GasifierLight.notAvailable)
        -- Carried: Status only.
        g.carried = true
        local _, carried = entries(g.item)
        T.eq(#carried, 2)
        T.eq(carried[2].name, "ContextMenu_TLG_PlaceFirst")
        T.ok(carried[2].notAvailable)
        carried[1].onSelect()
        T.eq(g.requests[#g.requests].command, "gasifier.status")
    end)
end)

T.case("integration: the gasifier's Status says what it does and what keeps it lit", function()
    local saved = getText
    getText = function(key, ...)
        local known = { IGUI_TLG_GasifierState_buffer_full = true, IGUI_TLG_GasifierHot_buffer_full = true,
            IGUI_TLG_GasifierHot = true, IGUI_TLG_GasifierHopper = true, IGUI_TLG_GasifierBuffer = true,
            IGUI_TLG_GasifierFilter = true, IGUI_TLG_GasifierHeld = true, IGUI_TLG_GasifierCarried = true,
            IGUI_TLG_GasifierState_hopper_empty = true, IGUI_TLG_GasifierVented = true,
            IGUI_TLG_GasifierState_Ready = true, IGUI_TLG_GasifierWarm = true, IGUI_TLG_GasifierState_warming = true }
        if not known[key] then return key end
        local args = { ... }
        return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
    end
    local ok, err = pcall(function()
        local text = Menu.describe({ state = "Paused", pause = "buffer_full", hopperKg = 80.4, buffer = 2, bufferCap = 2,
            holdLeft = 1.26, filter = 0.031, held = { wood_tar = 0.2, wood_ash = 0.15 }, placed = true })
        T.ok(string.find(text, "[IGUI_TLG_GasifierState_buffer_full]", 1, true) ~= nil, text)
        T.ok(string.find(text, "[IGUI_TLG_GasifierHot_buffer_full:1.3]", 1, true) ~= nil, text)
        T.ok(string.find(text, "[IGUI_TLG_GasifierBuffer:2.00,2.00]", 1, true) ~= nil, text)
        T.ok(string.find(text, "[IGUI_TLG_GasifierHeld:0.20,0.15]", 1, true) ~= nil, text)
        T.ok(string.find(text, "[IGUI_TLG_GasifierFilter:3%]", 1, true) ~= nil, text)
        -- A reason without a line of its own: the plain one.
        text = Menu.describe({ state = "Paused", pause = "paused_by_player", hopperKg = 1, buffer = 0, bufferCap = 2,
            holdLeft = 2, filter = 0, held = {} })
        T.ok(string.find(text, "[IGUI_TLG_GasifierHot:2.0]", 1, true) ~= nil, text)
        text = Menu.describe({ state = "Ready", hopperKg = 0, filter = 0, held = {}, placed = false, vented = 1.5 })
        T.ok(string.find(text, "[IGUI_TLG_GasifierVented:1.50]", 1, true) ~= nil, text)
        T.ok(string.find(text, "[IGUI_TLG_GasifierCarried]", 1, true) ~= nil, text)
        T.ok(string.find(text, "Buffer", 1, true) == nil, "no gas in hand when cold: " .. text)
        text = Menu.describe({ state = "Processing", mode = "warming", warm = 0.4, hopperKg = 30, buffer = 0,
            bufferCap = 2, filter = 0, held = {} })
        T.ok(string.find(text, "[IGUI_TLG_GasifierWarm:40%]", 1, true) ~= nil, text)
    end)
    getText = saved
    if not ok then error(err, 0) end
end)

T.case("integration: Gas status names propane only when there is some, and a wood-gas buffer to the millilitre", function()
    local saved = getText
    getText = function(key, ...)
        local args = { ... }
        return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
    end
    local ok, err = pcall(function()
        local GasMenu = TLG.UI.GasMenu
        local wood = GasMenu.describe({ fuel = 0.006, propaneKg = 0, woodgasNm3 = 0.0384, gasifiers = 1 })
        T.ok(string.find(wood, "[IGUI_TLG_GasBufferOnly:0.006]", 1, true) ~= nil, wood)
        T.ok(string.find(wood, "IGUI_TLG_GasBuffer:", 1, true) == nil, "no propane named: " .. wood)
        T.ok(string.find(wood, "[IGUI_TLG_GasWoodgas:0.038]", 1, true) ~= nil, wood)
        T.ok(string.find(wood, "[IGUI_TLG_GasGasifiers:1]", 1, true) ~= nil, wood)
        T.ok(string.find(wood, "[IGUI_TLG_GasNoTank]", 1, true) ~= nil, wood)
        local propane = GasMenu.describe({ fuel = 9.99936, propaneKg = 6.917, tankUses = 1160, tankKg = 2.089,
            gasifiers = 0 })
        T.ok(string.find(propane, "[IGUI_TLG_GasBuffer:9.999,6.917]", 1, true) ~= nil, propane)
        T.ok(string.find(propane, "IGUI_TLG_GasWoodgas", 1, true) == nil, propane)
        T.ok(string.find(propane, "[IGUI_TLG_GasTank:1160,2.09]", 1, true) ~= nil, propane)
    end)
    getText = saved
    if not ok then error(err, 0) end
end)
