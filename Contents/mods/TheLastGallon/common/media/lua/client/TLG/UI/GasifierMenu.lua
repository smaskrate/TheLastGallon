-- Menu of the gasifier (D-040, wood gas), on the item in the inventory and
-- on the floor: Load the hopper with wood, Light, Put out, Clean out tar and
-- ash, Status. Every action is a request to the authority
-- (TLG/Authority/GasifierHandlers.lua). The menu reads the record only to
-- offer what applies, on a copy brought to now: records advance when the
-- authority reads them, so the stored state can lag.
require "TLG/Client/Net"
require "TLG/Integration/Gasifiers"
require "TLG/UI/Format"
require "TLG/UI/Clicked"
require "TLG/Content/Feedstocks"

TLG.UI = TLG.UI or {}
TLG.UI.GasifierMenu = TLG.UI.GasifierMenu or {}
local Menu = TLG.UI.GasifierMenu
local GZ, Fmt, Gasifier, Tables = TLG.Integration.Gasifiers, TLG.UI.Format, TLG.Domain.Gas.Gasifier, TLG.Tables

local function show(text)
    local w, h = 420, 240
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
end

local function num(x, places)
    return string.format("%." .. tostring(places or 2) .. "f", x or 0)
end

-- The state line: lit gasifiers by what they do, or wait for.
function Menu.stateKey(r)
    if r.state == "Processing" then
        return "IGUI_TLG_GasifierState_" .. (r.mode == "warming" and "warming" or "running")
    elseif r.state == "Paused" then
        return "IGUI_TLG_GasifierState_" .. tostring(r.pause)
    end
    return "IGUI_TLG_GasifierState_" .. tostring(r.state)
end

