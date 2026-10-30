-- Single-player client harness (gates G01 client, G02, G03, G04, G05, G06,
-- G08, G09). Driven by <cachedir>/Lua/TLG_harness_request.txt:
--   sp-a  -> force-launch a debug scenario at the Muldraugh Gas2Go, run phase A,
--            save, write "sp-b", exit to menu
--   sp-b  -> main menu continues the latest save, run phase B (persistence),
--            write "done", quit to desktop
-- Results: <cachedir>/Lua/TLG_harness_sp.txt. Never shipped.
require "TLGHarness/Report"
require "TLGHarness/Steps"
require "TLGHarness/LuaProbe"

local REQUEST = TLGH.readRequest()
local RESULTS = "TLG_harness_sp.txt"
local EXPECT = "TLG_harness_expect.txt"
local STATION = { x0 = 10630, y0 = 10600, x1 = 10690, y1 = 10650 }
local START = { x = 10660, y = 10645, z = 0 }

local H = {}
local R

local function sq(x, y, z) return getCell():getGridSquare(x, y, z or 0) end
local function player() return getPlayer() end
local function hours() return getGameTime():getWorldAgeHours() end

local function giveCan(fullType, fills)
    local item = player():getInventory():AddItem(fullType)
    local fc = item:getFluidContainer()
    fc:Empty()
    for _, f in ipairs(fills or {}) do fc:addFluid(f[1], f[2]) end
    return item, fc
end

