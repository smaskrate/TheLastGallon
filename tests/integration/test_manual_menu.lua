require "support/fixtures"
-- The inventory menu entries that open the manual's further pages (client
-- UI, R7): which items get which entries, when they are greyed, and what an
-- entry puts in the game's print media window. The menu registers a game
-- event when it loads; a stand-in event list takes it.
local savedEvents = Events
local callbacks = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) callbacks[k] = fn end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/ManualMenu"
Events = savedEvents
local Menu, Manual = TLG.UI.ManualMenu, TLG.Integration.Manual

local function item(fullType)
    local it = { class = "InventoryItem" }
    function it:getFullType() return fullType end
    return it
end

-- Runs `fn(g, fill)` with the game's calls the menu makes stood in; `fill`
-- builds the menu for a list of items and returns its entries.
local function withGame(fn)
    local saved = { instanceof = instanceof, getSpecificPlayer = getSpecificPlayer, getText = getText,
        CharacterTrait = CharacterTrait, PZAPI = PZAPI, getJoypadData = getJoypadData,
        ISInventoryPaneContextMenu = ISInventoryPaneContextMenu }
    local g = { dark = false, asleep = false, illiterate = false, windows = {} }
    local player = {}
    function player:tooDarkToRead() return g.dark end
    function player:isAsleep() return g.asleep end
    function player:hasTrait() return g.illiterate end
    instanceof = function(value, class) return type(value) == "table" and value.class == class end
    getSpecificPlayer = function() return player end
    getText = function(key) return "<" .. key .. ">" end
    CharacterTrait = { ILLITERATE = "illiterate" }
    getJoypadData = function() return nil end
    ISInventoryPaneContextMenu = { addToolTip = function() return {} end }
    PZAPI = { UI = { PrintMedia = function(o)
        local win = { x = o.x, y = o.y, javaObj = {}, children = { bar = { children = { name = {} } } } }
        function win.javaObj:setAlwaysOnTop(v) win.onTop = v end
        function win:instantiate() self.shown = true end
        function win:centerOnScreen(n) self.centred = n end
        g.windows[#g.windows + 1] = win
        return win
    end } }
    local function fill(items)
        local c = { options = {} }
        function c:addOption(name, target, onSelect, param)
            local option = { name = name, target = target, onSelect = onSelect, param = param }
            self.options[#self.options + 1] = option
            return option
        end
        callbacks.OnFillInventoryObjectContextMenu(0, c, items)
        return c.options
    end
    local ok, err = pcall(fn, g, fill)
    for k, v in pairs(saved) do _G[k] = v end
    for _, k in ipairs({ "instanceof", "getSpecificPlayer", "getText", "CharacterTrait", "PZAPI", "getJoypadData",
        "ISInventoryPaneContextMenu" }) do
        if saved[k] == nil then _G[k] = nil end
    end
    if not ok then error(err, 0) end
end

T.case("integration: the manual offers both pages, each handbook its own, other items none", function()
    T.eq(table.concat(Manual.pagesOf("TLG.ManualFuelSystems"), ","), "biodiesel,gas")
    T.eq(table.concat(Manual.pagesOf("TLG.BiodieselHandbook"), ","), "biodiesel")
    T.eq(table.concat(Manual.pagesOf("TLG.WoodGasHandbook"), ","), "gas")
    T.eq(#Manual.pagesOf("TLG.FuelFilter"), 0)
    T.eq(#Manual.pagesOf(nil), 0)
    for _, ids in pairs(Manual.PAGES_OF) do
        for _, id in ipairs(ids) do T.ok(Manual.PAGES[id] ~= nil, id) end
    end
    withGame(function(g, fill)
        local options = fill({ item("TLG.ManualFuelSystems") })
        T.eq(#options, 2)
        T.eq(options[1].name, "<ContextMenu_TLG_ManualPage_biodiesel>")
        T.eq(options[2].name, "<ContextMenu_TLG_ManualPage_gas>")
        T.ok(not options[1].notAvailable, "offered in the light, awake")
        -- A stack, as the inventory pane hands it over.
        options = fill({ { items = { item("TLG.BiodieselHandbook"), item("TLG.BiodieselHandbook") } } })
        T.eq(#options, 1); T.eq(options[1].param, "biodiesel")
        options = fill({ item("TLG.WoodGasHandbook") })
        T.eq(#options, 1); T.eq(options[1].param, "gas")
        T.eq(#fill({ item("TLG.FuelFilter") }), 0)
        T.eq(#fill({}), 0)
    end)
end)

T.case("integration: a page's entry is greyed in the dark and asleep, and absent for one who cannot read", function()
    withGame(function(g, fill)
        g.dark = true
        local options = fill({ item("TLG.ManualFuelSystems") })
        T.eq(#options, 2)
        T.ok(options[1].notAvailable and options[2].notAvailable, "greyed in the dark")
        T.eq(options[1].toolTip.description, "<ContextMenu_TooDarkToInspect>")
        g.dark, g.asleep = false, true
        options = fill({ item("TLG.WoodGasHandbook") })
        T.ok(options[1].notAvailable, "greyed asleep")
        T.eq(options[1].toolTip.description, "<ContextMenu_NoOptionSleeping>")
        g.asleep, g.illiterate = false, true
        T.eq(#fill({ item("TLG.ManualFuelSystems") }), 0)
    end)
end)

T.case("integration: an entry opens its page in the game's print media window", function()
    withGame(function(g, fill)
        local options = fill({ item("TLG.ManualFuelSystems") })
        getText = function(key)
            if key == "IGUI_TLG_Manual_Gas_Text" then return "1. HEAD\\n\\nA paragraph." end
            return "<" .. key .. ">"
        end
        local win = options[2].onSelect(options[2].target, options[2].param)
        T.eq(#g.windows, 1)
        T.eq(win.data, "<IGUI_TLG_Manual_Gas_Page>")
        T.eq(win.textTitle, "<IGUI_TLG_Manual_Gas_Title>")
        T.eq(win.children.bar.children.name.text, "<IGUI_TLG_Manual_Gas_Title>")
        T.eq(win.textData, "1. HEAD\n\nA paragraph.", "the text's line breaks as the game reads them")
        T.ok(win.shown, "instantiated"); T.eq(win.centred, 0); T.eq(win.onTop, false)
        T.eq(win.media_id, nil, "no print media id: nothing is recorded as read")
        T.eq(Menu.open(0, "nothing"), nil)
        T.eq(#g.windows, 1)
    end)
end)