-- The text of a gasifier reply: what the action did, then its status.
function Menu.describe(r)
    local lines = {}
    if r.loadedKg then lines[#lines + 1] = getText("IGUI_TLG_GasifierLoaded", num(r.loadedKg, 1), tostring(r.items or 0)) end
    if r.vented then lines[#lines + 1] = getText("IGUI_TLG_GasifierVented", num(r.vented)) end
    if r.thrownAway then
        local t = r.thrownAway
        lines[#lines + 1] = getText("IGUI_TLG_GasifierServiced", num(t.wood_tar), num(t.wood_ash), num(t.water))
    end
    lines[#lines + 1] = getText(Menu.stateKey(r))
    if r.placed == false then lines[#lines + 1] = getText("IGUI_TLG_GasifierCarried") end
    lines[#lines + 1] = getText("IGUI_TLG_GasifierHopper", num(r.hopperKg, 1))
    if r.state == "Processing" and r.mode == "warming" then
        lines[#lines + 1] = getText("IGUI_TLG_GasifierWarm", string.format("%.0f%%", (r.warm or 0) * 100))
    end
    if r.state == "Processing" or r.state == "Paused" then
        lines[#lines + 1] = getText("IGUI_TLG_GasifierBuffer", num(r.buffer), num(r.bufferCap))
    end
    if r.holdLeft then
        -- What keeps it lit depends on why it waits. Asked with its
        -- argument: the game's Translator warns of a text with %1 asked
        -- without one (launch 358).
        local key, hold = "IGUI_TLG_GasifierHot_" .. tostring(r.pause), num(r.holdLeft, 1)
        local text = getText(key, hold)
        if text == key then text = getText("IGUI_TLG_GasifierHot", hold) end
        lines[#lines + 1] = text
    end
    lines[#lines + 1] = getText("IGUI_TLG_GasifierFilter", string.format("%.0f%%", (r.filter or 0) * 100))
    local held = r.held or {}
    if (held.wood_tar or 0) > 0 or (held.wood_ash or 0) > 0 then
        lines[#lines + 1] = getText("IGUI_TLG_GasifierHeld", num(held.wood_tar), num(held.wood_ash))
    end
    return table.concat(lines, " <LINE> ")
end

local function onReply(reply)
    if not reply.ok then
        local key = "IGUI_TLG_GasifierFail_" .. tostring(reply.reason)
        local text = getText(key)
        show(text ~= key and text or Fmt.failure(reply))
        return
    end
    show(Menu.describe(reply))
end

local function req(command, ref) TLG.Net.request(command, { target = ref }, onReply) end

-- The record as the authority would bring it to now, on a copy; nil for a
-- newer build's record.
function Menu.state(item)
    local ok, st = pcall(function()
        local rec = GZ.read(item, false)
        return rec and GZ.advance(item, rec, TLG.World.now())
    end)
    if ok then return st end
    return nil
end

-- Wood or charcoal the authority would load (TLG/Content/Feedstocks).
function Menu.hasWood(player)
    local list = player:getInventory():getAllEvalRecurse(function(it)
        local c = TLG.Feedstocks.contribution(it:getFullType())
        return c ~= nil and ((c.wood or 0) > 0 or (c.charcoal or 0) > 0)
    end)
    return list:size() > 0
end

local function addGasifier(playerNum, context, item, title)
    local player = getSpecificPlayer(playerNum)
    if item == nil or player == nil then return end
    local root = context:addOption(title or getText("ContextMenu_TLG_Gasifier"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local ref = GZ.refFor(item)
    sub:addOption(getText("ContextMenu_TLG_GasifierStatus"), nil, function() req("gasifier.status", ref) end)
    if not GZ.isPlaced(item) then
        local o = sub:addOption(getText("ContextMenu_TLG_PlaceFirst"), nil, nil)
        o.notAvailable = true
        return
    end
    local st = Menu.state(item)
    if st == nil then return end
    local s = Gasifier.status(st)
    local m = TLG.Registry.need("machine", st.machine)
    local load = sub:addOption(getText("ContextMenu_TLG_GasifierLoad"), nil, function() req("gasifier.load", ref) end)
    if s.hopperKg >= m.capacity - 1e-9 or not Menu.hasWood(player) then load.notAvailable = true end
    if GZ.lit(st) then
        sub:addOption(getText("ContextMenu_TLG_GasifierPutOut"), nil, function() req("gasifier.putOut", ref) end)
    else
        local light = sub:addOption(getText("ContextMenu_TLG_GasifierLight"), nil, function() req("gasifier.light", ref) end)
        if s.hopperKg <= 0 or st.state == "Faulted" then light.notAvailable = true end
    end
    if st.state ~= "Processing" and (st.filter > 0 or not Tables.isEmpty(st.held)) then
        sub:addOption(getText("ContextMenu_TLG_GasifierService"), nil, function() req("gasifier.service", ref) end)
    end
end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

function Menu.fill(playerNum, context, items)
    for _, entry in ipairs(items) do
        local item = firstItem(entry)
        if GZ.machineFor(item) then
            addGasifier(playerNum, context, item)
            return
        end
    end
end

-- On the floor, the gasifiers the click is on, found as the game finds the
-- items of its Grab entry (TLG/UI/Clicked.lua).
function Menu.fillWorld(playerNum, context, worldobjects, test)
    if getSpecificPlayer(playerNum) == nil then return end
    local items, seen = {}, {}
    for _, object in ipairs(TLG.UI.Clicked.worldItems(playerNum, context, worldobjects)) do
        local item = object:getItem()
        if GZ.machineFor(item) and not seen[item] then
            seen[item] = true
            items[#items + 1] = item
        end
    end
    if #items == 0 then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    for _, item in ipairs(items) do
        local title = getText("ContextMenu_TLG_Gasifier")
        if #items > 1 then title = title .. " - " .. item:getDisplayName() end
        addGasifier(playerNum, context, item, title)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)
Events.OnFillWorldObjectContextMenu.Add(Menu.fillWorld)

return Menu
