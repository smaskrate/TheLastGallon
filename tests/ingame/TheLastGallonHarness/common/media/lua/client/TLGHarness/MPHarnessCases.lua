-- Multiplayer harness, further cases (tools/run-mp-harness.ps1 -Only
-- machines|fuel|conversion), built from MPHarness.lua's helpers (MP.h).
-- machines: a running vessel moved where no Lua sees it (the world menu's
-- Grab and the inventory's Drop are item transactions on a client, D-015),
-- and two players loading one fermenter at once.
-- Results: <cachedir>/Lua/TLG_harness_mp.txt, as MPHarness.lua's.
require "TLGHarness/MPHarness"

local MP = TLGH.MP
if not MP or not MP.h then return end
local S = TLGH.MPShared
local h = MP.h
local report, player, check, send, call, once, wait = h.report, h.player, h.check, h.send, h.call, h.once, h.wait
local waitFrom, nextFrom, request, brief, walkTo, idle = h.waitFrom, h.nextFrom, h.request, h.brief, h.walkTo, h.idle
local floorItem, inventoryItem, countType, ids = h.floorItem, h.inventoryItem, h.countType, h.ids

local V = "TLG.FermenterVessel"
local C = {}
MP.C = C

-- The server's view of vessel `idFn()` (MPServer.lua probe_vessel), logged,
-- then judged.
local function probe(name, idFn, judge)
    return call(name, "probe_vessel", function() return { id = idFn() } end, "probe_vessel", function(m)
        report():line("OBS  MP.%s server: where=%s state=%s pause=%s site=%s listed=%s t=%.4f seen=%.4f done=%.4f"
            .. " now=%.4f inputs=%s takes=%s", name, tostring(m.where), tostring(m.state), tostring(m.pause),
            tostring(m.site), tostring(m.listed), tonumber(m.t) or -1, tonumber(m.seen) or -1, tonumber(m.done) or -1,
            tonumber(m.now) or -1, tostring(m.inputs), tostring(m.takes))
        judge(m)
    end)
end

-- Vessel `id` as this client sees it: in the inventory, or lying within
-- S.R squares of the spawn point.
local function findVessel(id)
    local item = inventoryItem(id)
    for x = S.CX - S.R, S.CX + S.R do
        for y = S.CY - S.R, S.CY + S.R do
            local sq = item == nil and getCell():getGridSquare(x, y, 0)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getID() == id then item = it end
            end
        end
    end
    return item
end

-- machine.status for vessel `idFn()` as the mod's menu asks it, from where
-- this client sees the vessel. A record moves on only when it is accessed.
local function status(name, idFn, judge)
    return request(name, "machine.status", function()
        local item = findVessel(idFn())
        return item and { target = TLG.Integration.Machines.refFor(item) }
    end, function(r)
        report():line("OBS  MP.%s reply: %s pause=%s stage=%s rev=%s", name, brief(r), tostring(r.pause),
            tostring(r.stage), tostring(r.rev))
        judge(r)
    end)
end

------------------------------------------------------------------------------
-- machines, A: a running vessel grabbed through the world menu, asked about
-- while carried, dropped through the inventory and asked about again.
------------------------------------------------------------------------------
local function gId() return C.grabId end

C.spawnGrab = call("spawn_grab_vessel", "spawn", function()
    local x, y = S.spot(3)
    return { item = V, x = x, y = y, batch = "1" }
end, "spawned", function(m) C.grabId = tonumber(m.id) end)

C.grabBefore = probe("grab_before", gId, function(m)
    C.takesBefore = m.takes or ""
    local x, y = S.spot(3)
    check("grab_vessel_running_on_the_floor", function()
        return m.where == "floor " .. x .. "," .. y and m.state == "Processing", "see the server's line above"
    end)
end)

-- The world menu's Grab (ISWorldObjectContextMenu.onGrabWItem): on a
-- client it queues an inventory transfer, which the server runs as an item
-- transaction.
C.grab = { name = "mp_grab_vessel", timeout = 2400, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local x, y = S.spot(3)
        local item = floorItem(x, y, V)
        local wi = item and item:getWorldItem()
        if not wi then
            report():line("FAIL MP.grab_queued_%s :: no vessel on %d,%d", MP.role, x, y)
            return true
        end
        ISWorldObjectContextMenu.onGrabWItem(nil, wi, 0)
        ctx.queued = ticks
        report():line("OBS  MP.grab queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    if ticks - ctx.idle < 120 then return nil end
    check("grab_in_the_inventory", function()
        local item = inventoryItem(C.grabId)
        return item ~= nil and not h.inBothHands(p, V), string.format("in the inventory=%s, in both hands=%s",
            tostring(item ~= nil), tostring(h.inBothHands(p, V)))
    end)
    return true
end }

C.grabbed = probe("grab_after", gId, function(m)
    local since = string.sub(m.takes or "", #(C.takesBefore or "") + 1)
    report():line("OBS  MP.grab the record right after the grab: state=%s pause=%s (a move no Lua sees leaves it as"
        .. " it was until the next access)", tostring(m.state), tostring(m.pause))
    check("grab_on_the_server_no_take", function()
        return m.where == "inventory tlga" and since == "", "where=" .. tostring(m.where) .. " takes since:" .. since
    end)
end)

C.statusCarried = status("grab_status_carried", gId, function(r)
    check("grab_status_carried_paused", function()
        return r.ok == true and r.state == "Paused" and r.pause == "not_placed", "see the reply above"
    end)
end)

C.carried1 = probe("grab_carried_1", gId, function(m) C.done1 = tonumber(m.done) end)
C.statusCarried2 = status("grab_status_carried_again", gId, function() end)
C.carried2 = probe("grab_carried_2", gId, function(m)
    check("grab_nothing_counted_while_carried", function()
        return m.state == "Paused" and tonumber(m.done) == C.done1, string.format("done %.4f then %.4f",
            C.done1 or -1, tonumber(m.done) or -1)
    end)
end)

C.drop = { name = "mp_drop_grabbed_vessel", timeout = 2400, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local item = inventoryItem(C.grabId)
        if not item then
            report():line("FAIL MP.grab_dropped_%s :: not in the inventory", MP.role)
            return true
        end
        ISInventoryPaneContextMenu.dropItem(item, 0)
        ctx.queued = ticks
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    return ticks - ctx.idle >= 120 or nil
end }

C.dropped = probe("grab_dropped", gId, function(m)
    C.dropSite = string.match(m.where or "", "^floor (.+)$")
    report():line("OBS  MP.grab the record right after the drop: state=%s pause=%s", tostring(m.state), tostring(m.pause))
    check("grab_dropped_on_the_floor", function() return C.dropSite ~= nil, "where=" .. tostring(m.where) end)
end)

C.statusDropped = status("grab_status_dropped", gId, function(r)
    check("grab_status_dropped_processing", function()
        return r.ok == true and r.state == "Processing", "see the reply above"
    end)
end)

C.placed1 = probe("grab_placed_1", gId, function(m)
    C.done3 = tonumber(m.done)
    check("grab_listed_where_it_lies", function()
        return m.state == "Processing" and m.site == C.dropSite and m.listed == C.dropSite, "see the server's line above"
    end)
end)
C.statusPlaced2 = status("grab_status_placed_again", gId, function() end)
C.placed2 = probe("grab_placed_2", gId, function(m)
    check("grab_runs_again_after_the_drop", function()
        return m.state == "Processing" and (tonumber(m.done) or 0) > (C.done3 or 0), string.format("done %.4f then %.4f",
            C.done3 or -1, tonumber(m.done) or -1)
    end)
end)

------------------------------------------------------------------------------
-- machines, A and B: one empty fermenter, both players loading it at once
-- as the mod's menu does (machine.loadFerment with the target alone). Each
-- carries 2 kg of sugar, a yeast and 10 L of water in a bucket.
------------------------------------------------------------------------------
local function fId() return C.loadId end
local LOAD = { items = "Base.Sugar;Base.Sugar;Base.Yeast;Base.BucketEmpty", water = "10" }

local function water()
    local litres, list = 0, player():getInventory():getItemsFromFullType("Base.BucketEmpty")
    for i = 0, (list and list:size() or 0) - 1 do
        local fc = list:get(i):getFluidContainer()
        if fc then litres = litres + fc:getAmount() end
    end
    return litres
end

local function carried() return string.format("sugar=%d yeast=%d water=%.1f", countType("Base.Sugar"),
    countType("Base.Yeast"), water()) end

C.spawnLoad = call("spawn_load_vessel", "spawn", function()
    local x, y = S.spot(-2)
    return { item = V, x = x, y = y }
end, "spawned", function(m) C.loadId = tonumber(m.id) end)

C.give = call("give_feedstock", "give", LOAD, "given", function() end)

C.haveFeed = { name = "mp_have_feedstock", timeout = 900, fn = function(ctx, ticks)
    if ticks < 60 then return nil end
    if countType("Base.Sugar") < 2 and ticks < 600 then return nil end
    C.before = carried()
    report():line("OBS  MP.load %s carries %s", MP.role, C.before)
    return true
end }

-- Sends the load as soon as `go` says so; the reply and the carried items
-- after it are kept for the check.
local function loadNow(first)
    return { name = "mp_load_now", timeout = 3600, fn = function(ctx, ticks)
        if not ctx.sent then
            if first then
                send("load_now", {})
            elseif not nextFrom("load_now") then
                return nil
            end
            local x, y = S.spot(-2)
            local item = floorItem(x, y, V)
            if not item then
                report():line("FAIL MP.load_sent_%s :: no vessel on %d,%d", MP.role, x, y)
                return true
            end
            ctx.sent = ticks
            TLG.Net.request("machine.loadFerment", { target = TLG.Integration.Machines.refFor(item) },
                function(r) ctx.reply = r end)
            report():line("OBS  MP.load %s sent at tick %d", MP.role, ticks)
            return nil
        end
        if not ctx.reply or ticks - ctx.sent < 120 then return nil end
        local r = ctx.reply
        C.reply, C.after = r, carried()
        report():line("OBS  MP.load %s reply: %s sugarKg=%s waterL=%s; carries %s", MP.role, brief(r),
            tostring(r.sugarKg), tostring(r.waterL), C.after)
        check("load_items_follow_the_reply", function()
            local all = C.after == "sugar=0 yeast=0 water=0.0"
            return (r.ok == true and all) or (r.ok ~= true and C.after == C.before),
                string.format("ok=%s; before %s, after %s", tostring(r.ok), tostring(C.before), C.after)
        end)
        send("load_result", { ok = tostring(r.ok), reason = tostring(r.reason) })
        return true
    end }
end

C.loadBoth = waitFrom("mp_wait_load_result", "load_result", function(m)
    local mine = C.reply or {}
    local okA, okB = mine.ok == true, m.ok == "true"
    report():line("OBS  MP.load A ok=%s reason=%s; B ok=%s reason=%s", tostring(okA), tostring(mine.reason),
        tostring(okB), tostring(m.reason))
    check("load_one_of_two_players", function()
        local busy = okA and m.reason or mine.reason
        return okA ~= okB and busy == "machine_busy", string.format("A ok=%s, B ok=%s, the other's reason %s",
            tostring(okA), tostring(okB), tostring(busy))
    end)
end)

------------------------------------------------------------------------------
-- machines, A: a vessel taken out of a crate (the container nearest the
-- spawn point; MPServer.lua crate_vessel) as a double-click in the loot
-- window takes it (equipHeavyItem, which walks to the container). From a
-- container the game's own complete works on a server, and the mod's take
-- leaves it to it (D-030).
------------------------------------------------------------------------------
local function crateId() return C.crateSite and tonumber(C.crateSite.id) end

C.crate = call("crate_vessel", "crate_vessel", {}, "crated", function(m)
    C.crateSite = m
    report():line("OBS  MP.crate vessel %s put in a %s at %s,%s %s", tostring(m.id), tostring(m.type), tostring(m.x),
        tostring(m.y), tostring(m.error or ""))
end)

C.takeFromCrate = { name = "mp_take_from_crate", timeout = 3600, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local s = C.crateSite
        local sq = s and s.x and getCell():getGridSquare(tonumber(s.x), tonumber(s.y), 0)
        local objs = sq and sq:getObjects()
        local item
        for i = 0, (objs and objs:size() or 0) - 1 do
            local c = objs:get(i):getContainer()
            item = item or (c and c:getItemWithID(crateId()))
        end
        if not item then
            if ticks < 600 then return nil end
            report():line("FAIL MP.crate_vessel_listed_%s :: this client does not see the vessel in the container", MP.role)
            return true
        end
        ISInventoryPaneContextMenu.equipHeavyItem(p, item)
        ctx.queued = ticks
        report():line("OBS  MP.crate take queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
    ctx.idle = ctx.idle or ticks
    if ticks - ctx.idle < 120 then return nil end
    local held = p:getPrimaryHandItem()
    check("crate_vessel_in_both_hands", function()
        return h.inBothHands(p, V) and held:getID() == crateId(), string.format("primary=%s id=%s",
            tostring(held and held:getFullType()), tostring(held and held:getID()))
    end)
    return true
end }

C.crateSeen = probe("crate_after", crateId, function(m)
    -- Trimmed: the first take of a run has no space before it (run 166).
    local since = string.match(string.sub(m.takes or "", #(C.takesBeforeCrate or "") + 1), "^%s*(.-)%s*$")
    report():line("OBS  MP.crate the server's takes since: %s", since)
    check("crate_vessel_left_to_the_game_on_server", function()
        return m.where == "inventory tlga both hands" and since == "tlga:nil", "where=" .. tostring(m.where)
            .. " takes since: " .. since
    end)
end)

C.loaded = probe("load_server", fId, function(m)
    C.takesBeforeCrate = m.takes or ""
    check("load_server_batch_from_one", function()
        return m.state == "Processing" and m.inputs == "{sugar_eq=2.0000,water=10.0000}", "see the server's line above"
    end)
end)

------------------------------------------------------------------------------
-- fuel, A: the single-player chain's hops at the Gas2Go pumps, each queued
-- through the game's own menu functions (which walk and equip as a click
-- does), with the server's view after each (MPServer.lua setup_fuel,
-- probe_fuel). The mod's pour is queued as its menu queues it, with the
-- harness's own result callback.
------------------------------------------------------------------------------
local FU = { ids = {} }
MP.FU = FU

local function site(k) return FU.site and tonumber(FU.site[k]) end

local function fuelArgs()
    local s = FU.site or {}
    return { px = s.px, py = s.py, car = s.car, g1x = s.g1x, g1y = s.g1y, g2x = s.g2x, g2y = s.g2y,
        ids = table.concat(FU.ids, ";") }
end

local function pumpObj()
    local sq = FU.site and getCell():getGridSquare(site("px"), site("py"), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if objs:get(i):getPipedFuelAmount() > 0 then return objs:get(i) end
    end
    return nil
end

local function car() return FU.site and getVehicleById(site("car")) end

local function tank()
    local v = car()
    return v and v:getPartById("GasTank")
end

local function gen(k)
    local sq = FU.site and getCell():getGridSquare(site("g" .. k .. "x"), site("g" .. k .. "y"), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
    end
    return nil
end

local function canL(key)
    local it = inventoryItem(FU[key])
    local fc = it and it:getFluidContainer()
    return fc and fc:getAmount() or -1
end

local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) <= (tol or 1e-3) end

local function probeFuel(name, judge)
    return call(name, "probe_fuel", fuelArgs, "probe_fuel", function(m)
        report():line("OBS  MP.%s server: pump units=%s %s", name, tostring(m.pumpUnits), tostring(m.pumpSide))
        report():line("OBS  MP.%s server: tank %.4f L, record %.4f L, engine running=%s %s", name,
            tonumber(m.tankL) or -1, tonumber(m.tankRecL) or -1, tostring(m.engine), tostring(m.tankSide))
        for _, k in ipairs({ "g1", "g2" }) do
            report():line("OBS  MP.%s server: %s fuel %.4f L, record %.4f L, on=%s %s", name, k,
                tonumber(m[k .. "Fuel"]) or -1, tonumber(m[k .. "RecL"]) or -1, tostring(m[k .. "On"]),
                tostring(m[k .. "Side"]))
        end
        report():line("OBS  MP.%s server: carried generator record %.4f L %s; items %s", name,
            tonumber(m.genItemRecL) or -1, tostring(m.genItemSide), tostring(m.items))
        judge(m)
    end)
end

-- A step that queues `queue(ctx, player)` once and waits until the player's
-- actions are done and `settle` ticks more have passed.
local function act(name, queue, settle)
    return { name = "mp_" .. name, timeout = 7200, fn = function(ctx, ticks)
        local p = player()
        if not ctx.queued then
            local ok, err = pcall(queue, ctx, p)
            if not ok then
                report():line("FAIL MP.%s_queued_%s :: %s", name, MP.role, tostring(err))
                return true
            end
            ctx.queued = ticks
            report():line("OBS  MP.%s queued: %s", name, h.actionNames(p))
            return nil
        end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        return ticks - ctx.idle >= (settle or 120) or nil
    end }
end

local function giveCan(name, args, key)
    local a = { items = "Base.PetrolCan" }
    for k, v in pairs(args) do a[k] = v end
    return call(name, "give", a, "given", function(m)
        local got = ids(m.ids)["Base.PetrolCan"]
        FU[key] = got and got[1]
        FU.ids[#FU.ids + 1] = tostring(FU[key])
    end)
end

local function arrived(key)
    return { name = "mp_" .. key .. "_arrives", timeout = 900, fn = function(ctx, ticks)
        if inventoryItem(FU[key]) == nil and ticks < 600 then return nil end
        report():line("OBS  MP.%s in the inventory=%s, %.4f L", key, tostring(inventoryItem(FU[key]) ~= nil), canL(key))
        return true
    end }
end

-- This client's line for item `key` as probe_fuel writes it.
local function itemText(key)
    local it = inventoryItem(FU[key])
    local fc = it and it:getFluidContainer()
    return tostring(FU[key]) .. "=" .. (fc and string.format("%.4f", fc:getAmount()) or "nil") .. " " .. S.sidecar(it)
end

FU.setup = call("fuel_site", "setup_fuel", {}, "fuel_site", function(m)
    FU.site = m
    report():line("OBS  MP.fuel site: pump %s,%s (%s units), car %s, generators %s,%s and %s,%s %s", tostring(m.px),
        tostring(m.py), tostring(m.units), tostring(m.car), tostring(m.g1x), tostring(m.g1y), tostring(m.g2x),
        tostring(m.g2y), tostring(m.error or ""))
end)

FU.seen = once("mp_fuel_site_seen", function()
    local t = tank()
    check("fuel_site_seen", function()
        return pumpObj() ~= nil and car() ~= nil and t ~= nil and near(t:getContainerContentAmount(), 0) and gen(1) ~= nil
            and gen(2) ~= nil and near(gen(1):getFuel(), 0) and near(gen(2):getFuel(), 0),
            string.format("pump=%s car=%s tank=%s g1=%s g2=%s", tostring(pumpObj() ~= nil), tostring(car() ~= nil),
                tostring(t and t:getContainerContentAmount()), tostring(gen(1) and gen(1):getFuel()),
                tostring(gen(2) and gen(2):getFuel()))
    end)
end)

FU.pumpToCan = act("pump_to_can", function(ctx, p)
    FU.units0 = pumpObj():getPipedFuelAmount()
    ISWorldObjectContextMenu.onTakeFuelNew(nil, pumpObj(), nil, inventoryItem(FU.can1), 0)
end, 180)

FU.afterPumpToCan = probeFuel("after_pump_to_can", function(m)
    FU.can1L = canL("can1")
    check("pump_to_can", function()
        return FU.can1L > 0 and string.find(m.items or "", itemText("can1"), 1, true) ~= nil and m.pumpSide ~= "nil"
            and tonumber(m.pumpUnits) < (FU.units0 or 0), string.format("can %.4f L; this client %s", FU.can1L,
            itemText("can1"))
    end)
end)

FU.canToCar = act("can_to_car", function(ctx, p) ISVehiclePartMenu.onAddGasoline(p, tank()) end, 180)

FU.afterCanToCar = probeFuel("after_can_to_car", function(m)
    FU.tank1 = tonumber(m.tankL)
    check("can_to_car", function()
        return (FU.can1L or 0) > 0 and near(FU.tank1, FU.can1L, 2e-3) and near(tonumber(m.tankRecL), FU.tank1, 2e-3)
            and near(tank():getContainerContentAmount(), FU.tank1, 2e-3), string.format("can had %.4f L; server tank"
            .. " %.4f L, record %.4f L; this client's tank %.4f L", FU.can1L or -1, FU.tank1 or -1,
            tonumber(m.tankRecL) or -1, tank():getContainerContentAmount())
    end)
end)

-- The two actions ISVehiclePartMenu.onPumpGasoline queues, with the
-- station's pump: its own search looks two squares round the filler, and
-- the car stands where the single-player chain parks it.
FU.pumpToCar = act("pump_to_car", function(ctx, p)
    FU.units1 = pumpObj():getPipedFuelAmount()
    local part = tank()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, part:getVehicle(), part:getArea()))
    ISTimedActionQueue.add(ISRefuelFromGasPump:new(p, part, pumpObj()))
end, 180)

FU.afterPumpToCar = probeFuel("after_pump_to_car", function(m)
    FU.tank2 = tonumber(m.tankL)
    FU.tank2b = FU.tank2
    check("pump_to_car", function()
        return FU.tank2 > (FU.tank1 or 0) + 1 and near(tonumber(m.tankRecL), FU.tank2, 2e-3)
            and tonumber(m.pumpUnits) < (FU.units1 or 0), string.format("tank %.4f -> %.4f L, record %.4f L",
            FU.tank1 or -1, FU.tank2 or -1, tonumber(m.tankRecL) or -1)
    end)
end)

-- Siphoning (the game's own menu: ISVehiclePartMenu.onTakeGasoline, with a
-- rubber hose, the item tagged base:siphongas) back into the can poured
-- into the car, which the menu prefers while it is still in hand.
FU.giveHose = call("give_hose", "give", { items = "Base.RubberHose" }, "given", function() end)

FU.siphon = act("siphon", function(ctx, p) ISVehiclePartMenu.onTakeGasoline(p, tank()) end, 180)

FU.afterSiphon = probeFuel("after_siphon", function(m)
    local can, rec = canL("can1"), tonumber(m["recL" .. tostring(FU.can1)])
    FU.tank2 = tonumber(m.tankL)
    check("siphon_car_to_can", function()
        return can > 0 and near(FU.tank2 + can, FU.tank2b, 2e-3) and near(tonumber(m.tankRecL), FU.tank2, 2e-3)
            and near(rec, can, 2e-3), string.format("tank %.4f -> %.4f L, record %.4f L; can %.4f L, record %.4f L",
            FU.tank2b or -1, FU.tank2 or -1, tonumber(m.tankRecL) or -1, can, rec or -1)
    end)
end)

FU.canToGen = act("can_to_generator", function(ctx, p)
    ISWorldObjectContextMenu.doAddFuelGenerator(nil, gen(1), nil, inventoryItem(FU.can2), 0)
end, 180)

FU.afterCanToGen = probeFuel("after_can_to_generator", function(m)
    FU.g1a = tonumber(m.g1Fuel)
    check("can_to_generator", function()
        return near(FU.g1a, 5, 2e-3) and near(tonumber(m.g1RecL), FU.g1a, 2e-3) and near(canL("can2"), 0),
            string.format("generator %.4f L, record %.4f L; can %.4f L", FU.g1a or -1, tonumber(m.g1RecL) or -1,
            canL("can2"))
    end)
end)

-- The mod's pour, queued as its menu queues it (FuelContextMenu.queuePour)
-- with the harness's own callback in place of the menu's messages.
local function pour(name, canKey, k, experimental)
    return act(name, function(ctx, p)
        FU[name] = nil
        local g = gen(k)
        ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU[canKey]),
            TLG.Authority.Resolver.refForObject(g, "generator"), g, experimental, function(r) FU[name] = r end))
    end, 180)
end

local function pourReached(name)
    return once("mp_" .. name .. "_result", function()
        local r = FU[name]
        report():line("OBS  MP.%s result on the player's client: %s", name, r and brief(r) or "none")
        check(name .. "_result_reaches_the_player", function()
            return r ~= nil, r and brief(r) or "the pour's callback never ran on the client"
        end)
    end)
end

FU.afterPourPetrol = probeFuel("after_pour_petrol", function(m)
    FU.g1b = tonumber(m.g1Fuel)
    check("pour_petrol_into_generator", function()
        return near(FU.g1b, (FU.g1a or 0) + 3, 2e-3) and near(tonumber(m.g1RecL), FU.g1b, 2e-3) and near(canL("can3"), 0),
            string.format("generator %.4f -> %.4f L, record %.4f L; can %.4f L", FU.g1a or -1, FU.g1b or -1,
            tonumber(m.g1RecL) or -1, canL("can3"))
    end)
end)

FU.afterPourEthanol = probeFuel("after_pour_ethanol", function(m)
    check("pour_ethanol_refused_nothing_moved", function()
        return near(tonumber(m.g1Fuel), FU.g1b, 1e-6) and near(canL("can4"), 3, 1e-6), string.format(
            "generator %.4f L (was %.4f); can %.4f L", tonumber(m.g1Fuel) or -1, FU.g1b or -1, canL("can4"))
    end)
end)

FU.afterPourConfirmed = probeFuel("after_pour_ethanol_confirmed", function(m)
    check("pour_ethanol_confirmed_into_empty_generator", function()
        return near(tonumber(m.g2Fuel), 3, 2e-3) and near(tonumber(m.g2RecL), 3, 2e-3) and near(canL("can4"), 0),
            string.format("generator 2 %.4f L, record %.4f L; can %.4f L", tonumber(m.g2Fuel) or -1,
            tonumber(m.g2RecL) or -1, canL("can4"))
    end)
end)

local function switch(name, k, on)
    return act(name, function(ctx, p) ISWorldObjectContextMenu.onActivateGenerator(nil, on, gen(k), 0) end, 180)
end

FU.afterStarts = probeFuel("after_generator_starts", function(m)
    FU.g1c = tonumber(m.g1Fuel)
    check("generator_on_petrol_starts", function() return m.g1On == "true", "g1 on=" .. tostring(m.g1On) end)
    check("generator_on_ethanol_refused", function() return m.g2On == "false", "g2 on=" .. tostring(m.g2On) end)
end)

-- The generator's record is reconciled with the game's burn when it is
-- read: the mod's status request reads it as a player looking at it does.
-- The reply gives the record as reconciled then (status writes nothing; the
-- next write keeps it: the take below carries the burned amount).
FU.genStatus = request("generator_status", "status", function()
    local g = gen(1)
    return g and { target = TLG.Authority.Resolver.refForObject(g, "generator") }
end, function(r)
    FU.genTotal = tonumber(r.total)
    report():line("OBS  MP.generator_status reply: %s total=%s", brief(r), tostring(r.total))
end)

FU.afterBurn = probeFuel("after_generator_burn", function(m)
    check("generator_burn_followed", function()
        return tonumber(m.g1Fuel) < (FU.g1c or 0) and near(FU.genTotal, tonumber(m.g1Fuel), 2e-3),
            string.format("fuel %.4f -> %.4f L; the status's record %.4f L", FU.g1c or -1, tonumber(m.g1Fuel) or -1,
            FU.genTotal or -1)
    end)
    FU.g1d = tonumber(m.g1Fuel)
end)

-- Taken as a player takes it: unplugged first (ISTakeGenerator.isValid
-- refuses a connected one; run 156 took nothing).
FU.unplug = act("unplug_generator", function(ctx, p)
    ISWorldObjectContextMenu.onPlugGenerator(nil, gen(1), 0, false)
end, 120)

FU.take = act("take_generator", function(ctx, p) ISWorldObjectContextMenu.onTakeGenerator(nil, gen(1), 0) end, 180)

FU.afterTake = probeFuel("after_take_generator", function(m)
    FU.taken = m.g1Fuel == -1 and m.genItemSide ~= "nil"
    check("generator_record_on_the_item", function()
        return m.g1Fuel == -1 and m.genItemSide ~= "nil" and near(tonumber(m.genItemRecL), FU.g1d, 2e-3),
            string.format("object fuel %s; item record %.4f L (generator had %.4f L)", tostring(m.g1Fuel),
            tonumber(m.genItemRecL) or -1, FU.g1d or -1)
    end)
end)

FU.place = act("place_generator", function(ctx, p)
    local it = p:getInventory():getFirstTypeRecurse("Base.Generator")
    ISTimedActionQueue.add(ISDropWorldItemAction:new(p, it, getCell():getGridSquare(site("g1x"), site("g1y"), 0),
        0.5, 0.5, 0, 0, false))
end, 180)

FU.afterPlace = probeFuel("after_place_generator", function(m)
    check("generator_record_back_on_the_object", function()
        return FU.taken and near(tonumber(m.g1Fuel), FU.g1d, 2e-3) and near(tonumber(m.g1RecL), FU.g1d, 2e-3),
            string.format("object fuel %.4f L, record %.4f L (carried %.4f L)", tonumber(m.g1Fuel) or -1,
            tonumber(m.g1RecL) or -1, FU.g1d or -1)
    end)
end)

FU.enter = act("enter_car", function(ctx, p) ISVehicleMenu.onEnter(p, car(), 0) end, 120)

-- Up to three tries, as the single-player gate step's (a start can fail by
-- chance: the mod's gate weighs the fuel's quality, run 159 failed once).
FU.start = { name = "mp_start_car", timeout = 7200, fn = function(ctx, ticks)
    local p = player()
    if not ctx.t then
        ctx.attempts, ctx.t = 1, ticks
        ISVehicleMenu.onStartEngine(p)
        return nil
    end
    if ticks - ctx.t < 300 or not TLGH.Steps.actionsIdle(p) then return nil end
    local v = car()
    if (v and v:isEngineRunning()) or ctx.attempts >= 3 then
        report():line("OBS  MP.start_car running=%s after %d attempt(s)", tostring(v and v:isEngineRunning()), ctx.attempts)
        return true
    end
    ctx.attempts, ctx.t = ctx.attempts + 1, ticks
    ISVehicleMenu.onStartEngine(p)
    return nil
end }

