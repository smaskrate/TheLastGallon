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
-- server (Machines.takeOnServer, D-030) with its result, every put-down
-- (Machines.putDown) with where and when, whether OnTick fires on the
-- server, and holds the fixtures and watches of the effects and timers
-- cases (below).
-- Results: <cachedir>/Lua/TLG_harness_mpserver.txt.
require "TLGHarness/Report"
require "TLGHarness/MPShared"

if not isServer() then return end

-- The multiplayer cases move petrol, and a client cannot tell which pump
-- gives it (the draw needs the world's seed, which the server holds):
-- in the harness's worlds no pump is drawn as diesel (D-036).
require "TLG/Domain/WorldInit"
TLG.Domain.WorldInit.STATION_DIESEL_SHARE = 0

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
    local item
    if sq and args.petrol then
        -- A can filled before it is put down, so the clients get it full.
        item = instanceItem(args.item)
        local fc = item and item:getFluidContainer()
        if fc then
            fc:Empty()
            fc:addFluid(Fluid.Petrol, tonumber(args.petrol))
        end
        if item then sq:AddWorldInventoryItem(item, 0.5, 0.5, 0) end
    else
        item = sq and sq:AddWorldInventoryItem(args.item, 0.5, 0.5, 0)
    end
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
-- point, in a dead body's inventory there, in an online player's inventory,
-- in both hands), how many vessels lie there or are carried in all, its
-- batch, the hourly reading's entry for it and the takes so far. With `pid`
-- a vessel holding that batch record counts as it too (an item may come
-- back under another id).
function services.probe_vessel(player, args)
    local id, pid, places, item, count = tonumber(args.id), args.pid, {}, nil, 0
    local function same(it)
        if it:getID() == id then return true end
        local rec = pid and it:getModData().tlgProc
        return type(rec) == "table" and rec.id == pid
    end
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            local sq = getCell():getGridSquare(x, y, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == "TLG.FermenterVessel" then count = count + 1 end
                if it and same(it) then
                    places[#places + 1] = "floor " .. x .. "," .. y
                    item = it
                end
            end
            local movs = sq and sq:getStaticMovingObjects()
            for i = 0, (movs and movs:size() or 0) - 1 do
                local o = movs:get(i)
                local c = instanceof(o, "IsoDeadBody") and o:getContainer() or nil
                local items = c and c:getItems()
                for j = 0, (items and items:size() or 0) - 1 do
                    local it = items:get(j)
                    if it:getFullType() == "TLG.FermenterVessel" then count = count + 1 end
                    if same(it) then
                        places[#places + 1] = "body " .. x .. "," .. y
                        item = it
                    end
                end
            end
        end
    end
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        count = count + p:getInventory():getCountTypeRecurse("TLG.FermenterVessel")
        local it = p:getInventory():getItemWithIDRecursiv(id)
        if it == nil and pid then
            local found = p:getInventory():getAllEvalRecurse(function(x) return same(x) end)
            it = found and found:size() > 0 and found:get(0) or nil
        end
        if it then
            local both = p:getPrimaryHandItem() == it and p:getSecondaryHandItem() == it
            places[#places + 1] = "inventory " .. p:getUsername() .. (both and " both hands" or "")
            item = it
        end
    end
    local rec = item and item:getModData().tlgProc
    local sites = TLG.World.server().machineSites or {}
    local listed = rec and rec.id and sites[rec.id]
    -- The mod's view of the hands (Machines.onHands): whether it holds the
    -- vessel as in someone's hands, and how many machines it watches land.
    local Machines = TLG.Integration.Machines
    local inHands = Machines.inHands or {}
    local holder = item and inHands[item]
    reply("probe_vessel", args, { where = #places > 0 and table.concat(places, "; ") or "nowhere", vessels = count,
        held = holder and tostring(holder:getUsername()) or "no", landing = #(Machines.landing or {}),
        state = tostring(rec and rec.state or "none"), pause = tostring(rec and rec.pause or "none"),
        site = rec and rec.site and rec.site.x and (rec.site.x .. "," .. rec.site.y) or "none",
        listed = listed and (listed.x .. "," .. listed.y) or "no", takes = table.concat(M.takes, " "),
        t = rec and rec.t or -1, seen = rec and rec.seen or -1, done = rec and workDone(rec) or -1,
        now = TLG.World.now(), inputs = S.text(rec and rec.inputs) })
end

-- The vessel `id` on the floor around the spawn point or in an online
-- player's inventory, as probe_vessel finds it.
local function vesselById(id)
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            local sq = getCell():getGridSquare(x, y, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getID() == id then return it end
            end
        end
    end
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local it = list:get(i):getInventory():getItemWithIDRecursiv(id)
        if it then return it end
    end
    return nil
end

-- -Restart: the vessel's record given, by the authority, the largest history
-- the mod keeps: 480 hours of readings and fire notes (Machines.MAX_READINGS),
-- for the hours to come so the trim keeps them. The restart then carries it
-- through the vault's digests (audit V-01, the compact store) and the
-- engine's save and load.
function services.fill_history(player, args)
    local M = TLG.Integration.Machines
    local item = vesselById(tonumber(args.id))
    local rec = item and M.stored(item)
    local out = { found = tostring(item ~= nil), record = tostring(rec ~= nil) }
    if rec then
        local now = math.floor(TLG.World.now())
        rec.temps, rec.fires = rec.temps or {}, rec.fires or {}
        for h = now + 1, now + M.MAX_READINGS do
            rec.temps[h] = 17 + (h % 11) * 0.137
            if h % 4 == 0 then
                rec.fires[h] = false
            else
                rec.fires[h] = { t = h + 0.83, f = 900 - h % 300, x = 1, y = 2, r = false, c = 35 }
            end
        end
        -- The mod's own trim: what the passes keep from now on (the
        -- readings filed so far are the oldest and go).
        M.trimTemps(rec, TLG.World.env())
        M.write(item, rec, true)
        out.temps, out.fires = TLG.Tables.count(rec.temps), TLG.Tables.count(rec.fires)
    end
    reply("fill_history", args, out)
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
    -- A new generator: the vault forgets what an earlier one on this tile had
    -- (TLG/Authority/Vault.lua), so the record is not put back.
    local holder = TLG.Integration.Generators.keyOf(g)
    TLG.Authority.Vault.release("supply", holder)
    TLG.Authority.Vault.release("project", holder)
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

-- The biodiesel case (D-036). Two rows north of the spawn point: the five
-- machines empty, and beside each one that loads from another machine, that
-- machine with a finished batch (run to its end through the domain, as
-- setup_production runs the fermenter's): a finished ash barrel by the
-- leacher, a finished retort and leacher by the reactor, a finished reactor
-- by the wash tank, and a finished wash tank to collect from. Each group is
-- more than two squares from the next, the reach of a load. Also a diesel
-- generator, an ambulance with 10 L and no record and its key, an empty
-- jerry can, and one untouched pump of the station given its first record
-- with the draw's share held at 1 (the harness's worlds draw no diesel
-- pump otherwise).
local BD = { fresh = { retort = { "TLG.WoodRetort", -6 }, barrel = { "TLG.AshBarrel", -5 }, leacher = { "TLG.LyeLeacher", -2 },
    reactor = { "TLG.BiodieselReactor", 2 }, wash = { "TLG.BiodieselWashTank", 6 } } }

local function doneMachine(itemType, recipe, inputs, firebox, dx, dy)
    local Machines, Process, World = TLG.Integration.Machines, TLG.Domain.Process, TLG.World
    local sq = getCell():getGridSquare(S.CX + dx, S.CY + dy, 0)
    local item = sq:AddWorldInventoryItem(itemType, 0.5, 0.5, 0)
    local env = TLG.Domain.Climate.new({ dayOfYear = 190, hourOfDay = 9 }, {}, nil)
    local rec = Process.new({ id = World.newId("P"), machine = Machines.machineFor(item), t = 0 })
    if firebox then rec = Process.addFirebox(rec, firebox).proc end
    rec = Process.load(rec, recipe, inputs).proc
    rec = Process.start(rec, 0).proc
    local t = 0
    while (rec.state == "Processing" or rec.state == "Paused") and t < 24 * 30 do
        t = t + 24
        rec = Process.advance(rec, t, env)
    end
    rec.t = World.now()
    item:getModData()[Machines.SIDECAR] = rec
    rec = Machines.advance(item, rec, World.now(), World.env())
    Machines.write(item, rec)
    Machines.index(item, rec)
    return item, rec
end

function services.setup_biodiesel(player, args)
    local out, blocked = {}, {}
    for dx = -6, 9 do
        for dy = -3, -2 do
            local sq = getCell():getGridSquare(S.CX + dx, S.CY + dy, 0)
            if not (sq and sq:isFree(false)) then blocked[#blocked + 1] = dx .. "," .. dy end
        end
    end
    out.blocked = table.concat(blocked, " ")
    for key, spec in pairs(BD.fresh) do
        local item = getCell():getGridSquare(S.CX + spec[2], S.CY - 2, 0):AddWorldInventoryItem(spec[1], 0.5, 0.5, 0)
        out[key], out[key .. "X"] = tostring(item:getID()), S.CX + spec[2]
    end
    local done = {
        barrelDone = { "TLG.AshBarrel", "ash_burn", { firewood = 99 }, nil, -2 },
        retortDone = { "TLG.WoodRetort", "methanol_wood_distill", { firewood = 99 }, 40, 1 },
        leacherDone = { "TLG.LyeLeacher", "lye_leach", { wood_ash = 1.485, water = 2.97 }, 20, 3 },
        reactorDone = { "TLG.BiodieselReactor", "biodiesel_react", { plant_oil = 17.1, methanol = 2.565, lye = 0.21375 }, 20, 6 },
        washDone = { "TLG.BiodieselWashTank", "biodiesel_wash",
            { biodiesel = 16.8435, methanol = 0.6766, plant_oil = 0.1881, sediment = 0.1729, water = 5.053 }, 10, 9 },
    }
    local states = {}
    for key, d in pairs(done) do
        local dy = key == "washDone" and -2 or -3
        local item, rec = doneMachine(d[1], d[2], d[3], d[4], d[5], dy)
        out[key], out[key .. "X"], out[key .. "Y"] = tostring(item:getID()), S.CX + d[5], S.CY + dy
        states[#states + 1] = key .. "=" .. tostring(rec.state) .. " " .. S.text(rec.outputs)
    end
    table.sort(states)
    out.states, out.y = table.concat(states, "; "), S.CY - 2
    -- The diesel generator, put down as emptyGenerator puts vanilla's.
    local gx, gy = S.CX - 3, S.CY + 3
    local g = IsoGenerator.new(instanceItem("TLG.DieselGenerator"), getCell(), getCell():getGridSquare(gx, gy, 0))
    g:setFuel(0)
    g:getModData().tlg = nil
    TLG.Authority.Vault.release("supply", TLG.Integration.Generators.keyOf(g))
    g:setConnected(true)
    g:sync()
    g:transmitModData()
    out.gx, out.gy = gx, gy
    -- The ambulance, as a vehicle of the map is found: fuel and no record.
    local van = addVehicleDebug("Base.VanAmbulance", IsoDirections.N, nil, getCell():getGridSquare(S.CX + 3, S.CY + 3, 0))
    local inv = player:getInventory()
    local key = van and van:createVehicleKey()
    if key then sendAddItemToContainer(inv, inv:AddItem(key)) end
    local tank = van and van:getPartById("GasTank")
    if tank then
        pcall(function() van:repair() end)
        tank:setContainerContentAmount(10)
        tank:getModData().tlg = nil
        van:transmitPartModData(tank)
    end
    out.van = tostring(van and van:getId())
    local can = inv:AddItem("Base.JerryCan")
    can:getFluidContainer():Empty()
    sendAddItemToContainer(inv, can)
    out.jerry = tostring(can:getID())
    -- A pump nothing has touched, nearest the spawn point, made a diesel pump.
    local St, W = TLG.Integration.Stations, TLG.Domain.WorldInit
    local best, bestD
    for x = STATION.x0, STATION.x1 do
        for y = STATION.y0, STATION.y1 do
            local p = pumpAt(x, y)
            if p and p:getPipedFuelAmount() > 100 and p:getModData().tlg == nil then
                local d = (x - S.CX) * (x - S.CX) + (y - S.CY) * (y - S.CY)
                if bestD == nil or d < bestD then best, bestD = p, d end
            end
        end
    end
    if best then
        local share = W.STATION_DIESEL_SHARE
        W.STATION_DIESEL_SHARE = 1
        local rec = St.read(best, true)
        St.writeSidecar(best, rec)
        W.STATION_DIESEL_SHARE = share
        out.px, out.py, out.pumpUnits = best:getSquare():getX(), best:getSquare():getY(), best:getPipedFuelAmount()
        out.pumpProduct = tostring(St.product(best))
    end
    out.dieselWorld = tostring(TLG.World.get().dieselVehicles)
    reply("biodiesel_site", args, out)
end

-- The server's view of the biodiesel case: each machine's state and
-- outputs, the generator, the ambulance, the pump, the requester's cans
-- (`ids`) and a generator item carried.
function services.probe_biodiesel(player, args)
    local out = {}
    local machines = {}
    for dx = -7, 10 do
        for dy = -4, -1 do
            local sq = getCell():getGridSquare(S.CX + dx, S.CY + dy, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and TLG.Integration.Machines.machineFor(it) then machines[tostring(it:getID())] = it end
            end
        end
    end
    for _, key in ipairs(split(args.keys)) do
        local it = machines[tostring(args[key])]
        local rec = it and it:getModData().tlgProc
        out[key] = tostring(rec and rec.state or (it and "no record" or "not found"))
        out[key .. "Out"] = S.text(rec and rec.outputs)
    end
    local g = generatorAt(tonumber(args.gx), tonumber(args.gy))
    out.gFound, out.gFuel, out.gOn = tostring(g ~= nil), g and g:getFuel() or -1, tostring(g and g:isActivated())
    out.gProfile = tostring(g and TLG.Integration.Generators.profile(g))
    out.gType = tostring(g and g:getGeneratorItemType())
    out.gSide = S.text(g and g:getModData().tlg)
    local carried
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        if TLG.Integration.Generators.ITEM_TYPES[items:get(i):getFullType()] then carried = items:get(i) end
    end
    out.carriedType = tostring(carried and carried:getFullType())
    out.carriedSide = S.text(carried and carried:getModData().tlg)
    local van = getVehicleById(tonumber(args.van) or -1)
    local tank = van and van:getPartById("GasTank")
    out.vanProfile = tostring(van and TLG.Integration.Vehicles.profile(van))
    out.vanL, out.vanSide = tank and tank:getContainerContentAmount() or -1, S.text(tank and tank:getModData().tlg)
    out.vanEngine = tostring(van and van:isEngineRunning())
    local pump = args.px and pumpAt(tonumber(args.px), tonumber(args.py))
    out.pumpUnits, out.pumpSide = pump and pump:getPipedFuelAmount() or -1, S.text(pump and pump:getModData().tlg)
    local cans = {}
    for _, id in ipairs(split(args.ids)) do
        local it = player:getInventory():getItemWithIDRecursiv(tonumber(id))
        local fc = it and it:getFluidContainer()
        cans[#cans + 1] = id .. "=" .. (fc and string.format("%.4f", fc:getAmount()) or "nil") .. " " .. S.sidecar(it)
    end
    out.cans = table.concat(cans, " | ")
    reply("probe_biodiesel", args, out)
end

-- handbook (-Only handbook): the sender's welding level set on the server
-- (the client sets its own, as the conversion cases do), and what the
-- server holds of the player: the five recipes known, the level, the Ash
-- Barrels carried. roll_handbook fills containers from the handbook's loot
-- lists as roll_manual does and counts the handbooks.
-- With rise = "1" the level is gained one at a time with LevelPerk, as the
-- single-player handbook mode gains it: launches 325 and 327 set Welding 3
-- with setPerkLevelDebug, and the crafting window then offered the two
-- Welding 4 recipes and made them.
function services.handbook_level(player, args)
    local want = tonumber(args.level) or 0
    -- `perk`: another skill than Welding (the onebelow case's Carving).
    local perk = args.perk and Perks[args.perk] or Perks.MetalWelding
    if args.rise == "1" then
        local guard = 0
        while player:getPerkLevel(perk) < want and guard < 12 do
            player:LevelPerk(perk)
            guard = guard + 1
        end
    else
        player:setPerkLevelDebug(perk, want)
    end
    reply("handbook_level", args, { level = player:getPerkLevel(perk), xp = player:getXp():getXP(perk) })
end

-- A recipe taught to the sender on the server, as a read magazine teaches it
-- (the onebelow2 case: a recipe of the game's own that must be learned).
function services.learn_recipe(player, args)
    player:learnRecipe(args.recipe)
    reply("learn_recipe", args, { recipe = args.recipe, known = tostring(player:getKnownRecipes():contains(args.recipe)) })
end

function services.probe_handbook(player, args)
    local known = {}
    for _, n in ipairs(TLG.Integration.Manual.HANDBOOK_RECIPES) do
        known[#known + 1] = player:getKnownRecipes():contains(n) and "1" or "0"
    end
    reply("probe_handbook", args, { known = table.concat(known), level = player:getPerkLevel(Perks.MetalWelding),
        barrels = player:getInventory():getCountTypeRecurse("TLG.AshBarrel"),
        read = tostring(player:getAlreadyReadBook():contains("TLG.BiodieselHandbook")) })
end

function services.roll_handbook(player, args)
    local total, fills, parts = 0, 0, {}
    for _, l in ipairs({ { "gasstorage", "other", "GasStorageMechanics" }, { "garagestorage", "crate", "CrateMechanics" },
        { "toolstore", "shelves", "ToolStoreBooks" }, { "library", "shelves", "LibraryMagazines" } }) do
        local dist = ItemPickerJava.getItemContainer(l[1], l[2], l[3], false)
        if dist == nil then
            parts[#parts + 1] = l[3] .. "=unknown"
        else
            local n, cont = 0, ItemContainer.new("crate", player:getCurrentSquare(), player)
            for _ = 1, 300 do
                cont:removeAllItems()
                ItemPickerJava.doRollItem(dist, cont, 1, player, true, nil)
                local got = cont:getItemsFromFullType("TLG.BiodieselHandbook")
                n = n + (got and got:size() or 0)
            end
            cont:removeAllItems()
            total, fills = total + n, fills + 300
            parts[#parts + 1] = l[3] .. "=" .. n
        end
    end
    reply("roll_handbook", args, { total = total, fills = fills, lists = table.concat(parts, " ") })
end

-- gensprite (tools/run-mp-harness.ps1 -Only gensprite -ModAway): a Diesel
-- Generator put down beside the spawn point, and later what the server
-- holds of it.
function services.setup_gensprite(player, args)
    local gx, gy = S.CX + 2, S.CY + 2
    local g = IsoGenerator.new(instanceItem("TLG.DieselGenerator"), getCell(), getCell():getGridSquare(gx, gy, 0))
    g:setFuel(0)
    g:setConnected(true)
    g:sync()
    g:transmitModData()
    reply("setup_gensprite", args, { gx = gx, gy = gy })
end

function services.probe_gensprite(player, args)
    local g = generatorAt(tonumber(args.gx), tonumber(args.gy))
    local name = "none"
    pcall(function()
        local s = g:getSprite()
        name = s and tostring(s:getName()) or "none"
    end)
    reply("probe_gensprite", args, { found = tostring(g ~= nil), sprite = name,
        fullType = tostring(g and g:getModData().generatorFullType),
        profile = tostring(g and TLG.Integration.Generators.profile(g)) })
end

------------------------------------------------------------------------------
-- gasfeed (tools/run-mp-harness.ps1 -Only gasfeed, one client, the shortest
-- day; D-040): the single-player gas measures (SPHarness RT.GM) where the
-- server runs them. A vanilla generator G beside the spawn point on 1 L,
-- with a battery charger beside it as the load switched (0.05 while on).
-- The server's own tick and minute watchers note each step, the load read
-- the tick before it, and whether the tick watcher and the first minute
-- event of the hour saw it already; then two refill policies run against
-- the charger switched on after the hour's minute-59 event and before its
-- boundary: phase "charger" (the load on and off), "steps" (three
-- boundaries on G's own fuel), "policy_tick", "policy_minute" (each over
-- at least three counted switch-ons and three boundaries, at most 8),
-- "done". setFuel on the server sends the generator to the clients (BC
-- IsoGenerator.setFuel calls sync()); the client compares its copy
-- (MPHarnessCases.lua).
------------------------------------------------------------------------------
local GF = { eps = 1e-4, tol = 2e-7, phase = "none" }
M.GF = GF

function GF.power(g)
    local p = -1
    pcall(function() p = g:getTotalPowerUsing() end)
    return p
end

function GF.setting(g)
    local s = -1
    pcall(function() s = g:getBasePowerConsumption() / 0.02 end)
    return s
end

function GF.ms()
    local t = -1
    pcall(function() t = getTimestampMs() end)
    return t
end

function GF.charging(on)
    if GF.charger == nil then return end
    if on then pcall(function() GF.battery:setUsedDelta(0) end) end
    GF.charger:setActivated(on == true)
end

function GF.clear()
    GF.drops, GF.boundaries, GF.marks, GF.attempts = {}, {}, {}, {}
    GF.minutes, GF.refills, GF.offTicks, GF.stops, GF.off, GF.trims = 0, 0, 0, 0, 0, 0
    GF.attempt, GF.lastAttempt, GF.attemptHour, GF.min59Hour = nil, nil, nil, nil
    GF.boundary, GF.lastFuel, GF.minuteFuel, GF.trimFrom, GF.sizeAt = nil, nil, nil, nil, nil
end

-- A policy phase sizes its buffer 10 ticks after it begins, once the
-- charger's going off has reached the load (launch 347 sized it from the
-- load before, and its minute phase tested nothing).
function GF.enter(phase)
    local g = GF.g
    GF.clear()
    GF.phase, GF.t0 = phase, GF.tick or 0
    GF.refill, GF.late = nil, false
    GF.charging(false)
    if phase == "steps" then
        g:setFuel(1.0)
    elseif phase == "policy_tick" or phase == "policy_minute" then
        if not g:isActivated() then g:setActivated(true) end
        GF.sizeAt = (GF.tick or 0) + 10
    end
    GF.lastFuel = g:getFuel()
    report():line("OBS  MPS.gf enter %s at %.5f h: fuel %.7f, running %s, load %.7f", phase,
        getGameTime():getWorldAgeHours(), g:getFuel(), tostring(g:isActivated()), GF.power(g))
end

-- A phase's results, logged and kept for the client's probe.
function GF.closeSteps()
    local bad, atEdge = 0, 0
    for _, d in ipairs(GF.drops) do
        if math.abs(d.drop - (d.before or -1)) > GF.tol then bad = bad + 1 end
        if d.age - math.floor(d.age) < 1 / 60 then atEdge = atEdge + 1 end
    end
    local tickSaw, minuteSaw, parts = 0, 0, {}
    for i, b in ipairs(GF.boundaries) do
        local m = GF.marks[i]
        if b.dropped then tickSaw = tickSaw + 1 end
        if m and m.dropped then minuteSaw = minuteSaw + 1 end
        parts[#parts + 1] = string.format("[boundary %.5f h tick %d: tick watcher saw the step %s; first minute event at " ..
            "%s h tick %s saw it %s, %s ms after the tick watcher]", b.age, b.tick, tostring(b.dropped),
            m and string.format("%.5f", m.age) or "-", m and tostring(m.tick) or "-", m and tostring(m.dropped) or "-",
            m and tostring(m.ms - b.ms) or "-")
    end
    GF.res.steps_n, GF.res.steps_bad, GF.res.steps_edge = #GF.drops, bad, atEdge
    GF.res.bounds, GF.res.marks, GF.res.tick_saw, GF.res.minute_saw = #GF.boundaries, #GF.marks, tickSaw, minuteSaw
    report():line("OBS  MPS.gf steps: %d drops, %d off the load read before by more than %.0e, %d in the hour's first game " ..
        "minute; order %s", #GF.drops, bad, GF.tol, atEdge, table.concat(parts, " "))
end

-- An attempt counts when the load rose before the boundary while the
-- buffer was short of the new step, so that a refill had to land between
-- the rise and the burn.
function GF.closePolicy()
    local counted, stoppedCounted, refilled, parts = 0, 0, 0, {}
    for _, at in ipairs(GF.attempts) do
        if at.rose and at.short and at.boundary then
            counted = counted + 1
            if at.stopped then stoppedCounted = stoppedCounted + 1 end
            if at.refilledBetween then refilled = refilled + 1 end
        end
        parts[#parts + 1] = string.format("[hour %d: on at %.5f h, load rose %s, fuel then %s (short of the step %s), " ..
            "boundary %s, a refill between %s, stopped %s]", at.hour, at.at, tostring(at.rose),
            at.fuelAtRise and string.format("%.7f", at.fuelAtRise) or "-", tostring(at.short == true),
            at.boundary and string.format("%.5f h", at.boundary.age) or "-", tostring(at.refilledBetween == true),
            tostring(at.stopped == true))
    end
    local gone = getGameTime():getWorldAgeHours() - (GF.h0 or 0)
    local key = GF.phase == "policy_tick" and "tick" or "minute"
    GF.res[key .. "_counted"], GF.res[key .. "_stopped"], GF.res[key .. "_stops"] = counted, stoppedCounted, GF.stops
    GF.res[key .. "_refilled"] = refilled
    GF.res[key .. "_bounds"], GF.res[key .. "_minutes_an_hour"] = #GF.boundaries,
        string.format("%.1f", (GF.minutes - (GF.m0 or 0)) / math.max(gone, 1e-9))
    report():line("OBS  MPS.gf %s: %.3f game h, %d boundaries, %d refills, %d trims, %d stops, %d ticks not running, %s " ..
        "minute events an hour; attempts %s", GF.phase, gone, #GF.boundaries, GF.refills, GF.trims, GF.stops, GF.offTicks,
        GF.res[key .. "_minutes_an_hour"], table.concat(parts, " "))
end

function GF.onTick()
    local g = GF.g
    if g == nil or GF.phase == "none" or GF.phase == "done" then return end
    GF.tick = (GF.tick or 0) + 1
    local age = getGameTime():getWorldAgeHours()
    local fl = math.floor(age)
    local f, p, on = g:getFuel(), GF.power(g), g:isActivated()
    if GF.lastFloor ~= nil and fl > GF.lastFloor then
        local b = { age = age, tick = GF.tick, ms = GF.ms(), dropped = GF.lastFuel ~= nil and f < GF.lastFuel - 1e-9 }
        GF.boundaries[#GF.boundaries + 1] = b
        GF.boundary = b
        if GF.attempt then
            GF.attempt.boundary = b
            GF.attempt.refilledBetween = GF.attempt.refillsAtRise ~= nil and GF.refills > GF.attempt.refillsAtRise
            GF.lastAttempt, GF.attempt = GF.attempt, nil
        end
    end
    if GF.lastFuel ~= nil and f < GF.lastFuel - 1e-9 then
        local b = GF.boundary
        GF.drops[#GF.drops + 1] = { age = age, drop = GF.lastFuel - f, before = GF.lastPower, on = on,
            ticks = b and (GF.tick - b.tick) or -1 }
        report():line("OBS  MPS.gf %s drop at %.5f h: %.7f L (load read the tick before %.7f), fuel now %.7f, running %s, " ..
            "%d ticks after the boundary was seen", GF.phase, age, GF.lastFuel - f, GF.lastPower or -1, f, tostring(on),
            b and (GF.tick - b.tick) or -1)
    end
    if GF.lastOn and not on then
        GF.stops = GF.stops + 1
        report():line("OBS  MPS.gf %s G stopped at %.5f h, fuel %.7f", GF.phase, age, f)
    end
    if not on then GF.offTicks = GF.offTicks + 1 end
    local la = GF.lastAttempt
    if la and la.boundary and GF.tick - la.boundary.tick <= 5 and not on then la.stopped = true end
    -- The phases.
    if GF.phase == "charger" then
        if not GF.c then
            GF.c = { p0 = p, t = GF.tick }
            GF.charging(true)
        elseif not GF.c.pOn then
            if p > GF.c.p0 + GF.chargerStep / 2 or GF.tick - GF.c.t > 300 then
                GF.c.pOn, GF.c.onTicks, GF.c.t = p, GF.tick - GF.c.t, GF.tick
                GF.charging(false)
            end
        elseif math.abs(p - GF.c.p0) <= 1e-7 or GF.tick - GF.c.t > 300 then
            GF.res.charger_rise = string.format("%.7f", GF.c.pOn - GF.c.p0)
            GF.res.charger_back = tostring(math.abs(p - GF.c.p0) <= 1e-7)
            report():line("OBS  MPS.gf charger: load %.7f -> %.7f within %d ticks, back to %.7f within %d ticks; expected " ..
                "rise %.7f", GF.c.p0, GF.c.pOn, GF.c.onTicks, p, GF.tick - GF.c.t, GF.chargerStep)
            if math.abs(GF.c.pOn - GF.c.p0 - GF.chargerStep) < 1e-6 and math.abs(p - GF.c.p0) <= 1e-7 then
                GF.enter("steps")
            else
                GF.res.abort = "the charger did not change G's load as expected"
                GF.phase = "done"
            end
        end
    elseif GF.phase == "steps" then
        if #GF.boundaries >= 3 and #GF.drops >= #GF.boundaries then
            GF.closeSteps()
            GF.enter("policy_tick")
        end
    elseif (GF.phase == "policy_tick" or GF.phase == "policy_minute") and GF.sizeAt then
        if GF.tick >= GF.sizeAt then
            g:setFuel(GF.power(g) + GF.eps)
            GF.refill, GF.late = GF.phase == "policy_tick" and "tick" or "minute", true
            GF.h0, GF.m0, GF.sizeAt = age, GF.minutes, nil
            report():line("OBS  MPS.gf %s sized at %.5f h: fuel %.7f for a load of %.7f", GF.phase, age, g:getFuel(),
                GF.power(g))
        end
    elseif GF.phase == "policy_tick" or GF.phase == "policy_minute" then
        if not on then
            GF.off = GF.off + 1
            if GF.off > 5 then
                g:setActivated(true)
                g:setFuel(GF.power(g) + GF.eps)
                GF.off = 0
            end
        else
            GF.off = 0
        end
        local counted = 0
        for _, at in ipairs(GF.attempts) do
            if at.rose and at.short and at.boundary then counted = counted + 1 end
        end
        local settled = not (GF.lastAttempt and GF.lastAttempt.boundary and GF.tick - GF.lastAttempt.boundary.tick <= 6)
        if ((counted >= 3 and #GF.boundaries >= 3) or #GF.boundaries >= 8) and settled then
            GF.closePolicy()
            if GF.phase == "policy_tick" then
                GF.enter("policy_minute")
            else
                GF.refill, GF.late = nil, false
                GF.charging(false)
                GF.phase = "done"
                report():line("OBS  MPS.gf done")
            end
        end
    end
    if GF.late and GF.charger then
        if GF.attempt == nil and GF.attemptHour ~= fl and GF.min59Hour == fl and on then
            GF.charging(true)
            GF.attempt = { hour = fl, at = age, powerBefore = p, rose = false }
            GF.attempts[#GF.attempts + 1] = GF.attempt
            GF.attemptHour = fl
        elseif GF.attempt and not GF.attempt.rose and p > GF.attempt.powerBefore + GF.chargerStep / 2 then
            GF.attempt.rose = true
            GF.attempt.short, GF.attempt.fuelAtRise, GF.attempt.refillsAtRise = f < p, f, GF.refills
        end
        if GF.attemptHour ~= fl and age - fl >= 0.5 and GF.charger:isActivated() then
            GF.charging(false)
            GF.trimFrom = p
        end
        -- Once the load has fallen back, the buffer is set down to it, so the
        -- next switch-on finds it sized for the lower load.
        if GF.trimFrom and p < GF.trimFrom - GF.chargerStep / 2 then
            if g:getFuel() > p + GF.eps then
                g:setFuel(p + GF.eps)
                GF.trims = GF.trims + 1
            end
            GF.trimFrom = nil
        end
    end
    if GF.refill == "tick" and g:isActivated() then
        local cap = GF.power(g) + GF.eps
        if g:getFuel() < cap - GF.eps / 2 then
            g:setFuel(cap)
            GF.refills = GF.refills + 1
        end
    end
    GF.lastFloor, GF.lastFuel, GF.lastPower, GF.lastOn = fl, g:getFuel(), GF.power(g), g:isActivated()
end

function GF.onMinute()
    local g = GF.g
    if g == nil or GF.phase == "none" or GF.phase == "done" then return end
    GF.minutes = GF.minutes + 1
    local age = getGameTime():getWorldAgeHours()
    local fl = math.floor(age)
    local f = g:getFuel()
    local minute = math.floor((age - fl) * 60 + 1e-4)
    if GF.minuteFloor ~= nil and fl > GF.minuteFloor then
        GF.marks[#GF.marks + 1] = { age = age, tick = GF.tick or 0, ms = GF.ms(), minute = minute,
            dropped = GF.refill == nil and GF.minuteFuel ~= nil and f < GF.minuteFuel - 1e-9 }
    end
    if minute == 59 then GF.min59Hour = fl end
    if GF.refill == "minute" and g:isActivated() then
        local cap = GF.power(g) + GF.eps
        if f < cap - GF.eps / 2 then
            g:setFuel(cap)
            GF.refills = GF.refills + 1
        end
    end
    GF.minuteFloor, GF.minuteFuel = fl, g:getFuel()
end

function services.setup_gasfeed(player, args)
    local gx, gy = S.CX + 6, S.CY + 6
    local out = {}
    if GF.g == nil then
        GF.res = {}
        GF.g = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), getCell():getGridSquare(gx, gy, 0))
        pcall(function()
            local cs = getCell():getGridSquare(gx + 2, gy, 0)
            GF.charger = IsoCarBatteryCharger.new(instanceItem("Base.CarBatteryCharger"), getCell(), cs)
            cs:AddSpecialObject(GF.charger)
            GF.battery = instanceItem("Base.CarBattery1")
            GF.battery:setUsedDelta(0)
            GF.charger:setBattery(GF.battery)
        end)
        GF.g:setConnected(true)
        GF.g:setFuel(1.0)
        GF.g:setActivated(true)
        GF.g:sync()
        GF.setting0 = GF.setting(GF.g)
        GF.chargerStep = 0.05 * GF.setting0
        GF.clear()
        Events.OnTick.Add(GF.onTick)
        Events.EveryOneMinute.Add(GF.onMinute)
        -- The load is read once G has updated, by the "charger" phase.
        GF.phase = "settle"
        GF.settleUntil = 120
    end
    out.gx, out.gy, out.setting = gx, gy, string.format("%.4f", GF.setting0)
    out.charger = tostring(GF.charger ~= nil)
    out.exterior = tostring(SandboxVars.AllowExteriorGenerator)
    out.sandbox = tostring(SandboxVars.GeneratorFuelConsumption)
    out.daylength = tostring(SandboxVars.DayLength)
    reply("setup_gasfeed", args, out)
end

-- The "settle" phase: 120 server ticks for G's first update to compute its
-- load before the charger is tried.
Events.OnTick.Add(function()
    if GF.phase ~= "settle" then return end
    GF.settleUntil = GF.settleUntil - 1
    if GF.settleUntil <= 0 then
        local g = GF.g
        report():line("OBS  MPS.gf placed: fuel %.7f, running %s, load %.7f, setting %.4f (SandboxVars %s), powering %s; " ..
            "charger %s", g:getFuel(), tostring(g:isActivated()), GF.power(g), GF.setting0,
            tostring(SandboxVars.GeneratorFuelConsumption), tostring(g:getItemsPowered()), tostring(GF.charger ~= nil))
        GF.phase = "charger"
    end
end)

function services.probe_gasfeed(player, args)
    local g = GF.g
    local out = { phase = GF.phase, found = tostring(g ~= nil) }
    if g then
        out.fuel = string.format("%.7f", g:getFuel())
        out.on = tostring(g:isActivated())
        out.load = string.format("%.7f", GF.power(g))
        out.age = string.format("%.5f", getGameTime():getWorldAgeHours())
    end
    for k, v in pairs(GF.res or {}) do out[k] = tostring(v) end
    reply("probe_gasfeed", args, out)
end

-- The Diesel Generator's sprite taken away on the server, as a load without
-- the mod leaves it (step "strip"), then the mod's repair run as the
-- server's LoadGridsquare runs it, on the generator's square (step
-- "repair"). A restart of the server without the mod is not played.
function services.sprite_repair(player, args)
    local g = generatorAt(tonumber(args.gx), tonumber(args.gy))
    local out = { found = tostring(g ~= nil), step = tostring(args.step) }
    local function name()
        local n = "none"
        pcall(function()
            local s = g:getSprite()
            n = s and tostring(s:getName()) or "none"
        end)
        return n
    end
    if g and args.step == "strip" then
        out.before = name()
        local ok = pcall(function() g:setSprite(nil) end)
        out.how = "setSprite(nil)"
        if not ok or name() == out.before then
            ok = pcall(function() g:setSprite(IsoSprite.new()) end)
            out.how = "a new sprite without a name"
        end
        out.ok = tostring(ok)
        out.sent = tostring(pcall(function() g:transmitUpdatedSpriteToClients() end))
        out.after = name()
    elseif g and args.step == "repair" then
        out.before = name()
        local ok, err = pcall(function() TLG.Integration.Generators.onLoadSquare(g:getSquare()) end)
        out.ok, out.err, out.after = tostring(ok), tostring(err), name()
    end
    reply("sprite_repair", args, out)
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

-- Wraps the mod's put-down (looked up at call time by its move hooks and
-- its landing watch) to log each one the server makes: the machine, its
-- square, the time it was put down from, and its record's pause before and
-- after. The death case reads from it when the vessel a dead carrier
-- dropped was put down (D-015 amendment).
local function watchPutDowns()
    local Machines = TLG and TLG.Integration and TLG.Integration.Machines
    if M.putDownsWatched or not (Machines and Machines.putDown) then return end
    M.putDownsWatched = true
    local orig = Machines.putDown
    Machines.putDown = function(item, now)
        local before = item and item:getModData().tlgProc
        local was = tostring(before and before.pause or "none")
        local ok, r = pcall(orig, item, now)
        local sq = item and Machines.square(item)
        local rec = item and item:getModData().tlgProc
        report():line("OBS  MPS.put_down of %s at %s from t=%.4f: pause %s -> %s, state %s%s", tostring(item and item:getID()),
            sq and (sq:getX() .. "," .. sq:getY()) or "nowhere", tonumber(now) or -1, was,
            tostring(rec and rec.pause or "none"), tostring(rec and rec.state), ok and "" or (" error " .. tostring(r)))
        if not ok then error(r, 0) end
        return r
    end
end

-- Whether OnTick fires on a dedicated server, where the mod's landing watch
-- runs on it (Machines.watchLanding): the first 300 ticks timed.
local function countTicks()
    local n, t0 = 0, getTimestampMs()
    local function tick()
        n = n + 1
        if n == 300 then
            Events.OnTick.Remove(tick)
            report():line("OBS  MPS.ticks 300 OnTick events in %d ms", getTimestampMs() - t0)
        end
    end
    Events.OnTick.Add(tick)
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
-- diesel 5 to 3, as the single-player mode's second leg poured them (ethanol
-- until 0.3.0, which now runs a stock engine lean: D-037).
function services.effects_blend(player, args)
    local V = TLG.Integration.Vehicles
    local v = efCar()
    local rec = V.read(v, true)
    local total = 0
    for _, q in pairs(rec.q) do total = total + q end
    rec.q = { gasoline = total * 5 / 8, diesel = total * 3 / 8 }
    rec.deg = { gasoline = rec.deg.gasoline or 0, diesel = 0 }
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
-- The wrong-fuel case (-Only wrongfuel; D-037 on a server). A petrol car, an
-- ambulance, a petrol generator and a Diesel Generator by the spawn point.
-- The server applies every rule: the start gates, the cost of a refused
-- start, wear and exhaust by the litre, a failure. Its draws are passed
-- through and written down (wfRecord), and each answer to the client carries
-- the draws since the answer before. Fixtures, as the single-player modes':
-- a tank's record rewritten in shares of the litres it holds (wf_set; the
-- litres come in through the game's own pour, which the client sees);
-- litres taken from a running engine's tank (wf_burn), with the stall draw
-- held meanwhile and, when asked, the failure draw held at 0.
------------------------------------------------------------------------------
local WFS = M.WFS or {}
M.WFS = WFS

local function wfObj(k)
    if k == "car" or k == "amb" then return WFS[k] and getVehicleById(WFS[k]) or nil, "vehicle" end
    return generatorAt(WFS[k .. "x"], WFS[k .. "y"]), "generator"
end

-- "id=number;id=number" as a table.
local function wfBlend(s)
    local q = {}
    for id, x in string.gmatch(s or "", "([^;=]+)=([^;]+)") do q[id] = tonumber(x) end
    return q
end

local function wfEval(e, out)
    out.compatible, out.harmful = tostring(e and e.compatible), tostring(e ~= nil and e.harmful == true)
    out.level, out.wrong = tostring(e and e.wrongLevel), tostring(e and e.wrongFuel)
    out.start, out.pf, out.wear = e and e.startFactor or -1, e and e.powerFactor or -1, e and e.wearFactor or -1
    out.failure, out.exhaust = tostring(e and e.failureChance), tostring(e and e.exhaustWear)
    out.attempt = e and e.attemptDamage and (tostring(e.attemptDamage[1]) .. "-" .. tostring(e.attemptDamage[2])) or "nil"
    out.reasons = e and e.reasons and table.concat(e.reasons, ",") or ""
    return out
end

-- What the server holds of `k`, with the draws since the last answer.
local function wfFacts(k, out)
    local V = TLG.Integration.Vehicles
    local o, kind = wfObj(k)
    if kind == "vehicle" and o then
        local engine, muffler, battery, tank = o:getPartById("Engine"), o:getPartById("Muffler"), o:getPartById("Battery"),
            o:getPartById("GasTank")
        local item = battery and battery:getInventoryItem()
        local fitted = muffler ~= nil and muffler:getInventoryItem() ~= nil
        out.cond = engine and engine:getCondition() or -1
        out.carry = engine and type(engine:getModData()[V.WEAR_KEY]) == "number" and engine:getModData()[V.WEAR_KEY] or 0
        out.muffler = fitted and muffler:getCondition() or -1
        out.mcarry = fitted and type(muffler:getModData()[V.WEAR_KEY]) == "number" and muffler:getModData()[V.WEAR_KEY] or 0
        out.charge = item and item:getCurrentUsesFloat() or -1
        out.running, out.power = tostring(o:isEngineRunning()), o:getEnginePower()
        out.tankL = tank and tank:getContainerContentAmount() or -1
        out.powerState = S.text(engine and engine:getModData()[V.POWER_KEY])
    elseif o then
        out.cond, out.on, out.fuel = o:getCondition(), tostring(o:isActivated()), o:getFuel()
    end
    out.found = tostring(o ~= nil)
    out.minute = WFS.minute or 0
    out.draws = table.concat(WFS.draws or {}, ";")
    WFS.draws = {}
    return out
end

local function wfRecord()
    local V, G = TLG.Integration.Vehicles, TLG.Integration.Generators
    if WFS.orig then return end
    local o = { V.startRoll, V.attemptRoll, V.attemptDamage, V.stallRoll, V.failRoll, G.startRoll, G.attemptRoll, G.attemptDamage,
        G.failRoll }
    WFS.orig, WFS.draws = o, {}
    local function note(k, x)
        local t = k
        if x ~= nil then t = k .. "=" .. (type(x) == "number" and string.format("%.4f", x) or tostring(x)) end
        WFS.draws[#WFS.draws + 1] = t
        return x
    end
    V.startRoll = function() return note("start", o[1]()) end
    V.attemptRoll = function(a, b) return note("roll", o[2](a, b)) end
    V.attemptDamage = function(v, e, p)
        note("refused")
        return note("points", o[3](v, e, p))
    end
    V.stallRoll = function()
        if WFS.holdStall then return 0.999 end
        return note("stall", o[4]())
    end
    V.failRoll = function()
        if WFS.holdFail then return note("failheld", 0) end
        return note("fail", o[5]())
    end
    G.startRoll = function() return note("gstart", o[6]()) end
    G.attemptRoll = function(a, b) return note("groll", o[7](a, b)) end
    G.attemptDamage = function(g, e, p)
        note("grefused")
        return note("gpoints", o[8](g, e, p))
    end
    G.failRoll = function()
        if WFS.holdGFail then return note("gfailheld", 0) end
        return note("gfail", o[9]())
    end
    Events.EveryOneMinute.Add(function() WFS.minute = (WFS.minute or 0) + 1 end)
end

local function wfUnrecord()
    local V, G, o = TLG.Integration.Vehicles, TLG.Integration.Generators, WFS.orig
    if o then
        V.startRoll, V.attemptRoll, V.attemptDamage, V.stallRoll, V.failRoll = o[1], o[2], o[3], o[4], o[5]
        G.startRoll, G.attemptRoll, G.attemptDamage, G.failRoll = o[6], o[7], o[8], o[9]
    end
    WFS.orig = nil
    WFS.holdStall, WFS.holdFail, WFS.holdGFail = nil, nil, nil
end

function services.setup_wrongfuel(player, args)
    local V, G = TLG.Integration.Vehicles, TLG.Integration.Generators
    local cell, inv = getCell(), player:getInventory()
    local function vehicle(script, dx)
        local v = addVehicleDebug(script, IsoDirections.N, nil, cell:getGridSquare(S.CX + dx, S.CY + 3, 0))
        if v == nil then return nil end
        -- Repaired as the single-player modes repair theirs, the engine and
        -- the exhaust sent to the clients, the battery full: the game's own
        -- start does not fail for them, and an exhaust is fitted.
        pcall(function() v:repair() end)
        local tank, engine, battery = v:getPartById("GasTank"), v:getPartById("Engine"), v:getPartById("Battery")
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        v:transmitPartModData(tank)
        engine:setCondition(100)
        v:transmitPartCondition(engine)
        local muffler = v:getPartById("Muffler")
        if muffler then pcall(function() v:transmitPartCondition(muffler) end) end
        local item = battery and battery:getInventoryItem()
        if item then
            item:setCurrentUsesFloat(1.0)
            v:transmitPartUsedDelta(battery)
        end
        local key = v:createVehicleKey()
        if key then sendAddItemToContainer(inv, inv:AddItem(key)) end
        return v
    end
    local car, amb = vehicle("Base.CarNormal", 3), vehicle("Base.VanAmbulance", 9)
    local g1x, g1y = S.spot(3)
    local g2x, g2y = S.spot(5)
    local g1 = emptyGenerator(g1x, g1y)
    local g2 = IsoGenerator.new(instanceItem("TLG.DieselGenerator"), cell, cell:getGridSquare(g2x, g2y, 0))
    g2:setFuel(0)
    g2:getModData().tlg = nil
    TLG.Authority.Vault.release("supply", G.keyOf(g2))
    TLG.Authority.Vault.release("project", G.keyOf(g2))
    for _, g in ipairs({ g1, g2 }) do
        g:setCondition(100)
        g:setConnected(true)
        g:sync()
        g:transmitModData()
    end
    WFS.car, WFS.amb = car and car:getId(), amb and amb:getId()
    WFS.g1x, WFS.g1y, WFS.g2x, WFS.g2y = g1x, g1y, g2x, g2y
    wfRecord()
    reply("wrongfuel_site", args, { car = tostring(WFS.car), amb = tostring(WFS.amb), g1x = g1x, g1y = g1y, g2x = g2x, g2y = g2y,
        carProfile = tostring(car and V.profile(car)), ambProfile = tostring(amb and V.profile(amb)),
        g1Profile = tostring(G.profile(g1)), g2Profile = tostring(G.profile(g2)),
        diesel = tostring(TLG.World.get().dieselVehicles), damage = tostring(V.wrongFuelDamageEnabled()),
        stalls = tostring(V.stallsEnabled()), carPower = car and car:getEnginePower() or -1,
        ambPower = amb and amb:getEnginePower() or -1, consumption = tostring(SandboxVars.CarGasConsumption),
        genConsumption = tostring(SandboxVars.GeneratorFuelConsumption), version = tostring(TLG.VERSION) })
end

-- A vehicle's or a generator's record rewritten as shares of the litres its
-- tank holds. Fresh fuel. Then the verdict.
function services.wf_set(player, args)
    local V, G = TLG.Integration.Vehicles, TLG.Integration.Generators
    local o, kind = wfObj(args.k)
    local q, out = wfBlend(args.q), {}
    if kind == "vehicle" then
        local total = o:getPartById("GasTank"):getContainerContentAmount()
        local rec = V.read(o, true)
        rec.q, rec.deg = {}, {}
        for id, share in pairs(q) do rec.q[id], rec.deg[id] = share * total, 0 end
        rec.rev = (rec.rev or 0) + 1
        V.writeSidecar(o, rec)
        V.lastTank[o:getId()] = nil
        wfEval(V.evaluate(o), out)
    else
        local total = o:getFuel()
        local rec = G.read(o, true)
        rec.q, rec.deg = {}, {}
        for id, share in pairs(q) do rec.q[id], rec.deg[id] = share * total, 0 end
        rec.rev = (rec.rev or 0) + 1
        G.writeSidecar(o, rec)
        wfEval((G.evaluate(o)), out)
    end
    reply("wf_set", args, wfFacts(args.k, out))
end

-- What the server holds now; with release, the held draws are let go.
function services.wf_probe(player, args)
    local o, kind = wfObj(args.k)
    local out = {}
    if o then
        if kind == "vehicle" then wfEval(TLG.Integration.Vehicles.evaluate(o), out)
        else wfEval((TLG.Integration.Generators.evaluate(o)), out) end
    end
    wfFacts(args.k, out)
    if args.release == "1" then WFS.holdStall, WFS.holdFail = nil, nil end
    reply("wf_probe", args, out)
end

function services.wf_hold(player, args)
    WFS.holdStall = args.stall == "1" or nil
    reply("wf_hold", args, { stall = tostring(WFS.holdStall == true), minute = WFS.minute or 0 })
end

-- Litres taken from a running engine's tank: the mod's next minute sees
-- them as burned.
function services.wf_burn(player, args)
    local v = wfObj(args.k)
    local tank = v:getPartById("GasTank")
    local out = wfFacts(args.k, {})
    WFS.holdStall = true
    WFS.holdFail = args.fail == "1" or nil
    tank:setContainerContentAmount(tank:getContainerContentAmount() - tonumber(args.litres))
    out.tankAfter = tank:getContainerContentAmount()
    reply("wf_burn", args, out)
end

-- The Diesel Generator, running: a litre gone, charged with the failure
-- draw held at 0.
function services.wf_gen_fail(player, args)
    local G = TLG.Integration.Generators
    local g = wfObj("g2")
    local out = { on0 = tostring(g:isActivated()), cond0 = g:getCondition() }
    G.chargeWear(g)
    g:setFuel(g:getFuel() - 1)
    WFS.holdGFail = true
    out.whole = G.chargeWear(g)
    WFS.holdGFail = nil
    g:sync()
    reply("wf_gen_fail", args, wfFacts("g2", out))
end

-- The sandbox option on the server, and the ambulance's verdict under it.
function services.wf_option(player, args)
    SandboxVars.TheLastGallon = SandboxVars.TheLastGallon or {}
    SandboxVars.TheLastGallon.WrongFuelDamage = args.on == "true"
    local out = wfEval(TLG.Integration.Vehicles.evaluate(wfObj("amb")), {})
    out.on = tostring(TLG.Integration.Vehicles.wrongFuelDamageEnabled())
    reply("wf_option", args, out)
end

function services.wf_cleanup(player, args)
    wfUnrecord()
    SandboxVars.TheLastGallon.WrongFuelDamage = true
    reply("wf_cleanup", args, { damage = tostring(TLG.Integration.Vehicles.wrongFuelDamageEnabled()) })
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

-- The death case (MPHarnessCases.lua, -Only death): the sender killed by the
-- server, should its own client's kill not take.
function services.kill(player, args)
    local ok, err = pcall(function()
        player:setGodMod(false)
        player:Kill(nil)
    end)
    reply("killed", args, { ok = tostring(ok), err = tostring(err), dead = tostring(player:isDead()) })
end

-- Whether a player's death fires these events on the server, what the
-- server's character then holds and where it stands, and how many machines
-- the mod watches land (Machines.onDeath, D-015 amendment).
local function deathSeen(event, c)
    if not instanceof(c, "IsoPlayer") then return end
    local p, s, sq = c:getPrimaryHandItem(), c:getSecondaryHandItem(), c:getSquare()
    local landing = TLG and TLG.Integration and TLG.Integration.Machines and TLG.Integration.Machines.landing
    report():line("OBS  MPS.%s %s at %s; hands %s/%s; machines watched to land %d", event, tostring(c:getUsername()),
        sq and (sq:getX() .. "," .. sq:getY()) or "nowhere", tostring(p and p:getFullType()), tostring(s and s:getFullType()),
        landing and #landing or -1)
end
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(c)
        local ok, err = pcall(deathSeen, "OnPlayerDeath", c)
        if not ok then report():line("STEPERR MPS.OnPlayerDeath :: %s", tostring(err)) end
    end)
end
if Events.OnCharacterDeath then
    Events.OnCharacterDeath.Add(function(c)
        local ok, err = pcall(deathSeen, "OnCharacterDeath", c)
        if not ok then report():line("STEPERR MPS.OnCharacterDeath :: %s", tostring(err)) end
    end)
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
        watchPutDowns()
        R:line("OBS  MPS.put_downs watched=%s", tostring(M.putDownsWatched == true))
        countTicks()
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

-- Security audit V-01 (AuditCases.lua): the mod's own reads of the forged
-- can, pump and generator on the server, through the vault (TLG/Authority/
-- Vault.lua), with each store as it was before the read and after it.
function services.probe_vault(player, args)
    local V = TLG.Authority.Vault
    local out = { active = tostring(V.active()) }
    local item = player:getInventory():getItemWithID(tonumber(args.id))
    if item then
        out.canBefore = S.sidecar(item)
        local rec = TLG.Integration.Containers.read(item, "item", true)
        out.canDeg = string.format("%.4f", rec and rec.deg and rec.deg.gasoline or -1)
        out.canStab = string.format("%.4f", rec and rec.stab or -1)
        out.canAfter = S.sidecar(item)
    end
    local pump = pumpAt(tonumber(args.px), tonumber(args.py))
    if pump then
        out.pumpBefore = S.text(pump:getModData().tlg)
        local rec = TLG.Integration.Stations.read(pump, true)
        out.pumpWater = string.format("%.4f", rec and rec.q.water or 0)
        out.pumpSediment = string.format("%.4f", rec and rec.q.sediment or 0)
        out.pumpAfter = S.text(pump:getModData().tlg)
    end
    local g = generatorAt(tonumber(args.gx), tonumber(args.gy))
    if g then
        out.genConvBefore = S.text(g:getModData().tlgConv)
        out.genProfile = tostring(TLG.Integration.Generators.profile(g))
        out.genConvAfter = S.text(g:getModData().tlgConv)
    end
    reply("probe_vault", args, out)
end

-- The vault's state on the server (V-01): whether it is in use, where its
-- own ids start, how many copies it holds, what its checks did since this
-- server started, the size of the server store as saved (Vault.bytes), and
-- the check of the given can and vessel now: for the vessel also its
-- readings and notes, and whether the vault keeps it compact (without them,
-- with their digests).
function services.probe_vault_stats(player, args)
    local V = TLG.Authority.Vault
    local store = TLG.World.store
    local v = store and store.vault
    local out = { active = tostring(V.active()), from = tostring(v and v.from), nextId = tostring(store and store.nextId),
        recs = tostring(v and TLG.Tables.count(v.recs or {})), storeBytes = tostring(store and V.bytes(store, 1e9)) }
    for k, n in pairs(V.stats) do out[k] = tostring(n) end
    local can = args.can and player:getInventory():getItemWithIDRecursiv(tonumber(args.can))
    if can then out.canCheck = select(2, V.check("supply", V.itemHolder(can), can:getModData().tlg)) end
    local vessel = args.vessel and vesselById(tonumber(args.vessel))
    if vessel then
        local raw = vessel:getModData().tlgProc
        out.vesselCheck = select(2, V.check("process", V.itemHolder(vessel), raw))
        out.vesselTemps = tostring(raw and raw.temps and TLG.Tables.count(raw.temps) or 0)
        out.vesselFires = tostring(raw and raw.fires and TLG.Tables.count(raw.fires) or 0)
        out.vesselBytes = tostring(raw and V.bytes(raw, 1e9))
        local e = v and raw and type(raw.id) == "string" and v.recs["process:" .. raw.id]
        out.entryBytes = tostring(e and V.bytes(e, 1e9))
        out.vesselCompact = tostring(e ~= nil and e ~= false and type(e.r) == "table" and e.r.temps == nil
            and e.r.fires == nil and type(e.d) == "table" and type(e.d.temps) == "number"
            and type(e.d.fires) == "number")
    end
    reply("probe_vault_stats", args, out)
end

-- -Restart -DropVault: the server store is saved without the vault, as the
-- mod saved it before the V-01 fix (commit fe50875), so the restarted
-- server starts a vault on a world that already has records.
function services.drop_vault(player, args)
    local store = TLG.World.store
    local had = store ~= nil and store.vault ~= nil
    if store then store.vault = nil end
    reply("drop_vault", args, { had = tostring(had), nextId = tostring(store and store.nextId) })
end