-- TLG sidecar summary (end-to-end proof: station -> can -> vehicle -> can -> generator).
local function sidecar(md)
    local s = md and md.tlg
    if s == nil then return "no-sidecar" end
    local q, d = {}, {}
    for _, k in ipairs(TLG.Tables.sortedKeys(s.q or {})) do q[#q + 1] = string.format("%s=%.4f", k, s.q[k]) end
    for _, k in ipairs(TLG.Tables.sortedKeys(s.deg or {})) do d[#d + 1] = string.format("%s=%.4f", k, s.deg[k]) end
    return string.format("id=%s rev=%s q[%s] deg[%s] t=%.2f", tostring(s.id), tostring(s.rev), table.concat(q, ","),
        table.concat(d, ","), s.t or -1)
end
local function chain(label, md)
    R:line("CHAIN %s :: %s", label, sidecar(md))
end

local function speedUp()
    pcall(function() UIManager.getSpeedControls():SetCurrentGameSpeed(4) end)
end
local function normalSpeed()
    pcall(function() UIManager.getSpeedControls():SetCurrentGameSpeed(1) end)
end

-- Queue an action and wait until the character is idle again.
local function actionStep(name, build, after, timeout)
    return { name = name, timeout = timeout or 6000, fn = function(ctx, ticks)
        if not ctx.queued then
            ctx.before = {}
            local action = build(ctx)
            if not action then return true end
            ISTimedActionQueue.add(action)
            ctx.queued = true
            ctx.t0 = ticks
            return nil
        end
        if ticks - ctx.t0 < 10 then return nil end
        if TLGH.Steps.actionsIdle(player()) then
            after(ctx)
            return true
        end
        return nil
    end }
end

------------------------------------------------------------------------------
-- Phase A
------------------------------------------------------------------------------
local stepsA = {}
local function add(step) stepsA[#stepsA + 1] = step end

add({ name = "wait_world", timeout = 3000, fn = function(ctx, ticks)
    if player() and sq(START.x, START.y, 0) and sq(STATION.x0, STATION.y0, 0) and ticks > 120 then
        R:line("worldName=%s start=%d,%d hours=%.4f", tostring(getWorld():getWorld()), START.x, START.y, hours())
        return true
    end
end })

add({ name = "lua_probe_client", fn = function()
    TLGH.runLuaProbe(R)
    R:observe("classmetatables", function() return type(__classmetatables) end)
    return true
end })

add({ name = "g01_client_translations", fn = function()
    R:check("G01c.translation_IG_UI", function() local t = getText("IGUI_TLG_ModName"); return t == "The Last Gallon", t end)
    R:check("G01c.translation_Fluid", function() local t = getText("Fluid_Name_TLG_Ethanol"); return t == "Ethanol", t end)
    R:check("G01c.item_display_name", function()
        local n = instanceItem("TLG.FuelSampleKit"):getDisplayName(); return n == "Fuel Sampling Kit", n
    end)
    R:observe("G13.icon_texture_GlassJar", function() return tostring(getTexture("Item_GlassJar") ~= nil) end)
    return true
end })

add({ name = "find_pumps", timeout = 600, fn = function()
    H.pumps = {}
    local others = {}
    for x = STATION.x0, STATION.x1 do
        for y = STATION.y0, STATION.y1 do
            local s = sq(x, y, 0)
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local amount = o:getPipedFuelAmount()
                    local sprite = o:getSprite() and o:getSprite():getName() or "?"
                    if amount > 0 then
                        H.pumps[#H.pumps + 1] = { obj = o, x = x, y = y, amount = amount, sprite = sprite }
                    elseif string.find(string.lower(sprite), "fuel") or string.find(string.lower(sprite), "gas") then
                        others[#others + 1] = string.format("%s@%d,%d", sprite, x, y)
                    end
                end
            end
        end
    end
    for _, p in ipairs(H.pumps) do
        R:line("OBS  G06.pump %s at %d,%d units=%d modData=%s", p.sprite, p.x, p.y, p.amount, tostring(p.obj:getModData() ~= nil))
    end
    R:line("OBS  G06.pump_count %d other_fuel_sprites=%s", #H.pumps, table.concat(others, ";"))
    R:observe("G06.sandbox_infinite", function() return tostring(SandboxVars.FuelStationGasInfinite) end)
    return true
end })

add({ name = "vehicle_scripts", fn = function()
    local all = getScriptManager():getAllVehicleScripts()
    local names = {}
    H.vehicleScript = nil
    for i = 0, all:size() - 1 do
        local n = all:get(i):getFullName()
        names[#names + 1] = n
        if n == "Base.CarNormal" then H.vehicleScript = n end
    end
    if not H.vehicleScript then
        for _, n in ipairs(names) do
            if string.find(n, "Car") then H.vehicleScript = n; break end
        end
    end
    R:line("OBS  G09.vehicle_script_count %d chosen=%s", #names, tostring(H.vehicleScript))
    R:line("OBS  G09.vehicle_scripts_first %s", table.concat(names, ",", 1, math.min(#names, 40)))
    return true
end })

add(actionStep("g06_pump_to_can", function(ctx)
    local pump = H.pumps[1]
    if not pump then R:line("SKIP g06_pump_to_can: no pump"); return nil end
    local can, fc = giveCan("Base.PetrolCan")
    player():setPrimaryHandItem(can)
    player():teleportTo(pump.x + 1, pump.y, 0)
    ctx.can, ctx.fc, ctx.pump = can, fc, pump
    ctx.pumpBefore = pump.obj:getPipedFuelAmount()
    ctx.canBefore = fc:getAmount()
    H.pumpCan = can
    return ISTakeFuel:new(player(), pump.obj, can)
end, function(ctx)
    local dPump = ctx.pumpBefore - ctx.pump.obj:getPipedFuelAmount()
    local dCan = ctx.fc:getAmount() - ctx.canBefore
    R:line("OBS  G06.pump_to_can pumpUnits %d->%d (-%d) canL %.4f->%.4f (+%.4f) fluids=%s",
        ctx.pumpBefore, ctx.pump.obj:getPipedFuelAmount(), dPump, ctx.canBefore, ctx.fc:getAmount(), dCan,
        TLGH.fluidSummary(ctx.fc))
    R:line("OBS  G06.pump_to_can litres_per_unit=%.4f created=%.4f", dPump > 0 and dCan / dPump or -1, dCan - dPump)
    chain("1 pump after pump->can", ctx.pump.obj:getModData())
    chain("1 can after pump->can", ctx.can:getModData())
end))

add({ name = "vehicle_spawn", timeout = 600, fn = function(ctx, ticks)
    if not ctx.spawned then
        local pump = H.pumps[1] or { x = START.x, y = START.y }
        local s = sq(pump.x + 3, pump.y + 3, 0)
        H.vehicle = addVehicleDebug(H.vehicleScript or "Base.CarNormal", IsoDirections.N, nil, s)
        ctx.spawned = true
        return nil
    end
    if ticks < 60 then return nil end
    local v = H.vehicle
    if not v then R:line("FAIL vehicle_spawn :: nil"); return true end
    H.tank = v:getPartById("GasTank")
    R:line("OBS  G03.vehicle id=%s sqlId=%s script=%s at %.1f,%.1f tankCap=%s amount=%s type=%s",
        tostring(v:getId()), tostring(v:getSqlId()), tostring(v:getScriptName()), v:getX(), v:getY(),
        tostring(H.tank and H.tank:getContainerCapacity()), tostring(H.tank and H.tank:getContainerContentAmount()),
        tostring(H.tank and H.tank:getContainerContentType()))
    if H.tank then
        H.tank:setContainerContentAmount(0)
        v:transmitPartModData(H.tank)
    end
    return true
end })

add(actionStep("g06_pump_to_vehicle", function(ctx)
    local pump, v, part = H.pumps[1], H.vehicle, H.tank
    if not (pump and v and part) then R:line("SKIP g06_pump_to_vehicle"); return nil end
    local c = v:getAreaCenter(part:getArea())
    player():teleportTo(c:getX(), c:getY(), 0)
    ctx.pump, ctx.part = pump, part
    ctx.pumpBefore = pump.obj:getPipedFuelAmount()
    ctx.tankBefore = part:getContainerContentAmount()
    ctx.inArea = v:isInArea(part:getArea(), player())
    return ISRefuelFromGasPump:new(player(), part, pump.obj)
end, function(ctx)
    local dPump = ctx.pumpBefore - ctx.pump.obj:getPipedFuelAmount()
    local dTank = ctx.part:getContainerContentAmount() - ctx.tankBefore
    R:line("OBS  G06.pump_to_vehicle inArea=%s pumpUnits %d->%d (-%d) tankL %.4f->%.4f (+%.4f) litres_per_unit=%.4f",
        tostring(ctx.inArea), ctx.pumpBefore, ctx.pump.obj:getPipedFuelAmount(), dPump, ctx.tankBefore,
        ctx.part:getContainerContentAmount(), dTank, dPump > 0 and dTank / dPump or -1)
    chain("2 tank after pump->vehicle", ctx.part:getModData())
end))

add(actionStep("g03_can_to_vehicle", function(ctx)
    local v, part = H.vehicle, H.tank
    if not (v and part) then return nil end
    local eth = Fluid.Get("TLG_Ethanol")
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Petrol, 6.0 }, { eth, 2.0 } })
    player():setPrimaryHandItem(can)
    local c = v:getAreaCenter(part:getArea())
    player():teleportTo(c:getX(), c:getY(), 0)
    part:setContainerContentAmount(math.max(0, part:getContainerCapacity() - 30))
    v:transmitPartModData(part)
    ctx.fc, ctx.part = fc, part
    ctx.tankBefore = part:getContainerContentAmount()
    ctx.canBefore = TLGH.fluidSummary(fc)
    H.mixCan = can
    return ISAddGasolineToVehicle:new(player(), part, can, nil)
end, function(ctx)
    R:line("OBS  G03.can_to_vehicle tankL %.4f->%.4f can %s -> %s", ctx.tankBefore, ctx.part:getContainerContentAmount(),
        ctx.canBefore, TLGH.fluidSummary(ctx.fc))
    chain("3 tank after can->vehicle", ctx.part:getModData())
end))

add(actionStep("g03_vehicle_to_can", function(ctx)
    local v, part = H.vehicle, H.tank
    if not (v and part) then return nil end
    local can, fc = giveCan("Base.PetrolCan")
    player():setPrimaryHandItem(can)
    ctx.fc, ctx.part = fc, part
    ctx.tankBefore = part:getContainerContentAmount()
    return ISTakeGasolineFromVehicle:new(player(), part, can, nil)
end, function(ctx)
    R:line("OBS  G03.vehicle_to_can tankL %.4f->%.4f can %s", ctx.tankBefore, ctx.part:getContainerContentAmount(),
        TLGH.fluidSummary(ctx.fc))
    chain("4 can after siphon", ctx.fc:getOwner():getModData())
    chain("4 tank after siphon", ctx.part:getModData())
end))

add({ name = "g03_vehicle_idle", timeout = 20000, fn = function(ctx, ticks)
    local v, part = H.vehicle, H.tank
    if not (v and part) then return true end
    if not ctx.started then
        ctx.started = true
        local entered = v:enter(0, player())
        pcall(function() v:setHotwired(true) end)
        pcall(function() v:tryStartEngine(true) end)
        ctx.entered = entered
        ctx.t0 = ticks
        return nil
    end
    if not ctx.running then
        if v:isEngineRunning() then
            ctx.running = true
            ctx.fuel0, ctx.h0 = part:getContainerContentAmount(), hours()
            speedUp()
            return nil
        end
        if ticks - ctx.t0 > 600 then
            R:line("OBS  G03.idle NOT RUN: engine did not start (entered=%s state=%s)", tostring(ctx.entered),
                tostring(v:getEngineState()))
            pcall(function() v:exit(player()) end)
            return true
        end
        if ticks - ctx.t0 == 120 then pcall(function() v:engineDoStartingSuccess() end) end
        return nil
    end
    if hours() - ctx.h0 >= 1.0 or ticks > 18000 then
        normalSpeed()
        R:line("OBS  G03.idle %.3f game h: tank %.4f -> %.4f (burn %.4f L) running=%s", hours() - ctx.h0, ctx.fuel0,
            part:getContainerContentAmount(), ctx.fuel0 - part:getContainerContentAmount(), tostring(v:isEngineRunning()))
        pcall(function() v:shutOff() end)
        pcall(function() v:engineDoShuttingDown() end)
        pcall(function() v:exit(player()) end)
        return true
    end
end })

add({ name = "g09_two_vehicles", timeout = 600, fn = function(ctx, ticks)
    if not ctx.spawned then
        local base = H.pumps[1] or { x = START.x, y = START.y }
        H.vehicle2 = addVehicleDebug(H.vehicleScript or "Base.CarNormal", IsoDirections.N, nil, sq(base.x + 8, base.y + 3, 0))
        ctx.spawned = true
        return nil
    end
    if ticks < 60 then return nil end
    local a, b = H.vehicle, H.vehicle2
    if not (a and b) then R:line("FAIL G09 :: vehicles missing"); return true end
    local ta, tb = a:getPartById("GasTank"), b:getPartById("GasTank")
    ta:getModData().tlgProbe = 123
    a:transmitPartModData(ta)
    local qa, pa = a:getEngineQuality(), a:getEnginePower()
    a:setEngineFeature(qa, a:getEngineLoudness(), math.floor(pa * 0.8))
    R:check("G09.part_moddata_per_instance", function()
        return ta:getModData().tlgProbe == 123 and tb:getModData().tlgProbe == nil,
            tostring(ta:getModData().tlgProbe) .. "/" .. tostring(tb:getModData().tlgProbe)
    end)
    R:check("G09.engine_feature_per_instance", function()
        return a:getEnginePower() ~= b:getEnginePower(), string.format("a=%d b=%d (a before %d)", a:getEnginePower(), b:getEnginePower(), pa)
    end)
    a:setEngineFeature(qa, a:getEngineLoudness(), pa)
    return true
end })

add({ name = "g05_wrappers", fn = function()
    local origNew = IsoGenerator.new
    local calls = 0
    IsoGenerator.new = function(item, cell, square)
        calls = calls + 1
        return origNew(item, cell, square)
    end
    local base = H.pumps[1] or { x = START.x, y = START.y }
    local s = sq(base.x - 4, base.y + 6, 0)
    local item = instanceItem("Base.Generator")
    H.gen = IsoGenerator.new(item, getCell(), s)
    IsoGenerator.new = origNew
    H.genSquare = { x = s:getX(), y = s:getY() }
    R:check("G05.IsoGenerator_new_wrappable", function() return calls == 1 and H.gen ~= nil, "calls=" .. calls end)
    R:observe("G04.generator", function()
        return string.format("type=%s maxFuel=%s fuel=%s cond=%s", tostring(H.gen:getGeneratorItemType()),
            tostring(H.gen:getMaxFuel()), tostring(H.gen:getFuel()), tostring(H.gen:getCondition()))
    end)
    return true
end })

add(actionStep("g04_can_to_generator", function(ctx)
    if not H.gen then return nil end
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Petrol, 8.0 } })
    player():setPrimaryHandItem(can)
    player():teleportTo(H.genSquare.x + 1, H.genSquare.y, 0)
    ctx.fc = fc
    ctx.genBefore = H.gen:getFuel()
    ctx.canBefore = fc:getAmount()
    return ISAddFuel:new(player(), H.gen, can)
end, function(ctx)
    R:line("OBS  G04.can_to_generator gen %.4f->%.4f can %.4f->%.4f", ctx.genBefore, H.gen:getFuel(), ctx.canBefore,
        ctx.fc:getAmount())
    chain("5 generator after can->generator", H.gen:getModData())
end))

add({ name = "g04_generator_burn", timeout = 20000, fn = function(ctx, ticks)
    if not H.gen then return true end
    if not ctx.started then
        H.gen:setConnected(true)
        H.gen:setActivated(true)
        ctx.started, ctx.f0, ctx.h0 = true, H.gen:getFuel(), hours()
        speedUp()
        return nil
    end
    if hours() - ctx.h0 >= 2.0 or ticks > 18000 then
        normalSpeed()
        R:line("OBS  G04.burn %.3f game h: fuel %.4f -> %.4f activated=%s powerUsing=%s sandboxConsumption=%s",
            hours() - ctx.h0, ctx.f0, H.gen:getFuel(), tostring(H.gen:isActivated()), tostring(H.gen:getTotalPowerUsing()),
            tostring(SandboxVars.GeneratorFuelConsumption))
        H.gen:setActivated(false)
        H.gen:setConnected(false)
        return true
    end
end })

add(actionStep("g05_pickup", function(ctx)
    if not H.gen then return nil end
    H.gen:getModData().tlg = { probe = 7.5, id = "GEN-TEST" }
    local orig = ISTakeGenerator.complete
    H.takeGenWrapped = 0
    ISTakeGenerator.complete = function(self)
        local sidecar = self.generator:getModData().tlg
        local before = self.character:getInventory():getItems():size()
        local res = orig(self)
        local items = self.character:getInventory():getItems()
        for i = before, items:size() - 1 do
            local it = items:get(i)
            if it and string.find(it:getFullType(), "Generator") then
                it:getModData().tlg = sidecar
                H.genItem = it
            end
        end
        H.takeGenWrapped = H.takeGenWrapped + 1
        ISTakeGenerator.complete = orig
        return res
    end
    player():teleportTo(H.genSquare.x + 1, H.genSquare.y, 0)
    ctx.fuel = H.gen:getFuel()
    return ISTakeGenerator:new(player(), H.gen)
end, function(ctx)
    local it = H.genItem
    R:check("G05.pickup_carries_sidecar_via_wrapper", function()
        return it ~= nil and it:getModData().tlg ~= nil and it:getModData().tlg.probe == 7.5,
            string.format("wrapped=%s itemFuel=%s tlg=%s", tostring(H.takeGenWrapped), tostring(it and it:getModData().fuel),
                tostring(it and it:getModData().tlg and it:getModData().tlg.probe))
    end)
    R:observe("G05.vanilla_item_fuel_equals_object_fuel", function()
        return string.format("object=%.4f item=%s", ctx.fuel, tostring(it and it:getModData().fuel))
    end)
end))

add({ name = "g05_drop_place", timeout = 600, fn = function(ctx, ticks)
    local it = H.genItem
    if not it then return true end
    if not ctx.dropped then
        local s = sq(H.genSquare.x, H.genSquare.y, 0)
        player():getInventory():Remove(it)
        player():setPrimaryHandItem(nil)
        player():setSecondaryHandItem(nil)
        ctx.result = s:AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
        ctx.dropped = true
        return nil
    end
    if ticks < 30 then return nil end
    local s = sq(H.genSquare.x, H.genSquare.y, 0)
    local found
    local objs = s:getObjects()
    for i = 0, objs:size() - 1 do
        if instanceof(objs:get(i), "IsoGenerator") then found = objs:get(i) end
    end
    H.gen2 = found
    R:observe("G05.drop_creates_generator_object", function()
        return string.format("generator=%s fuel=%s tlg=%s returned=%s", tostring(found ~= nil),
            tostring(found and found:getFuel()), tostring(found and found:getModData().tlg ~= nil), tostring(ctx.result))
    end)
    return true
end })

add({ name = "g02_world_container_and_expectations", fn = function()
    local eth = Fluid.Get("TLG_Ethanol")
    local base = H.pumps[1] or { x = START.x, y = START.y }
    local s = sq(base.x + 1, base.y - 2, 0)
    local canA = instanceItem("Base.JerryCan")
    local fcA = canA:getFluidContainer()
    fcA:Empty(); fcA:addFluid(Fluid.Petrol, 12.5); fcA:addFluid(eth, 3.25)
    canA:getModData().tlg = { id = "CAN-A", deg = { gasoline = 1.25, ethanol = 0.5 }, nested = { k = "v" } }
    s:AddWorldInventoryItem(canA, 0.5, 0.5, 0, false)
    local canB, fcB = giveCan("Base.PetrolCan", { { Fluid.Petrol, 4.0 }, { eth, 1.0 } })
    canB:getModData().tlg = { id = "CAN-B", deg = { gasoline = 2.0 } }
    local lines = {
        "canA.x=" .. s:getX(), "canA.y=" .. s:getY(),
        "canA.fluids=" .. TLGH.fluidSummary(fcA),
        "canB.fluids=" .. TLGH.fluidSummary(fcB),
        "world=" .. tostring(getWorld():getWorld()),
        "hours=" .. string.format("%.4f", hours()),
    }
    if H.vehicle and H.tank then
        H.tank:getModData().tlg = { id = "VEH-A", deg = { gasoline = 0.75 } }
        H.vehicle:transmitPartModData(H.tank)
        lines[#lines + 1] = "veh.x=" .. math.floor(H.vehicle:getX())
        lines[#lines + 1] = "veh.y=" .. math.floor(H.vehicle:getY())
        lines[#lines + 1] = "veh.tank=" .. string.format("%.4f", H.tank:getContainerContentAmount())
    end
    if H.gen2 then
        H.gen2:getModData().tlg = { id = "GEN-B", probe = 9 }
        lines[#lines + 1] = "gen.x=" .. H.genSquare.x
        lines[#lines + 1] = "gen.y=" .. H.genSquare.y
        lines[#lines + 1] = "gen.fuel=" .. string.format("%.4f", H.gen2:getFuel())
    end
    for _, p in ipairs(H.pumps) do
        lines[#lines + 1] = string.format("pump.%d.%d=%d", p.x, p.y, p.obj:getPipedFuelAmount())
    end
    local g = ModData.getOrCreate("TLGHarnessSP")
    g.marker = "phaseA"
    g.nested = { a = 1.5 }
    TLGH.writeFile(EXPECT, lines)
    R:line("OBS  G08.expectations %s", table.concat(lines, " | "))
    return true
end })

add({ name = "save_and_exit", timeout = 1200, fn = function(ctx, ticks)
    if not ctx.saved then
        R:finish(false)
        TLGH.writeFile("TLG_harness_request.txt", { "sp-b" })
        saveGame()
        ctx.saved = true
        return nil
    end
    if ticks == 180 then
        R:line("EXIT phase A -> main menu")
        getCore():exitToMenu()
    end
    return nil
end })

------------------------------------------------------------------------------
-- Phase B (after continuing the saved game)
------------------------------------------------------------------------------
local stepsB = {}
local function addB(step) stepsB[#stepsB + 1] = step end

addB({ name = "wait_world_b", timeout = 3000, fn = function(ctx, ticks)
    if player() and ticks > 120 then
        H.expect = TLGH.readKeyValues(EXPECT)
        R:line("phaseB worldName=%s expected=%s hours=%.4f", tostring(getWorld():getWorld()), tostring(H.expect.world), hours())
        return true
    end
end })

addB({ name = "g08_reload_checks", fn = function()
    local e = H.expect
    R:check("G08.same_world", function() return tostring(getWorld():getWorld()) == e.world, tostring(getWorld():getWorld()) end)
    R:check("G08.world_item_fluids_and_moddata", function()
        local s = sq(tonumber(e["canA.x"]), tonumber(e["canA.y"]), 0)
        if not s then return false, "square not loaded" end
        local wobjs = s:getWorldObjects()
        for i = 0, wobjs:size() - 1 do
            local it = wobjs:get(i):getItem()
            local md = it and it:getModData().tlg
            if md and md.id == "CAN-A" then
                local fl = TLGH.fluidSummary(it:getFluidContainer())
                return fl == e["canA.fluids"] and md.deg.gasoline == 1.25 and md.nested.k == "v",
                    fl .. " deg=" .. tostring(md.deg.gasoline)
            end
        end
        return false, "CAN-A not found among " .. wobjs:size()
    end)
    R:check("G08.inventory_item_fluids_and_moddata", function()
        local items = player():getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local md = it:getModData().tlg
            if md and md.id == "CAN-B" then
                local fl = TLGH.fluidSummary(it:getFluidContainer())
                return fl == e["canB.fluids"], fl
            end
        end
        return false, "CAN-B not in inventory"
    end)
    if e["veh.x"] then
        R:check("G08.vehicle_part_moddata_and_tank", function()
            local v
            for dx = -3, 3 do
                for dy = -3, 3 do
                    local s = sq(tonumber(e["veh.x"]) + dx, tonumber(e["veh.y"]) + dy, 0)
                    if s and s:getVehicleContainer() then v = s:getVehicleContainer() end
                end
            end
            if not v then return false, "vehicle not found" end
            local part = v:getPartById("GasTank")
            local md = part:getModData().tlg
            local amount = string.format("%.4f", part:getContainerContentAmount())
            return md and md.id == "VEH-A" and amount == e["veh.tank"], tostring(md and md.id) .. " tank=" .. amount
        end)
    end
    if e["gen.x"] then
        R:check("G08.generator_object_moddata_and_fuel", function()
            local s = sq(tonumber(e["gen.x"]), tonumber(e["gen.y"]), 0)
            local objs = s:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoGenerator") then
                    local md = o:getModData().tlg
                    return md and md.id == "GEN-B", string.format("fuel=%.4f expected=%s tlg=%s", o:getFuel(),
                        tostring(e["gen.fuel"]), tostring(md and md.id))
                end
            end
            return false, "no generator object"
        end)
    end
    for k, v in pairs(e) do
        local px, py = string.match(k, "^pump%.(%d+)%.(%d+)$")
        if px then
            R:check("G08.pump_amount_" .. px .. "_" .. py, function()
                local s = sq(tonumber(px), tonumber(py), 0)
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if o:getPipedFuelAmount() > 0 or tostring(o:getPipedFuelAmount()) == v then
                        return tostring(o:getPipedFuelAmount()) == v, tostring(o:getPipedFuelAmount()) .. " vs " .. v
                    end
                end
                return false, "pump not found"
            end)
        end
    end
    R:check("G08.global_moddata_sp", function()
        local g = ModData.get("TLGHarnessSP")
        return g ~= nil and g.marker == "phaseA" and g.nested.a == 1.5, tostring(g and g.marker)
    end)
    return true
end })

addB({ name = "quit", timeout = 600, fn = function(ctx, ticks)
    if not ctx.done then
        TLGH.writeFile("TLG_harness_request.txt", { "done" })
        R:finish(true)
        ctx.done = true
        return nil
    end
    if ticks == 60 then getCore():quitToDesktop() end
    return nil
end })

------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------
-- Diagnostics so a stall before the scenario can be located from the log.
print("[TLGH] SPHarness loaded, request=" .. tostring(REQUEST) .. " debug=" .. tostring(getDebug()))
Events.OnMainMenuEnter.Add(function()
    print("[TLGH] OnMainMenuEnter request=" .. tostring(REQUEST) .. " debug=" .. tostring(getDebug()) ..
        " scenarioA=" .. tostring(debugScenarios ~= nil and debugScenarios.TLGHarnessA ~= nil) ..
        " forceLaunch=" .. tostring(getDebugOptions():getBoolean("DebugScenario.ForceLaunch")))
end)

if REQUEST == "sp-a" then
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", true)
    debugScenarios = debugScenarios or {}
    debugScenarios.TLGHarnessA = {
        name = "TLG harness phase A",
        forceLaunch = true,
        startLoc = START,
        setSandbox = function()
            SandboxVars.Zombies = 6
            SandboxVars.FuelStationGasEmptyChance = 0
            SandboxVars.FuelStationGasInfinite = false
        end,
        onStart = function()
            R = TLGH.Report.new(RESULTS, "TLG single-player harness phase A")
            TLGH.Steps.run(R, stepsA, H, nil)
        end,
    }
else
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", false)
end

if REQUEST == "sp-b" then
    Events.OnMainMenuEnter.Add(function()
        if TLGH.continued then return end
        TLGH.continued = true
        MainScreen.instance:getLatestSave()
        print("[TLGH] continuing " .. tostring(MainScreen.latestSaveWorld))
        MainScreen.continueLatestSave(MainScreen.latestSaveGameMode, MainScreen.latestSaveWorld)
    end)
    Events.OnGameStart.Add(function()
        R = TLGH.Report.new(RESULTS, "TLG single-player harness phase B", true)
        TLGH.Steps.run(R, stepsB, H, nil)
    end)
end
