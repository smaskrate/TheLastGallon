-- Multiplayer harness, server side (tools/run-mp-harness.ps1). Logs what the
-- server runs with and every harness message a client sends, relays each
-- message to every client (the broadcast sendServerCommand, as vanilla
-- buildRecipeCode.lua uses it) so the two clients can wait on each other,
-- and answers the requests only the server can serve:
-- - give: items into the sender's inventory as vanilla's server commands do
--   (AddItem, then sendAddItemToContainer; ClientCommands.lua), a petrol
--   can filled first;
-- - spawn: an item put on a square by the server (AddWorldInventoryItem,
--   as ClientCommands.lua does), a machine with a running batch if asked;
-- - probe_item, probe_floor, probe_read, probe_vessel: what the server holds;
-- - roll_manual: containers filled from the manual's loot lists as the
--   game fills them (ItemPickerJava.doRollItem), the first manual given.
-- It also logs every take of a machine off the floor the mod makes on the
-- server (Machines.takeOnServer, D-030) with its result.
-- Results: <cachedir>/Lua/TLG_harness_mpserver.txt.
require "TLGHarness/Report"
require "TLGHarness/MPShared"

if not isServer() then return end

TLGH = TLGH or {}
TLGH.MPServer = TLGH.MPServer or {}
local M = TLGH.MPServer
local S = TLGH.MPShared

local function report()
    if not M.R then M.R = TLGH.Report.new("TLG_harness_mpserver.txt", "TLG multiplayer harness, server") end
    return M.R
end

local function describe(args)
    if type(args) ~= "table" then return tostring(args) end
    local keys = {}
    for k in pairs(args) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(args[k]) end
    return table.concat(parts, " ")
end

local function reply(command, request, fields)
    fields.role, fields.tag = request.role, request.tag
    report():line("OBS  MPS.reply %s %s", command, describe(fields))
    sendServerCommand("TLGH", command, fields)
end

