-- Multiplayer harness, client side (requests "mp-a" and "mp-b";
-- tools/run-mp-harness.ps1). At the main menu the client joins the TLGDev
-- server by IP as vanilla's Join by IP popup does (ServerConnectPopup.lua:
-- ConnectToServer.instance:connect), with the account the launcher left in
-- TLG_harness_connect.txt. A new character is made by pressing the creation
-- screens' own Next (CharacterCreationProfession and CharacterCreationMain
-- onOptionMouseDown "NEXT"). Joining reloads the Lua with the server's
-- mods, so the report and the client's progress live in files.
--
-- In the world client A acts and client B watches. Items come from the
-- server (MPServer.lua), never from the client, as a player's would. A
-- asks the mod's server for a fuel sample and a stabilizer treatment
-- (TLG.Net), repeats the treatment with the same request id, and compares
-- the can's record with the server's; A and B each ask, within reach, for
-- the status of a machine the server put down. A reads a manual the server
-- rolled from its loot lists, and a vanilla flier for comparison. A walks
-- to and drops the small items on a row and B photographs them; each
-- client's view of the floor is compared with the server's. A carries the
-- vessel through each gait while B photographs A and reads the carry
-- pose's variables off A's character on B's screen. Last, A leaves to the
-- main menu and joins again, and both look at the floor.
-- Results: <cachedir>/Lua/TLG_harness_mp.txt.
require "TLGHarness/Report"
require "TLGHarness/Steps"
require "TLGHarness/MPShared"

local REQUEST = TLGH.readRequest()
if REQUEST ~= "mp-a" and REQUEST ~= "mp-b" then return end

TLGH.MP = TLGH.MP or {}
local MP = TLGH.MP
local S = TLGH.MPShared
MP.role = REQUEST == "mp-a" and "A" or "B"
MP.other = MP.role == "A" and "B" or "A"

-- Joining reloads the Lua, so the report is reopened in each Lua state; the
-- checks of the earlier states count toward this client's summary (run
-- 145's A ended "pass=2 fail=0" for its second session alone).
local function report()
    if not MP.R then
        MP.R = TLGH.Report.new("TLG_harness_mp.txt", "TLG multiplayer harness, client " .. MP.role, true)
        for _, l in ipairs(MP.R.lines) do
            if string.sub(l, 1, 5) == "PASS " then MP.R.pass = MP.R.pass + 1 end
            if string.sub(l, 1, 5) == "FAIL " then MP.R.fail = MP.R.fail + 1 end
        end
    end
    return MP.R
end

-- Unattended, as SPHarness.lua: a Lua error is logged instead of stopping
-- in the debugger, and the Survival Guide stays closed.
pcall(function() UIManager.setShowLuaDebuggerOnError(false) end)
pcall(function() getCore():setOptionShowSurvivalGuide(false) end)

-- What the client has done so far, kept in a file because joining reloads
-- the Lua (the launcher deletes it): joining, joined, rejoin (A asked to
-- leave and join again), rejoining, rejoined.
local function phase() return TLGH.readKeyValues("TLG_harness_mpstate.txt").phase end
local function setPhase(p) TLGH.writeFile("TLG_harness_mpstate.txt", { "phase=" .. p }) end

------------------------------------------------------------------------------
-- Main menu: join, then make the character.
------------------------------------------------------------------------------
local fe = { ticks = 0 }

local function connect(next)
    local c = TLGH.readKeyValues("TLG_harness_connect.txt")
    setPhase(next)
    report():line("OBS  MP.connect %s as %s to %s:%s (%s)", MP.role, tostring(c.user), tostring(c.ip), tostring(c.port),
        next)
    ConnectToServer.instance:connect(MainScreen.instance, "", c.user, c.password, c.ip, "", c.port, c.serverPassword,
        false, true, 1)
end

-- A creation screen's Next is pressed 60 ticks after it shows.
local function pressNext(name, screen)
    if not (screen and screen:getIsVisible()) then
        fe[name] = nil
        return
    end
    fe[name] = fe[name] or fe.ticks
    if fe.ticks - fe[name] ~= 60 then return end
    if name == "profession" and not screen.profession then screen:onSelectProf(screen:getSelectedProf()) end
    local prof = name == "profession" and screen.profession
    report():line("OBS  MP.creation %s next%s", name,
        prof and (" (profession " .. tostring(prof:getType():getName()) .. ")") or "")
    screen:onOptionMouseDown(screen.playButton, 0, 0)
end

Events.OnFETick.Add(function()
    fe.ticks = fe.ticks + 1
    local ok, err = pcall(function()
        local p = phase()
        if not fe.joining and not isClient() and fe.ticks > 120 and MainScreen and MainScreen.instance
            and ConnectToServer and ConnectToServer.instance and (p == nil or p == "rejoin") then
            fe.joining = true
            connect(p == "rejoin" and "rejoining" or "joining")
        end
        local ms = MainScreen and MainScreen.instance
        if ms then
            pressNext("profession", ms.charCreationProfession)
            pressNext("main", ms.charCreationMain)
        end
    end)
    if not ok and not fe.failed then
        fe.failed = true
        report():line("STEPERR MP.frontend :: %s", tostring(err))
    end
end)

Events.OnConnected.Add(function()
    report():line("OBS  MP.connected %s (saved player: %s)", MP.role, tostring(checkSavePlayerExists()))
end)

Events.OnConnectFailed.Add(function(message, detail)
    report():line("FAIL MP.connect :: %s %s", tostring(message), tostring(detail))
    report():finish(true)
    getCore():quitToDesktop()
end)

------------------------------------------------------------------------------
-- In the world: helpers.
------------------------------------------------------------------------------
local function player() return getPlayer() end

local function check(name, fn) report():check("MP." .. name .. "_" .. MP.role, fn) end

-- Messages relayed by the server (MPServer.lua), kept by command.
MP.inbox = MP.inbox or {}
MP.cursor = MP.cursor or {}
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "TLGH" then return end
    MP.inbox[command] = MP.inbox[command] or {}
    table.insert(MP.inbox[command], args or {})
end)

local function send(command, args)
    args = args or {}
    args.role = MP.role
    sendClientCommand(player(), "TLGH", command, args)
end

