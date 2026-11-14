-- How a menu's reply reaches the player (D-016 as amended 2026-11-14, UX
-- review R6): a window for what is read (a status, a test's result) and
-- for a refusal with a list; a line over the character for what an action
-- did and for a refusal of one sentence. Until 0.5.0 every reply was a
-- window to close, one for each feed of a firebox.
--
-- The menus choose by the kind of reply (their own `line` functions), not
-- by the text's length: a translation must not turn a line into a window.
-- Every reply of the five menus goes through Say.window or Say.line; the
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

-- A window with `text` (the game's rich text), to close with OK.
function Say.window(text, width, height)
    local w, h = width or 420, height or 240
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, Say.playerNum)
    modal:initialise()
    modal:addToUIManager()
    return modal
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
