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
require "TLG/UI/Clicked"
require "TLG/UI/Tip"
require "TLG/UI/LoadPreview"
require "TLG/UI/Say"
require "TLG/UI/Repair"

TLG.UI = TLG.UI or {}
TLG.UI.MachineMenu = TLG.UI.MachineMenu or {}
local Menu = TLG.UI.MachineMenu
local Machines, Fmt, Tip = TLG.Integration.Machines, TLG.UI.Format, TLG.UI.Tip
local Picks, Preview = TLG.Integration.Picks, TLG.UI.LoadPreview

local Say = TLG.UI.Say

local function show(text) Say.window(text, 420, 240) end

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

local function num(x) return string.format("%.2f", tonumber(x) or 0) end

-- What a load, a feed or a collect took and gave, from the amounts the
-- authority's reply carries (TLG/Authority/MachineHandlers.lua); nil for a
-- reply that moved nothing (Status, Pause, Resume). The command names the
-- action, since waterL is a mash's water, a leacher's and what the dried
-- ethanol held. The collect line was read in a dialog in RT-SP launch
-- 416; the loads' and the feed's lines are NOT RUN in game.
function Menu.did(reply, kind)
    local c = reply.command
    if c == "machine.loadFerment" then
        return getText("IGUI_TLG_Did_loadFerment", num(reply.sugarKg), num(reply.waterL))
    elseif c == "machine.loadWash" then
        return getText("IGUI_TLG_Did_loadWash", num(reply.washL))
    elseif c == "machine.addFuel" then
        return getText("IGUI_TLG_Did_addFuel", num(reply.addedKg))
    elseif c == "machine.loadDry" then
        return getText("IGUI_TLG_Did_loadDry", num(reply.ethanolL), num(reply.waterL), num(reply.limeKg))
    elseif c == "machine.repair" then
        return getText("IGUI_TLG_Did_repair", string.format("%.0f%%", (tonumber(reply.cond) or 0) * 100))
    elseif c == "machine.collect" and type(reply.collected) == "table" then
        return getText("IGUI_TLG_Did_collect", Fmt.amounts(reply.collected))
    elseif c == "machine.load" then
        if kind == "retort" or kind == "fire_pit" then
            return getText("IGUI_TLG_Did_load_wood", num(reply.woodKg))
        elseif kind == "leacher" then
            return getText("IGUI_TLG_Did_load_leacher", num(reply.ashKg), num(reply.waterL))
        elseif kind == "reactor" then
            local text = getText("IGUI_TLG_Did_load_reactor", num(reply.oilL), num(reply.methanolL), num(reply.lyeKg))
            -- The load that took the retort's last methanol emptied it.
            if (tonumber(reply.charcoal) or 0) > 0 then
                text = text .. " <LINE> " .. getText("IGUI_TLG_Did_charcoal", tostring(reply.charcoal))
            end
            return text
        elseif kind == "settler" then
            return getText("IGUI_TLG_Did_load_settler", num(reply.crudeL), num(reply.washWaterL))
        end
    end
    return nil
end

