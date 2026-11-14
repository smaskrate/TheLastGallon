-- The Repair entry of a machine's and a gasifier's menu (UX review R8).
-- Shown when the machine is worn enough; what a repair takes and gives back is
-- beside the entry, from the selection the authority uses
-- (TLG/Integration/Picks.repair). Greyed, with the reason, while the
-- machine is busy or the character lacks the tool or a part.
-- RT-SP launches 424 (a pot still, a fermenter) and 425 (a gasifier).
require "TLG/Integration/Picks"
require "TLG/UI/Tip"

TLG.UI = TLG.UI or {}
TLG.UI.Repair = TLG.UI.Repair or {}
local Repair = TLG.UI.Repair
local Picks, Tip = TLG.Integration.Picks, TLG.UI.Tip

local function itemName(fullType)
    local ok, name = pcall(getItemNameFromFullType, fullType)
    if ok and name and name ~= "" then return name end
    return fullType
end

-- "2 Nails, 1 Plank" from { fullType = count }.
function Repair.partsText(parts)
    local out = {}
    for _, fullType in ipairs(TLG.Tables.sortedKeys(parts)) do
        out[#out + 1] = tostring(parts[fullType]) .. " " .. itemName(fullType)
    end
    return table.concat(out, ", ")
end

-- "Plank, Nails" from a list of types, each named once.
function Repair.namesText(list)
    local out, seen = {}, {}
    for _, fullType in ipairs(list or {}) do
        if not seen[fullType] then
            seen[fullType] = true
            out[#out + 1] = itemName(fullType)
        end
    end
    return table.concat(out, ", ")
end

-- What a repair of `machineId` gives back and takes, in one sentence.
function Repair.needs(machineId)
    local spec = Picks.repairSpec(machineId)
    return getText("IGUI_TLG_Tip_Repair", string.format("%.0f%%", Picks.REPAIR_STEP * 100), Repair.partsText(spec.parts),
        itemName(spec.tools[1]))
end

-- A refusal's list of what the repair lacks, for the dialog: " <LINE> - X".
function Repair.missingLines(reply)
    local text, seen = "", {}
    for _, fullType in ipairs(reply.missing or {}) do
        if not seen[fullType] then
            seen[fullType] = true
            text = text .. " <LINE> - " .. itemName(fullType)
        end
    end
    return text
end

-- Adds the entry to `sub` when the machine is worn enough for a whole
-- repair (Picks.repairable: at 75 % or less).
-- `busy` is the reason text while it cannot be repaired now (nil when it
-- can); `onClick` sends the request. Returns the entry, nil when not shown.
function Repair.add(sub, player, machineId, cond, busy, world, onClick)
    if not Picks.repairable(cond) then return nil end
    local o = sub:addOption(getText("ContextMenu_TLG_Repair"), nil, onClick)
    local needs = Repair.needs(machineId)
    if busy then
        Tip.grey(o, busy, world)
        return o
    end
    local pick = Picks.repair(player, machineId)
    if pick.ok then
        Tip.set(o, needs, world)
    else
        Tip.grey(o, getText("IGUI_TLG_Tip_RepairMissing", Repair.namesText(pick.missing)) .. " <LINE> " .. needs, world)
    end
    return o
end

return Repair
