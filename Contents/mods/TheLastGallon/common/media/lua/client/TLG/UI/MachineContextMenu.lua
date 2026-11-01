-- Context menu for TLG machine items (fermenter, stills, drying column).
-- All actions are authority requests; results are shown as text. Used RT-SP
-- 2026-10-31 (run 12) on the fermenter, reflux still and drying column:
-- Load mash, Feed the firebox, Load wash, Collect ethanol, Dry ethanol with
-- quicklime, Status; on the pot still in run 28 (Feed the firebox, Load wash
-- twice, Collect ethanol, Status); Pause, Resume and Abort batch on fermenters
-- and the drying column in run 31, where Abort discarded the batch unlisted.
-- Abort now keeps what the batch made and lists what it throws away, and
-- Pause, Resume and Abort are offered only where they apply (run 33).
require "TLG/Client/Net"
require "TLG/Integration/Machines"
require "TLG/UI/Format"

TLG.UI = TLG.UI or {}
TLG.UI.MachineMenu = TLG.UI.MachineMenu or {}
local Menu = TLG.UI.MachineMenu
local Machines, Fmt = TLG.Integration.Machines, TLG.UI.Format

local function show(text)
    local w, h = 420, 240
    local modal = ISModalRichText:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
end

-- In the player's units (vanilla's weather radio formats the same way,
-- SRC server/radio/ISWeatherChannel.lua:209).
local function temperatureText(c)
    local ok, s = pcall(function() return Temperature.getTemperatureString(c) end)
    if ok and type(s) == "string" then return s end
    return string.format("%.0f C", c)
end

-- The machine kind's own wording where it has one (a fermenter's finished
-- wash waits for a still, a still's ethanol for a can), else the shared one.
local function kindText(key, kind)
    local own = key .. "_" .. tostring(kind)
    local text = getText(own)
    if text ~= own then return text end
    return getText(key)
end