-- The next message `command` from the other client (messages that came
-- before the wait began count too), or nil.
local function nextFrom(command)
    local got = MP.inbox[command] or {}
    for i = (MP.cursor[command] or 0) + 1, #got do
        if got[i].role == MP.other then
            MP.cursor[command] = i
            return got[i]
        end
    end
    return nil
end

local function waitFrom(name, command, onGot, timeout)
    return { name = name, timeout = timeout or 18000, fn = function(ctx, ticks)
        local m = nextFrom(command)
        if not m then return nil end
        if onGot then onGot(m, ctx) end
        return true
    end }
end

-- Asks the server (`command`) and waits for its answer (`answer`) for this
-- client and step; `args` may be a function evaluated when the step starts.
local function call(name, command, args, answer, onAnswer, timeout)
    return { name = name, timeout = timeout or 1800, fn = function(ctx, ticks)
        if ticks == 1 then
            ctx.n = #(MP.inbox[answer] or {})
            local a = {}
            for k, v in pairs(type(args) == "function" and args(ctx) or args) do a[k] = v end
            a.tag = name
            send(command, a)
            return nil
        end
        local got = MP.inbox[answer] or {}
        for i = ctx.n + 1, #got do
            if got[i].role == MP.role and got[i].tag == name then
                onAnswer(got[i], ctx)
                return true
            end
        end
        return nil
    end }
end

-- A step that only runs `fn` once.
local function once(name, fn)
    return { name = name, timeout = 300, fn = function(ctx, ticks) fn(ctx); return true end }
end

local function wait(name, n)
    return { name = name, timeout = n + 60, fn = function(ctx, ticks) return ticks >= n or nil end }
end

