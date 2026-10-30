-- Inventory context menu for fuel containers. Every action is a request to
-- the authority (TLG.Net); the menu never changes fuel state itself.
require "TLG/Client/Net"
require "TLG/UI/Format"
require "TLG/Integration/Native"
require "TLG/Actions/ISTLGPourFuel"

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
    else
        Menu.addPourOptions(player, sub, item)
    end
    Menu.addDrainOptions(player, sub, item)
end

-- Pouring into engines goes through the authoritative transfer so that any
-- fuel (not only Petrol) and its condition reach the tank, and incompatible
-- blends need an explicit experimental confirmation.
local function queuePour(player, item, destination, face, experimental)
    if luautils and luautils.equipItems then luautils.equipItems(player, item, nil) end
    ISTimedActionQueue.add(ISTLGPourFuel:new(player, item, destination, face, experimental, function(reply)
        if reply.ok then return end
        if reply.reason == "incompatible" and not experimental then
            local text = getText("IGUI_TLG_Fail_Incompatible") .. " <LINE> <LINE> " .. Fmt.evaluation(reply.evaluation)
            local w, h = 440, 260
            local dlg = ISModalDialog:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
                w, h, text, true, nil, function(_, button)
                    if button.internal == "YES" then queuePour(player, item, destination, face, true) end
                end)
            dlg:initialise()
            dlg:addToUIManager()
        else
            show(Fmt.failure(reply))
        end
    end))
end

local function nearbyVehicleTank(player)
    local vehicles = getCell():getVehicles()
    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        local tank = v:getPartById("GasTank")
        if tank and v:isInArea(tank:getArea(), player) then return v end
    end
    return nil
end

local function nearbyGenerator(player)
    local sq = player:getSquare()
    if sq == nil then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
                end
            end
        end
    end
    return nil
end

local function nearbyPump(player)
    local sq = player:getSquare()
    if sq == nil then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if TLG.Integration.Stations.isPump(objs:get(i)) then return objs:get(i) end
                end
            end
        end
    end
    return nil
end

-- Vanilla has no way to empty a generator; conversions require a drained
-- fuel system, so TLG offers an authoritative drain into a can.
function Menu.addDrainOptions(player, sub, item)
    local free = item:getFluidContainer():getFreeCapacity()
    local g = nearbyGenerator(player)
    if g and free > 0.05 and g:getFuel() > 0 then
        sub:addOption(getText("ContextMenu_TLG_DrainGenerator"), nil, function()
            request("transfer", { source = TLG.Authority.Resolver.refForObject(g, "generator"),
                destination = { kind = "item", id = item:getID() }, amount = free })
        end)
    end
end

function Menu.addPourOptions(player, sub, item)
    local pump = nearbyPump(player)
    if pump then
        -- Restored station: the reservoir becomes player-run storage.
        sub:addOption(getText("ContextMenu_TLG_PourStation"), nil, function()
            request("transfer", { source = { kind = "item", id = item:getID() },
                destination = TLG.Authority.Resolver.refForObject(pump, "pump"),
                amount = item:getFluidContainer():getAmount() })
        end)
    end
    local v = nearbyVehicleTank(player)
    if v then
        sub:addOption(getText("ContextMenu_TLG_PourVehicle"), nil, function()
            queuePour(player, item, { kind = "vehicle", id = v:getId() }, v, false)
        end)
    end
    local g = nearbyGenerator(player)
    if g then
        sub:addOption(getText("ContextMenu_TLG_PourGenerator"), nil, function()
            queuePour(player, item, TLG.Authority.Resolver.refForObject(g, "generator"), g, false)
        end)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)

return Menu
