-- World context menu: workshop conversions for a nearby generator or
-- vehicle. All steps are authority requests (TLG.Net); work credit comes
-- from world time on the authority, so "Report progress" can be used any
-- time and never credits more than really elapsed.
require "TLG/Client/Net"
require "TLG/Authority/Resolver"

TLG.UI = TLG.UI or {}
TLG.UI.WorkshopMenu = TLG.UI.WorkshopMenu or {}
local Menu = TLG.UI.WorkshopMenu

local function show(text)
    local w, h = 440, 260
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
end

local function textOr(key, fallbackKey, arg)
    local t = getText(key, arg)
    if t == key then return getText(fallbackKey, arg) end
    return t
end

function Menu.describe(reply)
    if not reply.ok then
        local lines = { textOr("IGUI_TLG_ConvReason_" .. tostring(reply.reason), "IGUI_TLG_Fail_Generic", tostring(reply.reason)) }
        for _, m in ipairs(reply.missing or {}) do lines[#lines + 1] = "- " .. tostring(m) end
        return table.concat(lines, " <LINE> ")
    end
    local lines = { getText("IGUI_TLG_ConvState_" .. tostring(reply.state)) }
    if reply.conversion then lines[#lines + 1] = getText("IGUI_TLG_Conversion_" .. reply.conversion) end
    if reply.stage then lines[#lines + 1] = getText("IGUI_TLG_ConvStage", getText("IGUI_TLG_ConvStage_" .. reply.stage)) end
    if reply.blocked then
        lines[#lines + 1] = textOr("IGUI_TLG_ConvReason_" .. tostring(reply.blocked.reason), "IGUI_TLG_Fail_Generic",
            tostring(reply.blocked.reason))
        for _, m in ipairs(reply.blocked.missing or {}) do lines[#lines + 1] = "- " .. tostring(m) end
    end
    if reply.profile then lines[#lines + 1] = getText("IGUI_TLG_ConvProfile", getText("IGUI_TLG_Profile_" .. reply.profile)) end
    return table.concat(lines, " <LINE> ")
end

local function req(command, args) TLG.Net.request(command, args, function(r) show(Menu.describe(r)) end) end

local function nearbyGenerator(player)
    local sq = player:getSquare()
    for dx = -2, 2 do
        for dy = -2, 2 do
            local s = sq and getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
                end
            end
        end
    end
end

local function nearbyVehicle(player)
    local best, bestD
    local vehicles = getCell():getVehicles()
    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        local d = player:DistTo(v:getX(), v:getY())
        if d <= 4 and (bestD == nil or d < bestD) then best, bestD = v, d end
    end
    return best
end

local function addDeviceMenu(context, titleKey, deviceRef, kind, chassis)
    local root = context:addOption(getText(titleKey), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    sub:addOption(getText("ContextMenu_TLG_ConvStatus"), nil, function()
        TLG.Net.request("conversion.status", { device = deviceRef }, function(r)
            show(Menu.describe(r))
        end)
    end)
    for _, row in ipairs(TLG.Domain.ConversionService.matrix()) do
        if row.deviceKind == kind and row.chassis == chassis then
            sub:addOption(getText("ContextMenu_TLG_ConvBegin", getText("IGUI_TLG_Conversion_" .. row.conversion)), nil,
                function() req("conversion.begin", { device = deviceRef, conversion = row.conversion }) end)
        end
    end
    sub:addOption(getText("ContextMenu_TLG_ConvJoin"), nil, function() req("conversion.join", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvWork"), nil, function() req("conversion.work", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvDeliver"), nil, function() req("conversion.deliver", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvLeave"), nil,
        function() req("conversion.work", { device = deviceRef, leave = true }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvCancel"), nil, function() req("conversion.cancel", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvRemove"), nil, function() req("conversion.remove", { device = deviceRef }) end)
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:getVehicle() ~= nil then return end
    local gen = nearbyGenerator(player)
    if gen then
        addDeviceMenu(context, "ContextMenu_TLG_ConvGenerator", TLG.Authority.Resolver.refForObject(gen, "generator"),
            "generator", gen:getGeneratorItemType())
    end
    local v = nearbyVehicle(player)
    if v then
        addDeviceMenu(context, "ContextMenu_TLG_ConvVehicle", { kind = "vehicle", id = v:getId() }, "vehicle",
            v:getScriptName())
    end
end

Events.OnFillWorldObjectContextMenu.Add(Menu.fill)

return Menu
