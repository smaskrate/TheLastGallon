require "support/fixtures"
-- A machine's Status as a card that stays open (client UI, UX review
-- section 5): when it asks again, what closes it, its text, and the card
-- window's bookkeeping in TLG/UI/Say.lua. The request API registers a game
-- event when it loads; a stand-in event list takes it.
local savedEvents = Events
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function() end }
    rawset(t, k, e)
    return e
end })
require "TLG/UI/MachineCard"
Events = savedEvents
-- The menu that describes a Status is loaded by its own tests, which take
-- its event handlers: here only its table, with describe stood in.
TLG.UI.MachineMenu = TLG.UI.MachineMenu or {}
local Card, Say, Machines = TLG.UI.MachineCard, TLG.UI.Say, TLG.Integration.Machines

local function bracket(key, ...)
    local args = { ... }
    return "[" .. key .. (#args > 0 and (":" .. table.concat(args, ",")) or "") .. "]"
end

local function has(text, part) return string.find(text, part, 1, true) ~= nil end

local GLOBALS = { "getText", "getGameTime", "getTimestampMs", "JoypadState", "getItemNameFromFullType", "getSpecificPlayer",
    "ISCollapsableWindow", "ISToolTip", "getCore", "ISModalRichText" }

-- A game with a clock, a machine item and the menus' requests recorded;
-- Say.card stood in unless `realCard`.
local function stage(fn, realCard)
    local saved = { request = TLG.Net.request, card = Say.card, closeCard = Say.closeCard, isPlaced = Machines.isPlaced,
        describe = TLG.UI.MachineMenu.describe, cards = Say.cards, open = Card.open }
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local s = { hours = 100, ms = 50000, placed = true, requests = {}, shown = {}, closed = {} }
    getText = bracket
    getGameTime = function() return { getWorldAgeHours = function() return s.hours end } end
    getTimestampMs = function() return s.ms end
    JoypadState = nil
    getItemNameFromFullType = function(t) return "name of " .. t end
    s.item = { getID = function() return 7 end, getDisplayName = function() return "Pot Still" end }
    Machines.isPlaced = function() return s.placed end
    TLG.UI.MachineMenu.describe = function(reply) return "status " .. tostring(reply.n) end
    TLG.Net.request = function(command, args, cb) s.requests[#s.requests + 1] = { command = command, args = args, cb = cb } end
    Say.cards, Card.open = {}, {}
    if not realCard then
        Say.card = function(key, title, text, onUpdate, onClose, behind)
            s.shown[#s.shown + 1] = { key = key, title = title, text = text, behind = behind == true }
            s.onUpdate, s.onClose = onUpdate, onClose
            return "card"
        end
        Say.closeCard = function(key)
            s.closed[#s.closed + 1] = key
            if s.onClose then s.onClose(key) end
        end
    end
    local ok, err = pcall(fn, s)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    TLG.Net.request, Say.card, Say.closeCard, Machines.isPlaced = saved.request, saved.card, saved.closeCard, saved.isPlaced
    TLG.UI.MachineMenu.describe, Say.cards, Card.open = saved.describe, saved.cards, saved.open
    if not ok then error(err, 0) end
end

T.case("integration: a card asks again ten game minutes on, and never within three real seconds", function()
    T.eq(Card.due(100, 50000, 100, 50000), false)
    T.eq(Card.due(100, 50000, 100 + 9 / 60, 60000), false, "nine game minutes")
    T.eq(Card.due(100, 50000, 100 + 10 / 60, 53000), true)
    T.eq(Card.due(100, 50000, 100 + 5, 52999), false, "fast-forwarded: hours pass in under three seconds")
    T.eq(Card.due(100, 50000, 100 + 5, 53000), true)
    T.eq(Card.due(100, 50000, 99, 60000), true, "the game clock went back")
    T.eq(Card.due(100, 50000, 101, 100), true, "the real clock went back")
end)

T.case("integration: only a status of a machine still on the ground keeps its card", function()
    T.eq(Card.keeps({ ok = true, placed = true }), true)
    T.eq(Card.keeps({ ok = true }), true, "an authority that does not say: kept")
    T.eq(Card.keeps({ ok = true, placed = false }), false, "picked up")
    T.eq(Card.keeps({ ok = false, reason = "no_access" }), false, "out of reach")
    T.eq(Card.keeps({ ok = false, reason = "unknown_target" }), false, "gone")
    T.eq(Card.keeps(nil), false)
end)

T.case("integration: Status is a card for a machine on the ground without a controller", function()
    stage(function(s)
        T.eq(Card.wanted(0, s.item), true)
        s.placed = false
        T.eq(Card.wanted(0, s.item), false, "carried: the window")
        s.placed = true
        JoypadState = { players = { {} } }
        T.eq(Card.wanted(0, s.item), false, "a controller: the window")
        T.eq(Card.wanted(1, s.item), true, "the second player has none")
    end)
end)

T.case("integration: a card's text is Status and the machines it takes from", function()
    stage(function()
        local text = Card.text({ n = 1, takesFrom = true, sources = {
            { machine = "lye_leacher", type = "TLG.LyeLeacher", state = "OutputReady", tiles = 1 },
            { machine = "wood_retort", type = "TLG.WoodRetort", state = "Processing", tiles = 2 } } })
        T.ok(has(text, "status 1 <LINE> [IGUI_TLG_Card_Source1:name of TLG.LyeLeacher,1,[IGUI_TLG_MachineState_OutputReady_leacher]]"),
            text)
        T.ok(has(text, "[IGUI_TLG_Card_Source:name of TLG.WoodRetort,2,[IGUI_TLG_MachineState_Processing_retort]]"), text)
        -- Machines of one type in one state share a line: their number and
        -- the nearest one's distance, in the order the nearest come.
        local vessel = function(state, tiles)
            return { machine = "fermenter_barrel", type = "Base.Vessel", state = state, tiles = tiles }
        end
        local many = Card.sourceLines({ takesFrom = true, sources = { vessel("Processing", 1), vessel("OutputReady", 1),
            vessel("Processing", 2), vessel("Processing", 2) } })
        T.eq(#many, 2)
        T.eq(many[1], "[IGUI_TLG_Card_Sources1:3,name of Base.Vessel,1,[IGUI_TLG_MachineState_Processing_fermenter]]")
        T.eq(many[2], "[IGUI_TLG_Card_Source1:name of Base.Vessel,1,[IGUI_TLG_MachineState_OutputReady_fermenter]]")
        local far = Card.sourceLines({ takesFrom = true, sources = { vessel("Processing", 2), vessel("Processing", 2) } })
        T.eq(far[1], "[IGUI_TLG_Card_Sources:2,name of Base.Vessel,2,[IGUI_TLG_MachineState_Processing_fermenter]]")
        -- A chain machine with nothing near says so; another machine says nothing of it.
        T.eq(Card.text({ n = 2, takesFrom = true, sources = {} }), "status 2 <LINE> [IGUI_TLG_Card_NoSource]")
        T.eq(Card.text({ n = 3, takesFrom = false, sources = {} }), "status 3")
        T.eq(Card.text({ n = 4 }), "status 4", "an authority without the list")
    end)
end)

T.case("integration: an open card asks again when due, fills from the answer and closes without a word on a refusal", function()
    stage(function(s)
        local ref = { kind = "machine", id = 7 }
        T.eq(Card.show(s.item, ref, { ok = true, n = 1 }), "card")
        T.eq(#s.shown, 1); T.eq(s.shown[1].title, "Pot Still"); T.eq(s.shown[1].text, "status 1")
        T.eq(s.shown[1].key, "machine:7")
        -- Frames go by: nothing asked until ten game minutes and three seconds are up.
        s.onUpdate("machine:7")
        s.hours, s.ms = s.hours + 1, s.ms + 1000
        s.onUpdate("machine:7")
        T.eq(#s.requests, 0)
        s.ms = s.ms + 2000
        s.onUpdate("machine:7")
        T.eq(#s.requests, 1); T.eq(s.requests[1].command, "machine.status"); T.ok(s.requests[1].args.target == ref)
        -- While the answer is on its way, no second request.
        s.hours, s.ms = s.hours + 1, s.ms + 10000
        s.onUpdate("machine:7")
        T.eq(#s.requests, 1)
        s.requests[1].cb({ ok = true, placed = true, n = 2 })
        T.eq(#s.shown, 2); T.eq(s.shown[2].text, "status 2"); T.eq(s.shown[2].key, "machine:7", "the same card")
        T.eq(s.shown[2].behind, true, "a refresh does not bring the card forward"); T.eq(s.shown[1].behind, false)
        -- Status asked again from the menu fills the same card.
        Card.show(s.item, ref, { ok = true, n = 3 })
        T.eq(s.shown[3].key, "machine:7")
        -- Due again, and the character has walked away: closed, nothing shown.
        s.hours, s.ms = s.hours + 1, s.ms + 10000
        s.onUpdate("machine:7")
        T.eq(#s.requests, 2)
        s.requests[2].cb({ ok = false, reason = "no_access" })
        T.eq(#s.closed, 1); T.eq(#s.shown, 3); T.ok(Card.open["machine:7"] == nil, "forgotten")
        -- A late answer for a card that is gone does nothing.
        s.requests[2].cb({ ok = true, n = 9 })
        T.eq(#s.shown, 3)
        -- Picked up: closed at the next frame without asking.
        Card.show(s.item, ref, { ok = true, n = 4 })
        s.placed = false
        s.hours, s.ms = s.hours + 1, s.ms + 10000
        s.onUpdate("machine:7")
        T.eq(#s.closed, 2); T.eq(#s.requests, 2)
    end)
end)

T.case("integration: one card window for each key; closing it by any way tells its owner once", function()
    stage(function(s)
        local made, closedKeys = {}, {}
        -- The game's window classes, as far as a card uses them.
        ISCollapsableWindow = {}
        ISCollapsableWindow.__index = ISCollapsableWindow
        function ISCollapsableWindow:derive(type)
            local o = setmetatable({}, self)
            o.__index = o
            o.Type = type
            return o
        end
        function ISCollapsableWindow:new(x, y, w, h)
            local o = setmetatable({ x = x, y = y }, self)
            made[#made + 1] = o
            return o
        end
        function ISCollapsableWindow:setResizable() end
        function ISCollapsableWindow:initialise() end
        function ISCollapsableWindow:addToUIManager() self.added = true end
        function ISCollapsableWindow:removeFromUIManager() self.added = false end
        function ISCollapsableWindow:setVisible(v) self.visible = v end
        function ISCollapsableWindow:bringToTop() self.raised = (self.raised or 0) + 1 end
        ISToolTip = {}
        getCore = function() return { getScreenWidth = function() return 1280 end } end
        local function onClose(key) closedKeys[#closedKeys + 1] = key end
        T.eq(Say.card("a", "Pot Still", "one", nil, onClose), "card")
        T.eq(Say.card("a", "Pot Still", "two", nil, onClose, true), "card")
        T.eq(made[1].cardText, "two"); T.eq(made[1].raised, 1, "filled again by itself: not brought forward")
        T.eq(Say.card("a", "Pot Still", "two again", nil, onClose), "card")
        T.eq(#made, 1, "the same window"); T.eq(made[1].cardText, "two again"); T.eq(made[1].title, "Pot Still")
        T.eq(made[1].raised, 2, "asked for again: brought forward")
        Say.card("b", "Wood Retort", "three", nil, onClose)
        T.eq(#made, 2); T.ok(made[2].y > made[1].y, "a little lower than the first")
        -- The close button.
        made[1]:close()
        T.eq(table.concat(closedKeys, ","), "a"); T.eq(made[1].added, false); T.ok(Say.cards.a == nil)
        Say.closeCard("a")
        T.eq(#closedKeys, 1, "once")
        -- Asked for again: a new window.
        Say.card("a", "Pot Still", "four", nil, onClose)
        T.eq(#made, 3)
        Say.closeCards()
        T.eq(#closedKeys, 3); T.ok(Say.cards.a == nil and Say.cards.b == nil)
    end, true)
end)

T.case("integration: without the game's window classes a card's text opens the window", function()
    stage(function(s)
        local windows = {}
        ISCollapsableWindow, ISToolTip = nil, nil
        getCore = function() return { getScreenWidth = function() return 1280 end, getScreenHeight = function() return 720 end } end
        ISModalRichText = { new = function(_, _, _, _, _, text)
            local o = { text = text }
            function o:initialise() end
            function o:addToUIManager() windows[#windows + 1] = self end
            return o
        end }
        T.eq(Card.show(s.item, {}, { ok = true, n = 1 }), "window")
        T.eq(#windows, 1); T.eq(windows[1].text, "status 1")
        T.ok(Card.open["machine:7"] == nil, "no card to keep up to date")
    end, true)
end)

T.case("integration: a card closes at once when its player is out of the machine's reach", function()
    stage(function(s)
        local function sq(x, y)
            return { x = x, y = y, DistToProper = function(self, o) return math.sqrt((o.x - self.x) ^ 2 + (o.y - self.y) ^ 2) end }
        end
        local at, there = sq(10, 10), sq(11, 10)
        local savedSquare = Machines.square
        Machines.square = function() return there end
        getSpecificPlayer = function(n) return n == 0 and { getSquare = function() return at end } or nil end
        local ok, err = pcall(function()
            Card.show(s.item, {}, { ok = true, n = 1 }, 0)
            s.onUpdate("machine:7")
            T.eq(#s.closed, 0, "a tile away")
            at.x = 12.5
            s.onUpdate("machine:7")
            T.eq(#s.closed, 0, "two and a half tiles: still within reach")
            at.x = 14
            s.onUpdate("machine:7")
            T.eq(#s.closed, 1, "three tiles away"); T.eq(#s.requests, 0, "without asking")
            -- A player this client cannot read: left to the authority's answer.
            Card.show(s.item, {}, { ok = true, n = 2 }, 1)
            s.onUpdate("machine:7")
            T.eq(#s.closed, 1)
            T.eq(Card.inReach({ item = s.item, playerNum = 0 }), false)
            there = nil
            T.eq(Card.inReach({ item = s.item, playerNum = 0 }), true, "no square to measure from")
        end)
        Machines.square = savedSquare
        if not ok then error(err, 0) end
    end)
end)