local function split(s)
    local out = {}
    for part in string.gmatch(s or "", "[^;]+") do out[#out + 1] = part end
    return out
end

local services = {}

function services.give(player, args)
    local ids, inv = {}, player:getInventory()
    for _, fullType in ipairs(split(args.items)) do
        local item = inv:AddItem(fullType)
        if item and fullType == "Base.PetrolCan" and args.petrol then
            local fc = item:getFluidContainer()
            fc:Empty()
            fc:addFluid(Fluid.Petrol, tonumber(args.petrol))
        end
        sendAddItemToContainer(inv, item)
        ids[#ids + 1] = fullType .. "=" .. tostring(item and item:getID())
    end
    reply("given", args, { ids = table.concat(ids, ";") })
end

-- A heavy item put straight into both hands, as ISEquipHeavyItem.complete
-- does it on the server (AddItem, sendAddItemToContainer, both hands,
-- sendEquip): the harness's fallback when the vessel does not come off the
-- floor (the game's own way fails on a server, runs 141-145).
function services.hold(player, args)
    local inv = player:getInventory()
    local item = inv:AddItem(args.item)
    sendAddItemToContainer(inv, item)
    player:setPrimaryHandItem(item)
    player:setSecondaryHandItem(item)
    sendEquip(player)
    reply("held", args, { id = tostring(item and item:getID()) })
end

-- A machine's batch running, as loading it and starting it leave the record
-- (TLG.Domain.Process: ethanol_ferment from 6 sugar and 30 water), written as
-- the mod's machine requests write it (Machines.advance, write, index).
local function startBatch(item)
    local Machines, Process, World = TLG.Integration.Machines, TLG.Domain.Process, TLG.World
    local now = World.now()
    local rec = Process.new({ id = World.newId("P"), machine = Machines.machineFor(item), t = now })
    rec = Process.load(rec, "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc
    rec = Process.start(rec, now).proc
    rec = Machines.advance(item, rec, now, World.env())
    Machines.write(item, rec)
    Machines.index(item, rec)
    return rec
end

function services.spawn(player, args)
    local sq = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), 0)
    local item = sq and sq:AddWorldInventoryItem(args.item, 0.5, 0.5, 0)
    local rec = item and args.batch and startBatch(item)
    reply("spawned", args, { id = tostring(item and item:getID()), item = args.item, x = args.x, y = args.y,
        batch = tostring(rec and rec.state) })
end

-- The machine takes the mod made on the server, "user:result" in order.
M.takes = M.takes or {}

-- Where the server holds the vessel `id` (on the floor around the spawn
-- point, in an online player's inventory, in both hands), how many vessels
-- lie there or are carried in all, its batch, the hourly reading's entry for
-- it and the takes so far.
function services.probe_vessel(player, args)
    local id, places, item, count = tonumber(args.id), {}, nil, 0
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            local sq = getCell():getGridSquare(x, y, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == "TLG.FermenterVessel" then count = count + 1 end
                if it and it:getID() == id then
                    places[#places + 1] = "floor " .. x .. "," .. y
                    item = it
                end
            end
        end
    end
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        count = count + p:getInventory():getCountTypeRecurse("TLG.FermenterVessel")
        local it = p:getInventory():getItemWithIDRecursiv(id)
        if it then
            local both = p:getPrimaryHandItem() == it and p:getSecondaryHandItem() == it
            places[#places + 1] = "inventory " .. p:getUsername() .. (both and " both hands" or "")
            item = it
        end
    end
    local rec = item and item:getModData().tlgProc
    local sites = TLG.World.get().machineSites or {}
    local listed = rec and rec.id and sites[rec.id]
    reply("probe_vessel", args, { where = #places > 0 and table.concat(places, "; ") or "nowhere", vessels = count,
        state = tostring(rec and rec.state or "none"), pause = tostring(rec and rec.pause or "none"),
        site = rec and rec.site and rec.site.x and (rec.site.x .. "," .. rec.site.y) or "none",
        listed = listed and (listed.x .. "," .. listed.y) or "no", takes = table.concat(M.takes, " ") })
end

-- The take a second player's action makes when it completes after the
-- first's has taken the vessel: ISEquipHeavyItem:new(player, vessel):complete()
-- run here as the server runs a completed action (NetTimedAction.perform
-- calls complete), for the online player who does not hold the vessel.
function services.try_take(player, args)
    local id, list, holder, taker, item = tonumber(args.id), getOnlinePlayers(), nil, nil, nil
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        local it = p:getInventory():getItemWithIDRecursiv(id)
        if it then
            holder, item = p, it
        elseif taker == nil then
            taker = p
        end
    end
    local ok, r = false, "no holder or no other player"
    if holder and taker then
        ok, r = pcall(function() return ISEquipHeavyItem:new(taker, item):complete() end)
    end
    local keeps = holder ~= nil and holder:getInventory():getItemWithIDRecursiv(id) ~= nil
        and holder:getPrimaryHandItem() == item and holder:getSecondaryHandItem() == item
    local has = taker ~= nil and taker:getInventory():getItemWithIDRecursiv(id) ~= nil
    reply("try_take", args, { holder = tostring(holder and holder:getUsername()),
        taker = tostring(taker and taker:getUsername()), result = ok and tostring(r) or ("error " .. tostring(r)),
        holderKeeps = tostring(keeps), takerHas = tostring(has), takes = table.concat(M.takes, " ") })
end

-- Wraps the mod's server-side take (looked up at call time by its hook on
-- ISEquipHeavyItem.complete) to log each call and what it returned.
local function watchTakes()
    local Machines = TLG and TLG.Integration and TLG.Integration.Machines
    if M.takesWatched or not (Machines and Machines.takeOnServer) then return end
    M.takesWatched = true
    local orig = Machines.takeOnServer
    Machines.takeOnServer = function(character, item)
        local ok, r = pcall(orig, character, item)
        local user = tostring(character and character:getUsername())
        local result = ok and tostring(r) or "error"
        M.takes[#M.takes + 1] = user .. ":" .. result
        report():line("OBS  MPS.take of %s by %s: %s%s", tostring(item and item:getID()), user, result,
            ok and "" or (" " .. tostring(r)))
        if not ok then error(r, 0) end
        return r
    end
end

function services.probe_item(player, args)
    local item = player:getInventory():getItemWithID(tonumber(args.id))
    reply("probe_item", args, { found = tostring(item ~= nil), sidecar = S.sidecar(item),
        fluid = item and item:getFluidContainer() and string.format("%.4f", item:getFluidContainer():getAmount()) or "nil" })
end

function services.probe_floor(player, args)
    reply("probe_floor", args, { floor = S.floorAround() })
end

function services.probe_read(player, args)
    reply("probe_read", args, { read = tostring(player:isPrintMediaRead(args.media)) })
end

function services.roll_manual(player, args)
    local id, fills, found, kept = TLG.Integration.Manual.ITEM, 0, 0, nil
    local lists = { { "gasstorage", "other", "GasStorageMechanics" }, { "garagestorage", "crate", "CrateMechanics" },
        { "toolstore", "shelves", "ToolStoreBooks" }, { "library", "shelves", "LibraryMagazines" } }
    local cont = ItemContainer.new("crate", player:getCurrentSquare(), player)
    for _, l in ipairs(lists) do
        local dist = ItemPickerJava.getItemContainer(l[1], l[2], l[3], false)
        for _ = 1, dist and tonumber(args.fills) or 0 do
            cont:removeAllItems()
            ItemPickerJava.doRollItem(dist, cont, 1, player, true, nil)
            fills = fills + 1
            local got = cont:getItemsFromFullType(id)
            if got and got:size() > 0 then
                found = found + got:size()
                if not kept then
                    kept = got:get(0)
                    cont:Remove(kept)
                end
            end
        end
    end
    if kept then
        player:getInventory():AddItem(kept)
        sendAddItemToContainer(player:getInventory(), kept)
    end
    reply("rolled", args, { fills = fills, manuals = found, id = tostring(kept and kept:getID()),
        printMedia = tostring(kept and kept:getModData().printMedia ~= nil) })
end

Events.OnServerStarted.Add(function()
    local ok, err = pcall(function()
        local R = report()
        local zc = SandboxVars.ZombieConfig or {}
        R:line("OBS  MPS.sandbox Zombies=%s PopulationMultiplier=%s Start=%s Peak=%s", tostring(SandboxVars.Zombies),
            tostring(zc.PopulationMultiplier), tostring(zc.PopulationStartMultiplier), tostring(zc.PopulationPeakMultiplier))
        -- No fog, held off as vanilla's tutorial does (Tutorial1.lua): run
        -- 138's morning fog again. The clients take the server's climate.
        local cm = getClimateManager()
        local fog = cm:getClimateFloat(5)
        local before = fog:getFinalValue()
        if cm:getWeatherPeriod():isRunning() then cm:stopWeatherAndThunder() end
        fog:setEnableOverride(true)
        fog:setOverride(0, 1)
        R:line("OBS  MPS.fog intensity %.2f when the override was set", before)
        watchTakes()
        R:line("OBS  MPS.takes watched=%s", tostring(M.takesWatched == true))
    end)
    if not ok then print("[TLGH] mp server report failed: " .. tostring(err)) end
end)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "TLGH" then return end
    local ok, err = pcall(function()
        report():line("OBS  MPS.message from %s: %s %s", tostring(player and player:getUsername()), tostring(command),
            describe(args))
        if services[command] then
            services[command](player, args)
        else
            sendServerCommand("TLGH", command, args)
        end
    end)
    if not ok then report():line("STEPERR MPS.%s :: %s", tostring(command), tostring(err)) end
end)
