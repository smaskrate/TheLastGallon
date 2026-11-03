-- Multiplayer harness, client side (requests "mp-a" and "mp-b";
-- tools/run-mp-harness.ps1). At the main menu the client joins the TLGDev
-- server by IP as vanilla's Join by IP popup does (ServerConnectPopup.lua:
-- ConnectToServer.instance:connect), with the account the launcher left in
-- TLG_harness_connect.txt. A new character is made by pressing the creation
-- screens' own Next (CharacterCreationProfession and CharacterCreationMain
-- onOptionMouseDown "NEXT"). Joining reloads the Lua with the server's
-- mods, so the report is reopened and appended to in each Lua state. In the
-- world the client runs its steps, then quits.
-- Results: <cachedir>/Lua/TLG_harness_mp.txt.
require "TLGHarness/Report"
require "TLGHarness/Steps"

local REQUEST = TLGH.readRequest()
if REQUEST ~= "mp-a" and REQUEST ~= "mp-b" then return end

TLGH.MP = TLGH.MP or {}
local MP = TLGH.MP
MP.role = REQUEST == "mp-a" and "A" or "B"

local function report()
    if not MP.R then MP.R = TLGH.Report.new("TLG_harness_mp.txt", "TLG multiplayer harness, client " .. MP.role, true) end
    return MP.R
end

-- Unattended, as SPHarness.lua: a Lua error is logged instead of stopping
-- in the debugger, and the Survival Guide stays closed.
pcall(function() UIManager.setShowLuaDebuggerOnError(false) end)
pcall(function() getCore():setOptionShowSurvivalGuide(false) end)

------------------------------------------------------------------------------
-- Main menu: join, then make the character.
------------------------------------------------------------------------------
local fe = { ticks = 0 }

-- What the client has done so far, kept in a file because joining reloads
-- the Lua (the launcher deletes it): "joining" once the join is asked for.
local function phase() return TLGH.readKeyValues("TLG_harness_mpstate.txt").phase end
local function setPhase(p) TLGH.writeFile("TLG_harness_mpstate.txt", { "phase=" .. p }) end

local function connect()
    local c = TLGH.readKeyValues("TLG_harness_connect.txt")
    setPhase("joining")
    report():line("OBS  MP.connect %s as %s to %s:%s", MP.role, tostring(c.user), tostring(c.ip), tostring(c.port))
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
        if not fe.joining and not isClient() and fe.ticks > 120 and MainScreen and MainScreen.instance
            and ConnectToServer and ConnectToServer.instance and phase() == nil then
            fe.joining = true
            connect()
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
-- In the world.
------------------------------------------------------------------------------
local function player() return getPlayer() end

-- A screenshot with the interface hidden (as SPHarness's RT.MI.shot).
local function shot(name)
    return { name = "mp_shot_" .. name, timeout = 600, fn = function(ctx, ticks)
        if ticks == 1 then ISUIHandler.setVisibleAllUI(false) end
        if ticks == 60 then
            local file = "tlg_mp" .. MP.role:lower() .. "_" .. name .. ".png"
            local ok, err = pcall(function() getCore():TakeFullScreenshot(file) end)
            local p = player()
            report():line("OBS  MP.screenshot %s ok=%s %s; zoom %.2f; player %d,%d", file, tostring(ok),
                ok and "" or tostring(err), getCore():getZoom(0), math.floor(p:getX()), math.floor(p:getY()))
        end
        if ticks == 120 then ISUIHandler.setVisibleAllUI(true) end
        return ticks >= 150 or nil
    end }
end

-- Messages relayed by the server (MPServer.lua), kept by command.
MP.inbox = MP.inbox or {}
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

MP.waitWorld = { name = "mp_wait_world", timeout = 3000, fn = function(ctx, ticks)
    local p = player()
    if not p or ticks < 120 then return nil end
    local R = report()
    local zombies = getCell():getZombieList()
    R:line("OBS  MP.world %s user=%s at %d,%d isClient=%s online=%s role=%s zombies in cell=%s Zombies=%s",
        MP.role, tostring(p:getUsername()), math.floor(p:getX()), math.floor(p:getY()), tostring(isClient()),
        tostring(getOnlinePlayers() and getOnlinePlayers():size()),
        tostring(select(2, pcall(function() return p:getRole():getName() end))),
        tostring(zombies and zombies:size()), tostring(SandboxVars.Zombies))
    R:check("MP.joined_" .. MP.role, function()
        local want = TLGH.readKeyValues("TLG_harness_connect.txt").user
        return isClient() and p:getUsername() == want, string.format("isClient=%s user=%s", tostring(isClient()),
            tostring(p:getUsername()))
    end)
    return true
end }

-- A message to the server, back through its relay: the path the harness's
-- two clients use to wait on each other.
MP.relay = { name = "mp_relay", timeout = 900, fn = function(ctx, ticks)
    if ticks == 1 then
        ctx.n = #(MP.inbox.hello or {})
        send("hello", {})
        return nil
    end
    local got = MP.inbox.hello or {}
    for i = ctx.n + 1, #got do
        if got[i].role == MP.role then
            report():check("MP.relay_" .. MP.role, function() return true, string.format("echo after %d ticks", ticks) end)
            return true
        end
    end
    if ticks >= 900 then report():check("MP.relay_" .. MP.role, function() return false, "no echo" end) end
    return nil
end }

MP.finish = { name = "mp_finish", timeout = 600, fn = function(ctx, ticks)
    if not ctx.done then
        report():finish(true)
        ctx.done = true
        return nil
    end
    if ticks == 60 then getCore():quitToDesktop() end
    return nil
end }

MP.steps = { MP.waitWorld, MP.relay, shot("joined"), MP.finish }

Events.OnGameStart.Add(function()
    setPhase("joined")
    report():line("OBS  MP.game_start %s", MP.role)
    TLGH.Steps.run(report(), MP.steps, {}, nil)
end)