-- "T=id;T=id" (the server's give answer) as { type = id }.
local function ids(s)
    local out = {}
    for t, id in string.gmatch(s or "", "([^;=]+)=([^;]+)") do
        out[t] = out[t] or {}
        table.insert(out[t], tonumber(id))
    end
    return out
end

local function inventoryItem(id) return id and player():getInventory():getItemWithID(id) end

local function countType(fullType) return player():getInventory():getCountTypeRecurse(fullType) end

local function teleport(x, y)
    ISTimedActionQueue.clear(player())
    player():teleportTo(x + 0.5, y + 0.5, 0)
end

-- Scrolls the zoom to `target` one level at a time (as SPHarness's
-- RT.MI.zoomTo, which reads the direction from Core.getNextZoom).
local function zoomTo(name, target)
    return { name = name, timeout = 1800, fn = function(ctx, ticks)
        local c = getCore()
        local z = c:getZoom(0)
        if not ctx.from then
            ctx.from, ctx.last, ctx.still, ctx.scrolls = z, z, 0, 0
            ctx.inward = (c:getNextZoom(0, -1) < z or c:getNextZoom(0, 1) > z) and -1 or 1
            return nil
        end
        if math.abs(z - ctx.last) > 1e-4 then
            ctx.last, ctx.still = z, 0
            return nil
        end
        ctx.still = ctx.still + 1
        if ctx.still < 30 then return nil end
        if math.abs(z - target) > 0.01 and ctx.scrolls < 12 then
            c:doZoomScroll(0, z > target and ctx.inward or -ctx.inward)
            ctx.scrolls, ctx.still = ctx.scrolls + 1, 0
            return nil
        end
        report():line("OBS  MP.zoom %.2f -> %.2f", ctx.from, z)
        return true
    end }
end

local function screenshot(name)
    local file = "tlg_mp" .. MP.role:lower() .. "_" .. name .. ".png"
    local ok, err = pcall(function() getCore():TakeFullScreenshot(file) end)
    local p = player()
    report():line("OBS  MP.screenshot %s ok=%s %s; zoom %.2f; player %.1f,%.1f", file, tostring(ok),
        ok and "" or tostring(err), getCore():getZoom(0), p:getX(), p:getY())
end

-- A screenshot with the interface hidden.
local function shot(name)
    return { name = "mp_shot_" .. name, timeout = 600, fn = function(ctx, ticks)
        if ticks == 1 then ISUIHandler.setVisibleAllUI(false) end
        if ticks == 60 then screenshot(name) end
        if ticks == 120 then ISUIHandler.setVisibleAllUI(true) end
        return ticks >= 150 or nil
    end }
end

-- The other player's character on this client.
local function otherPlayer()
    local want = MP.role == "A" and "tlgb" or "tlga"
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p:getUsername() == want then return p end
    end
    return nil
end

-- A TLG request through the mod's own client API, waiting for its reply.
local function request(name, command, argsFn, onReply, timeout)
    return { name = name, timeout = timeout or 1800, fn = function(ctx, ticks)
        if ticks == 1 then
            ctx.args = argsFn(ctx)
            if not ctx.args then
                report():line("FAIL MP.%s_%s :: nothing to ask about", name, MP.role)
                return true
            end
            TLG.Net.request(command, ctx.args, function(r) ctx.reply = r end)
            return nil
        end
        if not ctx.reply then return nil end
        onReply(ctx.reply, ctx)
        return true
    end }
end

local function brief(r)
    return string.format("ok=%s reason=%s duplicate=%s state=%s", tostring(r and r.ok), tostring(r and r.reason),
        tostring(r and r.duplicate), tostring(r and r.state))
end

------------------------------------------------------------------------------
-- Both clients.
------------------------------------------------------------------------------
MP.waitWorld = { name = "mp_wait_world", timeout = 3000, fn = function(ctx, ticks)
    local p = player()
    if not p or ticks < 120 then return nil end
    local zombies = getCell():getZombieList()
    report():line("OBS  MP.world %s user=%s at %d,%d isClient=%s online=%s role=%s zombies in cell=%s Zombies=%s fog=%.2f",
        MP.role, tostring(p:getUsername()), math.floor(p:getX()), math.floor(p:getY()), tostring(isClient()),
        tostring(getOnlinePlayers() and getOnlinePlayers():size()),
        tostring(select(2, pcall(function() return p:getRole():getName() end))),
        tostring(zombies and zombies:size()), tostring(SandboxVars.Zombies),
        getClimateManager():getClimateFloat(5):getFinalValue())
    check("joined", function()
        local want = TLGH.readKeyValues("TLG_harness_connect.txt").user
        return isClient() and p:getUsername() == want, string.format("isClient=%s user=%s", tostring(isClient()),
            tostring(p:getUsername()))
    end)
    return true
end }

MP.finish = { name = "mp_finish", timeout = 600, fn = function(ctx, ticks)
    if not ctx.done then
        ISUIHandler.setVisibleAllUI(true)
        report():finish(true)
        ctx.done = true
        return nil
    end
    if ticks == 60 then getCore():quitToDesktop() end
    return nil
end }


------------------------------------------------------------------------------
-- Both clients: moving and looking.
------------------------------------------------------------------------------
-- Walks to a square as a player would, then waits a second. A teleport
-- left the server's idea of the character a square or more behind, and
-- run 139's drops landed where the server last saw her. `x` may be a
-- function giving x, y when the step starts.
local function walkTo(name, x, y)
    return { name = name, timeout = 2400, fn = function(ctx, ticks)
        local p = player()
        if ticks == 1 then
            local tx, ty = x, y
            if type(x) == "function" then tx, ty = x() end
            ISTimedActionQueue.clear(p)
            ISTimedActionQueue.add(ISWalkToTimedAction:new(p, getCell():getGridSquare(tx, ty, 0)))
            return nil
        end
        if ticks < 30 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        return ticks - ctx.idle >= 60 or nil
    end }
end

local function idle(name)
    return { name = name, timeout = 3600, fn = function(ctx, ticks)
        if ticks < 30 or not TLGH.Steps.actionsIdle(player()) then return nil end
        ctx.idle = ctx.idle or ticks
        return ticks - ctx.idle >= 60 or nil
    end }
end

-- The world item on (x, y) of `fullType`, as this client sees it.
local function floorItem(x, y, fullType)
    local sq = getCell():getGridSquare(x, y, 0)
    local objs = sq and sq:getWorldObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local item = objs:get(i):getItem()
        if item and item:getFullType() == fullType then return item end
    end
    return nil
end

-- The small items the row is checked for.
MP.small = { "TLG.FuelSampleKit", "TLG.YeastStarter", "TLG.FuelStabilizer", "TLG.ManualFuelSystems", "TLG.FuelFilter" }

-- What lies on the floor around the spawn point on this client's screen
-- against what the server holds there, and all five small items there.
local function compareFloor(name)
    return call(name, "probe_floor", {}, "probe_floor", function(m)
        local mine = S.floorAround()
        report():line("OBS  MP.%s this client %s", name, mine)
        report():line("OBS  MP.%s the server  %s", name, tostring(m.floor))
        local missing = {}
        for _, t in ipairs(MP.small) do
            if not string.find(m.floor or "", t, 1, true) then missing[#missing + 1] = t end
        end
        check(name, function()
            return mine == m.floor and #missing == 0, string.format("same as the server=%s; missing on the server: %s",
                tostring(mine == m.floor), #missing > 0 and table.concat(missing, " ") or "none")
        end)
    end)
end

local function vesselStatus(name)
    return request(name, "machine.status", function()
        local x, y = S.spot(3)
        local item = floorItem(x, y, "TLG.FermenterVessel")
        return item and { target = TLG.Integration.Machines.refFor(item) }
    end, function(r)
        check("machine_status", function() return r.ok == true and r.state ~= nil, brief(r) end)
    end)
end

-- A print medium given by the server, read through the inventory menu's
-- Inspect (as SPHarness's RT.MN.read); `idFn` gives the item's id.
local function readMedia(name, idFn)
    return { name = name, timeout = 9000, fn = function(ctx, ticks)
        local p = player()
        if not ctx.item then
            ctx.item = inventoryItem(idFn())
            if not ctx.item then
                if ticks > 600 then
                    report():line("FAIL MP.%s_%s :: it never reached the inventory", name, MP.role)
                    return true
                end
                return nil
            end
            local pm = ctx.item:getModData().printMedia
            ctx.media = pm and pm.id
            ISTimedActionQueue.clear(p)
            local context = ISInventoryPaneContextMenu.createMenu(0, true, { ctx.item }, 100, 100)
            local inspect = context and context:getOptionFromName(getText("ContextMenu_Inspect"))
            if context then context:setVisible(false) end
            check(name .. "_offers_inspect", function()
                return inspect ~= nil, string.format("%s printMedia on the client: %s", ctx.item:getFullType(),
                    tostring(ctx.media))
            end)
            if inspect then inspect.onSelect(inspect.target, inspect.param1, inspect.param2) end
            ctx.started = ticks
            return nil
        end
        if ticks - ctx.started < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        if not ctx.after then
            ctx.after = ticks
            return nil
        end
        -- The read as this client knows it, at once and a few seconds on
        -- (run 140: the server records it, this client does not, for the
        -- manual and for vanilla's flier alike).
        if ticks - ctx.after == 1 then ctx.soon = p:isPrintMediaRead(ctx.media) end
        if ticks - ctx.after < 300 then return nil end
        MP.readMedia = MP.readMedia or {}
        MP.readMedia[name] = ctx.media
        MP.readClient = MP.readClient or {}
        MP.readClient[name] = p:isPrintMediaRead(ctx.media)
        report():line("OBS  MP.%s read on this client: isPrintMediaRead(%s) when the read ended=%s, 5 s later=%s", name,
            tostring(ctx.media), tostring(ctx.soon), tostring(MP.readClient[name]))
        return true
    end }
end

local function readOnServer(name, which)
    return call(name, "probe_read", function() return { media = MP.readMedia and MP.readMedia[which] } end, "probe_read",
        function(m)
            MP.readServer = MP.readServer or {}
            MP.readServer[which] = m.read == "true"
            check(name, function() return m.read == "true", "server isPrintMediaRead=" .. tostring(m.read) end)
        end)
end

-- The manual's read is kept as vanilla's own print media's is: the same on
-- the server and on this client as for the flier.
local function readLikeVanilla(name)
    return once(name, function()
        local c, s = MP.readClient or {}, MP.readServer or {}
        check(name, function()
            return s.manual == true and s.manual == s.flier and c.manual == c.flier, string.format(
                "manual: server %s, client %s; flier: server %s, client %s", tostring(s.manual), tostring(c.manual),
                tostring(s.flier), tostring(c.flier))
        end)
    end)
end

------------------------------------------------------------------------------
-- Client A.
------------------------------------------------------------------------------
local A = { ids = {} }
MP.A = A

-- The row (k -2..2) the small items are dropped on and A walks along
-- carrying the vessel; the vessel's square (k 3); B stands a square nearer
-- the camera than the middle of the row (at zoom 0.5 a character on the
-- row behind stood above B's frame).

-- T1: the server's answers to the mod's item requests.
A.give1 = call("give_fuel", "give", { items = "Base.PetrolCan;TLG.FuelStabilizer;TLG.FuelStabilizer", petrol = "5" },
    "given", function(m) A.ids = ids(m.ids) end)

A.haveFuel = { name = "mp_have_fuel", timeout = 900, fn = function(ctx, ticks)
    A.can = inventoryItem(A.ids["Base.PetrolCan"] and A.ids["Base.PetrolCan"][1])
    if not A.can and ticks < 600 then return nil end
    check("items_from_server", function()
        return A.can ~= nil and countType("TLG.FuelStabilizer") == 2, string.format(
            "can %s (%s L), stabilizers %d", tostring(A.can and A.can:getID()),
            tostring(A.can and A.can:getFluidContainer() and A.can:getFluidContainer():getAmount()),
            countType("TLG.FuelStabilizer"))
    end)
    return true
end }

A.sample = request("sample", "sample", function()
    return A.can and { target = { kind = "item", id = A.can:getID() }, method = "visual" }
end, function(r)
    check("sample", function() return r.ok == true and r.observation ~= nil, brief(r) end)
end)

A.treat = request("treat", "treat", function()
    return A.can and { target = { kind = "item", id = A.can:getID() }, op = "stabilize" }
end, function(r, ctx)
    A.treatArgs = ctx.args
    check("stabilize", function() return r.ok == true, brief(r) end)
end)

A.afterTreat = { name = "mp_after_treat", timeout = 900, fn = function(ctx, ticks)
    if ticks < 120 then return nil end
    check("stabilizer_used_once", function()
        return countType("TLG.FuelStabilizer") == 1, string.format("stabilizers left %d", countType("TLG.FuelStabilizer"))
    end)
    return true
end }

-- The same treatment again with the same request id, as a retry would send
-- it: the server must answer from its ledger and use nothing more.
A.retry = { name = "mp_retry", timeout = 1200, fn = function(ctx, ticks)
    if ticks == 1 then
        if not A.treatArgs then return true end
        TLG.Net.pending[A.treatArgs.requestId] = function(r) ctx.reply = r end
        sendClientCommand(player(), "TLG", "treat", A.treatArgs)
        return nil
    end
    if not ctx.reply or ticks < 120 then return nil end
    check("retry_answered_from_ledger", function()
        return ctx.reply.duplicate == true and countType("TLG.FuelStabilizer") == 1,
            brief(ctx.reply) .. string.format(" stabilizers left %d", countType("TLG.FuelStabilizer"))
    end)
    return true
end }

A.compare = call("probe_can", "probe_item", function() return { id = A.can and A.can:getID() } end, "probe_item",
    function(m)
        local mine = S.sidecar(A.can)
        report():line("OBS  MP.can_record client %s", mine)
        report():line("OBS  MP.can_record server %s (fluid %s)", tostring(m.sidecar), tostring(m.fluid))
        check("can_record_same_on_client", function()
            return m.found == "true" and m.sidecar ~= "no-sidecar" and m.sidecar == mine, "see the two records above"
        end)
    end)

-- T2: a machine the server put down, its status asked for within reach by
-- A, then by B (run 139 asked from four tiles away and the mod refused:
-- no_access).
A.spawnVessel = call("spawn_vessel", "spawn", function()
    local x, y = S.spot(3)
    return { item = "TLG.FermenterVessel", x = x, y = y, batch = "1" }
end, "spawned", function(m)
    A.vesselId = tonumber(m.id)
    report():line("OBS  MP.vessel %s spawned with its batch %s", tostring(m.id), tostring(m.batch))
end)

-- T5: a manual the server rolled from its loot lists, then a vanilla flier
-- given by the server, each read through Inspect.
A.roll = call("roll_manual", "roll_manual", { fills = "100" }, "rolled", function(m)
    A.manualId = tonumber(m.id)
    check("manual_in_server_loot", function()
        return tonumber(m.manuals or 0) > 0, string.format("%s manuals in %s containers filled on the server; printMedia=%s",
            tostring(m.manuals), tostring(m.fills), tostring(m.printMedia))
    end)
end, 3600)

A.giveFlier = call("give_flier", "give", { items = "Base.Flier_Nolans" }, "given", function(m)
    local got = ids(m.ids)
    A.flierId = got["Base.Flier_Nolans"] and got["Base.Flier_Nolans"][1]
end)

-- T3: the small items, dropped one a square as a player drops them
-- (ISInventoryPaneContextMenu.dropItem) after walking there.
A.give3 = call("give_floor", "give", { items = "TLG.FuelSampleKit;TLG.YeastStarter;TLG.FuelFilter" }, "given",
    function(m) for t, list in pairs(ids(m.ids)) do A.ids[t] = list end end)

local function dropOne(fullType)
    return once("mp_drop_" .. fullType, function()
        local item
        if fullType == "TLG.ManualFuelSystems" then
            item = inventoryItem(A.manualId)
        else
            local list = player():getInventory():getItemsFromFullType(fullType)
            item = list and list:size() > 0 and list:get(0) or nil
        end
        if item then
            ISInventoryPaneContextMenu.dropItem(item, 0)
        else
            report():line("OBS  MP.drop %s: not in the inventory", fullType)
        end
    end)
end

-- T4: a heavy item taken off the floor as a double-click in the loot
-- window takes it: A stands on its square, the loot window lists it, and
-- equipHeavyItem gets the item as that floor container holds it
-- (ISInventoryPane.lua does the same). The server's ISEquipHeavyItem.complete
-- fails there ("attempted index: DoRemoveItem of non-table", runs 141-145:
-- the world item has no container on the server), so vanilla's meteorite
-- must stay on the floor; the mod takes the vessel itself (D-030). If the
-- vessel does not come into A's hands, the server hands it over
-- (MPServer.lua hold) so the carry pose can still be watched from both
-- screens.
local function floorListing(fullType)
    local floor = ISInventoryPage.GetFloorContainer(0)
    local items = floor and floor:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        if items:get(i):getFullType() == fullType then return floor, items:get(i) end
    end
    return floor, nil
end

local function actionNames(p)
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    local names = {}
    for _, a in ipairs(q and q.queue or {}) do names[#names + 1] = tostring(a.Type) end
    return #names > 0 and table.concat(names, ", ") or "none"
end

local function inBothHands(p, fullType)
    local held = p:getPrimaryHandItem()
    return held ~= nil and held:getFullType() == fullType and p:getSecondaryHandItem() == held
end

-- `taken`: whether the item must come into both hands (the mod's vessel) or
-- stay on its square (vanilla's own heavy items on a server).
local function takeHeavy(name, fullType, k, taken)
    return { name = "mp_take_" .. name, timeout = 2400, fn = function(ctx, ticks)
        local p = player()
        if ticks == 1 then
            ISUIHandler.setVisibleAllUI(true)
            pcall(function() getPlayerLoot(0):refreshBackpacks() end)
            return nil
        end
        if ticks == 60 then
            pcall(function() getPlayerLoot(0):refreshBackpacks() end)
            local x, y = S.spot(k)
            local onSquare = floorItem(x, y, fullType)
            local floor, listed = floorListing(fullType)
            local item = listed or onSquare
            report():line("OBS  MP.%s on its square=%s; the loot window's floor (%s) lists it=%s, the same object=%s",
                name, tostring(onSquare ~= nil), tostring(floor and floor:getType()), tostring(listed ~= nil),
                tostring(listed ~= nil and listed == onSquare))
            if not item then
                report():line("FAIL MP.%s_from_floor_%s :: not on its square", name, MP.role)
                return true
            end
            ISInventoryPaneContextMenu.equipHeavyItem(p, item)
            report():line("OBS  MP.%s pickup queued: %s", name, actionNames(p))
            ctx.queued = ticks
            return nil
        end
        if not ctx.queued then return nil end
        if ticks - ctx.queued == 30 then report():line("OBS  MP.%s pickup 30 ticks on: %s", name, actionNames(p)) end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        if ticks - ctx.idle < 120 then return nil end
        local held = p:getPrimaryHandItem()
        local x, y = S.spot(k)
        local still = floorItem(x, y, fullType) ~= nil
        local detail = string.format("primary=%s secondary=%s; still on its square=%s",
            tostring(held and held:getFullType()),
            tostring(p:getSecondaryHandItem() and p:getSecondaryHandItem():getFullType()), tostring(still))
        if taken then
            check(name .. "_from_floor", function() return inBothHands(p, fullType) and not still, detail end)
        else
            check(name .. "_left_on_floor_by_the_game", function()
                return not inBothHands(p, fullType) and still, detail
            end)
        end
        return true
    end }
end

-- Where the server holds the vessel, how many vessels it holds around, the
-- vessel's batch and the mod's takes on the server so far (MPServer.lua
-- probe_vessel).
local function probeVessel(name, judge)
    return call(name, "probe_vessel", function() return { id = A.vesselId } end, "probe_vessel", function(m)
        report():line("OBS  MP.%s server: where=%s vessels=%s state=%s pause=%s site=%s listed=%s takes=%s", name,
            tostring(m.where), tostring(m.vessels), tostring(m.state), tostring(m.pause), tostring(m.site),
            tostring(m.listed), tostring(m.takes))
        judge(m)
    end)
end

-- Taken by the mod on the server: in A's inventory and both hands, the only
-- vessel there, its batch carried (paused, off the hourly list).
A.takenSeen = probeVessel("vessel_taken", function(m)
    check("vessel_taken_on_server", function()
        return m.where == "inventory tlga both hands" and m.vessels == 1 and m.state == "Paused"
            and m.pause == "not_placed" and m.listed == "no", "see the server's line above"
    end)
end)

-- The record A's client got with the vessel: the batch carried, as the
-- server accounted it before sending the item (Machines.takeOnServer).
A.carriedRecord = once("mp_carried_record", function()
    local held = player():getPrimaryHandItem()
    local rec = held and held:getModData().tlgProc
    check("vessel_record_carried_on_client", function()
        return rec ~= nil and rec.pause == "not_placed", string.format("state=%s pause=%s", tostring(rec and rec.state),
            tostring(rec and rec.pause))
    end)
end)

-- The vessel handed over by the server, unless A already holds it.
A.holdVessel = { name = "mp_hold_vessel", timeout = 1800, fn = function(ctx, ticks)
    local p = player()
    if ticks == 1 then
        if inBothHands(p, "TLG.FermenterVessel") then
            ctx.done = true
            return nil
        end
        ctx.n = #(MP.inbox.held or {})
        send("hold", { item = "TLG.FermenterVessel", tag = "hold_vessel" })
        return nil
    end
    if not ctx.done and not inBothHands(p, "TLG.FermenterVessel") and ticks < 1200 then return nil end
    if ticks < 120 then return nil end
    ISUIHandler.setVisibleAllUI(false)
    check("vessel_in_both_hands", function()
        local held = p:getPrimaryHandItem()
        return inBothHands(p, "TLG.FermenterVessel"), string.format("%s; primary=%s RightHandMask=%s",
            ctx.done and "taken off the floor" or "handed over by the server", tostring(held and held:getFullType()),
            tostring(p:getVariableString("RightHandMask")))
    end)
    return true
end }

-- What is carried in both hands put down at the feet, from a multiplayer
-- client by the server's command for it (as ISEnterVehicle.lua and the
-- mod's Machines.putDownForAction do).
local function dropHeavy(p) sendClientCommand(p, "player", "onDropHeavyItem", { id = p:getOnlineID() }) end

A.dropHeavy = { name = "mp_drop_heavy", timeout = 600, fn = function(ctx, ticks)
    if ticks == 1 then dropHeavy(player()) end
    return ticks >= 120 or nil
end }

-- One gait: A moves (or stands), tells B half way along (at the leg's
-- start in run 142, so A stood at the edge of B's frame), and waits until
-- B has its shot. Running also turns on Toggle to Run, as SPHarness's
-- RT.VG legs do (run 142 read running=false without it).
local function gait(name, opts)
    return { name = "mp_gait_" .. name, timeout = 3600, fn = function(ctx, ticks)
        local p = player()
        if ticks == 1 then
            ISTimedActionQueue.clear(p)
            p:setSneaking(opts.sneak == true)
            ctx.toggle = getCore():isToggleToRun()
            if opts.run then getCore():setToggleToRun(true) end
            if opts.to then
                local x, y = S.spot(opts.to)
                ctx.x0, ctx.y0, ctx.x1, ctx.y1 = p:getX(), p:getY(), x + 0.5, y + 0.5
                ISTimedActionQueue.add(ISWalkToTimedAction:new(p, getCell():getGridSquare(x, y, 0)))
            end
            return nil
        end
        if opts.run then p:setForceRun(true) end
        if opts.sprint then p:setForceSprint(true) end
        local half
        if opts.to then
            local total = math.sqrt((ctx.x1 - ctx.x0) ^ 2 + (ctx.y1 - ctx.y0) ^ 2)
            local done = math.sqrt((p:getX() - ctx.x0) ^ 2 + (p:getY() - ctx.y0) ^ 2)
            half = total > 0 and done / total >= 0.45
        else
            half = ticks >= 60
        end
        if not ctx.sent and half then
            ctx.sent = ticks
            ctx.n = #(MP.inbox.gait_shot or {})
            send("gait", { name = name })
            screenshot("carry_" .. name)
            report():line("OBS  MP.carry %s on A's own screen: running=%s sprinting=%s sneaking=%s RightHandMask=%s"
                .. " both hands=%s", name, tostring(p:isRunning()), tostring(p:isSprinting()), tostring(p:isSneaking()),
                tostring(p:getVariableString("RightHandMask")),
                tostring(p:getPrimaryHandItem() ~= nil and p:getPrimaryHandItem() == p:getSecondaryHandItem()))
            return nil
        end
        if not ctx.sent then return nil end
        local got = MP.inbox.gait_shot or {}
        for i = ctx.n + 1, #got do
            if got[i].role == "B" and got[i].name == name then ctx.shot = true end
        end
        if not ctx.shot or not TLGH.Steps.actionsIdle(p) then return nil end
        p:setForceRun(false)
        p:setForceSprint(false)
        getCore():setToggleToRun(ctx.toggle)
        return true
    end }
end

A.putDown = { name = "mp_put_down", timeout = 900, fn = function(ctx, ticks)
    local p = player()
    if ticks == 1 then
        p:setSneaking(false)
        dropHeavy(p)
        ISUIHandler.setVisibleAllUI(true)
        return nil
    end
    if ticks < 120 then return nil end
    report():line("OBS  MP.vessel put down: in the hands %s", tostring(p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()))
    return true
end }

-- Put down at A's feet: on the floor where its record says, listed for the
-- hourly reading there, its batch running again.
A.putDownSeen = probeVessel("vessel_put_down", function(m)
    A.vesselAt, A.takesBefore = m.site, m.takes or ""
    check("vessel_put_down_on_server", function()
        return m.where == "floor " .. tostring(m.site) and m.vessels == 1 and m.state == "Processing"
            and m.pause == "none" and m.listed == m.site, "see the server's line above"
    end)
end)

-- T6: both players take the vessel off the floor at once (D-030's refusal).
-- B stands next to it; A tells B and starts at once, B starts on the tick
-- the message comes. The server parses both actions while the vessel still
-- lies there, so the one completing second finds it in the first's
-- inventory and must be refused: one vessel, one holder. Whether that
-- second action reached the server's complete or its client stopped it
-- first shows in the server's takes. The same take, run on the server for
-- the player without the vessel (MPServer.lua try_take), must be refused.
local V = "TLG.FermenterVessel"
local B = {}
MP.B = B

local function holdsVessel(p) return p ~= nil and inBothHands(p, V) end

local function count(s, pattern) return select(2, string.gsub(s or "", pattern, "")) end

-- The loot window refreshed, then `message` sent (with `args()`).
local function raceReady(name, message, args)
    return { name = name, timeout = 900, fn = function(ctx, ticks)
        if ticks == 1 then
            pcall(function() getPlayerLoot(0):refreshBackpacks() end)
            return nil
        end
        if ticks < 60 then return nil end
        local _, listed = floorListing(V)
        report():line("OBS  MP.race %s ready: the loot window lists the vessel=%s", MP.role, tostring(listed ~= nil))
        send(message, args and args() or {})
        return true
    end }
end

local function raceTake(first)
    return { name = "mp_race_take", timeout = 3600, fn = function(ctx, ticks)
        local p = player()
        if not ctx.queued then
            if first then
                send("race_now", {})
            elseif not nextFrom("race_now") then
                return nil
            end
            local _, listed = floorListing(V)
            if not listed then
                report():line("FAIL MP.race_listed_%s :: the loot window does not list the vessel", MP.role)
                return true
            end
            ISInventoryPaneContextMenu.equipHeavyItem(p, listed)
            ctx.queued = ticks
            report():line("OBS  MP.race %s queued at tick %d: %s", MP.role, ticks, actionNames(p))
            return nil
        end
        if ticks - ctx.queued == 30 then report():line("OBS  MP.race %s 30 ticks on: %s", MP.role, actionNames(p)) end
        if ticks - ctx.queued < 60 or not TLGH.Steps.actionsIdle(p) then return nil end
        ctx.idle = ctx.idle or ticks
        if ticks - ctx.idle < 180 then return nil end
        local other = otherPlayer()
        local mine, theirs = holdsVessel(p), holdsVessel(other)
        check("race_one_holder_seen", function()
            return (mine and 1 or 0) + (theirs and 1 or 0) == 1, string.format("this player holds it=%s, the other=%s"
                .. " (found=%s)", tostring(mine), tostring(theirs), tostring(other ~= nil))
        end)
        return true
    end }
end

A.raceSeen = probeVessel("race", function(m)
    local since = string.sub(m.takes or "", #(A.takesBefore or "") + 1)
    local taken, refused = count(since, ":true"), count(since, ":false")
    report():line("OBS  MP.race the server's takes since the put-down:%s; the second action %s", since,
        refused > 0 and "was refused on the server" or "did not reach the server's complete")
    check("race_one_vessel_one_holder_on_server", function()
        return m.vessels == 1 and taken == 1 and (m.where == "inventory tlga both hands"
            or m.where == "inventory tlgb both hands") and m.pause == "not_placed", "see the server's line above"
    end)
end)

A.tryTake = call("try_take", "try_take", function() return { id = A.vesselId } end, "try_take", function(m)
    report():line("OBS  MP.try_take holder=%s taker=%s result=%s holder keeps it=%s taker has it=%s takes=%s",
        tostring(m.holder), tostring(m.taker), tostring(m.result), tostring(m.holderKeeps), tostring(m.takerHas),
        tostring(m.takes))
    check("take_of_a_held_vessel_refused_on_server", function()
        return m.result == "false" and m.holderKeeps == "true" and m.takerHas == "false", "see the line above"
    end)
end)

-- Whoever holds the vessel after the race puts it down again.
local function raceDrop()
    return { name = "mp_race_drop", timeout = 600, fn = function(ctx, ticks)
        if ticks == 1 then
            if holdsVessel(player()) then dropHeavy(player()) end
            return nil
        end
        return ticks >= 120 or nil
    end }
end

local function raceStepsA()
    return {
        raceReady("mp_race_ready", "race_ready", function()
            local x, y = string.match(A.vesselAt or "", "(%-?%d+),(%-?%d+)")
            return { x = tonumber(x), y = tonumber(y) }
        end),
        waitFrom("mp_wait_race_at", "race_at"), raceTake(true), waitFrom("mp_wait_race_done", "race_done"),
        A.raceSeen, A.tryTake, once("mp_race_drop_please", function() send("race_drop", {}) end), raceDrop() }
end

local function raceStepsB(backX, backY)
    return {
        waitFrom("mp_wait_race_ready", "race_ready", function(m) B.raceX, B.raceY = tonumber(m.x), tonumber(m.y) end),
        walkTo("mp_walk_to_race", function()
            local nx, ny = S.spot(2)
            return (B.raceX or nx) + 1, (B.raceY or ny) + 1
        end),
        raceReady("mp_race_at", "race_at"), raceTake(false), once("mp_race_done", function() send("race_done", {}) end),
        waitFrom("mp_wait_race_drop", "race_drop"), raceDrop(), walkTo("mp_walk_back_after_race", backX, backY) }
end

-- Last: leave to the main menu and join again (MainScreen's in-game Exit).
A.leave = { name = "mp_leave", timeout = 600, fn = function(ctx, ticks)
    if ticks == 1 then
        send("reconnecting", {})
        return nil
    end
    if ticks < 60 then return nil end
    setPhase("rejoin")
    report():line("OBS  MP.leaving to the main menu")
    setGameSpeed(1)
    getCore():quit()
    return true
end }

local function stand(name, x, y, d)
    return once(name, function() teleport(x + (d or 0), y + (d or 0)) end)
end

local bx0, by0 = S.behind(0)
local nearX, nearY = S.spot(2)
MP.stepsA = {
    MP.waitWorld, zoomTo("mp_zoom", 0.5), stand("mp_stand", bx0, by0),
    waitFrom("mp_wait_b", "hello", function() send("start", {}) end),
    A.give1, A.haveFuel, A.sample, A.treat, A.afterTreat, A.retry, A.compare,
    A.spawnVessel, wait("mp_vessel_lands", 120),
    walkTo("mp_walk_to_vessel", nearX, nearY), vesselStatus("status"), walkTo("mp_walk_back", bx0, by0),
    once("mp_status_please", function() send("status_please", {}) end), waitFrom("mp_wait_status_b", "status_done"),
    A.roll, readMedia("manual", function() return A.manualId end), readOnServer("manual_read_on_server", "manual"),
    A.giveFlier, readMedia("flier", function() return A.flierId end), readOnServer("flier_read_on_server", "flier"),
    readLikeVanilla("manual_read_kept_like_vanilla"),
    A.give3, wait("mp_floor_items_arrive", 180),
}
for i, t in ipairs(MP.small) do
    local x, y = S.spot(i - 3)
    table.insert(MP.stepsA, walkTo("mp_walk_drop_" .. i, x, y))
    table.insert(MP.stepsA, dropOne(t))
    table.insert(MP.stepsA, idle("mp_dropped_" .. i))
end
for _, s in ipairs({
    walkTo("mp_walk_floor_view", bx0, by0),
    once("mp_floor_ready", function() send("floor_ready", {}) end), shot("floor"),
    waitFrom("mp_wait_floor_b", "floor_shot"), compareFloor("floor_seen"),
}) do table.insert(MP.stepsA, s) end
local function carrySteps()
    return {
        call("spawn_meteorite", "spawn", function()
            local x, y = S.spot(4)
            return { item = "Base.LargeMeteorite", x = x, y = y }
        end, "spawned", function() end),
        wait("mp_meteorite_lands", 120), walkTo("mp_walk_onto_meteorite", S.spot(4)),
        takeHeavy("meteorite", "Base.LargeMeteorite", 4, false), A.dropHeavy,
        walkTo("mp_walk_onto_vessel", S.spot(3)), takeHeavy("vessel", "TLG.FermenterVessel", 3, true), A.takenSeen,
        A.carriedRecord, A.holdVessel,
        walkTo("mp_walk_carry_start", S.spot(-2)),
        gait("stand", {}), gait("walk", { to = 2 }), gait("run", { to = -2, run = true }),
        gait("sprint", { to = 2, sprint = true }), gait("sneak", { to = -2, sneak = true }),
        gait("crouch", { sneak = true }), A.putDown, A.putDownSeen }
end
for _, s in ipairs(carrySteps()) do table.insert(MP.stepsA, s) end
for _, s in ipairs(raceStepsA()) do table.insert(MP.stepsA, s) end
table.insert(MP.stepsA, walkTo("mp_walk_back_end", bx0, by0))
table.insert(MP.stepsA, A.leave)

-- `-Only carry` (tools/run-mp-harness.ps1): the vessel's pickup and gaits alone.
MP.only = TLGH.readKeyValues("TLG_harness_connect.txt").only
if MP.only == "carry" then
    MP.stepsA = { MP.waitWorld, zoomTo("mp_zoom", 0.5), stand("mp_stand", bx0, by0),
        waitFrom("mp_wait_b", "hello", function() send("start", {}) end), A.spawnVessel, wait("mp_vessel_lands", 120) }
    for _, s in ipairs(carrySteps()) do table.insert(MP.stepsA, s) end
    for _, s in ipairs(raceStepsA()) do table.insert(MP.stepsA, s) end
    table.insert(MP.stepsA, once("mp_finish_b", function() send("finish", {}) end))
    table.insert(MP.stepsA, MP.finish)
elseif MP.only == "heavy" then
    -- `-Only heavy` (with -NoMod, a server and client without the mod):
    -- vanilla's meteorite taken off the floor the same way, alone.
    MP.stepsA = { MP.waitWorld, zoomTo("mp_zoom", 0.5), stand("mp_stand", bx0, by0),
        call("spawn_meteorite", "spawn", function()
            local x, y = S.spot(4)
            return { item = "Base.LargeMeteorite", x = x, y = y }
        end, "spawned", function() end),
        wait("mp_meteorite_lands", 120), walkTo("mp_walk_onto_meteorite", S.spot(4)),
        takeHeavy("meteorite", "Base.LargeMeteorite", 4, false), shot("meteorite"), A.dropHeavy, MP.finish }
end

-- After joining again: the floor as A's client receives it from the server.
MP.stepsRejoined = {
    MP.waitWorld, zoomTo("mp_zoom", 0.5), wait("mp_settle", 120),
    compareFloor("floor_after_rejoin"), shot("after_rejoin"),
    once("mp_rejoined", function() send("rejoined", {}) end), waitFrom("mp_wait_rejoin_b", "rejoin_shot"),
    once("mp_finish_b", function() send("finish", {}) end), MP.finish,
}

------------------------------------------------------------------------------
-- Client B: stands where it sees the row and answers A.
------------------------------------------------------------------------------
-- What B sees of A carrying the vessel: B's own screenshot, taken the tick
-- A's message comes, and the carry pose's variables on A's character as
-- B's client holds it.
local function seeGait(name)
    return waitFrom("mp_see_" .. name, "gait", function(g)
        screenshot("carry_" .. tostring(g.name))
        local a = otherPlayer()
        local held = a and a:getPrimaryHandItem()
        local mask = a and a:getVariableString("RightHandMask")
        report():line("OBS  MP.carry %s on B's screen: A found=%s running=%s sprinting=%s sneaking=%s RightHandMask=%s"
            .. " primary=%s secondary=%s", tostring(g.name), tostring(a ~= nil), tostring(a and a:isRunning()),
            tostring(a and a:isSprinting()), tostring(a and a:isSneaking()), tostring(mask),
            tostring(held and held:getFullType()), tostring(a and a:getSecondaryHandItem() and a:getSecondaryHandItem():getFullType()))
        check("carry_seen_" .. tostring(g.name), function()
            return a ~= nil and held ~= nil and held:getFullType() == "TLG.FermenterVessel"
                and a:getSecondaryHandItem() == held and mask == "tlgcarryvessel",
                string.format("RightHandMask=%s primary=%s", tostring(mask), tostring(held and held:getFullType()))
        end)
        send("gait_shot", { name = g.name })
    end)
end

local vx, vy = S.spot(0)
MP.stepsB = {
    MP.waitWorld, zoomTo("mp_zoom", 0.5), stand("mp_stand", vx, vy, 1),
    once("mp_hide_ui", function() ISUIHandler.setVisibleAllUI(false) end),
    once("mp_hello", function() send("hello", {}) end), waitFrom("mp_wait_start", "start"),
    waitFrom("mp_wait_status_please", "status_please"),
    walkTo("mp_walk_to_vessel", nearX, nearY), vesselStatus("status"), walkTo("mp_walk_back", vx + 1, vy + 1),
    once("mp_status_done", function() send("status_done", {}) end),
    waitFrom("mp_wait_floor", "floor_ready"), wait("mp_floor_settle", 60),
    once("mp_floor_shot", function() screenshot("floor") end), compareFloor("floor_seen_by_other"),
    once("mp_floor_shot_done", function() send("floor_shot", {}) end),
    seeGait("stand"), seeGait("walk"), seeGait("run"), seeGait("sprint"), seeGait("sneak"), seeGait("crouch"),
}
for _, s in ipairs(raceStepsB(vx + 1, vy + 1)) do table.insert(MP.stepsB, s) end
for _, s in ipairs({
    waitFrom("mp_wait_reconnecting", "reconnecting", function() report():line("OBS  MP.A is leaving to join again") end),
    waitFrom("mp_wait_rejoined", "rejoined"), wait("mp_rejoin_settle", 60),
    once("mp_rejoin_shot", function() screenshot("after_rejoin") end), compareFloor("floor_seen_after_other_rejoined"),
    once("mp_rejoin_shot_done", function() send("rejoin_shot", {}) end),
    waitFrom("mp_wait_finish", "finish"), MP.finish,
}) do table.insert(MP.stepsB, s) end
if MP.only == "carry" then
    MP.stepsB = { MP.waitWorld, zoomTo("mp_zoom", 0.5), stand("mp_stand", vx, vy, 1),
        once("mp_hide_ui", function() ISUIHandler.setVisibleAllUI(false) end),
        once("mp_hello", function() send("hello", {}) end), waitFrom("mp_wait_start", "start"),
        seeGait("stand"), seeGait("walk"), seeGait("run"), seeGait("sprint"), seeGait("sneak"), seeGait("crouch") }
    for _, s in ipairs(raceStepsB(vx + 1, vy + 1)) do table.insert(MP.stepsB, s) end
    table.insert(MP.stepsB, waitFrom("mp_wait_finish", "finish"))
    table.insert(MP.stepsB, MP.finish)
end

Events.OnGameStart.Add(function()
    local p = phase()
    if p == "rejoining" then
        setPhase("rejoined")
        report():line("OBS  MP.game_start %s again", MP.role)
        TLGH.Steps.run(report(), MP.stepsRejoined, {}, nil)
        return
    end
    setPhase("joined")
    report():line("OBS  MP.game_start %s", MP.role)
    TLGH.Steps.run(report(), MP.role == "A" and MP.stepsA or MP.stepsB, {}, nil)
end)
