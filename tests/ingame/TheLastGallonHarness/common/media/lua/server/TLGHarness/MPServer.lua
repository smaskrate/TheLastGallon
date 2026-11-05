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
-- server (Machines.takeOnServer, D-030) with its result, and holds the
-- fixtures and watches of the effects and timers cases (below).
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
    local sites = TLG.World.server().machineSites or {}
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

------------------------------------------------------------------------------
-- The effects case (-Only effects; D-031 on a server). The server applies the
-- engine effects: Vehicles.lua's pass every game minute, and a generator's
-- wear charged in ISAddFuel.new when the server builds a client's refuel.
-- The fixtures are the single-player mode's (SPHarness.lua RT.E): the tank's
-- record aged in place, an unfit blend written over it, the stall option, the
-- wear rates scaled. A watch every game minute, registered after the mod's
-- pass, logs the car's engine and follows each run of it: its own power, the
-- target the fuel gives, how many minute passes it took to get there, whether
-- it strayed, quality and loudness, the stop and the power coming back. The
-- litres the mod charges wear for are counted at V.applyWear, as
-- RT.E.wrapWear counts them, and its cost per call is timed.
------------------------------------------------------------------------------
local EF = M.EF or {}
M.EF = EF

local function efCar() return EF.car and getVehicleById(EF.car) or nil end

-- The car's engine as the server holds it.
local function engineFacts(v)
    local V = TLG.Integration.Vehicles
    local engine = v and v:getPartById("Engine")
    local tank = v and v:getPartById("GasTank")
    local md = engine and engine:getModData()
    return { power = v and v:getEnginePower() or -1, quality = v and v:getEngineQuality() or -1,
        loudness = v and v:getEngineLoudness() or -1, running = tostring(v ~= nil and v:isEngineRunning()),
        state = tostring(v and v:getEngineState()), cond = engine and engine:getCondition() or -1,
        tankL = tank and tank:getContainerContentAmount() or -1,
        powerState = S.text(md and md[V.POWER_KEY]), wearCarry = S.text(md and md[V.WEAR_KEY]) }
end

local function stallsOption(on)
    SandboxVars.TheLastGallon = SandboxVars.TheLastGallon or {}
    SandboxVars.TheLastGallon.VehicleStalls = on
    report():line("OBS  MPS.effects sandbox VehicleStalls=%s", tostring(SandboxVars.TheLastGallon.VehicleStalls))
end

-- The fuel as the engine sees it, as text and fields.
local function evaluation(e)
    return { compatible = tostring(e and e.compatible), grade = tostring(e and e.grade),
        powerFactor = e and e.powerFactor or -1, wearFactor = e and e.wearFactor or -1,
        startFactor = e and e.startFactor or -1, reasons = e and e.reasons and table.concat(e.reasons, ",") or "" }
end

-- One game minute of the car, after the mod's pass.
local function efMinute()
    local ok, err = pcall(function()
        local v = efCar()
        if v == nil then return end
        local V, EE = TLG.Integration.Vehicles, TLG.Domain.EngineEffects
        EF.minute = (EF.minute or 0) + 1
        local f = engineFacts(v)
        local running = v:isEngineRunning()
        local run = EF.run
        if running and (run == nil or run.stoppedAt ~= nil) then
            local st = v:getPartById("Engine"):getModData()[V.POWER_KEY]
            local e = V.evaluate(v)
            local factor = (e ~= nil and e.grade ~= "empty") and e.powerFactor or 1
            local base = (st and st.base) or f.power
            run = { from = EF.minute, base = base, factor = factor, target = EE.targetPower(base, factor) }
            EF.run = run
            EF.runs = (EF.runs or 0) + 1
            report():line("OBS  MPS.effects run %d seen at minute %d: own power %d, factor %.6f, target %d",
                EF.runs, EF.minute, base, factor, run.target)
        end
        if run then
            if running then
                if run.reachedAt == nil and f.power == run.target then run.reachedAt = EF.minute - run.from end
                if run.reachedAt ~= nil and f.power ~= run.target and run.strayed == nil then
                    run.strayed = string.format("%d at minute %d", f.power, EF.minute - run.from)
                end
            elseif run.stoppedAt == nil then
                run.stoppedAt = EF.minute
            end
            if run.stoppedAt ~= nil and run.backAt == nil and f.power == run.base and f.powerState == "nil" then
                run.backAt = EF.minute - run.stoppedAt
            end
        end
        if EF.q0 ~= nil and (f.quality ~= EF.q0 or f.loudness ~= EF.l0) and EF.featuresChanged == nil then
            EF.featuresChanged = string.format("quality %d loudness %d at minute %d", f.quality, f.loudness, EF.minute)
        end
        -- The log: every minute while it runs and the minute it stops.
        if running or (run and run.stoppedAt == EF.minute) or EF.minute % 10 == 0 then
            report():line("OBS  MPS.effects minute %d: running %s %s power %d quality %d loudness %d engine %d tank %.4f"
                .. " power state %s wear carry %s", EF.minute, f.running, f.state, f.power, f.quality, f.loudness,
                f.cond, f.tankL, f.powerState, f.wearCarry)
        end
    end)
    if not ok then report():line("STEPERR MPS.effects_minute :: %s", tostring(err)) end