FU.afterStart = probeFuel("after_car_start", function(m)
    FU.tank3 = tonumber(m.tankL)
    check("car_starts_on_station_fuel", function()
        return m.engine == "true", string.format("engine running=%s; driver=%s", tostring(m.engine),
            tostring(car() and car():isDriver(player())))
    end)
end)

-- As the generator's: the tank's record is reconciled with the game's burn
-- when it is read (Vehicles.read; the per-minute pass only decides stalls).
FU.carStatus = request("car_status", "status", function()
    return FU.site and { target = { kind = "vehicle", id = site("car") } }
end, function(r)
    FU.carTotal = tonumber(r.total)
    report():line("OBS  MP.car_status reply: %s total=%s", brief(r), tostring(r.total))
end)

FU.afterIdle = probeFuel("after_car_idle", function(m)
    check("car_idle_burn_followed", function()
        return tonumber(m.tankL) < (FU.tank3 or 0) and near(FU.carTotal, tonumber(m.tankL), 2e-3),
            string.format("tank %.4f -> %.4f L; the status's record %.4f L", FU.tank3 or -1, tonumber(m.tankL) or -1,
            FU.carTotal or -1)
    end)
end)

------------------------------------------------------------------------------
-- conversion, A: a generator converted at the workshop as its menu does it
-- (WorkshopMenu: conversion.begin, conversion.deliver, then Menu.work's
-- ISTLGConversionWork, which reports as world time passes), on the shortest
-- day (the launcher's DayLength 1); then ethanol poured into it without a
-- confirmation, and the generator started on it.
------------------------------------------------------------------------------
local CV = {}
MP.CV = CV

local function cvGen()
    local sq = CV.site and getCell():getGridSquare(tonumber(CV.site.x), tonumber(CV.site.y), 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then return objs:get(i) end
    end
    return nil
end

local function cvRef()
    local g = cvGen()
    return g and TLG.Authority.Resolver.refForObject(g, "generator")
end

CV.setup = call("conversion_site", "setup_conversion", {}, "conversion_site", function(m)
    CV.site = m
    report():line("OBS  MP.conversion generator at %s,%s; the server's player: Mechanics %s, Electricity %s",
        tostring(m.x), tostring(m.y), tostring(m.mechanics), tostring(m.electricity))
end)

-- The same skills and recipe on this client, as the single-player loop sets
-- them.
CV.train = once("mp_train", function()
    local p = player()
    p:setPerkLevelDebug(Perks.Mechanics, 4)
    p:setPerkLevelDebug(Perks.Electricity, 2)
    p:getKnownRecipes():add("Generator")
end)

local function convRequest(name, command, extra, judge)
    return request(name, command, function()
        local ref = cvRef()
        if not ref then return nil end
        local a = { device = ref }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end, function(r)
        report():line("OBS  MP.%s reply: %s stage=%s missing=%s consumed=%s done=%s/%s", name, brief(r), tostring(r.stage),
            S.text(r.missing), S.text(r.consumed), tostring(r.doneHours), tostring(r.totalHours))
        judge(r)
    end)
end

CV.begin = convRequest("conversion_begin", "conversion.begin", { conversion = "flex_generator" }, function(r)
    check("conversion_begun", function() return r.ok == true and r.state == "InProgress", brief(r) end)
end)

CV.deliver = convRequest("conversion_deliver", "conversion.deliver", nil, function(r)
    check("conversion_parts_handed_over", function() return r.ok == true, brief(r) end)
end)

-- "Work on it" (WorkshopMenu.work), until the action ends by itself.
CV.work = { name = "mp_conversion_work", timeout = 60000, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        local g = cvGen()
        if not g then
            report():line("FAIL MP.conversion_work_%s :: no generator", MP.role)
            return true
        end
        TLG.UI.WorkshopMenu.work(p, cvRef(), g)
        ctx.queued = ticks
        report():line("OBS  MP.conversion work queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 120 or not TLGH.Steps.actionsIdle(p) then return nil end
    report():line("OBS  MP.conversion work ended after %d ticks, %d replies, the last: %s", ticks - ctx.queued,
        CV.replies or 0, CV.last and brief(CV.last) or "none")
    return true
end }

CV.status = convRequest("conversion_status", "conversion.status", nil, function(r)
    check("conversion_commissioned", function() return r.ok == true and r.state == "Commissioned", brief(r) end)
end)

local function probeGen(name, judge)
    return call(name, "probe_generator", function() return { x = CV.site and CV.site.x, y = CV.site and CV.site.y } end,
        "probe_generator", function(m)
            report():line("OBS  MP.%s server: profile=%s fuel=%.4f on=%s %s", name, tostring(m.profile),
                tonumber(m.fuel) or -1, tostring(m.on), tostring(m.side))
            judge(m)
        end)
end

CV.profile = probeGen("converted_generator", function(m)
    check("generator_converted_to_flex", function() return m.profile == "generator_si_flex", "profile=" .. tostring(m.profile) end)
end)

CV.pour = act("pour_ethanol_into_flex", function(ctx, p)
    local g = cvGen()
    ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU.cvCan), TLG.Authority.Resolver.refForObject(g, "generator"),
        g, false, function(r) CV.pourReply = r end))
end, 180)