function Menu.describe(reply)
    local def = reply.machine and TLG.Registry.get("machine", reply.machine)
    local kind = def and def.kind
    local lines = {}
    if reply.aborted then lines[1] = getText(reply.spoiled and "IGUI_TLG_AbortedSpoiled" or "IGUI_TLG_Aborted") end
    lines[#lines + 1] = Menu.did(reply, kind)
    -- Output an abort kept is not a finished batch.
    local state = "IGUI_TLG_MachineState_" .. tostring(reply.state)
    if reply.stoppedEarly and reply.state == "OutputReady" then state = state .. "_stopped" end
    lines[#lines + 1] = kindText(state, kind)
    if reply.pause then lines[#lines + 1] = kindText("IGUI_TLG_Pause_" .. tostring(reply.pause), kind) end
    -- How far the batch is and how long it still takes, as the authority
    -- worked it out (Process.estimate): a client's copy of the record has
    -- no hourly readings to tell the rate from. The stage's share and the
    -- estimate were read in a dialog in RT-SP launch 414; the other lines
    -- are NOT RUN in game.
    local p = type(reply.progress) == "table" and reply.progress or nil
    if reply.stage then
        local name = getText("IGUI_TLG_Stage_" .. reply.stage)
        if p and (tonumber(p.stageHours) or 0) > 0 then
            local share = math.max(0, math.min(1, (tonumber(p.stageDone) or 0) / p.stageHours))
            lines[#lines + 1] = getText("IGUI_TLG_StageDone", name, string.format("%.0f%%", share * 100))
        else
            lines[#lines + 1] = getText("IGUI_TLG_Stage", name)
        end
    end
    if p then
        if reply.state == "Processing" and type(p.etaHours) == "number" then
            local key = p.slowed and "IGUI_TLG_EtaSlowed" or (p.tempBound and "IGUI_TLG_EtaTemp" or "IGUI_TLG_Eta")
            lines[#lines + 1] = getText(key, Fmt.duration(p.etaHours))
            if type(p.woodShortKg) == "number" then
                lines[#lines + 1] = getText("IGUI_TLG_WoodShort", string.format("%.1f", p.woodShortKg))
            end
        elseif type(p.workLeft) == "number" then
            lines[#lines + 1] = getText(reply.state == "Paused" and "IGUI_TLG_WorkLeft" or "IGUI_TLG_WorkLeftNow",
                Fmt.duration(p.workLeft))
        end
        if type(p.maxPauseHours) == "number" and (tonumber(p.pausedFor) or 0) > 0 then
            lines[#lines + 1] = getText("IGUI_TLG_StoodStill", Fmt.duration(p.pausedFor), Fmt.duration(p.maxPauseHours))
        end
    end
    if type(reply.siteC) == "number" and reply.site then
        lines[#lines + 1] = getText(reply.siteNow and "IGUI_TLG_SiteNow" or "IGUI_TLG_SiteToday",
            temperatureText(reply.siteC), getText("IGUI_TLG_Site_" .. reply.site))
    end
    if reply.firebox and reply.firebox > 0 then
        local wood = string.format("%.1f", reply.firebox)
        if def and def.firebox and def.firebox.capacityKg then
            lines[#lines + 1] = getText("IGUI_TLG_FireboxOf", wood, string.format("%.0f", def.firebox.capacityKg))
        else
            lines[#lines + 1] = getText("IGUI_TLG_Firebox", wood)
        end
    end
    -- Status says how worn the machine is and what that costs in yield:
    -- before, the yield fell batch after batch with nothing to read it
    -- from. RT-SP launch 424.
    if reply.command == "machine.status" then lines[#lines + 1] = Fmt.condition(reply.cond) end
    if reply.outputs then
        for _, id in ipairs(TLG.Tables.sortedKeys(reply.outputs)) do
            lines[#lines + 1] = Fmt.componentName(id) .. ": " .. Fmt.amount(id, reply.outputs[id])
        end
    end
    -- What an abort threw away, a wash tank's load (the reactor's glycerin)
    -- and the collect that emptied a machine (its stillage or spent lime).
    if type(reply.discarded) == "table" and not TLG.Tables.isEmpty(reply.discarded) then
        lines[#lines + 1] = getText("IGUI_TLG_Discarded", Fmt.amounts(reply.discarded))
    end
    if reply.aborted and reply.stoppedEarly and reply.state == "OutputReady" then
        lines[#lines + 1] = getText("IGUI_TLG_AbortAgain")
    end
    return table.concat(lines, " <LINE> ")
end

-- What the authority counted of the material a load was short of, by the
-- refusal's code. Only that material: the others are counted up to what
-- the batch would take, not all the player has.
local FOUND = {
    not_enough_sugar_eq = { "sugarAvailableKg", "IGUI_TLG_Found_sugar" },
    not_enough_water = { "waterAvailableL", "IGUI_TLG_Found_water" },
    not_enough_firewood = { "woodAvailableKg", "IGUI_TLG_Found_wood" },
    not_enough_plant_oil = { "oilAvailableL", "IGUI_TLG_Found_oil" },
    not_enough_methanol = { "methanolAvailableL", "IGUI_TLG_Found_methanol" },
    not_enough_lye = { "lyeAvailableKg", "IGUI_TLG_Found_lye" },
    not_enough_wood_ash = { "ashAvailableKg", "IGUI_TLG_Found_ash" },
}

-- The text of a refusal: the machines' own wording, else the shared one,
-- then what was found of the material that was short. NOT RUN in game.
function Menu.failureText(reply)
    local key = "IGUI_TLG_MachineFail_" .. tostring(reply.reason)
    local text = getText(key)
    if text == key then text = Fmt.failure(reply) end
    text = text .. TLG.UI.Repair.missingLines(reply)
    local found = FOUND[tostring(reply.reason)]
    if found and type(reply[found[1]]) == "number" then
        text = text .. " <LINE> " .. getText(found[2], num(reply[found[1]]))
    end
    return text
end

-- What an action did, in one sentence for over the character; nil for a
-- reply that belongs in a window: Status, which is read; an abort and
-- anything thrown away, which the player must not miss; and the reactor's
-- load that also emptied the retort (two things happened). The sentence is
-- what the action took or gave (Menu.did), for a feed with what the firebox
-- now holds, and for an action that moved nothing (Pause, Resume) the
-- machine's state. The rest of the dialog's lines stay in Status.
function Menu.line(reply)
    -- A reply that does not say what was asked is read as a status.
    if reply.command == nil or reply.command == "machine.status" or reply.aborted then return nil end
    if type(reply.discarded) == "table" and not TLG.Tables.isEmpty(reply.discarded) then return nil end
    local def = reply.machine and TLG.Registry.get("machine", reply.machine)
    local kind = def and def.kind
    local did = Menu.did(reply, kind)
    if did == nil then
        local text = kindText("IGUI_TLG_MachineState_" .. tostring(reply.state), kind)
        if reply.pause then text = text .. " " .. kindText("IGUI_TLG_Pause_" .. tostring(reply.pause), kind) end
        return text
    end
    if string.find(did, "<LINE>", 1, true) then return nil end
    if reply.command == "machine.addFuel" and reply.firebox and def and def.firebox and def.firebox.capacityKg then
        did = did .. " " .. getText("IGUI_TLG_FireboxOf", string.format("%.1f", reply.firebox),
            string.format("%.0f", def.firebox.capacityKg))
    end
    return did
end

-- A refusal goes over the character unless it lists what was found; what
-- an action did goes there too (Menu.line), the rest opens a window.
local function onReply(reply)
    if not reply.ok then
        Say.refusal(Menu.failureText(reply))
        return
    end
    local line = Menu.line(reply)
    -- A Resume that leaves the machine waiting is not good news.
    local good = not (reply.command == "machine.resume" and reply.state == "Paused")
    if line then Say.line(line, good) else show(Menu.describe(reply)) end
end

local function req(command, args) TLG.Net.request(command, args, onReply) end

local function firstItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

-- What a can may hold to be topped up with a machine's output: the fuel
-- itself and what its batches carry with it.
local ETHANOL = { main = "ethanol", ethanol = true, water = true }
local BIODIESEL = { main = "biodiesel", biodiesel = true, plant_oil = true, methanol = true, sediment = true,
    water = true }

local function holdsOnly(fc, family)
    local comp, foreign = TLG.Integration.Native.readComposition(fc)
    if foreign > 1e-6 or (comp[family.main] or 0) <= 0 then return false end
    for id in pairs(comp) do
        if id ~= "main" and not family[id] then return false end
    end
    return true
end

local function onlyEthanolAndWater(fc) return holdsOnly(fc, ETHANOL) end

-- Where a machine's fuel goes: an empty fuel can first, else one holding
-- only that fuel's family (ethanol and water; biodiesel and what its
-- batches carry). A can with any other fuel is never used; this used to
-- take the first can with room, petrol can included (found 2026-10-31).
local function fuelCanWithRoom(player, except, family)
    family = family or ETHANOL
    local list = player:getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return it ~= except and not Picks.kept(it) and fc ~= nil and fc:getFreeCapacity() > 0.1
            and TLG.ContainerProfiles.items[it:getFullType()] ~= nil
    end)
    local topUp
    for i = 0, list:size() - 1 do
        local fc = list:get(i):getFluidContainer()
        if fc:isEmpty() then return list:get(i) end
        if topUp == nil and holdsOnly(fc, family) then topUp = list:get(i) end
    end
    return topUp
end

-- The biodiesel chain's machines (D-036): one load each, named after what
-- it takes (ContextMenu_TLG_Load_<kind>).
local CHAIN = { retort = true, fire_pit = true, leacher = true, reactor = true, settler = true }
-- The two that load wood from the inventory, by their recipe.
local WOOD_LOAD = { retort = "methanol_wood_distill", fire_pit = "ash_burn" }

-- A can holding ethanol and water only (still output to dry).
local function hydrousEthanolCan(player)
    local list = player:getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return not Picks.kept(it) and fc ~= nil and not fc:isEmpty() and onlyEthanolAndWater(fc)
    end)
    if list:size() > 0 then return list:get(0) end
    return nil
end

-- Collect into a fuel can: the entry names the can it will fill and its
-- room, or is greyed with the can it needs (TLG/UI/Tip.lua).
local function addCollect(sub, player, ref, labelKey, except, family, world)
    local can = fuelCanWithRoom(player, except, family)
    local o = sub:addOption(getText(labelKey), nil, function()
        req("machine.collect", { target = ref, destination = { kind = "item", id = can:getID() } })
    end)
    if can == nil then
        Tip.grey(o, getText("IGUI_TLG_Tip_NeedCan_" .. family.main), world)
    else
        Tip.set(o, getText("IGUI_TLG_Tip_Into", tostring(can:getDisplayName()),
            string.format("%.1f", can:getFluidContainer():getFreeCapacity())), world)
    end
end

-- The machine's record brought to now without writing it, as Menu.controls
-- reads it (on a multiplayer client: as the server last sent it); an empty
-- table before the machine has one.
local function recordNow(item)
    local rec = item:getModData()[Machines.SIDECAR]
    if type(rec) ~= "table" then return {} end
    if not (isClient and isClient()) then
        local ok, now = pcall(function() return Machines.advance(item, Machines.read(item, false), TLG.World.now(), TLG.World.env()) end)
        if ok and type(now) == "table" then rec = now end
    end
    return rec
end

-- Feed the firebox takes logs, firewood and twigs. With planks carried a
-- second entry burns those too (machine.addFuel with `planks`): they are
-- building material first. Each entry says what it would take.
local function addFirebox(sub, player, rec, def, ref, world)
    local room = def.firebox.capacityKg - (tonumber(rec.firebox) or 0)
    local o = sub:addOption(getText("ContextMenu_TLG_AddFirewood"), nil, function() req("machine.addFuel", { target = ref }) end)
    Preview.attach(o, world, Preview.firebox, player, room, false)
    local planks = player:getInventory():getAllEvalRecurse(function(it)
        return Picks.PLANKS[it:getFullType()] == true and not Picks.kept(it)
    end)
    if planks:size() > 0 then
        o = sub:addOption(getText("ContextMenu_TLG_AddFirewoodPlanks"), nil,
            function() req("machine.addFuel", { target = ref, planks = true }) end)
        Preview.attach(o, world, Preview.firebox, player, room, true)
    end
end

local function addMachine(playerNum, context, item, title, world)
    Say.from(playerNum)
    local player = getSpecificPlayer(playerNum)
    if item == nil or player == nil then return end
    local def = TLG.Registry.need("machine", Machines.machineFor(item))
    local kind = def.kind
    local root = context:addOption(title or getText("ContextMenu_TLG_Machine"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)
    local ref = Machines.refFor(item)
    sub:addOption(getText("ContextMenu_TLG_MachineStatus"), nil, function() req("machine.status", { target = ref }) end)
    if not Machines.isPlaced(item) then
        local o = sub:addOption(getText("ContextMenu_TLG_PlaceFirst"), nil, nil)
        o.notAvailable = true
        return
    end
    -- The record brought to now, read once for the previews and the controls.
    local rec = recordNow(item)
    if kind == "fermenter" then
        local o = sub:addOption(getText("ContextMenu_TLG_LoadFerment"), nil,
            function() req("machine.loadFerment", { target = ref }) end)
        Preview.attach(o, world, Preview.mash, player, rec)
    elseif kind == "still" then
        sub:addOption(getText("ContextMenu_TLG_LoadWash"), nil, function() req("machine.loadWash", { target = ref }) end)
        addFirebox(sub, player, rec, def, ref, world)
        addCollect(sub, player, ref, "ContextMenu_TLG_CollectEthanol", nil, ETHANOL, world)
    elseif kind == "dryer" then
        local src = hydrousEthanolCan(player)
        local d = sub:addOption(getText("ContextMenu_TLG_LoadDry"), nil, function()
            req("machine.loadDry", { target = ref, source = { kind = "item", id = src:getID() } })
        end)
        if src == nil then Tip.grey(d, getText("IGUI_TLG_MachineFail_no_source"), world) end
        addCollect(sub, player, ref, "ContextMenu_TLG_CollectEthanol", src, ETHANOL, world)
    elseif CHAIN[kind] then
        local o = sub:addOption(getText("ContextMenu_TLG_Load_" .. kind), nil, function() req("machine.load", { target = ref }) end)
        if WOOD_LOAD[kind] then Preview.attach(o, world, Preview.woodLoad, player, WOOD_LOAD[kind], rec) end
        if def.firebox then
            addFirebox(sub, player, rec, def, ref, world)
        end
        -- Only the wash tank's biodiesel goes into a can; the others hand
        -- their output to the next machine.
        if kind == "settler" then
            addCollect(sub, player, ref, "ContextMenu_TLG_CollectBiodiesel", nil, BIODIESEL, world)
        end
    end
    -- Repair, for a worn machine: only while it is idle and empty.
    TLG.UI.Repair.add(sub, player, def.id, tonumber(rec.cond), rec.state ~= nil and rec.state ~= "Ready"
        and getText("IGUI_TLG_MachineFail_machine_busy") or nil, world, function() req("machine.repair", { target = ref }) end)
    local c = Menu.controls(item, rec)
    if c.pause then sub:addOption(getText("ContextMenu_TLG_Pause"), nil, function() req("machine.pause", { target = ref }) end) end
    if c.resume then sub:addOption(getText("ContextMenu_TLG_Resume"), nil, function() req("machine.resume", { target = ref }) end) end
    if c.abort then
        -- Abort batch on what an earlier abort kept throws it away: it
        -- asks first, and says so beside the entry.
        local kept = rec.state == "OutputReady" and rec.stoppedEarly == true
        local o = sub:addOption(getText("ContextMenu_TLG_Abort"), nil, function()
            if kept then
                TLG.UI.Confirm.ask(getText("IGUI_TLG_Confirm_AbortAgain"), function() req("machine.abort", { target = ref }) end,
                    playerNum)
            else
                req("machine.abort", { target = ref })
            end
        end)
        if kept then Tip.set(o, getText("IGUI_TLG_Tip_AbortAgain"), world) end
    end
end

function Menu.fill(playerNum, context, items)
    for _, entry in ipairs(items) do
        local item = firstItem(entry)
        if Machines.machineFor(item) then
            addMachine(playerNum, context, item, nil, false)
            return
        end
    end
end

-- The world picker supplies the floor tile instead of the 3D items on it:
-- the machines the click is on are found as the game finds the items of its
-- Grab entry (TLG/UI/Clicked.lua). Until 0.3.0 every machine on the clicked
-- tile was offered, also for a click on the bare ground beside it.
function Menu.fillWorld(playerNum, context, worldobjects, test)
    if getSpecificPlayer(playerNum) == nil then return end
    local items, seenItems = {}, {}
    for _, object in ipairs(TLG.UI.Clicked.worldItems(playerNum, context, worldobjects)) do
        local item = object:getItem()
        if Machines.machineFor(item) and not seenItems[item] then
            seenItems[item] = true
            items[#items + 1] = item
        end
    end
    if #items == 0 then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    for _, item in ipairs(items) do
        local title = getText("ContextMenu_TLG_Machine")
        if #items > 1 then title = title .. " - " .. item:getDisplayName() end
        addMachine(playerNum, context, item, title, true)
    end
end

-- Which of Pause, Resume and Abort batch apply to the machine now, from its
-- record brought to now without writing it (records advance lazily, so the
-- stored state can lag). Run 31 showed all three in every state. A
-- multiplayer client judges on the record as the server last sent it
-- (WorldItemRecords: after each of its actions, a Status and a move). It
-- comes without the hourly readings, and brought forward without them it
-- can disagree with the server: in a cold room warmed by a fire, 7.8 stage
-- hours done where the server had 9.0 (test_machine_sites).
function Menu.controls(item, known)
    local rec = known or recordNow(item)
    local s = rec.state
    return {
        pause = s == "Processing",
        resume = s == "Paused" and rec.manualPause == true,
        abort = s == "Processing" or s == "Paused" or s == "InputsReserved" or (s == "Faulted" and rec.pause == "batch_spoiled")
            or (s == "OutputReady" and rec.stoppedEarly == true),
    }
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.fill)
Events.OnFillWorldObjectContextMenu.Add(Menu.fillWorld)

return Menu