end

local function efWrap()
    local V, EE = TLG.Integration.Vehicles, TLG.Domain.EngineEffects
    if not EF.wearOrig then
        EF.wearOrig = V.applyWear
        V.applyWear = function(vehicle, e)
            local id = vehicle:getId()
            local last = V.lastTank[id]
            local tank = V.tank(vehicle)
            local now = tank and tank:getContainerContentAmount()
            local r = EF.wearOrig(vehicle, e)
            if EF.count and last and now and now < last and e and e.grade ~= "empty" then
                local K = EF.count
                K.calls, K.litres = K.calls + 1, K.litres + (last - now)
                K.accrual = K.accrual + (last - now) * math.max(0, e.wearFactor - 1)
                    * EE.vehicleWearPerLitre(SandboxVars and SandboxVars.CarGasConsumption)
            end
            return r
        end
    end
    if not EF.effectsOrig then
        EF.effectsOrig = V.applyEffects
        EF.cost = { n = 0, ms = 0, max = 0 }
        V.applyEffects = function(vehicle, rng)
            local t0 = getTimestampMs()
            local r = EF.effectsOrig(vehicle, rng)
            local ms = getTimestampMs() - t0
            EF.cost.n, EF.cost.ms = EF.cost.n + 1, EF.cost.ms + ms
            if ms > EF.cost.max then EF.cost.max = ms end
            return r
        end
    end
    if not EF.watching then
        Events.EveryOneMinute.Add(efMinute)
        EF.watching = true
    end
end

local function efRestore()
    local V, EE, G = TLG.Integration.Vehicles, TLG.Domain.EngineEffects, TLG.Integration.Generators
    if EF.wearOrig then V.applyWear, EF.wearOrig = EF.wearOrig, nil end
    if EF.effectsOrig then V.applyEffects, EF.effectsOrig = EF.effectsOrig, nil end
    if EF.vehicleRate then EE.VEHICLE_WEAR_PER_LITRE, EF.vehicleRate = EF.vehicleRate, nil end
    if EF.genRate then EE.generatorWearPerLitre, EF.genRate = EF.genRate, nil end
    if EF.chargeOrig then G.chargeWear, EF.chargeOrig = EF.chargeOrig, nil end
    if EF.watching then
        Events.EveryOneMinute.Remove(efMinute)
        EF.watching = false
    end
    stallsOption(true)
end

-- The site: a car three squares off the spawn point with an empty tank, its
-- key to the requester (as setup_carconv), and an empty generator, connected.
function services.setup_effects(player, args)
    local car = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(S.CX + 3, S.CY + 3, 0))
    local tank = car and car:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        car:transmitPartModData(tank)
    end
    local inv = player:getInventory()
    local key = car and car:createVehicleKey()
    if key then sendAddItemToContainer(inv, inv:AddItem(key)) end
    local gx, gy = S.spot(3)
    local g = emptyGenerator(gx, gy)
    pcall(function() g:setCondition(100) end)
    EF.car, EF.gx, EF.gy = car and car:getId(), gx, gy
    local f = engineFacts(car)
    reply("effects_site", args, { car = tostring(EF.car), g1x = gx, g1y = gy, power = f.power, quality = f.quality,
        loudness = f.loudness, cond = f.cond, genCond = g and g:getCondition() or -1,
        oneIn = tostring(g and TLG.Integration.Generators.lowerChanceOneIn(g)) })