CV.afterPour = probeGen("flex_after_pour", function(m)
    report():line("OBS  MP.pour_ethanol_into_flex result on the player's client: %s",
        CV.pourReply and brief(CV.pourReply) or "none")
    check("flex_generator_takes_ethanol_unconfirmed", function()
        return near(tonumber(m.fuel), 3, 2e-3) and near(canL("cvCan"), 0), string.format("generator %.4f L; can %.4f L",
            tonumber(m.fuel) or -1, canL("cvCan"))
    end)
end)

CV.start = act("start_flex_generator", function(ctx, p)
    ISWorldObjectContextMenu.onActivateGenerator(nil, true, cvGen(), 0)
end, 180)

CV.afterStart = probeGen("flex_after_start", function(m)
    check("flex_generator_starts_on_ethanol", function() return m.on == "true", "on=" .. tostring(m.on) end)
end)

------------------------------------------------------------------------------
-- carconv, A: a Base.CarNormal converted to flex fuel as the workshop menu
-- does it (begin, hand over parts, Menu.work, which paths to the engine
-- area first), on the shortest day; then ethanol poured into it without a
-- confirmation, and the car started on it with its key.
------------------------------------------------------------------------------
local CC = {}
MP.CC = CC

local function ccCar() return CC.site and getVehicleById(tonumber(CC.site.car)) end
local function ccRef() return CC.site and { kind = "vehicle", id = tonumber(CC.site.car) } end

