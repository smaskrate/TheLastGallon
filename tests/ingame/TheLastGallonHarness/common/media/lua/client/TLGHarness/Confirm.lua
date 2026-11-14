-- The mod asks before cancelling or removing a conversion and before
-- throwing away what an aborted batch left (TLG/UI/Confirm.lua). A harness
-- run has nobody to click: the question is answered yes, here for every
-- mode, single player and multiplayer clients alike. The dialog itself is
-- therefore never opened by the harness.
local function answerYes()
    if TLG and TLG.UI and TLG.UI.Confirm then
        TLG.UI.Confirm.ask = function(text, onYes) onYes() end
    end
end

answerYes()
-- Again once the game starts, in case this file loaded before the mod's.
Events.OnGameStart.Add(answerYes)
