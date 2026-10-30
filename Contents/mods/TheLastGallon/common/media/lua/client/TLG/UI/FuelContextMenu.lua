-- Inventory context menu for fuel containers. Every action is a request to
-- the authority (TLG.Net); the menu never changes fuel state itself.
require "TLG/Client/Net"
require "TLG/UI/Format"
require "TLG/Integration/Native"

TLG.UI = TLG.UI or {}
TLG.UI.FuelMenu = TLG.UI.FuelMenu or {}
local Menu = TLG.UI.FuelMenu
local Fmt, Native = TLG.UI.Format, TLG.Integration.Native

local function show(text)
    local w, h = 420, 260
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
end

local function onReply(reply)
    if not reply.ok then
        show(Fmt.failure(reply))
        return
    end
    if reply.observation then
        show(getText("IGUI_TLG_InspectionTitle") .. " <LINE> <LINE> " .. Fmt.observation(reply.observation))
    elseif reply.command == "status" and reply.evaluation then
        show(Fmt.evaluation(reply.evaluation))
    elseif reply.command == "treat" then
        show(getText("IGUI_TLG_TreatDone_" .. tostring(reply.op)))
    end
end

local function itemRef(item) return { kind = "item", id = item:getID() } end

local function request(command, args) TLG.Net.request(command, args, onReply) end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

local function isFuelCan(item)
    local fc = item and item:getFluidContainer()
    if fc == nil then return false end
    if fc:isEmpty() then return TLG.ContainerProfiles.items[item:getFullType()] ~= nil end
    return Native.isFuelContainer(fc)
end

function Menu.fill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local item
    for _, entry in ipairs(items) do
        local it = firstItem(entry)
        if isFuelCan(it) then item = it; break end
    end
    if item == nil or player == nil then return end
    local root = context:addOption(getText("ContextMenu_TLG_Fuel"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local ref = itemRef(item)
    local know = player:getModData().tlgKnowledge
    local side = item:getModData().tlg
    local known = side and know and know[tostring(side.id)]
    sub:addOption(getText("ContextMenu_TLG_ShowKnown"), nil, function()
        show(getText("IGUI_TLG_InspectionTitle") .. " <LINE> <LINE> " .. Fmt.observation(known))
    end)
    sub:addOption(getText("ContextMenu_TLG_Look"), nil, function() request("sample", { target = ref, method = "visual" }) end)
    local kit = sub:addOption(getText("ContextMenu_TLG_SampleKit"), nil,
        function() request("sample", { target = ref, method = "kit" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelSampleKit") then kit.notAvailable = true end
    local stab = sub:addOption(getText("ContextMenu_TLG_Stabilize"), nil,
        function() request("treat", { target = ref, op = "stabilize" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelStabilizer") then stab.notAvailable = true end
    local filt = sub:addOption(getText("ContextMenu_TLG_Filter"), nil,
        function() request("treat", { target = ref, op = "filter" }) end)
    if not player:getInventory():getFirstTypeRecurse("TLG.FuelFilter") then filt.notAvailable = true end
    sub:addOption(getText("ContextMenu_TLG_DrainWater"), nil, function() request("treat", { target = ref, op = "separate" }) end)
    if side == nil or side.sealed ~= false then
        sub:addOption(getText("ContextMenu_TLG_Unseal"), nil, function() request("treat", { target = ref, op = "unseal" }) end)
    else
        sub:addOption(getText("ContextMenu_TLG_Seal"), nil, function() request("treat", { target = ref, op = "seal" }) end)
    end
    if item:getFluidContainer():isEmpty() then
        sub:addOption(getText("ContextMenu_TLG_Clean"), nil, function() request("treat", { target = ref, op = "clean" }) end)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)

return Menu