end

-- The tank's record aged in place to `deg` (fixture), then the fuel as the
-- engine sees it.
function services.effects_age(player, args)
    local V = TLG.Integration.Vehicles
    local v = efCar()
    local rec = V.read(v, true)
    for id, _ in pairs(rec.deg) do rec.deg[id] = tonumber(args.deg) end
    V.writeSidecar(v, rec)
    local out = evaluation(V.evaluate(v))
    out.tank = S.text(v:getPartById("GasTank"):getModData().tlg)
    out.tankL = v:getPartById("GasTank"):getContainerContentAmount()
    reply("effects_age", args, out)
end

-- The tank's litres made a blend no stock engine takes (fixture): petrol and
-- ethanol 5 to 3, as the single-player mode's second leg poured them.
function services.effects_blend(player, args)
    local V = TLG.Integration.Vehicles
    local v = efCar()
    local rec = V.read(v, true)
    local total = 0
    for _, q in pairs(rec.q) do total = total + q end
    rec.q = { gasoline = total * 5 / 8, ethanol = total * 3 / 8 }
    rec.deg = { gasoline = rec.deg.gasoline or 0, ethanol = 0 }
    rec.rev = (rec.rev or 0) + 1
    V.writeSidecar(v, rec)
    local out = evaluation(V.evaluate(v))
    out.tank = S.text(v:getPartById("GasTank"):getModData().tlg)
    reply("effects_blend", args, out)
end

-- A leg begins: the stall option, the car wear rate times `scale` (fixture),
-- the counters reset, the engine's quality, loudness, condition and wear
-- carried as they are now (the engine off).
function services.effects_arm(player, args)
    local V, EE = TLG.Integration.Vehicles, TLG.Domain.EngineEffects
    local v = efCar()
    stallsOption(args.stalls == "true")
    EF.vehicleRate = EF.vehicleRate or EE.VEHICLE_WEAR_PER_LITRE
    EE.VEHICLE_WEAR_PER_LITRE = EF.vehicleRate * (tonumber(args.scale) or 1)
    efWrap()
    local f = engineFacts(v)
    local w = v:getPartById("Engine"):getModData()[V.WEAR_KEY]
    EF.q0, EF.l0, EF.cond0, EF.carry0 = f.quality, f.loudness, f.cond, type(w) == "number" and w or 0
    EF.count = { calls = 0, litres = 0, accrual = 0 }
    EF.run, EF.featuresChanged = nil, nil
    report():line("OBS  MPS.effects armed: car wear %.4f per litre at factor 2 (x%s fixture); engine %d, carry %.6f; "
        .. "quality %d loudness %d power %d", EE.VEHICLE_WEAR_PER_LITRE, tostring(args.scale), f.cond, EF.carry0,
        f.quality, f.loudness, f.power)
    f.rate = EE.VEHICLE_WEAR_PER_LITRE
    reply("effects_arm", args, f)
end

-- The stall option switched with the engine as it is.
function services.effects_stalls(player, args)
    stallsOption(args.on == "true")
    EF.stallsAt = EF.minute or 0
    reply("effects_stalls", args, { on = tostring(SandboxVars.TheLastGallon.VehicleStalls), minute = EF.stallsAt })
end

-- The engine now and the current run, the wear counted since the leg began.
function services.effects_probe(player, args)
    local V = TLG.Integration.Vehicles
    local v = efCar()
    local f = engineFacts(v)
    local run = EF.run or {}
    local K = EF.count or { calls = 0, litres = 0, accrual = 0 }
    local w = v and v:getPartById("Engine"):getModData()[V.WEAR_KEY]
    f.minute, f.runs = EF.minute or 0, EF.runs or 0
    f.base, f.factor, f.target = run.base or -1, run.factor or -1, run.target or -1
    f.reachedAt, f.strayed = run.reachedAt or -1, run.strayed or ""
    f.stoppedAfter = run.stoppedAt and run.stoppedAt - (EF.stallsAt or 0) or -1
    f.ranFor = run.from and ((run.stoppedAt or EF.minute) - run.from) or -1
    f.backAt = run.backAt or -1
    f.featuresChanged = EF.featuresChanged or ""
    f.q0, f.l0, f.cond0, f.carry0 = EF.q0 or -1, EF.l0 or -1, EF.cond0 or -1, EF.carry0 or 0
    f.carry = type(w) == "number" and w or 0
    f.calls, f.litres, f.accrual = K.calls, K.litres, K.accrual
    f.costN, f.costMs, f.costMax = EF.cost and EF.cost.n or 0, EF.cost and EF.cost.ms or 0, EF.cost and EF.cost.max or 0
    reply("effects_probe", args, f)
