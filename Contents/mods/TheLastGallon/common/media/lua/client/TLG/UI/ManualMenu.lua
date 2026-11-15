-- Inventory menu entries that open the manual's further pages
-- (TLG.Integration.Manual.PAGES): "Read: Biodiesel" and "Read: Gas
-- generators" on the field manual, the first on the Biodiesel Handbook and
-- the second on the Wood Gas Handbook. A page opens at once in the game's
-- print media window, built as the game builds it after reading (SRC
-- ISReadABook.lua displayPrintMedia); nothing is recorded and the server is
-- not asked. The game's own entries stay as they are: Inspect on the manual,
-- Read on a handbook. Run in single player, English and Italian (launches
-- 436 and 437).
require "TLG/Integration/Manual"
require "TLG/UI/Tip"

TLG.UI = TLG.UI or {}
TLG.UI.ManualMenu = TLG.UI.ManualMenu or {}
local Menu = TLG.UI.ManualMenu
local Manual = TLG.Integration.Manual

-- Why the page cannot be read now, as the game refuses its Inspect entry
-- (SRC ISInventoryPaneContextMenu.lua doPrintMediaMenu): the text key, or
-- nil.
function Menu.refusal(player)
    if player:tooDarkToRead() then return "ContextMenu_TooDarkToInspect" end
    if player:isAsleep() then return "ContextMenu_NoOptionSleeping" end
    return nil
end

-- Opens the page `id` for the player `playerNum` and returns its window.
function Menu.open(playerNum, id)
    local p = Manual.PAGES[id]
    if p == nil then return nil end
    local win = PZAPI.UI.PrintMedia{ x = 730, y = 100 }
    win.data = getText(p.page)
    win.children.bar.children.name.text = getText(p.title)
    win.textTitle = getText(p.title)
    win.textData = string.gsub(getText(p.text), "\\n", "\n")
    win:instantiate()
    win.javaObj:setAlwaysOnTop(false)
    win:centerOnScreen(playerNum)
    if getJoypadData(playerNum) then
        ISAtomUIJoypad.Apply(win)
        win.playerNum = playerNum
        win.prevFocus = getJoypadData(playerNum).focus
        win.close = function(self)
            UIManager.RemoveElement(self.javaObj)
            if getJoypadData(self.playerNum) then setJoypadFocus(self.playerNum, self.prevFocus) end
        end
        win.children.bar.children.closeButton.onLeftClick = function(button)
            getSoundManager():playUISound(button.sounds.activate)
            button.parent.parent:close()
        end
        win.onJoypadDown = function(self, button)
            if button == Joypad.BButton then self.children.bar.children.closeButton:onLeftClick() end
            if button == Joypad.XButton then self:onClickNewspaperButton() end
        end
        setJoypadFocus(playerNum, win)
    end
    return win
end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

-- The first manual or handbook among `items` gets its entries. A character
-- who cannot read gets none, as the game's Inspect does nothing for one.
function Menu.fill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:hasTrait(CharacterTrait.ILLITERATE) then return end
    for _, entry in ipairs(items) do
        local item = firstItem(entry)
        local pages = item and Manual.pagesOf(item:getFullType()) or {}
        if #pages > 0 then
            local why = Menu.refusal(player)
            for _, id in ipairs(pages) do
                local option = context:addOption(getText(Manual.PAGES[id].entry), playerNum, Menu.open, id)
                option.itemForTexture = item
                if why then TLG.UI.Tip.grey(option, getText(why), false) end
            end
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)

return Menu
