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
    -- Appended: a restart (-Restart) starts a new Lua state on the same file,
    -- which the launcher deletes before each run.
    if not M.R then M.R = TLGH.Report.new("TLG_harness_mpserver.txt", "TLG multiplayer harness, server", true) end
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
        if item and fullType == "Base.PetrolCan" and (args.petrol or args.fill) then
            local fc = item:getFluidContainer()
            fc:Empty()
            local litres = tonumber(args.litres or args.petrol) or 0
            if litres > 0 then fc:addFluid(args.fill and Fluid.Get(args.fill) or Fluid.Petrol, litres) end
        end
        -- Water as the single-player harness carries it: a bucket filled.
        if item and fullType == "Base.BucketEmpty" and args.water then
            item:getFluidContainer():addFluid(Fluid.Water, tonumber(args.water))
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

-- Stage hours a batch has done (its recipe's stages before the current one,
-- and the current one's hours so far).
local function workDone(rec)
    local done = 0
    for i, st in ipairs(rec.recipe and rec.recipe.params.stages or {}) do
        if i < (rec.stage or 0) then
            done = done + st.hours
        elseif i == rec.stage then
            done = done + (rec.stageDone or 0)
        end
    end
    return done
end

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
        listed = listed and (listed.x .. "," .. listed.y) or "no", takes = table.concat(M.takes, " "),
        t = rec and rec.t or -1, seen = rec and rec.seen or -1, done = rec and workDone(rec) or -1,
        now = TLG.World.now(), inputs = S.text(rec and rec.inputs) })
end

-- The fuel case's site at the Muldraugh Gas2Go (SPHarness.lua's STATION):
-- the first pump with stock, a car with an empty tank three squares off it
-- (as the single-player chain parks it) and two empty generators,
-- connected, put down by the server (IsoGenerator's constructor sends a
-- new one to the clients, BC; addVehicleDebug as ProfessionVehicles.lua
-- calls it on a server).
local STATION = { x0 = 10630, y0 = 10600, x1 = 10690, y1 = 10650 }

local function pumpAt(x, y)
    local sq = getCell():getGridSquare(x, y, 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if o:getPipedFuelAmount() > 0 then return o end
    end
    return nil
end

local function generatorAt(x, y)
    local sq = getCell():getGridSquare(x, y, 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
    end
    return nil
end

local function emptyGenerator(x, y)
    local g = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), getCell():getGridSquare(x, y, 0))
    g:setFuel(0)
    g:getModData().tlg = nil
    g:setConnected(true)
    g:sync()
    g:transmitModData()
    return g
end

function services.setup_fuel(player, args)
    local px, py
    for x = STATION.x0, STATION.x1 do
        for y = STATION.y0, STATION.y1 do
            local p = px == nil and pumpAt(x, y)
            if p and p:getPipedFuelAmount() > 200 then px, py = x, y end
        end
    end
    if not px then
        reply("fuel_site", args, { error = "no pump with stock" })
        return
    end
    local car = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(px + 3, py + 3, 0))
    -- Its key to the requester, who unlocks, drives and starts it with it
    -- (run 157: the menu queued an unlock without one and A never got in).
    local key = car and car:createVehicleKey()
    if key then
        player:getInventory():AddItem(key)
        sendAddItemToContainer(player:getInventory(), key)
    end
    local tank = car and car:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        car:transmitPartModData(tank)
    end
    emptyGenerator(px - 4, py + 6)
    emptyGenerator(px - 6, py + 6)
    reply("fuel_site", args, { px = px, py = py, car = tostring(car and car:getId()), g1x = px - 4, g1y = py + 6,
        g2x = px - 6, g2y = py + 6, units = pumpAt(px, py):getPipedFuelAmount() })
end

