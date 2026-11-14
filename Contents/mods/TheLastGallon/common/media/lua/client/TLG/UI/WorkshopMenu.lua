-- World context menu: workshop conversions for the generator or the vehicle
-- the click is on (TLG/UI/Clicked.lua; until 0.3.0 for any within reach of
-- the character, whatever was clicked, so the entry also showed on bare
-- ground beside a car). All steps are authority requests (TLG.Net). "Work on it" walks to
-- the device and starts ISTLGConversionWork, which reports while the
-- character stays there; time away from the device is never credited.
-- Start, Hand over parts and Work on it used RT-SP 2026-10-31 (run 12) on a
-- Base.Generator and a Base.CarNormal; Project status, Cancel and Remove
-- are NOT RUN.
require "TLG/Client/Net"
require "TLG/Authority/Resolver"
require "TLG/Integration/ConversionDevices"
require "TLG/Actions/ISTLGConversionWork"
require "TLG/UI/Clicked"
require "TLG/UI/Format"

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

-- What is missing, in the player's words: items by display name (vanilla
-- getItemNameFromFullType), skills as "Mechanics 4", recipes as named.
function Menu.missingText(m)
    m = tostring(m)
    local skill, level = string.match(m, "^(%a+):(%d+)$")
    if skill then
        local name = getText("IGUI_perks_" .. skill)
        if name == "IGUI_perks_" .. skill then name = skill end
        return name .. " " .. level
    end
    if string.find(m, ".", 1, true) then
        local ok, name = pcall(getItemNameFromFullType, m)
        if ok and name and name ~= "" then return name end
    end
    return m
end

-- "4 Screws, 1 Rubber Hose": parts by display name with their counts, from
-- a table { fullType = count }; nil when it is empty or missing.
function Menu.partsText(t)
    if type(t) ~= "table" or TLG.Tables.isEmpty(t) then return nil end
    local parts = {}
    for _, id in ipairs(TLG.Tables.sortedKeys(t)) do
        parts[#parts + 1] = tostring(t[id]) .. " " .. Menu.missingText(id)
    end
    return table.concat(parts, ", ")
end

-- A refusal's text: the workshop's own wording, else the shared one
-- (TLG/UI/Format.lua).
local function reasonText(reason)
    local key = "IGUI_TLG_ConvReason_" .. tostring(reason)
    local text = getText(key)
    if text == key then return TLG.UI.Format.failure({ reason = reason }) end
    return text
end

-- The text of a workshop reply. After the state it lists what the step
-- moved, from the reply (TLG/Authority/ConversionHandlers.lua): the parts
-- handed over and those still needed, the parts a cancel or a removal gave
-- back and lost, and the hours of work done. The hours were read in a
-- dialog in RT-SP launch 413; the lists of parts are NOT RUN in game.
function Menu.describe(reply)
    if not reply.ok then
        local lines = { reasonText(reply.reason) }
        for _, m in ipairs(reply.missing or {}) do lines[#lines + 1] = "- " .. Menu.missingText(m) end
        return table.concat(lines, " <LINE> ")
    end
    local lines = { getText("IGUI_TLG_ConvState_" .. tostring(reply.state)) }
    if reply.conversion then lines[#lines + 1] = getText("IGUI_TLG_Conversion_" .. reply.conversion) end
    if reply.stage then lines[#lines + 1] = getText("IGUI_TLG_ConvStage", getText("IGUI_TLG_ConvStage_" .. reply.stage)) end
    if type(reply.doneHours) == "number" and type(reply.totalHours) == "number" and reply.totalHours > 0 then
        lines[#lines + 1] = getText("IGUI_TLG_ConvHours", string.format("%.1f", reply.doneHours),
            string.format("%.1f", reply.totalHours))
    end
    for _, row in ipairs({ { "consumed", "IGUI_TLG_ConvConsumed" }, { "outstanding", "IGUI_TLG_ConvOutstanding" },
        { "returned", "IGUI_TLG_ConvReturned" }, { "lost", "IGUI_TLG_ConvLost" } }) do
        local parts = Menu.partsText(reply[row[1]])
        if parts then lines[#lines + 1] = getText(row[2], parts) end
    end
    if reply.blocked then
        lines[#lines + 1] = reasonText(reply.blocked.reason)
        for _, m in ipairs(reply.blocked.missing or {}) do lines[#lines + 1] = "- " .. Menu.missingText(m) end
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
    -- getVehicles() is a java.util.HashSet on 42.21 (see Integration/Vehicles.lua).
    for _, v in ipairs(getCell():getVehicles():toArray()) do
        local d = player:DistTo(v:getX(), v:getY())
        if d <= 4 and (bestD == nil or d < bestD) then best, bestD = v, d end
    end
    return best
end

-- Walks to the engine area (vehicle) or next to the generator, then works.
function Menu.work(player, deviceRef, device)
    local action = ISTLGConversionWork:new(player, deviceRef, device, function(r) show(Menu.describe(r)) end)
    if deviceRef.kind == "vehicle" then
        local engine = device:getPartById("Engine")
        if engine then ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, device, engine:getArea())) end
        ISTimedActionQueue.add(action)
    elseif luautils.walkAdj(player, device:getSquare()) then
        ISTimedActionQueue.add(action)
    end
end

local function addDeviceMenu(context, player, titleKey, deviceRef, device, kind, chassis)
    local root = context:addOption(getText(titleKey), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    sub:addOption(getText("ContextMenu_TLG_ConvStatus"), nil, function()
        TLG.Net.request("conversion.status", { device = deviceRef }, function(r)
            show(Menu.describe(r))
        end)
    end)
    for _, row in ipairs(TLG.Domain.ConversionService.matrix()) do
        if row.deviceKind == kind and row.chassis == chassis and TLG.Integration.ConversionDevices.offered(row.conversion) then
            sub:addOption(getText("ContextMenu_TLG_ConvBegin", getText("IGUI_TLG_Conversion_" .. row.conversion)), nil,
                function() req("conversion.begin", { device = deviceRef, conversion = row.conversion }) end)
        end
    end
    sub:addOption(getText("ContextMenu_TLG_ConvDeliver"), nil, function() req("conversion.deliver", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvJoin"), nil, function() Menu.work(player, deviceRef, device) end)
    sub:addOption(getText("ContextMenu_TLG_ConvCancel"), nil, function() req("conversion.cancel", { device = deviceRef }) end)
    sub:addOption(getText("ContextMenu_TLG_ConvRemove"), nil, function() req("conversion.remove", { device = deviceRef }) end)
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:getVehicle() ~= nil then return end
    -- With a controller there is no cursor: the nearest in reach, as before.
    local gen = TLG.UI.Clicked.generator(playerNum, worldobjects, function() return nearbyGenerator(player) end)
    if gen then
        addDeviceMenu(context, player, "ContextMenu_TLG_ConvGenerator",
            TLG.Authority.Resolver.refForObject(gen, "generator"), gen, "generator", gen:getGeneratorItemType())
    end
    local v = TLG.UI.Clicked.vehicle(playerNum, worldobjects, function() return nearbyVehicle(player) end)
    if v then
        addDeviceMenu(context, player, "ContextMenu_TLG_ConvVehicle", { kind = "vehicle", id = v:getId() }, v,
            "vehicle", v:getScriptName())
    end
end

Events.OnFillWorldObjectContextMenu.Add(Menu.fill)

return Menu
