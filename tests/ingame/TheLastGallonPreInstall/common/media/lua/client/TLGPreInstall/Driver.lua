-- Development-only driver for release gate 7: a save that gains The Last
-- Gallon after being played without it. Request "ex-a" in
-- <cachedir>/Lua/TLG_harness_request.txt force-launches a debug scenario at
-- the Muldraugh Gas2Go with only this mod active (it does not require The
-- Last Gallon, which is never loaded here), puts petrol where a player
-- would have it (a can carried, a can on the ground; the station's pumps
-- are the map's), lets the world age AGE_DAYS on the game clock, saves,
-- writes what it left where to TLG_existing_expect.txt and quits to the
-- desktop. tools/rehearse-install.ps1 -Scenario existing then adds the mod
-- to the save and continues it with the harness (requests "ex-b", "ex-c").
-- Never shipped.

local function readRequest()
    local r = getFileReader("TLG_harness_request.txt", false)
    if not r then return nil end
    local line = r:readLine()
    r:close()
    return line
end

local function writeFile(name, lines)
    local w = getFileWriter(name, true, false)
    for _, l in ipairs(lines) do w:write(l .. "\n") end
    w:close()
end

local REQUEST = readRequest()
print("[TLGX] pre-install driver loaded, request=" .. tostring(REQUEST))

-- Back at the menu after the save: leave.
if REQUEST == "ex-a-done" then
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", false)
    Events.OnMainMenuEnter.Add(function() getCore():quitToDesktop() end)
    return
end
if REQUEST ~= "ex-a" then return end

local AGE_DAYS = 10
local START = { x = 10660, y = 10645, z = 0 }
local RESULTS = "TLG_harness_sp.txt"
local EXPECT = "TLG_existing_expect.txt"

-- As the harness does: errors are logged, nothing waits for a click
-- (SRC DebugUIs/DebugToolstrip.lua, SurvivalGuide/SurvivalGuide.lua).
local function unattended()
    pcall(function() UIManager.setShowLuaDebuggerOnError(false) end)
    pcall(function() getCore():setOptionShowSurvivalGuide(false) end)
end
unattended()
Events.OnGameStart.Add(unattended)

local report, passed, failed = {}, 0, 0
local function line(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    report[#report + 1] = s
    print("[TLGX] " .. s)
    writeFile(RESULTS, report)
end

local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    line("%s %s :: %s", ok and "PASS" or "FAIL", name, tostring(detail))
end

local function hours() return getGameTime():getWorldAgeHours() end

local function petrolCan(litres)
    local item = instanceItem("Base.PetrolCan")
    local fc = item:getFluidContainer()
    fc:Empty()
    fc:addFluid(Fluid.Petrol, litres)
    return item, fc
end

-- Days on the game clock: needs are reset now and then (the character is
-- invulnerable and invisible meanwhile).
local function keepFit(p)
    local st = p:getStats()
    for _, k in ipairs({ "HUNGER", "THIRST", "FATIGUE", "BOREDOM", "UNHAPPINESS", "STRESS" }) do
        pcall(function() st:reset(CharacterStat[k]) end)
    end
end

local S = { phase = "wait", ticks = 0 }

local function tick()
    S.ticks = S.ticks + 1
    local p = getPlayer()
    if S.phase == "wait" then
        if p and S.ticks > 120 then S.phase = "stock" end
        return
    end
    if S.phase == "stock" then
        p:setGodMod(true)
        p:setInvisible(true)
        pcall(function() p:setUnlimitedCarry(true) end)
        local a, fcA = petrolCan(10)
        p:getInventory():AddItem(a)
        local d, fcD = petrolCan(10)
        local ground = getCell():getGridSquare(START.x + 3, START.y, START.z)
        ground:AddWorldInventoryItem(d, 0.5, 0.5, 0, false)
        S.a, S.d, S.fcA, S.fcD, S.ground = a, d, fcA, fcD, ground
        S.h0 = hours()
        S["until"] = S.h0 + AGE_DAYS * 24
        line("OBS  EXA.stocked world=%s hours=%.4f; can A (carried) id=%s %.2f L petrol; can D on %d,%d id=%s %.2f L petrol",
            tostring(getWorld():getWorld()), S.h0, tostring(a:getID()), fcA:getAmount(), START.x + 3, START.y,
            tostring(d:getID()), fcD:getAmount())
        local listed = "?"
        pcall(function() listed = tostring(getActivatedMods():contains("TheLastGallon")) end)
        check("EXA.mod_absent", TLG == nil and listed ~= "true",
            string.format("TLG loaded=%s, listed active=%s", tostring(TLG ~= nil), listed))
        S.phase = "age"
        return
    end
    if S.phase == "age" then
        if S.ticks % 30 == 0 then keepFit(p) end
        pcall(function() getGameTime():setMultiplier(100) end)
        if hours() < S["until"] then return end
        pcall(function() getGameTime():setMultiplier(1) end)
        local onGround = false
        local wobjs = S.ground:getWorldObjects()
        for i = 0, wobjs:size() - 1 do
            if wobjs:get(i):getItem() == S.d then onGround = true end
        end
        check("EXA.world_aged", hours() - S.h0 >= AGE_DAYS * 24,
            string.format("%.2f game hours since stocking (%.4f -> %.4f)", hours() - S.h0, S.h0, hours()))
        check("EXA.cans_kept", S.fcA:getAmount() > 9.99 and S.fcD:getAmount() > 9.99 and onGround,
            string.format("A %.4f L, D %.4f L, D still on the ground=%s", S.fcA:getAmount(), S.fcD:getAmount(),
                tostring(onGround)))
        writeFile(EXPECT, {
            "world=" .. tostring(getWorld():getWorld()),
            string.format("hours=%.6f", hours()),
            "canA=" .. tostring(S.a:getID()),
            "canD=" .. tostring(S.d:getID()),
            "canD.x=" .. tostring(START.x + 3),
            "canD.y=" .. tostring(START.y),
            "ageDays=" .. tostring(AGE_DAYS),
        })
        line("OBS  EXA.saving at world hours %.4f", hours())
        saveGame()
        S.phase, S.saveTick = "saved", S.ticks
        return
    end
    if S.phase == "saved" and S.ticks - S.saveTick == 180 then
        writeFile("TLG_harness_request.txt", { "ex-a-done" })
        line("SUMMARY pass=%d fail=%d", passed, failed)
        line("DONE")
        getCore():exitToMenu()
        S.phase = "leaving"
    end
end

getDebugOptions():setBoolean("DebugScenario.ForceLaunch", true)
debugScenarios = debugScenarios or {}
debugScenarios.TLGPreInstall = {
    name = "TLG pre-install world",
    forceLaunch = true,
    startLoc = START,
    setSandbox = function()
        -- The new world takes the active mods (this one only), as the harness
        -- does (SRC MainScreen.lua:1400).
        ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
        SandboxVars.Zombies = 6
        SandboxVars.FuelStationGasEmptyChance = 0
        SandboxVars.FuelStationGasInfinite = false
    end,
    onStart = function()
        line("# TLG existing save, launch 1: a world played without the mod")
        line("game=%s", tostring(getCore():getVersion()))
        -- One error per message is logged; the step machine stops on it.
        local seen = {}
        Events.OnTick.Add(function()
            local ok, err = pcall(tick)
            if not ok and not seen[tostring(err)] then
                seen[tostring(err)] = true
                line("STEPERR %s :: %s", tostring(S.phase), tostring(err))
            end
        end)
    end,
}