-- "Water 29.67, Stillage 0.40": what an abort threw away.
local function amounts(t)
    local parts = {}
    for _, id in ipairs(TLG.Tables.sortedKeys(t)) do
        parts[#parts + 1] = Fmt.componentName(id) .. " " .. string.format("%.2f", t[id])
    end
    return table.concat(parts, ", ")
end

function Menu.describe(reply)
    local def = reply.machine and TLG.Registry.get("machine", reply.machine)
    local kind = def and def.kind
    local lines = {}
    if reply.aborted then lines[1] = getText(reply.spoiled and "IGUI_TLG_AbortedSpoiled" or "IGUI_TLG_Aborted") end
    -- Output an abort kept is not a finished batch.
    local state = "IGUI_TLG_MachineState_" .. tostring(reply.state)
    if reply.stoppedEarly and reply.state == "OutputReady" then state = state .. "_stopped" end
    lines[#lines + 1] = kindText(state, kind)
    if reply.pause then lines[#lines + 1] = kindText("IGUI_TLG_Pause_" .. tostring(reply.pause), kind) end
    if reply.stage then lines[#lines + 1] = getText("IGUI_TLG_Stage", getText("IGUI_TLG_Stage_" .. reply.stage)) end
    if type(reply.siteC) == "number" and reply.site then
        lines[#lines + 1] = getText(reply.siteNow and "IGUI_TLG_SiteNow" or "IGUI_TLG_SiteToday",
            temperatureText(reply.siteC), getText("IGUI_TLG_Site_" .. reply.site))
    end
    if reply.firebox and reply.firebox > 0 then
        lines[#lines + 1] = getText("IGUI_TLG_Firebox", string.format("%.1f", reply.firebox))
    end
    if reply.outputs then
        for _, id in ipairs(TLG.Tables.sortedKeys(reply.outputs)) do
            lines[#lines + 1] = Fmt.componentName(id) .. ": " .. string.format("%.2f", reply.outputs[id])
        end
    end
    if reply.aborted and reply.discarded and not TLG.Tables.isEmpty(reply.discarded) then
        lines[#lines + 1] = getText("IGUI_TLG_Discarded", amounts(reply.discarded))
    end
    if reply.aborted and reply.stoppedEarly and reply.state == "OutputReady" then
        lines[#lines + 1] = getText("IGUI_TLG_AbortAgain")
    end
    return table.concat(lines, " <LINE> ")
end

local function onReply(reply)
    if not reply.ok then
        show(getText("IGUI_TLG_MachineFail_" .. tostring(reply.reason)) ~= ("IGUI_TLG_MachineFail_" .. tostring(reply.reason))
            and getText("IGUI_TLG_MachineFail_" .. tostring(reply.reason)) or Fmt.failure(reply))
        return
    end
    show(Menu.describe(reply))
end

local function req(command, args) TLG.Net.request(command, args, onReply) end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

local function onlyEthanolAndWater(fc)
    local comp, foreign = TLG.Integration.Native.readComposition(fc)
    if foreign > 1e-6 or (comp.ethanol or 0) <= 0 then return false end
    for id in pairs(comp) do
        if id ~= "ethanol" and id ~= "water" then return false end
    end
    return true
end

-- Where collected ethanol goes: an empty fuel can first, else one holding
-- only ethanol and water. A can with any other fuel is never used; this used
-- to take the first can with room, petrol can included (found 2026-10-31).
local function fuelCanWithRoom(player, except)
    local list = player:getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return it ~= except and fc ~= nil and fc:getFreeCapacity() > 0.1 and TLG.ContainerProfiles.items[it:getFullType()] ~= nil
    end)
    local topUp
    for i = 0, list:size() - 1 do
        local fc = list:get(i):getFluidContainer()
        if fc:isEmpty() then return list:get(i) end
        if topUp == nil and onlyEthanolAndWater(fc) then topUp = list:get(i) end
    end
    return topUp
end

-- A can holding ethanol and water only (still output to dry).
local function hydrousEthanolCan(player)
    local list = player:getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and onlyEthanolAndWater(fc)
    end)
    if list:size() > 0 then return list:get(0) end
    return nil
end

function Menu.fill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local item
    for _, entry in ipairs(items) do
        local it = firstItem(entry)
        if Machines.machineFor(it) then item = it; break end
    end
    if item == nil or player == nil then return end
    local kind = TLG.Registry.need("machine", Machines.machineFor(item)).kind
    local root = context:addOption(getText("ContextMenu_TLG_Machine"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local ref = Machines.refFor(item)
    sub:addOption(getText("ContextMenu_TLG_MachineStatus"), nil, function() req("machine.status", { target = ref }) end)
    if not Machines.isPlaced(item) then
        local o = sub:addOption(getText("ContextMenu_TLG_PlaceFirst"), nil, nil)
        o.notAvailable = true
        return
    end
    if kind == "fermenter" then
        sub:addOption(getText("ContextMenu_TLG_LoadFerment"), nil,
            function() req("machine.loadFerment", { target = ref }) end)
    elseif kind == "still" then
        sub:addOption(getText("ContextMenu_TLG_LoadWash"), nil, function() req("machine.loadWash", { target = ref }) end)
        sub:addOption(getText("ContextMenu_TLG_AddFirewood"), nil, function() req("machine.addFuel", { target = ref }) end)
        local can = fuelCanWithRoom(player)
        local o = sub:addOption(getText("ContextMenu_TLG_CollectEthanol"), nil, function()
            req("machine.collect", { target = ref, destination = { kind = "item", id = can:getID() } })
        end)
        if can == nil then o.notAvailable = true end
    elseif kind == "dryer" then
        local src = hydrousEthanolCan(player)
        local d = sub:addOption(getText("ContextMenu_TLG_LoadDry"), nil, function()
            req("machine.loadDry", { target = ref, source = { kind = "item", id = src:getID() } })
        end)
        if src == nil then d.notAvailable = true end
        local can = fuelCanWithRoom(player, src)
        local o = sub:addOption(getText("ContextMenu_TLG_CollectEthanol"), nil, function()
            req("machine.collect", { target = ref, destination = { kind = "item", id = can:getID() } })
        end)
        if can == nil then o.notAvailable = true end
    end
    local c = Menu.controls(item)
    if c.pause then sub:addOption(getText("ContextMenu_TLG_Pause"), nil, function() req("machine.pause", { target = ref }) end) end
    if c.resume then sub:addOption(getText("ContextMenu_TLG_Resume"), nil, function() req("machine.resume", { target = ref }) end) end
    if c.abort then sub:addOption(getText("ContextMenu_TLG_Abort"), nil, function() req("machine.abort", { target = ref }) end) end
end

-- Which of Pause, Resume and Abort batch apply to the machine now, from its
-- record brought to now without writing it (records advance lazily, so the
-- stored state can lag). Run 31 showed all three in every state.
function Menu.controls(item)
    local rec = item:getModData()[Machines.SIDECAR]
    if type(rec) ~= "table" then return {} end
    local ok, now = pcall(function() return Machines.advance(item, Machines.read(item, false), TLG.World.now(), TLG.World.env()) end)
    if ok and type(now) == "table" then rec = now end
    local s = rec.state
    return {
        pause = s == "Processing",
        resume = s == "Paused" and rec.manualPause == true,
        abort = s == "Processing" or s == "Paused" or s == "InputsReserved" or (s == "Faulted" and rec.pause == "batch_spoiled")
            or (s == "OutputReady" and rec.stoppedEarly == true),
    }
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)

return Menu