CC.setup = call("carconv_site", "setup_carconv", {}, "carconv_site", function(m)
    CC.site = m
    report():line("OBS  MP.carconv car %s; the server's player: Mechanics %s", tostring(m.car), tostring(m.mechanics))
end)

CC.train = once("mp_train_mechanics", function()
    player():setPerkLevelDebug(Perks.Mechanics, 4)
    player():getKnownRecipes():add("Basic Mechanics")
end)

local function ccRequest(name, command, extra, judge)
    return request(name, command, function()
        local a = { device = ccRef() }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a.device and a
    end, function(r)
        report():line("OBS  MP.%s reply: %s stage=%s missing=%s consumed=%s done=%s/%s", name, brief(r), tostring(r.stage),
            S.text(r.missing), S.text(r.consumed), tostring(r.doneHours), tostring(r.totalHours))
        judge(r)
    end)
end

CC.begin = ccRequest("carconv_begin", "conversion.begin", { conversion = "flex_car_normal" }, function(r)
    check("carconv_begun", function() return r.ok == true and r.state == "InProgress", brief(r) end)
end)

CC.deliver = ccRequest("carconv_deliver", "conversion.deliver", nil, function(r)
    check("carconv_parts_handed_over", function() return r.ok == true, brief(r) end)
end)