end

-- The generator's record aged in place to `deg` (fixture), then switched on
-- by the server as the single-player mode switches it (fixture: the start
-- gate's roll is not what this case is about).
function services.effects_gen_age(player, args)
    local G = TLG.Integration.Generators
    local g = generatorAt(EF.gx, EF.gy)
    local rec = G.read(g, true)
    for id, _ in pairs(rec.deg) do rec.deg[id] = tonumber(args.deg) end
    G.writeSidecar(g, rec)
    local out = evaluation(G.evaluate(g))
    g:setActivated(true)
    g:sync()
    out.fuel, out.cond, out.on = g:getFuel(), g:getCondition(), tostring(g:isActivated())
    out.side = S.text(g:getModData().tlg)
    out.hours = getGameTime():getWorldAgeHours()
    reply("effects_gen_age", args, out)
end

-- Before the charging refuel: the generator rate times `scale` (fixture), its
-- wear state cleared, and every chargeWear on the server logged with what it
-- owes as the single-player check computes it (the record as written, aged
-- to the call; RT.E.genCharge).
function services.effects_gen_arm(player, args)
    local G, EE = TLG.Integration.Generators, TLG.Domain.EngineEffects
    local g = generatorAt(EF.gx, EF.gy)
    EF.genRate = EF.genRate or EE.generatorWearPerLitre
    local base, scale = EF.genRate, tonumber(args.scale) or 1
    EE.generatorWearPerLitre = function(n, c) return scale * base(n, c) end
    g:getModData()[G.WEAR_KEY] = nil
    EF.charges = {}
    if not EF.chargeOrig then
        EF.chargeOrig = G.chargeWear
        G.chargeWear = function(gen)
            local b = {}
            pcall(function()
                local side = gen:getModData().tlg
                local written = 0
                for _, q in pairs(side and side.q or {}) do written = written + q end
                local w = gen:getModData()[G.WEAR_KEY]
                local ambient
                pcall(function() ambient = getClimateManager():getTemperature() end)
                local now = TLG.Domain.Aging.advance((G.read(gen, false)), TLG.World.now(), TLG.World.env())
                local e = TLG.Domain.Consumers.evaluate(G.profile(gen), now, { ambientC = ambient })
                b = { cond = gen:getCondition(), fuel = gen:getFuel(), written = written,
                    carry = (type(w) == "table" and w.c) or 0, charged = (type(w) == "table" and w.charged) or 0,
                    perLitre = EE.generatorWearPerLitre(G.lowerChanceOneIn(gen),
                        SandboxVars and SandboxVars.GeneratorFuelConsumption), wear = e.wearFactor }
            end)
            local whole = EF.chargeOrig(gen)
            local w = gen:getModData()[G.WEAR_KEY]
            b.whole, b.cond1, b.carry1 = whole, gen:getCondition(), (type(w) == "table" and w.c) or 0
            if EF.charges then
                EF.charges[#EF.charges + 1] = b
                report():line("OBS  MPS.effects chargeWear %d: written %.6f L, fuel %.6f L, charged before %.6f L, "
                    .. "factor %.6f, %.4f points a litre at factor 2: condition %s -> %s, carry %.6f -> %.6f, %s taken",
                    #EF.charges, b.written or -1, b.fuel or -1, b.charged or -1, b.wear or -1, b.perLitre or -1,
                    tostring(b.cond), tostring(b.cond1), b.carry or -1, b.carry1, tostring(whole))
            end
            return whole
        end
    end
    reply("effects_gen_arm", args, { fuel = g:getFuel(), cond = g:getCondition(), side = S.text(g:getModData().tlg),
        hours = getGameTime():getWorldAgeHours() })
end

-- After the refuel: the first charge that owed something, then one more
-- charge at once (it must take nothing); the generator switched off and
-- every fixture undone.
function services.effects_gen_probe(player, args)
    local G = TLG.Integration.Generators
    local g = generatorAt(EF.gx, EF.gy)
    local out, first, later = {}, nil, 0
    for i, b in ipairs(EF.charges or {}) do
        if first == nil and (b.written or 0) - (b.fuel or 0) > 1e-6 then
            first = b
            out.firstIndex = i
        elseif first ~= nil then
            later = later + (b.whole or 0)
        end
    end
    out.charges = #(EF.charges or {})
    if first then
        out.cond, out.cond1, out.carry, out.carry1 = first.cond, first.cond1, first.carry, first.carry1
        out.burned = first.written - first.fuel - first.charged
        out.due = first.carry + out.burned * (first.wear - 1) * first.perLitre
        out.whole, out.wear, out.perLitre = first.whole, first.wear, first.perLitre
    end
    local c0 = g:getCondition()
    out.again = G.chargeWear(g)
    out.againCond = g:getCondition()
    out.againFrom = c0
    out.later = later
    out.fuelNow = g:getFuel()
    out.condNow = g:getCondition()
    g:setActivated(false)
    g:sync()
    efRestore()
    reply("effects_gen_probe", args, out)
end

function services.effects_cleanup(player, args)
    efRestore()
    reply("effects_cleanup", args, { stalls = tostring(SandboxVars.TheLastGallon.VehicleStalls) })
end

------------------------------------------------------------------------------
-- The timers case (-Only timers; D-032 on a server). A campfire the server
-- builds, fuels and lights as the single-player open fires mode does
-- (SCampfireSystem.instance:addCampfire; the global object's setFuel and
-- lightFire), four running fermenters beside it and 28 more out of its
-- reach. The harness's own hourly and ten-minute handlers, registered after
-- the mod's, run right after its readings and notes in the same event and
-- compare each record with what they read themselves: the hour's reading
-- with the air at the machine (Machines.airAt), the ten-minute note with
-- whether the air there is above the unwarmed value and, if so, the campfire
-- (its offset, its fuel by the server's own campfire object). Each of the
-- mod's timer calls is timed.
------------------------------------------------------------------------------
local TM = M.TM or {}
M.TM = TM

local function free(s)
    if s == nil then return false end
    local ok, r = pcall(function()
        return s:getFloor() ~= nil and s:isFree(false) and s:isOutside() and not s:isInARoom()
            and s:getWorldObjects():size() == 0
    end)
    return ok and r == true
end

-- A spot with it and the eight squares round it free outdoor floor, nearest
-- (x0, y0) first.
local function openSpot(x0, y0)
    for r = 0, 20 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y, ok = x0 + dx, y0 + dy, true
                    for ax = -1, 1 do
                        for ay = -1, 1 do
                            if ok and not free(getCell():getGridSquare(x + ax, y + ay, 0)) then ok = false end
                        end
                    end
                    if ok then return x, y end
                end
            end
        end
    end
    return nil
end

local function campLua()
    local ok, o = pcall(function() return SCampfireSystem.instance:getLuaObjectAt(TM.fx, TM.fy, 0) end)
    return ok and o or nil
end

-- A timer of the mod's, timed on every call.
local function timed(tbl, name, key)
    local orig = tbl[name]
    TM.orig = TM.orig or {}
    TM.orig[key] = { tbl = tbl, name = name, fn = orig }
    TM.costs[key] = { n = 0, list = {} }
    tbl[name] = function(...)
        local t0 = getTimestampMs()
        local a, b, c = orig(...)
        local c1 = TM.costs[key]
        c1.n = c1.n + 1
        c1.list[#c1.list + 1] = getTimestampMs() - t0
        return a, b, c
    end
end

local function machineItem(m)
    local sq = getCell():getGridSquare(m.x, m.y, 0)
    local objs = sq and sq:getWorldObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local it = objs:get(i):getItem()
        if it and it:getID() == m.id then return it, sq end
    end
    return nil, sq
end

-- After the mod's reading: each machine's reading for the hour that ended
-- against the air read now.
local function tmHour()
    local ok, err = pcall(function()
        local Machines = TLG.Integration.Machines
        local slot = math.floor(TLG.World.now() - 0.5)
        TM.hours = (TM.hours or 0) + 1
        for _, m in ipairs(TM.machines) do
            local item, sq = machineItem(m)
            local rec = item and item:getModData()[Machines.SIDECAR]
            local got = rec and rec.temps and rec.temps[slot]
            local air = sq and Machines.airAt(sq)
            if got ~= nil and air ~= nil and got == air then
                m.readings = (m.readings or 0) + 1
            else
                m.badReadings = (m.badReadings or 0) + 1
                report():line("OBS  MPS.timers hour slot %d machine %s at %d,%d: reading %s, air now %s", slot,
                    tostring(m.id), m.x, m.y, tostring(got), tostring(air))
            end
        end
        report():line("OBS  MPS.timers hour %d (slot %d) checked", TM.hours, slot)
    end)
    if not ok then report():line("STEPERR MPS.timers_hour :: %s", tostring(err)) end
end

-- After the mod's note: each machine's note for this hour against the air
-- read now and the campfire.
local function tmTen()
    local ok, err = pcall(function()
        local Machines = TLG.Integration.Machines
        local hour = math.floor(TLG.World.now())
        local camp = campLua()
        local fuel = camp and camp.fuelAmt or -1
        TM.tens = (TM.tens or 0) + 1
        local warmCount = 0
        for _, m in ipairs(TM.machines) do
            local item, sq = machineItem(m)
            local rec = item and item:getModData()[Machines.SIDECAR]
            local note = rec and rec.fires and rec.fires[hour]
            local air = sq and Machines.airAt(sq)
            local warm = air ~= nil and air > Machines.unwarmedAt(sq) + Machines.FIRE_TOL
            local good
            if warm then
                warmCount = warmCount + 1
                good = type(note) == "table" and note.k == "campfire" and note.x == TM.fx - m.x and note.y == TM.fy - m.y
                    and math.abs((note.f or -99) - fuel) <= 1
            else
                good = note == false
            end
            if warm then m.warmNotes = (m.warmNotes or 0) + 1 end
            if good then
                m.goodNotes = (m.goodNotes or 0) + 1
            else
                m.badNotes = (m.badNotes or 0) + 1
                report():line("OBS  MPS.timers note hour %d machine %s at %d,%d: %s; air %.4f, unwarmed %.4f, campfire fuel %s",
                    hour, tostring(m.id), m.x, m.y, S.text(note), air or -99, Machines.unwarmedAt(sq), tostring(fuel))
            end
        end
        if TM.tens <= 3 or TM.tens % 6 == 0 then
            local m1 = TM.machines[1]
            local item, sq = machineItem(m1)
            local rec = item and item:getModData()[Machines.SIDECAR]
            report():line("OBS  MPS.timers ten minutes %d (hour %d): %d machine(s) warm; campfire fuel %s lit %s; "
                .. "machine 1 air %.4f unwarmed %.4f note %s", TM.tens, hour, warmCount, tostring(fuel),
                tostring(camp and camp.isLit), Machines.airAt(sq) or -99, Machines.unwarmedAt(sq),
                S.text(rec and rec.fires and rec.fires[hour]))
        end
    end)
    if not ok then report():line("STEPERR MPS.timers_ten :: %s", tostring(err)) end
end

function services.setup_timers(player, args)
    local Machines = TLG.Integration.Machines
    local fx, fy = openSpot(S.CX - 8, S.CY + 8)
    if fx == nil then
        reply("timers_site", args, { error = "no open spot for the campfire" })
        return
    end
    TM.fx, TM.fy = fx, fy
    local okC, errC = pcall(function() SCampfireSystem.instance:addCampfire(getCell():getGridSquare(fx, fy, 0)) end)
    local camp = campLua()
    if camp then
        camp:setFuel(tonumber(args.fuel) or 480)
        camp:lightFire()
        camp:saveData()
    end
    -- Four beside the fire, then 28 out of its reach (13 squares or more),
    -- every other square, nearest the spawn point first.
    TM.machines = {}
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local s = getCell():getGridSquare(fx + d[1], fy + d[2], 0)
        local item = s:AddWorldInventoryItem("TLG.FermenterVessel", 0.5, 0.5, 0)
        local rec = startBatch(item)
        TM.machines[#TM.machines + 1] = { id = item:getID(), x = fx + d[1], y = fy + d[2], near = true, state = rec.state }
    end
    local want = tonumber(args.far) or 28
    for r = 0, 20 do
        for dx = -r, r, 2 do
            for dy = -r, r, 2 do
                if #TM.machines < 4 + want and math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = S.CX + 4 + dx, S.CY - 4 + dy
                    local far = (x - fx) * (x - fx) + (y - fy) * (y - fy) >= 13 * 13
                    local s = getCell():getGridSquare(x, y, 0)
                    if far and free(s) then
                        local item = s:AddWorldInventoryItem("TLG.FermenterVessel", 0.5, 0.5, 0)
                        local rec = startBatch(item)
                        TM.machines[#TM.machines + 1] = { id = item:getID(), x = x, y = y, near = false, state = rec.state }
                    end
                end
            end
        end
    end
    TM.costs = {}
    timed(Machines, "sampleSites", "hour_readings")
    timed(Machines, "observeFires", "ten_minute_notes")
    timed(TLG.World, "recordClimate", "hour_climate")
    timed(TLG.Authority.Handlers.commands, "machine.status", "machine_status")
    Events.EveryHours.Add(tmHour)
    Events.EveryTenMinutes.Add(tmTen)
    TM.h0 = TLG.World.now()
    local near, farN = {}, 0
    for _, m in ipairs(TM.machines) do
        if m.near then near[#near + 1] = m.id .. "@" .. m.x .. "," .. m.y else farN = farN + 1 end
    end
    report():line("OBS  MPS.timers site: campfire %d,%d built=%s %s lit=%s fuel %s exterior %s radius %s; beside it %s; "
        .. "%d out of reach", fx, fy, tostring(okC), tostring(errC or ""), tostring(camp and camp.isLit),
        tostring(camp and camp.fuelAmt), tostring(camp and camp.exterior), tostring(camp and camp:fireRadius()),
        table.concat(near, " "), farN)
    local m1, mf = TM.machines[1], TM.machines[#TM.machines]
    reply("timers_site", args, { fx = fx, fy = fy, built = tostring(okC), lit = tostring(camp and camp.isLit),
        fuel = camp and camp.fuelAmt or -1, machines = #TM.machines, far = farN, nearId = tostring(m1.id),
        nearX = m1.x, nearY = m1.y, farId = tostring(mf.id), farX = mf.x, farY = mf.y, h0 = TM.h0 })
end

local function costText(key)
    local c = TM.costs[key]
    if c == nil or c.n == 0 then return key .. " none" end
    local s = {}
    for i, v in ipairs(c.list) do s[i] = v end
    table.sort(s)
    local sum = 0
    for _, v in ipairs(s) do sum = sum + v end
    return string.format("%s %d call(s): median %.0f ms, mean %.2f ms, max %.0f ms", key, c.n,
        s[math.floor((#s + 1) / 2)], sum / #s, s[#s])
end

-- What the hours and notes gave each machine, and the timers' costs so far.
function services.probe_timers(player, args)
    local Machines = TLG.Integration.Machines
    local out = { hours = TM.hours or 0, tens = TM.tens or 0, machines = #TM.machines }
    local readings, badR, goodN, badN, warmNear, warmFar, nearNotes = 0, 0, 0, 0, 0, 0, 0
    local slotsMin = 99999
    for _, m in ipairs(TM.machines) do
        readings, badR = readings + (m.readings or 0), badR + (m.badReadings or 0)
        goodN, badN = goodN + (m.goodNotes or 0), badN + (m.badNotes or 0)
        if m.near and (m.warmNotes or 0) > 0 then warmNear = warmNear + 1 end
        if not m.near and (m.warmNotes or 0) > 0 then warmFar = warmFar + 1 end
        local item = machineItem(m)
        local rec = item and item:getModData()[Machines.SIDECAR]
        local n = 0
        for _ in pairs(rec and rec.temps or {}) do n = n + 1 end
        if n < slotsMin then slotsMin = n end
        if m.near then
            for _, note in pairs(rec and rec.fires or {}) do
                if type(note) == "table" and note.k == "campfire" then nearNotes = nearNotes + 1 end
            end
        end
    end
    out.readings, out.badReadings, out.goodNotes, out.badNotes = readings, badR, goodN, badN
    out.warmNear, out.warmFar, out.nearCampfireHours, out.slotsMin = warmNear, warmFar, nearNotes, slotsMin
    local camp = campLua()
    out.fuel, out.lit = camp and camp.fuelAmt or -1, tostring(camp and camp.isLit)
    out.now = TLG.World.now()
    for _, k in ipairs({ "hour_climate", "hour_readings", "ten_minute_notes", "machine_status" }) do
        out["cost_" .. k] = costText(k)
        report():line("OBS  MPS.timers cost %s", out["cost_" .. k])
    end
    reply("probe_timers", args, out)
end

-- The timers' bodies on the server, as the single-player performance mode
-- times them (RT.PF.bench: the first call alone, then five batches of at
-- least 200 ms, the median batch's ms per call); the hour's climate record
-- put back after.
function services.bench_timers(player, args)
    local Machines, W = TLG.Integration.Machines, TLG.World
    local function bench(fn)
        local t0 = getTimestampMs()
        fn()
        local first = getTimestampMs() - t0
        local per, calls = {}, 1
        for _ = 1, 5 do
            local n, s, e = 0, getTimestampMs(), 0
            repeat
                fn()
                n = n + 1
                e = getTimestampMs() - s
            until e >= 200 or n >= 200000
            per[#per + 1] = e / n
            calls = calls + n
        end
        table.sort(per)
        return string.format("first %.0f ms; median %.4f ms per call (batches %.4f-%.4f, %d calls)", first, per[3],
            per[1], per[5], calls), per[3]
    end
    -- The originals, not the timed wrappers. The bench's writes stay on the
    -- server (Machines.write quiet): hundreds of hourly readings would each
    -- send 32 records to the client. The timed events above include the
    -- sends; the bench times the work without them.
    local sample = TM.orig.hour_readings.fn
    local notes = TM.orig.ten_minute_notes.fn
    local climate = TM.orig.hour_climate.fn
    local write = Machines.write
    Machines.write = function(item, rec) return write(item, rec, true) end
    local md = W.get()
    local acc, log = TLG.Tables.deepCopy(md.climateAcc), TLG.Tables.deepCopy(md.climateLog)
    local out = {}
    local ok, err = pcall(function()
        out.hourText, out.hour = bench(function() climate(); sample() end)
        md.climateAcc, md.climateLog = acc, log
        out.tenText, out.ten = bench(notes)
        -- The status request's catch-up for the machine beside the fire
        -- (MachineHandlers machineState: read, advance; then the site's air).
        local item = machineItem(TM.machines[1])
        out.statusText, out.status = bench(function()
            local rec = Machines.read(item, true)
            rec = Machines.advance(item, rec, W.now(), W.env())
            Machines.siteTemp(item, rec, W.now(), W.env())
        end)
    end)
    Machines.write = write
    if not ok then out.error = tostring(err) end
    for _, k in ipairs({ "hour", "ten", "status" }) do
        report():line("OBS  MPS.timers bench %s: %s", k, tostring(out[k .. "Text"]))
    end
    if out.error then report():line("STEPERR MPS.bench_timers :: %s", out.error) end
    reply("bench_timers", args, out)
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

------------------------------------------------------------------------------
-- Security audit probes (2026-11-05 audit, AuditCases.lua): what the server
-- holds, read-only. probe_square: a square's power as the server sees it;
-- probe_world: the mod's world record and its server store (seed, next id,
-- the hourly reading's machine list; V-03), and whether the store lists a
-- machine at args x, y.
------------------------------------------------------------------------------
function services.probe_square(player, args)
    local sq = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), 0)
    local grid, elec
    pcall(function() grid = sq:hasGridPower() end)
    pcall(function() elec = sq:haveElectricity() end)
    reply("probe_square", args, { found = tostring(sq ~= nil), grid = tostring(grid), elec = tostring(elec),
        user = tostring(player:getUsername()),
        level = tostring(select(2, pcall(function() return player:getRole():getName() end))) })
end

function services.probe_world(player, args)
    local md, srv = TLG.World.get(), TLG.World.server()
    local hit = false
    for _, p in pairs(srv.machineSites or {}) do
        if type(p) == "table" and p.x == tonumber(args.x) and p.y == tonumber(args.y) then hit = true end
    end
    reply("probe_world", args, { store = tostring(TLG.World.store ~= nil and srv ~= md), seed = tostring(srv.seed),
        nextId = tostring(srv.nextId), policy = tostring(md.policy), sites = S.text(srv.machineSites or {}),
        siteHit = tostring(hit), pubSeed = tostring(md.seed), pubNextId = tostring(md.nextId),
        pubSites = md.machineSites and S.text(md.machineSites) or "nil" })
end
