-- A yes/no question before an action that throws something away: cancelling
-- or removing a conversion, emptying what an aborted batch left. The game's
-- own dialog, opened as the game opens its sleep question (SRC
-- client/ISUI/ISWorldObjectContextMenu.lua, sleepDialog): at 0,0 the dialog
-- centres itself on the player's screen, and with a controller it takes
-- the focus. The in-game harness answers yes by replacing Confirm.ask.
-- NOT RUN in game.
TLG.UI = TLG.UI or {}
TLG.UI.Confirm = TLG.UI.Confirm or {}
local Confirm = TLG.UI.Confirm

-- Asks `text` of player `playerNum`; `onYes` runs on Yes, nothing on No.
function Confirm.ask(text, onYes, playerNum)
    local dialog = ISModalDialog:new(0, 0, 420, 180, text, true, nil, function(_, button)
        if button.internal == "YES" then onYes() end
    end, playerNum)
    dialog:initialise()
    dialog:addToUIManager()
    if JoypadState ~= nil and JoypadState.players ~= nil and JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, dialog)
    end
end

return Confirm