-- The conversion case: an empty generator by the spawn point, the tools and
-- parts the single-player loop hands over (SPHarness.lua
-- loop_convert_generator), and the skills and recipe the conversion asks
-- for, set on the server's player as the single-player loop sets them
-- (the conversion's handlers read them there).
function services.setup_conversion(player, args)
    local x, y = S.spot(3)
    emptyGenerator(x, y)
    local inv = player:getInventory()
    for _, t in ipairs({ { "Base.Wrench", 1 }, { "Base.Pliers", 1 }, { "Base.Screwdriver", 1 }, { "Base.RubberHose", 3 },
        { "Base.Screws", 10 }, { "Base.ElectricWire", 3 } }) do
        for _ = 1, t[2] do sendAddItemToContainer(inv, inv:AddItem(t[1])) end
    end
    player:setPerkLevelDebug(Perks.Mechanics, 4)
    player:setPerkLevelDebug(Perks.Electricity, 2)
    player:getKnownRecipes():add("Generator")
    reply("conversion_site", args, { x = x, y = y, mechanics = player:getPerkLevel(Perks.Mechanics),
        electricity = player:getPerkLevel(Perks.Electricity) })
end

-- A generator's consumer profile, fuel and state on the server.
function services.probe_generator(player, args)
    local g = generatorAt(tonumber(args.x), tonumber(args.y))
    local profile = g and TLG.Integration.Generators.profile(g)
    reply("probe_generator", args, { found = tostring(g ~= nil), profile = tostring(profile),
        fuel = g and g:getFuel() or -1, on = tostring(g and g:isActivated()), side = S.text(g and g:getModData().tlg) })
end

-- Litres in a TLG record's fuel table.
local function litres(side)
    local total = 0
    for _, q in pairs(side and side.q or {}) do total = total + q end
    return total
end

-- The server's view of the fuel case: the pump, the car's tank, both
-- generators, the generator item a player carries, and the requester's
-- items `ids` ("id;id"): amounts, and each TLG record as text.
function services.probe_fuel(player, args)
    local out = {}
    local pump = pumpAt(tonumber(args.px), tonumber(args.py))
    out.pumpUnits = pump and pump:getPipedFuelAmount() or -1
    out.pumpSide = S.text(pump and pump:getModData().tlg)
    local car = getVehicleById(tonumber(args.car) or -1)
    local tank = car and car:getPartById("GasTank")
    out.tankL = tank and tank:getContainerContentAmount() or -1
    out.tankSide = S.text(tank and tank:getModData().tlg)
    out.tankRecL = litres(tank and tank:getModData().tlg)
    out.engine = tostring(car and car:isEngineRunning())
    for _, k in ipairs({ "g1", "g2" }) do
        local g = generatorAt(tonumber(args[k .. "x"]), tonumber(args[k .. "y"]))
        out[k .. "Fuel"] = g and g:getFuel() or -1
        out[k .. "On"] = tostring(g and g:isActivated())
        out[k .. "Side"] = S.text(g and g:getModData().tlg)
        out[k .. "RecL"] = litres(g and g:getModData().tlg)
    end
    local carried = player:getInventory():getFirstTypeRecurse("Base.Generator")
    out.genItemSide = S.text(carried and carried:getModData().tlg)
    out.genItemRecL = litres(carried and carried:getModData().tlg)
    local items = {}
    for _, id in ipairs(split(args.ids)) do
        local it = player:getInventory():getItemWithIDRecursiv(tonumber(id))
        local fc = it and it:getFluidContainer()
        items[#items + 1] = id .. "=" .. (fc and string.format("%.4f", fc:getAmount()) or "nil") .. " " .. S.sidecar(it)
        out["recL" .. id] = litres(it and it:getModData().tlg)
    end
    out.items = table.concat(items, " | ")
    reply("probe_fuel", args, out)
end

-- The crate case: a vessel put into the container nearest the spawn point
-- (a crate if one is within reach of the search), as a player finds one.
function services.crate_vessel(player, args)
    local best, bestD, bestType
    for dx = -40, 40 do
        for dy = -40, 40 do
            local sq = getCell():getGridSquare(S.CX + dx, S.CY + dy, 0)
            local objs = sq and sq:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                local c = o:getContainer()
                if c and not instanceof(o, "IsoGenerator") then
                    local d = dx * dx + dy * dy - (c:getType() == "crate" and 1e6 or 0)
                    if bestD == nil or d < bestD then best, bestD, bestType = o, d, c:getType() end
                end
            end
        end
    end
    if not best then
        reply("crated", args, { error = "no container within 40 squares" })
        return
    end
    local c = best:getContainer()
    local item = c:AddItem("TLG.FermenterVessel")
    sendAddItemToContainer(c, item)
    reply("crated", args, { id = tostring(item and item:getID()), type = bestType, x = best:getSquare():getX(),
        y = best:getSquare():getY(), index = best:getObjectIndex() })
end

-- The car conversion case: a car with an empty tank (the conversion drains
-- it first) and its key, the tools and parts the conversion asks for, and
-- the skills and recipe on the server's player (as setup_conversion).
function services.setup_carconv(player, args)
    local x, y = S.CX + 3, S.CY + 3
    local car = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(x, y, 0))
    local tank = car and car:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        car:transmitPartModData(tank)
    end
    local inv = player:getInventory()
    local key = car and car:createVehicleKey()
    if key then sendAddItemToContainer(inv, inv:AddItem(key)) end
    for _, t in ipairs({ { "Base.Wrench", 1 }, { "Base.Pliers", 1 }, { "Base.Screwdriver", 1 }, { "Base.RubberHose", 2 },
        { "Base.EngineParts", 2 }, { "Base.Screws", 6 }, { "Base.ElectricWire", 2 } }) do
        for _ = 1, t[2] do sendAddItemToContainer(inv, inv:AddItem(t[1])) end
    end
    player:setPerkLevelDebug(Perks.Mechanics, 4)
    player:getKnownRecipes():add("Basic Mechanics")
    reply("carconv_site", args, { car = tostring(car and car:getId()), mechanics = player:getPerkLevel(Perks.Mechanics) })
end

-- A car's consumer profile, tank and engine on the server.
function services.probe_vehicle(player, args)
    local car = getVehicleById(tonumber(args.car) or -1)
    local tank = car and car:getPartById("GasTank")
    reply("probe_vehicle", args, { found = tostring(car ~= nil),
        profile = tostring(car and TLG.Integration.Vehicles.profile(car)),
        tankL = tank and tank:getContainerContentAmount() or -1, recL = litres(tank and tank:getModData().tlg),
        side = S.text(tank and tank:getModData().tlg), engine = tostring(car and car:isEngineRunning()) })
end

-- The stills case. A fermenter whose batch is done stands between both
-- stills and the drying column, each a square from the player's square
-- (the spawn point). 97 hours of fermentation do not fit a run, so the
-- batch is run to its end through the domain as the domain tests run it
-- (tests/domain/test_production.lua: July, a day at a step) and kept done
-- from now; the stills load its wash and everything after goes through the
-- mod's requests. The player gets the lime and cans the single-player loop
-- hands over; the wood comes a still's worth at a time (give), as a
-- firebox takes all the wood it has room for.
function services.setup_production(player, args)
    local Machines, Process, World = TLG.Integration.Machines, TLG.Domain.Process, TLG.World
    local env = TLG.Domain.Climate.new({ dayOfYear = 190, hourOfDay = 9 }, {}, nil)
    local rec = Process.new({ id = World.newId("P"), machine = "fermenter_barrel", t = 0 })
    rec = Process.load(rec, "ethanol_ferment", { sugar_eq = 20, water = 100 }).proc
    rec = Process.start(rec, 0).proc
    local t = 0
    while (rec.state == "Processing" or rec.state == "Paused") and t < 24 * 30 do
        t = t + 24
        rec = Process.advance(rec, t, env)
    end
    rec.t = World.now()
    local function put(type, dx, dy)
        local sq = getCell():getGridSquare(S.CX + dx, S.CY + dy, 0)
        return sq:AddWorldInventoryItem(type, 0.5, 0.5, 0)
    end
    local fermenter = put("TLG.FermenterVessel", -1, 0)
    fermenter:getModData()[Machines.SIDECAR] = rec
    rec = Machines.advance(fermenter, rec, World.now(), World.env())
    Machines.write(fermenter, rec)
    Machines.index(fermenter, rec)
    local pot, reflux, dryer = put("TLG.PotStill", 1, 0), put("TLG.RefluxStill", 0, 1), put("TLG.DryingColumn", 0, -1)
    local inv = player:getInventory()
    for _, t2 in ipairs({ { "Base.Quicklime", 2 }, { "Base.JerryCan", 3 } }) do
        for _ = 1, t2[2] do
            local it = inv:AddItem(t2[1])
            if it and it:getFluidContainer() then it:getFluidContainer():Empty() end
            sendAddItemToContainer(inv, it)
        end
    end
    reply("production_site", args, { fermenter = tostring(fermenter:getID()), pot = tostring(pot:getID()),
        reflux = tostring(reflux:getID()), dryer = tostring(dryer:getID()), state = tostring(rec.state),
        outputs = S.text(rec.outputs), hours = t })
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
        R:line("OBS  MPS.sandbox Zombies=%s PopulationMultiplier=%s Start=%s Peak=%s DayLength=%s",
            tostring(SandboxVars.Zombies), tostring(zc.PopulationMultiplier), tostring(zc.PopulationStartMultiplier),
            tostring(zc.PopulationPeakMultiplier), tostring(SandboxVars.DayLength))
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