CC.work = { name = "mp_carconv_work", timeout = 72000, fn = function(ctx, ticks)
    local p = player()
    if not ctx.queued then
        if not ccCar() then
            report():line("FAIL MP.carconv_work_%s :: no car", MP.role)
            return true
        end
        TLG.UI.WorkshopMenu.work(p, ccRef(), ccCar())
        ctx.queued = ticks
        report():line("OBS  MP.carconv work queued: %s", h.actionNames(p))
        return nil
    end
    if ticks - ctx.queued < 120 or not TLGH.Steps.actionsIdle(p) then return nil end
    report():line("OBS  MP.carconv work ended after %d ticks, %d replies, the last: %s", ticks - ctx.queued,
        CV.replies or 0, CV.last and brief(CV.last) or "none")
    return true
end }

CC.status = ccRequest("carconv_status", "conversion.status", nil, function(r)
    check("carconv_commissioned", function() return r.ok == true and r.state == "Commissioned", brief(r) end)
end)

local function probeCar(name, judge)
    return call(name, "probe_vehicle", function() return { car = CC.site and CC.site.car } end, "probe_vehicle",
        function(m)
            report():line("OBS  MP.%s server: profile=%s tank %.4f L, record %.4f L, engine running=%s %s", name,
                tostring(m.profile), tonumber(m.tankL) or -1, tonumber(m.recL) or -1, tostring(m.engine), tostring(m.side))
            judge(m)
        end)
