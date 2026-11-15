-- How a menu's reply reaches the player (D-016 as amended 2026-11-14, UX
-- review R6): a window for what is read (a status, a test's result) and
-- for a refusal with a list; a line over the character for what an action
-- did and for a refusal of one sentence. Until 0.5.0 every reply was a
-- window to close, one for each feed of a firebox.
--
-- The menus choose by the kind of reply (their own `line` functions), not
-- by the text's length: a translation must not turn a line into a window.
-- Every reply of the five menus goes through Say.window, Say.line or, for a
-- machine's Status, Say.card; the
-- in-game harness reads the texts here (TLGHarness, captureDialogs).
--
-- The line is the game's own text over the character (BC
-- zombie.characters.HaloTextHelper.addGoodText / addBadText(player, text),
-- as SRC client/ISUI/ISWorldObjectContextMenu.lua uses for "not safe to
-- sleep"). How two lines sent together show, and a line sent while the
-- game is paused, are NOT RUN. RT-SP launch 423: five lines of a gasifier taken
-- by the game, none fell back to the window. How a line looks was
-- not looked at.
TLG.UI = TLG.UI or {}
TLG.UI.Say = TLG.UI.Say or {}
local Say = TLG.UI.Say

-- The player the next replies are for: the one whose menu was opened last
-- (each menu's fill calls Say.from). The reply itself does not say.
Say.playerNum = Say.playerNum or 0

function Say.from(playerNum)
    if type(playerNum) == "number" then Say.playerNum = playerNum end
end

-- The game's speed as its speed controls have it, or nil where the game
-- has none.
local function gameSpeed()
    local ok, speed = pcall(function() return UIManager.getSpeedControls():getCurrentGameSpeed() end)
    if ok and type(speed) == "number" then return speed end
    return nil
end

-- Runs `destroy(modal)`, the game's way to close the window, and then
-- gives the game back the speed it had. Both of the game's windows set
-- the speed to 1 when they close (SRC client/ISUI/ISModalRichText.lua and
-- ISModalDialog.lua, destroy; launch 440 for the first), so a Status read while waiting
-- at a faster speed drops the wait to normal speed at its OK (UX review
-- R14). A paused game stays paused.
function Say.closeWith(modal, destroy)
    local before = gameSpeed()
    destroy(modal)
    if before ~= nil and before ~= gameSpeed() then
        pcall(function() UIManager.getSpeedControls():SetCurrentGameSpeed(before) end)
    end
end

-- A window of the mod's (ISModalRichText) closed with the speed kept.
function Say.close(modal)
    Say.closeWith(modal, ISModalRichText.destroy)
end

-- Makes a yes/no question of the game's (an ISModalDialog) keep the speed
-- when it is answered; returns the dialog.
function Say.keepSpeed(dialog)
    dialog.destroy = function(self) Say.closeWith(self, ISModalDialog.destroy) end
    return dialog
end

-- A window with `text` (the game's rich text), to close with OK. Closing
-- it leaves the game's speed as it was (Say.close).
function Say.window(text, width, height)
    local w, h = width or 420, height or 240
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, Say.playerNum)
    modal.destroy = Say.close
    modal:initialise()
    modal:addToUIManager()
    return modal
end

-- A card: a small window that stays open and is not in the way, as the
-- game's Generator Info is (SRC client/ISUI/ISGeneratorInfoWindow.lua: a
-- collapsable window around a tooltip panel, sized by its text). One card
-- for each `key`; calling again sets its text and brings it forward, or,
-- with `behind`, only sets its text.
-- `onUpdate(key)` is called at each frame the card is shown (the caller
-- paces what it does there) and `onClose(key)` when it goes, however it
-- goes: its close button, Say.closeCard, Say.closeCards. Where the game's
-- window classes are missing the text opens the window instead. Returns
-- "card" or "window". UX review, section 5.
Say.cards = Say.cards or {}
local CardWindow

local function cardClass()
    if ISCollapsableWindow == nil or ISToolTip == nil then return nil end
    if CardWindow then return CardWindow end
    CardWindow = ISCollapsableWindow:derive("TLGCardWindow")
    function CardWindow:createChildren()
        ISCollapsableWindow.createChildren(self)
        self.panel = ISToolTip:new()
        self.panel.followMouse = false
        self.panel:initialise()
        self:addView(self.panel)
    end
    function CardWindow:update()
        ISCollapsableWindow.update(self)
        self.panel.maxLineWidth = 400
        self.panel.description = self.cardText
        self:setWidth(math.max(self.panel:getWidth(), 220))
        self:setHeight(self:titleBarHeight() + self.panel:getHeight())
        if self.onUpdate then self.onUpdate(self.cardKey) end
    end
    -- The close button: the base class only hides the window, and a hidden
    -- card would go on asking.
    function CardWindow:close() Say.closeCard(self.cardKey) end
    return CardWindow
end

function Say.card(key, title, text, onUpdate, onClose, behind)
    local class = cardClass()
    if class == nil then
        Say.window(text)
        return "window"
    end
    local card = Say.cards[key]
    if card == nil then
        -- Beside the centre, each new card a little lower than the last.
        local n = 0
        for _ in pairs(Say.cards) do n = n + 1 end
        card = class:new(getCore():getScreenWidth() / 2 + 60, 120 + 40 * (n - math.floor(n / 8) * 8), 320, 120)
        card.cardKey = key
        card:setResizable(false)
        card:initialise()
        card:addToUIManager()
        Say.cards[key] = card
    end
    local new = card.cardText == nil
    card.title, card.cardText, card.onUpdate, card.onClose = title, text, onUpdate, onClose
    -- A card filled again by itself stays where it is among the windows.
    if behind and not new then return "card" end
    card:setVisible(true)
    card:bringToTop()
    return "card"
end

-- Removes the card of `key`, if there is one, and tells its owner.
function Say.closeCard(key)
    local card = Say.cards[key]
    if card == nil then return end
    Say.cards[key] = nil
    card.onUpdate = nil
    pcall(function() card:setVisible(false); card:removeFromUIManager() end)
    if card.onClose then pcall(card.onClose, key) end
end

function Say.closeCards()
    local keys = {}
    for key in pairs(Say.cards) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do Say.closeCard(key) end
end

-- `text` over the character, green when `good` and red otherwise. Text
-- with a line break, and any text the game cannot put over a character,
-- opens the window instead: a reply is never dropped. Returns "line" or
-- "window".
function Say.line(text, good)
    if type(text) == "string" and text ~= "" and not string.find(text, "<LINE>", 1, true) then
        local ok = pcall(function()
            local player = getSpecificPlayer(Say.playerNum)
            if player == nil then error("no player") end
            if good then HaloTextHelper.addGoodText(player, text) else HaloTextHelper.addBadText(player, text) end
        end)
        if ok then return "line" end
    end
    Say.window(text)
    return "window"
end

-- A refusal: over the character when it is one sentence, in a window when
-- it carries a list (what was found, what is missing).
function Say.refusal(text)
    return Say.line(text, false)
end

return Say
