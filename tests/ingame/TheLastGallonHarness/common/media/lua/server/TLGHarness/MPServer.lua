-- Multiplayer harness, server side (tools/run-mp-harness.ps1). Logs what the
-- server runs with and every harness message a client sends, relays each
-- message to every client (the broadcast sendServerCommand, as vanilla
-- buildRecipeCode.lua uses it) so the two clients can wait on each other,
-- and answers the requests only the server can serve:
-- - give: items into the sender's inventory as vanilla's server commands do
--   (AddItem, then sendAddItemToContainer; ClientCommands.lua), a petrol
--   can filled first;
-- - spawn: an item put on a square by the server (AddWorldInventoryItem,
--   as ClientCommands.lua does);
-- - probe_item, probe_floor, probe_read: what the server holds;
-- - roll_manual: containers filled from the manual's loot lists as the
--   game fills them (ItemPickerJava.doRollItem), the first manual given.
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
-- sendEquip): run 141's pickup off the floor failed there.
function services.hold(player, args)
    local inv = player:getInventory()
    local item = inv:AddItem(args.item)
    sendAddItemToContainer(inv, item)
    player:setPrimaryHandItem(item)
    player:setSecondaryHandItem(item)
    sendEquip(player)
    reply("held", args, { id = tostring(item and item:getID()) })
end

function services.spawn(player, args)
    local sq = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), 0)
    local item = sq and sq:AddWorldInventoryItem(args.item, 0.5, 0.5, 0)
    reply("spawned", args, { id = tostring(item and item:getID()), item = args.item, x = args.x, y = args.y })
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