end

CC.profile = probeCar("converted_car", function(m)
    check("car_converted_to_flex", function() return m.profile == "engine_si_flex", "profile=" .. tostring(m.profile) end)
end)

-- From the filler, where the mod's menu offers the pour (FuelContextMenu:
-- the player in the tank's area) and the server takes it (run 168 poured
-- from the engine, where the work had left A: not_at_fuel_cap).
CC.pour = act("pour_ethanol_into_flex_car", function(ctx, p)
    local car = ccCar()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, car, car:getPartById("GasTank"):getArea()))
    ISTimedActionQueue.add(ISTLGPourFuel:new(p, inventoryItem(FU.ccCan), ccRef(), car, false,
        function(r) CC.pourReply = r end))
end, 180)

CC.afterPour = probeCar("flex_car_after_pour", function(m)
    report():line("OBS  MP.pour_ethanol_into_flex_car result on the player's client: %s",
        CC.pourReply and brief(CC.pourReply) or "none")
    check("flex_car_takes_ethanol_unconfirmed", function()
        return CC.pourReply ~= nil and CC.pourReply.ok == true and near(tonumber(m.tankL), 3, 2e-3)
            and near(tonumber(m.recL), 3, 2e-3), string.format("tank %.4f L, record %.4f L; result %s",
            tonumber(m.tankL) or -1, tonumber(m.recL) or -1, CC.pourReply and brief(CC.pourReply) or "none")
    end)
end)

-- Started as FU.start does it, up to three tries.
local function startCar(name, getCar)
    return { name = "mp_" .. name, timeout = 7200, fn = function(ctx, ticks)
        local p = player()
        if not ctx.t then
            ctx.attempts, ctx.t = 1, ticks
            ISVehicleMenu.onStartEngine(p)
            return nil
        end
        if ticks - ctx.t < 300 or not TLGH.Steps.actionsIdle(p) then return nil end
        local v = getCar()
        if (v and v:isEngineRunning()) or ctx.attempts >= 3 then
            report():line("OBS  MP.%s running=%s after %d attempt(s)", name, tostring(v and v:isEngineRunning()),
                ctx.attempts)
            return true
        end
        ctx.attempts, ctx.t = ctx.attempts + 1, ticks
        ISVehicleMenu.onStartEngine(p)
        return nil
    end }
