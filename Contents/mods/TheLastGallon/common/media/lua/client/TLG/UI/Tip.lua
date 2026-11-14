-- A line beside a menu entry: why it is greyed, or what it will use. The
-- game shows an entry's toolTip also when the entry is not available
-- (SRC client/ISUI/ISContextMenu.lua). The inventory menu and the world
-- menu each keep their own tooltips and take them back when they are next
-- built (ISInventoryPaneContextMenu.addToolTip,
-- ISWorldObjectContextMenu.addToolTip), so the caller says which of the two
-- it fills. NOT RUN in game.
TLG.UI = TLG.UI or {}
TLG.UI.Tip = TLG.UI.Tip or {}
local Tip = TLG.UI.Tip

-- Sets `text` as the tooltip of `option`; `world` is true in the world
-- menu. Without the game's menus (the domain tests) it does nothing.
function Tip.set(option, text, world)
    if option == nil or text == nil or text == "" then return end
    local owner
    if world then owner = ISWorldObjectContextMenu else owner = ISInventoryPaneContextMenu end
    if type(owner) ~= "table" or type(owner.addToolTip) ~= "function" then return end
    local ok, tip = pcall(owner.addToolTip)
    if not ok or type(tip) ~= "table" then return end
    tip.description = text
    option.toolTip = tip
end

-- Greys `option` and says why.
function Tip.grey(option, text, world)
    if option == nil then return end
    option.notAvailable = true
    Tip.set(option, text, world)
end

return Tip
