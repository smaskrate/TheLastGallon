-- Security audit cases for the multiplayer harness (2026-11-05 audit):
-- tools/run-mp-harness.ps1 -Clients 1 -Only audit -NonAdmin
-- Client A is a plain player (no admin role). Every request below is what a
-- modified client could send through the channels the mod and the engine
-- expose: the mod's "TLG" client commands (TLG.Net.request), the engine's
-- global ModData request, and the engine's client-authoritative syncs of
-- object and item mod data (IsoObject.transmitModData, syncItemFields).
-- The server's view is read through MPServer.lua's probe services.
-- Results: <cachedir>/Lua/TLG_harness_mp.txt, lines prefixed AUD.
require "TLGHarness/MPHarnessCases"

local MP = TLGH.MP
if not MP or not MP.h or MP.only ~= "audit" then return end
local S = TLGH.MPShared
local h = MP.h
local report, player, check, send, call, once, wait = h.report, h.player, h.check, h.send, h.call, h.once, h.wait
local walkTo, request, inventoryItem, ids, brief = h.walkTo, h.request, h.inventoryItem, h.ids, h.brief
local FU = MP.FU

local AU = {}
MP.AU = AU

local function site(k) return FU.site and tonumber(FU.site[k]) end

local function objAt(x, y, pred)
    local sq = x and y and getCell():getGridSquare(x, y, 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        if pred(objs:get(i)) then return objs:get(i) end
    end
    return nil
end

local function pumpObj() return objAt(site("px"), site("py"), function(o) return o:getPipedFuelAmount() > 0 end) end
local function genObj(k)
    return objAt(site("g" .. k .. "x"), site("g" .. k .. "y"), function(o) return instanceof(o, "IsoGenerator") end)
end
local function car() return FU.site and getVehicleById(site("car")) end
local function pumpRef() return TLG.Authority.Resolver.refForObject(pumpObj(), "pump") end
local function genRef(k) return TLG.Authority.Resolver.refForObject(genObj(k), "generator") end

local function obs(fmt, ...) report():line("OBS  AUD." .. fmt, ...) end

-- A step that queues `queue(ctx, player)` once and waits until the player's
-- actions are done (MPHarnessCases.lua's act).
local function act(name, queue, settle)
    return { name = "aud_" .. name, timeout = 7200, fn = function(ctx, ticks)
        local p = player()
        if not ctx.queued then
            local ok, err = pcall(queue, ctx, p)
            if not ok then
                report():line("FAIL AUD.%s_queued :: %s", name, tostring(err))
                return true
            end
            ctx.queued = ticks
            return nil
        end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        return ticks - ctx.idle >= (settle or 120) or nil
    end }
end

local function canL(id)
    local it = inventoryItem(id)
    local fc = it and it:getFluidContainer()
    return fc and fc:getAmount() or -1
end

------------------------------------------------------------------------------
-- AUD-1 (V-02): "status" answered about objects the player cannot reach
-- (runs 1-2). Since the fix it refuses them (no_access), as sample does;
-- within reach it still answers (AUD1_status_pump_in_reach_answered below,
-- and the fuel case's generator and car status).
------------------------------------------------------------------------------
AU.where = once("aud_where", function()
    local p, v = player(), car()
    obs("where: player %.1f,%.1f role=%s; car %s at %s,%s dist=%.1f; pump %s,%s; g1 %s,%s", p:getX(), p:getY(),
        tostring(select(2, pcall(function() return p:getRole():getName() end))), tostring(site("car")),
        tostring(v and v:getX()), tostring(v and v:getY()), v and p:DistTo(v:getX(), v:getY()) or -1,
        tostring(site("px")), tostring(site("py")), tostring(site("g1x")), tostring(site("g1y")))
end)

AU.statusCarFar = request("aud_status_vehicle_far", "status", function()
    return { target = { kind = "vehicle", id = site("car") } }
end, function(r)
    obs("status vehicle far: %s total=%s cap=%s primary=%s sealed=%s rev=%s grade=%s", brief(r), tostring(r.total),
        tostring(r.cap), tostring(r.primary), tostring(r.sealed), tostring(r.rev),
        tostring(r.evaluation and r.evaluation.grade))
    check("AUD1_status_vehicle_out_of_reach_refused", function()
        return r.ok == false and r.reason == "no_access" and r.total == nil, brief(r)
    end)
end)

AU.sampleCarFar = request("aud_sample_vehicle_far", "sample", function()
    return { target = { kind = "vehicle", id = site("car") }, method = "visual" }
end, function(r)
    obs("sample vehicle far: %s detail=%s", brief(r), tostring(r.detail))
    check("AUD1_sample_vehicle_out_of_reach_refused", function()
        return r.ok == false and r.reason == "no_access", brief(r)
    end)
end)

AU.statusPumpFar = request("aud_status_pump_far", "status", function()
    return { target = pumpRef() }
end, function(r)
    obs("status pump far: %s total=%s primary=%s", brief(r), tostring(r.total), tostring(r.primary))
    check("AUD1_status_pump_out_of_reach_refused", function()
        return r.ok == false and r.reason == "no_access" and r.total == nil, brief(r)
    end)
end)

AU.statusGenFar = request("aud_status_generator_far", "status", function()
    return { target = genRef(1) }
end, function(r)
    obs("status generator far: %s total=%s grade=%s", brief(r), tostring(r.total),
        tostring(r.evaluation and r.evaluation.grade))
    check("AUD1_status_generator_out_of_reach_refused", function()
        return r.ok == false and r.reason == "no_access" and r.total == nil, brief(r)
    end)
end)

AU.statusBogus = request("aud_status_bogus_vehicle", "status", function()
    return { target = { kind = "vehicle", id = 987654321 } }
end, function(r)
    obs("status bogus vehicle id: %s detail=%s", brief(r), tostring(r.detail))
end)

------------------------------------------------------------------------------
-- AUD-2 (V-03): the world record (with machineSites and the seed) was sent
-- to any client asking for it (run 1). Since the fix those fields live in
-- the server store (a server-side global object system's mod data): the
-- server still has the vessel's square there, the record a client receives
-- has no seed, next id or machine squares.
------------------------------------------------------------------------------
AU.spawnVessel = call("aud_spawn_running_vessel", "spawn", function()
    local x, y = S.spot(5)
    return { item = "TLG.FermenterVessel", x = x, y = y, batch = "1" }
end, "spawned", function(m)
    AU.vesselId, AU.vx, AU.vy = tonumber(m.id), tonumber(m.x), tonumber(m.y)
    obs("spawned vessel id=%s at %s,%s batch=%s", tostring(m.id), tostring(m.x), tostring(m.y), tostring(m.batch))
end)

AU.serverWorld = call("aud_probe_world", "probe_world", function() return { x = AU.vx, y = AU.vy } end,
    "probe_world", function(m)
    AU.serverSites = tostring(m.sites)
    obs("server world: store=%s seed=%s nextId=%s sites=%s; record seed=%s nextId=%s sites=%s", tostring(m.store),
        tostring(m.seed), tostring(m.nextId), tostring(m.sites), tostring(m.pubSeed), tostring(m.pubNextId),
        tostring(m.pubSites))
    check("AUD2_server_store_keeps_the_machine_site", function()
        return m.store == "true" and m.siteHit == "true" and tonumber(m.seed) ~= nil and m.pubSeed == "nil"
            and m.pubSites == "nil", string.format("store=%s hit=%s seed=%s record seed=%s sites=%s",
            tostring(m.store), tostring(m.siteHit), tostring(m.seed), tostring(m.pubSeed), tostring(m.pubSites))
    end)
end)

AU.requestWorld = once("aud_request_world", function()
    AU.received = nil
    Events.OnReceiveGlobalModData.Add(function(key, data)
        if key == "TLG_World" then AU.received = data end
    end)
    ModData.request("TLG_World")
end)

AU.readWorld = { name = "aud_read_world", timeout = 1200, fn = function(ctx, ticks)
    if not AU.received and ticks < 900 then return nil end
    local md = AU.received or ModData.getOrCreate("TLG_World")
    local sites = type(md) == "table" and md.machineSites or {}
    local n, hit = 0, false
    for id, p in pairs(sites) do
        n = n + 1
        if type(p) == "table" and p.x == AU.vx and p.y == AU.vy then hit = true end
    end
    obs("client received world: event=%s seed=%s policy=%s nextId=%s climateAcc=%s machineSites=%d %s",
        tostring(AU.received ~= nil), tostring(md.seed), tostring(md.policy), tostring(md.nextId),
        tostring(md.climateAcc ~= nil), n, S.text(sites))
    check("AUD2_world_record_sent_without_server_fields", function()
        return AU.received ~= nil and md.policy ~= nil and n == 0 and not hit and md.seed == nil and md.nextId == nil
            and md.climateAcc == nil, string.format("event=%s policy=%s %d sites, seed=%s nextId=%s",
            tostring(AU.received ~= nil), tostring(md.policy), n, tostring(md.seed), tostring(md.nextId))
    end)
    return true
end }

-- AUD-2b: a client transmitting its own copy of the world record must not
-- change the server's (the mod's handler stores it on clients only).
AU.forgeWorld = once("aud_transmit_forged_world", function()
    local md = ModData.getOrCreate("TLG_World")
    AU.nextIdBefore = md.nextId
    md.nextId = 999999
    md.audit = "forged"
    ModData.transmit("TLG_World")
    obs("transmitted a forged world record (nextId=999999, audit=forged) from the client")
end)

AU.serverWorldAfter = call("aud_probe_world_after", "probe_world", {}, "probe_world", function(m)
    obs("server world after the client's transmit: nextId=%s sites=%s", tostring(m.nextId), tostring(m.sites))
    check("AUD2b_server_world_record_not_overwritten_by_client", function()
        return m.nextId ~= "999999" and tonumber(m.nextId) ~= nil, "nextId=" .. tostring(m.nextId)
    end)
end)

------------------------------------------------------------------------------
-- AUD-3: the mod's "transfer" moves fuel out of a pump with no timed action,
-- into a can and into a car (the engine gates the pump on power itself:
-- getPipedFuelAmount reports nothing unpowered, audit run 1).
------------------------------------------------------------------------------
AU.power = call("aud_probe_square", "probe_square", function() return { x = site("px"), y = site("py") } end,
    "probe_square", function(m)
    local sq = pumpObj() and pumpObj():getSquare()
    local grid, elec
    pcall(function() grid = sq:hasGridPower() end)
    pcall(function() elec = sq:haveElectricity() end)
    obs("pump square power: server grid=%s elec=%s; client grid=%s elec=%s; ElecShutModifier=%s", tostring(m.grid),
        tostring(m.elec), tostring(grid), tostring(elec), tostring(SandboxVars.ElecShutModifier))
    AU.powered = (m.grid == "true" or m.elec == "true")
end)

AU.giveCan = call("aud_give_can", "give", { items = "Base.PetrolCan", petrol = "0" }, "given", function(m)
    local got = ids(m.ids)["Base.PetrolCan"]
    AU.can = got and got[1]
    obs("given can id=%s", tostring(AU.can))
end)

AU.canArrives = { name = "aud_can_arrives", timeout = 900, fn = function(ctx, ticks)
    if inventoryItem(AU.can) == nil and ticks < 600 then return nil end
    obs("can in inventory=%s %.4f L", tostring(inventoryItem(AU.can) ~= nil), canL(AU.can))
    return true
end }

AU.walkToPump = act("walk_to_pump", function(ctx, p)
    ISTimedActionQueue.clear(p)
    luautils.walkAdj(p, pumpObj():getSquare())
end, 60)

-- V-02 regression: within reach, status still answers.
AU.statusPumpNear = request("aud_status_pump_near", "status", function()
    return { target = pumpRef() }
end, function(r)
    obs("status pump in reach: %s total=%s primary=%s", brief(r), tostring(r.total), tostring(r.primary))
    check("AUD1_status_pump_in_reach_answered", function() return r.ok == true and r.total ~= nil, brief(r) end)
end)

AU.pumpToCan = request("aud_transfer_pump_to_can", "transfer", function()
    AU.units0 = pumpObj():getPipedFuelAmount()
    AU.can0 = canL(AU.can)
    return { source = pumpRef(), destination = { kind = "item", id = AU.can }, amount = 5 }
end, function(r)
    AU.pumpToCanReply = r
    obs("transfer pump->can: %s moved=%s detail=%s (pump units before %s, power=%s)", brief(r), tostring(r.moved),
        tostring(r.detail), tostring(AU.units0), tostring(AU.powered))
end)

AU.afterPumpToCan = { name = "aud_after_pump_to_can", timeout = 600, fn = function(ctx, ticks)
    if ticks < 120 then return nil end
    local units1 = pumpObj():getPipedFuelAmount()
    obs("after transfer pump->can: can %.4f -> %.4f L; pump units %s -> %s", AU.can0 or -1, canL(AU.can),
        tostring(AU.units0), tostring(units1))
    check("AUD3_pump_to_can_without_action", function()
        local r = AU.pumpToCanReply
        return r and r.ok == true and (r.moved or 0) > 0 and canL(AU.can) > (AU.can0 or 0),
            string.format("moved=%s can %.4f L power=%s", tostring(r and r.moved), canL(AU.can), tostring(AU.powered))
    end)
    return true
end }

AU.walkToTank = act("walk_to_tank", function(ctx, p)
    local v = car()
    local part = v:getPartById("GasTank")
    ISTimedActionQueue.clear(p)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, v, part:getArea()))
end, 60)

AU.pumpToCar = request("aud_transfer_pump_to_car", "transfer", function()
    local v = car()
    local part = v:getPartById("GasTank")
    AU.tank0 = part:getContainerContentAmount()
    AU.units1 = pumpObj():getPipedFuelAmount()
    obs("at the filler: inArea=%s dist to pump square=%.2f", tostring(v:isInArea(part:getArea(), player())),
        player():getSquare():DistToProper(pumpObj():getSquare()))
    return { source = pumpRef(), destination = { kind = "vehicle", id = site("car") }, amount = 10 }
end, function(r)
    AU.pumpToCarReply = r
    obs("transfer pump->car: %s moved=%s detail=%s", brief(r), tostring(r.moved), tostring(r.detail))
end)

AU.afterPumpToCar = call("aud_probe_fuel_after_transfers", "probe_fuel", function()
    local s = FU.site or {}
    return { px = s.px, py = s.py, car = s.car, g1x = s.g1x, g1y = s.g1y, g2x = s.g2x, g2y = s.g2y,
        ids = tostring(AU.can) }
end, "probe_fuel", function(m)
    obs("server after transfers: pump units=%s side=%s; tank %.4f L record %.4f L; items %s", tostring(m.pumpUnits),
        tostring(m.pumpSide), tonumber(m.tankL) or -1, tonumber(m.tankRecL) or -1, tostring(m.items))
    AU.pumpSide0 = tostring(m.pumpSide)
    local r = AU.pumpToCarReply
    if r and r.ok then
        check("AUD3_pump_to_car_without_action", function()
            return tonumber(m.tankL) > (AU.tank0 or 0) + 1, string.format("tank %.4f -> %.4f L", AU.tank0 or -1,
                tonumber(m.tankL) or -1)
        end)
    else
        obs("pump->car not moved (%s): the car's filler is out of the pump's 3.5 tiles here", brief(r))
    end
end)

------------------------------------------------------------------------------
-- AUD-4: the engine applies mod data a client sends for items and objects
-- (SyncItemFields, ObjectModData), so a client still rewrites the stores on
-- the server; since the V-01 fix the mod's own reads there put its records
-- back from the vault (TLG/Authority/Vault.lua) and drop forged ones.
------------------------------------------------------------------------------
AU.lookCan = request("aud_look_can", "sample", function()
    return { target = { kind = "item", id = AU.can }, method = "visual" }
end, function(r)
    obs("look at can: %s", brief(r))
end)

AU.forgeItem = { name = "aud_forge_item_sidecar", timeout = 900, fn = function(ctx, ticks)
    local it = inventoryItem(AU.can)
    local md = it and it:getModData()
    if not (md and type(md.tlg) == "table") and ticks < 600 then return nil end
    if not (md and type(md.tlg) == "table") then
        obs("forge item: the can has no sidecar on this client yet")
        return true
    end
    obs("forge item: sidecar before %s", S.sidecar(it))
    md.tlg.deg = md.tlg.deg or {}
    md.tlg.deg.gasoline = 7.7777
    md.tlg.stab = 1.5
    md.tlg.audit = "forged"
    it:syncItemFields()
    AU.forgedItem = true
    return true
end }

AU.probeItem = call("aud_probe_item_forged", "probe_item", function() return { id = AU.can } end, "probe_item",
    function(m)
    obs("server item after client sync: found=%s sidecar=%s fluid=%s", tostring(m.found), tostring(m.sidecar),
        tostring(m.fluid))
    check("AUD4_item_sidecar_reaches_server_mod_data", function()
        return AU.forgedItem == true and string.find(tostring(m.sidecar), "audit=forged", 1, true) ~= nil
            and string.find(tostring(m.sidecar), "7.7777", 1, true) ~= nil, tostring(m.sidecar)
    end)
end)

AU.forgePump = once("aud_forge_pump_sidecar", function()
    local p = pumpObj()
    local md = p:getModData()
    obs("forge pump: sidecar before %s", S.text(md.tlg))
    if type(md.tlg) == "table" then
        md.tlg.q = md.tlg.q or {}
        md.tlg.q.water = nil
        md.tlg.q.sediment = nil
        md.tlg.deg = { gasoline = 0 }
        md.tlg.audit = "forged"
        p:transmitModData()
        AU.forgedPump = true
    else
        obs("forge pump: no sidecar on this client (the transfer left none here)")
    end
end)

AU.forgeGenerator = once("aud_forge_generator_conversion", function()
    local g = genObj(1)
    local md = g:getModData()
    obs("forge generator: modData before tlgConv=%s deviceId=%s", S.text(md.tlgConv), tostring(md.tlgDeviceId))
    md.tlgDeviceId = "AUDIT-D"
    md.tlgEngineId = "AUDIT-E"
    md.tlgConv = {
        v = 1, id = "AUDIT-C", rev = 1, conversion = "flex_generator", state = "Commissioned", t = 0,
        snap = { targetConsumerProfile = "generator_si_flex", fuelStorageChanges = {}, cargoAndWeightImpact = {},
            visualConfiguration = {}, workStages = {}, requiredModules = {}, requiredTools = {},
            reversalAndSalvageRules = {} },
        hours = {}, delivered = {}, workers = {}, credit = {}, deviceKey = "gen:AUDIT-D",
        chassis = "Base.Generator", deviceKind = "generator", engineId = "AUDIT-E",
        originalProfile = "generator_si_stock", commissionedAt = 0,
    }
    g:transmitModData()
    AU.forgedGen = true
end)

AU.probeForged = call("aud_probe_fuel_forged", "probe_fuel", function()
    local s = FU.site or {}
    return { px = s.px, py = s.py, car = s.car, g1x = s.g1x, g1y = s.g1y, g2x = s.g2x, g2y = s.g2y,
        ids = tostring(AU.can) }
end, "probe_fuel", function(m)
    obs("server after object syncs: pump side=%s; g1 side=%s", tostring(m.pumpSide), tostring(m.g1Side))
    check("AUD4_pump_sidecar_reaches_server_mod_data", function()
        return AU.forgedPump == true and string.find(tostring(m.pumpSide), "audit=forged", 1, true) ~= nil,
            string.format("before %s, after %s", tostring(AU.pumpSide0), tostring(m.pumpSide))
    end)
end)

-- The mod's own reads on the server, through the vault.
AU.probeVault = call("aud_probe_vault", "probe_vault", function()
    local s = FU.site or {}
    return { id = AU.can, px = s.px, py = s.py, gx = s.g1x, gy = s.g1y }
end, "probe_vault", function(m)
    obs("server reads through the vault (active=%s): can %s -> deg %s stab %s -> %s", tostring(m.active),
        tostring(m.canBefore), tostring(m.canDeg), tostring(m.canStab), tostring(m.canAfter))
    obs("  pump %s -> water %s sediment %s -> %s", tostring(m.pumpBefore), tostring(m.pumpWater),
        tostring(m.pumpSediment), tostring(m.pumpAfter))
    obs("  generator project %s -> profile %s -> %s", tostring(m.genConvBefore), tostring(m.genProfile),
        tostring(m.genConvAfter))
    check("AUD4_vault_active_on_server", function() return m.active == "true", tostring(m.active) end)
    check("AUD4_item_record_put_back", function()
        return AU.forgedItem == true and tonumber(m.canDeg) ~= nil and math.abs(tonumber(m.canDeg) - 7.7777) > 1e-3
            and math.abs((tonumber(m.canStab) or 1.5) - 1.5) > 1e-3
            and string.find(tostring(m.canAfter), "audit=forged", 1, true) == nil,
            string.format("deg %s stab %s, after %s", tostring(m.canDeg), tostring(m.canStab), tostring(m.canAfter))
    end)
    check("AUD4_pump_record_put_back", function()
        return AU.forgedPump == true and string.find(tostring(m.pumpAfter), "audit=forged", 1, true) == nil
            and (tonumber(m.pumpWater) or 0) + (tonumber(m.pumpSediment) or 0) > 0
            and tostring(m.pumpAfter) == tostring(AU.pumpSide0),
            string.format("before the forgery %s, after the read %s", tostring(AU.pumpSide0), tostring(m.pumpAfter))
    end)
    check("AUD4_generator_conversion_reaches_server_mod_data", function()
        return AU.forgedGen == true and string.find(tostring(m.genConvBefore), "AUDIT-C", 1, true) ~= nil,
            tostring(m.genConvBefore)
    end)
    check("AUD4_generator_forged_conversion_dropped", function()
        return m.genProfile == "generator_si_stock" and string.find(tostring(m.genConvAfter), "AUDIT-C", 1, true) == nil,
            string.format("profile %s, project after %s", tostring(m.genProfile), tostring(m.genConvAfter))
    end)
end)

AU.probeGenerator = call("aud_probe_generator_forged", "probe_generator", function()
    return { x = site("g1x"), y = site("g1y") }
end, "probe_generator", function(m)
    obs("server generator after client sync: found=%s profile=%s side=%s", tostring(m.found), tostring(m.profile),
        tostring(m.side))
    check("AUD4_generator_forged_conversion_ignored", function()
        return AU.forgedGen == true and m.profile == "generator_si_stock", tostring(m.profile)
    end)
end)

------------------------------------------------------------------------------
-- The mode.
------------------------------------------------------------------------------
MP.stepsA = {
    MP.waitWorld, FU.setup, wait("aud_fuel_site_arrives", 300), FU.seen, AU.where,
    AU.statusCarFar, AU.sampleCarFar, AU.statusPumpFar, AU.statusGenFar, AU.statusBogus,
    AU.spawnVessel, wait("aud_vessel_lands", 120), AU.serverWorld, AU.requestWorld, AU.readWorld,
    AU.forgeWorld, wait("aud_world_transmit_settles", 120), AU.serverWorldAfter,
    AU.power, AU.giveCan, AU.canArrives, AU.walkToPump, AU.statusPumpNear, AU.pumpToCan, AU.afterPumpToCan,
    AU.walkToTank, AU.pumpToCar, AU.afterPumpToCar,
    AU.lookCan, wait("aud_record_settles", 120), AU.forgeItem, wait("aud_item_sync_settles", 180), AU.probeItem,
    AU.walkToPump, AU.forgePump, AU.forgeGenerator, wait("aud_object_sync_settles", 180), AU.probeForged,
    AU.probeVault, AU.probeGenerator,
    once("mp_finish_b", function() send("finish", {}) end), MP.finish,
}
MP.stepsB = { MP.waitWorld, h.waitFrom("mp_wait_finish", "finish"), MP.finish }