end

CC.enter = act("enter_flex_car", function(ctx, p) ISVehicleMenu.onEnter(p, ccCar(), 0) end, 120)
CC.start = startCar("start_flex_car", ccCar)

CC.afterStart = probeCar("flex_car_after_start", function(m)
    check("flex_car_starts_on_ethanol", function() return m.engine == "true", "engine running=" .. tostring(m.engine) end)
end)

------------------------------------------------------------------------------
-- stills, A: both stills and the drying column, run through the mod's
-- machine requests as their menu sends them, around a fermenter the server
-- made done (MPServer.lua setup_production), on the shortest day: firewood
-- and the wash into each still, distilled, collected into a can each, the
-- reflux still's run dried with quicklime and collected again.
------------------------------------------------------------------------------
local PR = {}
MP.PR = PR

local function machineRef(key)
    local it = PR.site and findVessel(tonumber(PR.site[key]))
    return it and TLG.Integration.Machines.refFor(it)
end

-- The player's empty jerry cans by id, the first for the pot still's run,
-- the second for the reflux still's, the third for the dried ethanol.
local function jerry(n)
    local list = player():getInventory():getItemsFromFullType("Base.JerryCan")
    local cans = {}
    for i = 0, (list and list:size() or 0) - 1 do cans[#cans + 1] = list:get(i) end
    table.sort(cans, function(a, b) return a:getID() < b:getID() end)
    return cans[n]
end

local function mreq(name, command, key, extra, judge)
    return request(name, command, function()
        local ref = machineRef(key)
        if not ref then return nil end
        local a = { target = ref }
        for k, v in pairs(type(extra) == "function" and extra() or extra or {}) do a[k] = v end
        return a
    end, function(r)
        report():line("OBS  MP.%s reply: %s pause=%s stage=%s outputs=%s firebox=%s washL=%s", name, brief(r),
            tostring(r.pause), tostring(r.stage), S.text(r.outputs), tostring(r.firebox), tostring(r.washL))
        judge(r)
    end)
end

PR.setup = call("production_site", "setup_production", {}, "production_site", function(m)
    PR.site = m
    report():line("OBS  MP.production fermenter %s (%s after %s h, outputs %s), pot still %s, reflux still %s,"
        .. " drying column %s", tostring(m.fermenter), tostring(m.state), tostring(m.hours), tostring(m.outputs),
        tostring(m.pot), tostring(m.reflux), tostring(m.dryer))
end)

PR.fermenter = mreq("fermenter_status", "machine.status", "fermenter", nil, function(r)
    check("fermenter_done", function() return r.ok == true and r.state == "OutputReady", brief(r) end)
end)

local function logs(name) return call(name, "give", { items = "Base.Log;Base.Log" }, "given", function() end) end

local function fed(name, key)
    return mreq(name, "machine.addFuel", key, nil, function(r)
        check(name, function() return r.ok == true and (tonumber(r.firebox) or 0) > 0, brief(r) end)
    end)
end

local function washed(name, key)
    return mreq(name, "machine.loadWash", key, nil, function(r)
        check(name, function() return r.ok == true and r.state == "Processing" and (tonumber(r.washL) or 0) > 0,
            brief(r) .. " washL=" .. tostring(r.washL) end)
    end)
end

-- Asks each machine's status every 5 s (an access is what moves a record
-- on) until all are OutputReady. A still that stops for heat (its firebox
-- burned out, pause no_heat) is fed again as a player tends it: two more
-- logs, then its firewood (run 170: 60 L of wash in the pot still need 51
-- kWh; two logs give it 34, and it waited).
local function ready(name, keys)
    return { name = "mp_" .. name, timeout = 72000, fn = function(ctx, ticks)
        if ctx.pending then return nil end
        ctx.answers = ctx.answers or {}
        if ctx.feed then
            if ticks < ctx.feed.at then return nil end
            ctx.pending = 1
            local k = ctx.feed.key
            TLG.Net.request("machine.addFuel", { target = machineRef(k) }, function(r)
                report():line("OBS  MP.%s %s fed again: %s firebox=%s", name, k, brief(r), tostring(r.firebox))
                ctx.feed, ctx.pending, ctx.answers = nil, nil, {}
            end)
            return nil
        end
        local all = true
        for _, k in ipairs(keys) do
            if ctx.answers[k] ~= "OutputReady" then all = false end
            if ctx.answers[k] == "no_heat" then
                send("give", { items = "Base.Log;Base.Log", tag = "refeed_" .. k })
                report():line("OBS  MP.%s %s stopped for heat after %d ticks: two more logs", name, k, ticks)
                ctx.feed = { key = k, at = ticks + 120 }
                return nil
            end
        end
        if all then
            report():line("OBS  MP.%s all done after %d ticks", name, ticks)
            return true
        end
        if ctx.next and ticks < ctx.next then return nil end
        ctx.pending, ctx.next = #keys, ticks + 300
        for _, k in ipairs(keys) do
            TLG.Net.request("machine.status", { target = machineRef(k) }, function(r)
                ctx.answers[k] = r.pause == "no_heat" and "no_heat" or r.state
                ctx.pending = ctx.pending - 1
                if ctx.pending <= 0 then ctx.pending = nil end
            end)
        end
        return nil
    end }
end

local function collected(name, key, n)
    return mreq(name, "machine.collect", key, function()
        local can = jerry(n)
        return { destination = { kind = "item", id = can and can:getID() } }
    end, function(r)
        check(name, function() return r.ok == true, brief(r) end)
    end)
end

-- What this client holds of a can's fuel: its litres and its TLG record's
-- ethanol and water (the server writes it and sends it with the item).
local function canFuel(n)
    local can = jerry(n)
    local q = can and can:getModData().tlg and can:getModData().tlg.q or {}
    return can and can:getFluidContainer():getAmount() or -1, q.ethanol or 0, q.water or 0
end

-- The reflux still's run to the single-player loop's purity (under 7 %
-- water, LOOP.distill_completed); the pot still makes weaker spirit.
PR.cans = once("mp_stills_cans", function()
    for n, still in ipairs({ "pot", "reflux" }) do
        local litres, eth, water = canFuel(n)
        report():line("OBS  MP.%s still's run in can %s: %.4f L, ethanol %.4f, water %.4f", still,
            tostring(jerry(n) and jerry(n):getID()), litres, eth, water)
        check(still .. "_still_run_bottled", function()
            local pure = still == "pot" or water / math.max(1e-9, eth + water) < 0.07
            return eth > 0.5 and pure and near(eth + water, litres, 2e-3),
                string.format("%.4f L: ethanol %.4f, water %.4f", litres, eth, water)
        end)
    end
end)

PR.dry = mreq("dry_load", "machine.loadDry", "dryer", function()
    local can = jerry(2)
    return { source = { kind = "item", id = can and can:getID() } }
end, function(r)
    check("dry_loaded", function() return r.ok == true and r.state == "Processing", brief(r) end)
end)

PR.dried = once("mp_dried_can", function()
    local litres, eth, water = canFuel(3)
    report():line("OBS  MP.dried ethanol in can %s: %.4f L, ethanol %.4f, water %.4f",
        tostring(jerry(3) and jerry(3):getID()), litres, eth, water)
    check("dried_ethanol_bottled", function()
        return eth > 0.5 and water <= eth * 0.005 + 1e-4 and near(eth + water, litres, 2e-3),
            string.format("%.4f L: ethanol %.4f, water %.4f", litres, eth, water)
    end)
end)

-- Each reply the work action gets from the server, logged (the first few
-- and any that is not plain progress).
if (MP.only == "conversion" or MP.only == "carconv") and ISTLGConversionWork then
    local onReply = ISTLGConversionWork.onReply
    ISTLGConversionWork.onReply = function(self, r)
        CV.replies, CV.last = (CV.replies or 0) + 1, r
        if CV.replies <= 3 or r.state ~= "InProgress" or not r.ok then
            report():line("OBS  MP.work reply %d: %s stage=%s done=%s/%s credited=%s", CV.replies, brief(r),
                tostring(r.stage), tostring(r.doneHours), tostring(r.totalHours), tostring(r.credited))
        end
        return onReply(self, r)
    end
end

local function standNear(name, dx, dy)
    return walkTo(name, function()
        local x, y = S.spot(-2)
        return x + dx, y + dy
    end)
end

if MP.only == "machines" then
    local bx0, by0, vx, vy = h.bx0, h.by0, h.vx, h.vy
    MP.stepsA = {
        MP.waitWorld, h.zoomTo("mp_zoom", 0.5), h.stand("mp_stand", bx0, by0),
        waitFrom("mp_wait_b", "hello", function() send("start", {}) end),
        C.spawnGrab, wait("mp_grab_vessel_lands", 120), C.grabBefore,
        walkTo("mp_walk_to_grab", S.spot(2)), C.grab, C.grabbed, C.statusCarried, C.carried1,
        wait("mp_carried_a_while", 900), C.statusCarried2, C.carried2, C.drop, C.dropped, C.statusDropped,
        C.placed1, wait("mp_placed_a_while", 900), C.statusPlaced2, C.placed2,
        C.spawnLoad, C.give, C.haveFeed, standNear("mp_walk_to_load", 1, -1),
        once("mp_load_setup", function() send("load_setup", {}) end), waitFrom("mp_wait_load_ready", "load_ready"),
        loadNow(true), C.loadBoth, C.loaded,
        C.crate, wait("mp_crate_vessel_arrives", 120), C.takeFromCrate, C.crateSeen,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = {
        MP.waitWorld, h.zoomTo("mp_zoom", 0.5), h.stand("mp_stand", vx, vy, 1),
        once("mp_hello", function() send("hello", {}) end), waitFrom("mp_wait_start", "start"),
        waitFrom("mp_wait_load_setup", "load_setup"), C.give, C.haveFeed, standNear("mp_walk_to_load", 1, 1),
        once("mp_load_ready", function() send("load_ready", {}) end), loadNow(false),
        waitFrom("mp_wait_finish", "finish"), MP.finish,
    }
elseif MP.only == "fuel" then
    MP.stepsA = {
        MP.waitWorld, FU.setup, wait("mp_fuel_site_arrives", 300), FU.seen,
        giveCan("give_empty_can", { petrol = "0" }, "can1"), arrived("can1"), FU.pumpToCan, FU.afterPumpToCan,
        FU.canToCar, FU.afterCanToCar, FU.pumpToCar, FU.afterPumpToCar,
        FU.giveHose, wait("mp_hose_arrives", 120), FU.siphon, FU.afterSiphon,
        giveCan("give_petrol_can", { petrol = "5" }, "can2"), arrived("can2"), FU.canToGen, FU.afterCanToGen,
        giveCan("give_pour_can", { petrol = "3" }, "can3"), arrived("can3"),
        walkTo("mp_walk_to_generator_1", function() return site("g1x") + 1, site("g1y") end),
        pour("pour_petrol", "can3", 1, false), pourReached("pour_petrol"), FU.afterPourPetrol,
        giveCan("give_ethanol_can", { fill = "TLG_Ethanol", litres = "3" }, "can4"), arrived("can4"),
        pour("pour_ethanol", "can4", 1, false), pourReached("pour_ethanol"), FU.afterPourEthanol,
        walkTo("mp_walk_to_generator_2", function() return site("g2x") + 1, site("g2y") end),
        pour("pour_ethanol_confirmed", "can4", 2, true), pourReached("pour_ethanol_confirmed"), FU.afterPourConfirmed,
        switch("start_generator_1", 1, true), switch("start_generator_2", 2, true), FU.afterStarts,
        wait("mp_generator_runs", 1800), FU.genStatus, FU.afterBurn,
        switch("stop_generator_1", 1, false), FU.unplug, FU.take, FU.afterTake, FU.place, FU.afterPlace,
        FU.enter, FU.start, FU.afterStart, wait("mp_car_idles", 1800), FU.carStatus, FU.afterIdle,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "conversion" then
    MP.stepsA = {
        MP.waitWorld, CV.setup, CV.train, wait("mp_conversion_items_arrive", 300),
        walkTo("mp_walk_to_conversion", S.spot(2)),
        CV.begin, CV.deliver, CV.work, CV.status, CV.profile,
        giveCan("give_conversion_ethanol", { fill = "TLG_Ethanol", litres = "3" }, "cvCan"), arrived("cvCan"),
        CV.pour, CV.afterPour, CV.start, CV.afterStart,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "carconv" then
    MP.stepsA = {
        MP.waitWorld, CC.setup, CC.train, wait("mp_carconv_items_arrive", 300),
        walkTo("mp_walk_to_car", S.CX + 1, S.CY + 1),
        CC.begin, CC.deliver, CC.work, CC.status, CC.profile,
        giveCan("give_carconv_ethanol", { fill = "TLG_Ethanol", litres = "3" }, "ccCan"), arrived("ccCan"),
        CC.pour, CC.afterPour, CC.enter, CC.start, CC.afterStart,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
elseif MP.only == "stills" then
    MP.stepsA = {
        MP.waitWorld, PR.setup, wait("mp_production_site_arrives", 300), PR.fermenter,
        logs("give_logs_pot"), wait("mp_logs_pot_arrive", 120), fed("pot_firewood", "pot"), washed("pot_wash", "pot"),
        logs("give_logs_reflux"), wait("mp_logs_reflux_arrive", 120), fed("reflux_firewood", "reflux"),
        washed("reflux_wash", "reflux"), ready("stills_distil", { "pot", "reflux" }),
        collected("pot_collect", "pot", 1), collected("reflux_collect", "reflux", 2), wait("mp_runs_arrive", 120),
        PR.cans, PR.dry, ready("drying", { "dryer" }), collected("dry_collect", "dryer", 3),
        wait("mp_dried_arrives", 120), PR.dried,
        once("mp_finish_b", function() send("finish", {}) end), MP.finish,
    }
    MP.stepsB = { MP.waitWorld, waitFrom("mp_wait_finish", "finish"), MP.finish }
end
