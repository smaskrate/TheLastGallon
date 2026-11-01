-- Single-player client harness (gates G01 client, G02, G03, G04, G05, G06,
-- G08, G09 and the end-to-end proof). Driven by
-- <cachedir>/Lua/TLG_harness_request.txt:
--   sp-a  -> force-launch a debug scenario at the Muldraugh Gas2Go, run phase A,
--            save, write "sp-b", exit to menu
--   sp-b  -> main menu continues the latest save, run phase B (persistence),
--            write "done", quit to desktop
--   sp-rt -> same scenario, only the ethanol loop on the real game clock,
--            write "done", quit to desktop (no save/reload)
--   sp-rtw -> the same from 15 January: fermenters by site in the cold
--   sp-rtf -> the same January world: a fermenter beside a map fireplace
--   sp-rtfs -> the same, saved mid-batch and exited to the menu ("sp-rtfb")
--   sp-rtfb -> main menu continues that save, checks the records, finishes
--   sp-rtp -> summer, grid on: fermenters picked up mid-batch and put down,
--             one of them grabbed where no Lua sees it (as in multiplayer)
--   sp-rtpot -> summer, grid on: a batch through the pot still (two runs),
--             dried and checked against the engines' rules
--   sp-rtc -> summer, grid on: Pause, Resume and Abort batch from the menu
--   sp-rtof -> the January world: fermenters beside a campfire and a barbecue
-- Results: <cachedir>/Lua/TLG_harness_sp.txt. Never shipped.
--
-- The end-to-end proof moves ONE batch of fuel station -> can -> vehicle ->
-- can -> generator through the vanilla actions (TLG adapters installed) and
-- checks litres, proportions, contaminants and condition after every hop.
require "TLGHarness/Report"
require "TLGHarness/Steps"
require "TLGHarness/LuaProbe"

local REQUEST = TLGH.readRequest()

-- Unattended runs: a Lua error must be logged, not halt the game in the Lua
-- debugger ("Break On Error" tick box, SRC DebugUIs/DebugToolstrip.lua:28-29;
-- RT-SP 2026-10-31 stopped there), and the Survival Guide window must not
-- open over the game (SRC SurvivalGuide/SurvivalGuide.lua:15).
local function unattended()
    pcall(function() UIManager.setShowLuaDebuggerOnError(false) end)
    pcall(function() getCore():setOptionShowSurvivalGuide(false) end)
end
if REQUEST == "sp-a" or REQUEST == "sp-b" or REQUEST == "sp-rt" or REQUEST == "sp-rtw" or REQUEST == "sp-rtf"
    or REQUEST == "sp-rtfs" or REQUEST == "sp-rtfb" or REQUEST == "sp-rtp" or REQUEST == "sp-rtpot" or REQUEST == "sp-rtc"
    or REQUEST == "sp-rtof" then
    unattended()
    Events.OnGameStart.Add(unattended)
end

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

-- Raw sidecar summary (persistence checks compare these strings).
local function sidecar(md)
    local s = md and md.tlg
    if s == nil then return "no-sidecar" end
    local q, d = {}, {}
    for _, k in ipairs(TLG.Tables.sortedKeys(s.q or {})) do q[#q + 1] = string.format("%s=%.4f", k, s.q[k]) end
    for _, k in ipairs(TLG.Tables.sortedKeys(s.deg or {})) do d[#d + 1] = string.format("%s=%.4f", k, s.deg[k]) end
    return string.format("id=%s rev=%s q[%s] deg[%s] t=%.2f", tostring(s.id), tostring(s.rev), table.concat(q, ","),
        table.concat(d, ","), s.t or -1)
end

-- TLG's current view of a store, aged to now; read-only (persist = false).
local function tlgView(kind, obj)
    local I = TLG.Integration
    local rec, status
    if kind == "item" then
        rec, status = I.Containers.read(obj, "item", false)
    elseif kind == "vehicle" then
        rec, status = I.Vehicles.read(obj, false)
    elseif kind == "generator" then
        rec, status = I.Generators.read(obj, false)
    elseif kind == "pump" then
        rec, status = I.Stations.read(obj, false)
    end
    if rec == nil then return nil, status end
    return TLG.Domain.Aging.advance(rec, TLG.World.now(), TLG.World.env()), status
end

local function viewText(rec, status)
    if rec == nil then return "nil(" .. tostring(status) .. ")" end
    local q, d = {}, {}
    for _, k in ipairs(TLG.Tables.sortedKeys(rec.q)) do q[#q + 1] = string.format("%s=%.4f", k, rec.q[k]) end
    for _, k in ipairs(TLG.Tables.sortedKeys(rec.deg)) do d[#d + 1] = string.format("%s=%.4f", k, rec.deg[k]) end
    return string.format("%s id=%s rev=%s total=%.4f q[%s] deg[%s] mic=%s stab=%s", tostring(status), tostring(rec.id),
        tostring(rec.rev), TLG.Domain.Supply.total(rec), table.concat(q, ","), table.concat(d, ","), tostring(rec.mic),
        tostring(rec.stab))
end

-- Same fuel: equal volume fractions per component, equal degradation per
-- present component and equal microbial load, within `tol`.
local function sameFuel(a, b, tol)
    local ta, tb = TLG.Domain.Supply.total(a), TLG.Domain.Supply.total(b)
    if ta <= 0 or tb <= 0 then return false, string.format("empty a=%.4f b=%.4f", ta, tb) end
    local keys = {}
    for k in pairs(a.q) do keys[k] = true end
    for k in pairs(b.q) do keys[k] = true end
    local worst, where = math.abs((a.mic or 0) - (b.mic or 0)), "mic"
    for _, k in ipairs(TLG.Tables.sortedKeys(keys)) do
        local df = math.abs((a.q[k] or 0) / ta - (b.q[k] or 0) / tb)
        if df > worst then worst, where = df, "fraction:" .. k end
        if (a.q[k] or 0) > 1e-6 and (b.q[k] or 0) > 1e-6 then
            local dd = math.abs((a.deg[k] or 0) - (b.deg[k] or 0))
            if dd > worst then worst, where = dd, "deg:" .. k end
        end
    end
    return worst <= tol, string.format("worst=%.2e at %s", worst, where)
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

-- Transfer bookkeeping shared by the chain hops and the single-path checks.
local function hopBegin(ctx, name, srcKind, src, srcAmount, dstKind, dst, dstAmount)
    ctx.name = name
    ctx.srcKind, ctx.src, ctx.srcAmount = srcKind, src, srcAmount
    ctx.dstKind, ctx.dst, ctx.dstAmount = dstKind, dst, dstAmount
    ctx.s0, ctx.d0 = srcAmount(), dstAmount()
    ctx.srcView, ctx.srcStatus = tlgView(srcKind, src)
    ctx.dstView0 = tlgView(dstKind, dst)
    R:line("OBS  %s.before src %s", name, viewText(ctx.srcView, ctx.srcStatus))
    R:line("OBS  %s.before dst %s", name, viewText(ctx.dstView0, "-"))
end

-- `emptyDestination`: the destination held nothing, so it must now hold
-- exactly the source's fuel (otherwise only quantities are checked).
local function hopEnd(ctx, emptyDestination)
    local name = ctx.name
    local s1, d1 = ctx.srcAmount(), ctx.dstAmount()
    local out, moved = ctx.s0 - s1, d1 - ctx.d0
    local dv, dstatus = tlgView(ctx.dstKind, ctx.dst)
    local sv, sstatus = tlgView(ctx.srcKind, ctx.src)
    R:line("OBS  %s litres src %.4f->%.4f dst %.4f->%.4f", name, ctx.s0, s1, ctx.d0, d1)
    R:line("OBS  %s.after src %s", name, viewText(sv, sstatus))
    R:line("OBS  %s.after dst %s", name, viewText(dv, dstatus))
    R:check(name .. ".litres_conserved", function()
        return moved > 0.5 and math.abs(out - moved) <= 1e-3, string.format("out=%.5f in=%.5f", out, moved)
    end)
    R:check(name .. ".tlg_total_matches_native", function()
        if dv == nil then return false, tostring(dstatus) end
        local t = TLG.Domain.Supply.total(dv)
        return math.abs(t - d1) <= 1e-3, string.format("tlg=%.5f native=%.5f status=%s", t, d1, tostring(dstatus))
    end)
    if emptyDestination then
        R:check(name .. ".fuel_state_carried", function()
            if ctx.srcView == nil or dv == nil then return false, "missing view" end
            local src = TLG.Domain.Aging.advance(ctx.srcView, TLG.World.now(), TLG.World.env())
            return sameFuel(src, dv, 1e-3)
        end)
    end
    return moved, dv
end

local function canAmount(fc) return function() return fc:getAmount() end end
local function tankAmount(part) return function() return part:getContainerContentAmount() end end
local function genAmount() return function() return H.gen:getFuel() end end
local function pumpAmount(obj)
    return function()
        local r = TLG.Integration.Stations.read(obj, false)
        return r and TLG.Domain.Supply.total(r) or -1
    end
end

local function findGenerator(cx, cy, radius, wantId)
    local any
    for dx = -radius, radius do
        for dy = -radius, radius do
            local s = sq(cx + dx, cy + dy, 0)
            local objs = s and s:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoGenerator") then
                    local md = o:getModData().tlg
                    if wantId and md and md.id == wantId then return o end
                    any = any or o
                end
            end
        end
    end
    return any
end

local function generatorItem()
    local items = player():getInventory():getItems()
    local found
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and TLG.Integration.Generators.ITEM_TYPES[it:getFullType()] then found = it end
    end
    return found
end

------------------------------------------------------------------------------
-- Phase A
------------------------------------------------------------------------------
local stepsA = {}
local function add(step) stepsA[#stepsA + 1] = step end

add({ name = "wait_world", timeout = 3000, fn = function(ctx, ticks)
    if player() and sq(START.x, START.y, 0) and sq(STATION.x0, STATION.y0, 0) and ticks > 120 then
        R:line("worldName=%s start=%d,%d hours=%.4f tlgNow=%.4f", tostring(getWorld():getWorld()), START.x, START.y,
            hours(), TLG.World.now())
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
    R:check("G01c.translation_ContextMenu", function()
        local t = getText("ContextMenu_TLG_Fuel"); return t ~= "ContextMenu_TLG_Fuel", t
    end)
    R:check("G01c.item_display_name", function()
        local n = instanceItem("TLG.FuelSampleKit"):getDisplayName(); return n == "Fuel Sampling Kit", n
    end)
    R:observe("G13.icon_texture_GlassJar", function() return tostring(getTexture("Item_GlassJar") ~= nil) end)
    R:observe("G01c.adapters", function()
        return string.format("transferWrapped=%s pumpWrapped=%s", tostring(FluidContainer.Transfer ~= TLG.Integration.Containers.originalTransfer()),
            tostring(ISTakeFuel.new ~= nil))
    end)
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
        R:line("OBS  G06.pump %s at %d,%d units=%d isPump=%s", p.sprite, p.x, p.y, p.amount,
            tostring(TLG.Integration.Stations.isPump(p.obj)))
    end
    R:line("OBS  G06.pump_count %d other_fuel_sprites=%s", #H.pumps, table.concat(others, ";"))
    R:observe("G06.sandbox", function()
        return string.format("infinite=%s contamination=%s", tostring(SandboxVars.FuelStationGasInfinite),
            tostring(SandboxVars.TheLastGallon and SandboxVars.TheLastGallon.StationContamination))
    end)
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
    return true
end })

add({ name = "vehicles_spawn", timeout = 600, fn = function(ctx, ticks)
    local base = H.pumps[1] or { x = START.x, y = START.y }
    if not ctx.spawned then
        H.vehicle = addVehicleDebug(H.vehicleScript or "Base.CarNormal", IsoDirections.N, nil, sq(base.x + 3, base.y + 3, 0))
        H.vehicle2 = addVehicleDebug(H.vehicleScript or "Base.CarNormal", IsoDirections.N, nil, sq(base.x + 8, base.y + 3, 0))
        ctx.spawned = true
        return nil
    end
    if ticks < 60 then return nil end
    for i, v in ipairs({ H.vehicle or false, H.vehicle2 or false }) do
        if not v then
            R:line("FAIL vehicles_spawn :: vehicle %d nil", i)
        else
            local tank = v:getPartById("GasTank")
            R:line("OBS  G03.vehicle%d id=%s script=%s at %.1f,%.1f tankCap=%s amount=%s side=%s", i, tostring(v:getId()),
                tostring(v:getScriptName()), v:getX(), v:getY(), tostring(tank and tank:getContainerCapacity()),
                tostring(tank and tank:getContainerContentAmount()), sidecar(tank and tank:getModData()))
            if tank then
                tank:setContainerContentAmount(0)
                tank:getModData().tlg = nil
                v:transmitPartModData(tank)
            end
        end
    end
    H.tank = H.vehicle and H.vehicle:getPartById("GasTank")
    H.tank2 = H.vehicle2 and H.vehicle2:getPartById("GasTank")
    return true
end })

add({ name = "generator_spawn", fn = function()
    local origNew = IsoGenerator.new
    local calls = 0
    IsoGenerator.new = function(item, cell, square)
        calls = calls + 1
        return origNew(item, cell, square)
    end
    local base = H.pumps[1] or { x = START.x, y = START.y }
    local s = sq(base.x - 4, base.y + 6, 0)
    local ok, err = pcall(function() H.gen = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), s) end)
    IsoGenerator.new = origNew
    if not ok then R:line("STEPERR generator_spawn :: %s", tostring(err)) end
    H.genSquare = { x = s:getX(), y = s:getY() }
    R:check("G05.IsoGenerator_new_wrappable", function() return calls == 1 and H.gen ~= nil, "calls=" .. calls end)
    if H.gen then
        R:observe("G04.generator", function()
            return string.format("type=%s maxFuel=%s fuel=%s cond=%s index=%s md.generatorFullType=%s", tostring(H.gen:getGeneratorItemType()),
                tostring(H.gen:getMaxFuel()), tostring(H.gen:getFuel()), tostring(H.gen:getCondition()),
                tostring(H.gen:getObjectIndex()), tostring(H.gen:getModData().generatorFullType))
        end)
        H.gen:setFuel(0)
        H.gen:getModData().tlg = nil
    end
    return true
end })

-- End-to-end proof, hop 1: pump -> empty can (vanilla ISTakeFuel).
add(actionStep("chain_1_pump_to_can", function(ctx)
    local pump = H.pumps[1]
    if not pump then R:line("SKIP chain: no pump"); return nil end
    local can, fc = giveCan("Base.PetrolCan")
    player():setPrimaryHandItem(can)
    player():teleportTo(pump.x + 1, pump.y, 0)
    H.can1, H.can1fc, H.pump = can, fc, pump
    ctx.unitsBefore = pump.obj:getPipedFuelAmount()
    hopBegin(ctx, "CHAIN.1_pump_to_can", "pump", pump.obj, pumpAmount(pump.obj), "item", can, canAmount(fc))
    H.chain = { pumpView = ctx.srcView, reservoir0 = ctx.s0 }
    return ISTakeFuel:new(player(), pump.obj, can)
end, function(ctx)
    local units = ctx.pump and ctx.pump.obj or H.pump.obj
    local unitsAfter = units:getPipedFuelAmount()
    local moved = hopEnd(ctx, true)
    R:line("OBS  G06.pump_to_can units %d->%d (-%d) canL +%.4f litres_per_unit=%.4f frac=%s fluids=%s",
        ctx.unitsBefore, unitsAfter, ctx.unitsBefore - unitsAfter, moved,
        (ctx.unitsBefore - unitsAfter) > 0 and moved / (ctx.unitsBefore - unitsAfter) or -1,
        tostring(units:getModData().tlg and units:getModData().tlg.frac), TLGH.fluidSummary(H.can1fc))
    R:observe("G03.vanilla_menus_accept_station_can", function() return tostring(H.can1fc:contains(Fluid.Petrol)) end)
end))

-- Hop 2: that can -> empty vehicle tank (vanilla ISAddGasolineToVehicle).
add(actionStep("chain_2_can_to_vehicle", function(ctx)
    local v, part = H.vehicle, H.tank
    if not (v and part and H.can1) then R:line("SKIP chain_2"); return nil end
    player():setPrimaryHandItem(H.can1)
    local c = v:getAreaCenter(part:getArea())
    player():teleportTo(c:getX(), c:getY(), 0)
    hopBegin(ctx, "CHAIN.2_can_to_vehicle", "item", H.can1, canAmount(H.can1fc), "vehicle", v, tankAmount(part))
    return ISAddGasolineToVehicle:new(player(), part, H.can1, nil)
end, function(ctx) hopEnd(ctx, true) end))

-- Hop 3: vehicle tank -> empty can (vanilla ISTakeGasolineFromVehicle).
add(actionStep("chain_3_vehicle_to_can", function(ctx)
    local v, part = H.vehicle, H.tank
    if not (v and part) then return nil end
    local can, fc = giveCan("Base.PetrolCan")
    player():setPrimaryHandItem(can)
    H.can2, H.can2fc = can, fc
    hopBegin(ctx, "CHAIN.3_vehicle_to_can", "vehicle", v, tankAmount(part), "item", can, canAmount(fc))
    return ISTakeGasolineFromVehicle:new(player(), part, can, nil)
end, function(ctx) hopEnd(ctx, true) end))

-- Hop 4: that can -> empty generator (vanilla ISAddFuel).
add(actionStep("chain_4_can_to_generator", function(ctx)
    if not (H.gen and H.can2) then R:line("SKIP chain_4"); return nil end
    player():setPrimaryHandItem(H.can2)
    player():teleportTo(H.genSquare.x + 1, H.genSquare.y, 0)
    hopBegin(ctx, "CHAIN.4_can_to_generator", "item", H.can2, canAmount(H.can2fc), "generator", H.gen, genAmount())
    H.chain.gen0 = H.gen:getFuel()
    return ISAddFuel:new(player(), H.gen, H.can2)
end, function(ctx) hopEnd(ctx, true) end))

add({ name = "chain_summary", fn = function()
    local c = H.chain
    if not (c and H.gen and H.can2fc and H.tank) then R:line("SKIP chain_summary"); return true end
    local drawn = c.reservoir0 - pumpAmount(H.pump.obj)()
    local inGen = H.gen:getFuel() - (c.gen0 or 0)
    local left = H.can1fc:getAmount() + H.tank:getContainerContentAmount() + H.can2fc:getAmount()
    R:check("CHAIN.end_to_end.litres", function()
        return drawn > 0.5 and math.abs(drawn - inGen - left) <= 2e-3,
            string.format("drawn=%.5f generator=%.5f left_on_the_way=%.5f", drawn, inGen, left)
    end)
    R:check("CHAIN.end_to_end.fuel_state", function()
        local gv = tlgView("generator", H.gen)
        if not (c.pumpView and gv) then return false, "missing view" end
        local src = TLG.Domain.Aging.advance(c.pumpView, TLG.World.now(), TLG.World.env())
        local ok, detail = sameFuel(src, gv, 2e-3)
        return ok, detail .. " | station " .. viewText(src, "aged") .. " | generator " .. viewText(gv, "now")
    end)
    return true
end })

-- G06: pump -> vehicle directly (vanilla counts 1.25 L per unit here).
-- ISRefuelFromGasPump:isValid() only checks isInArea (SRC :5-7). A
-- three-number teleportTo resolves to teleportTo(int, int, int) (BC
-- overloads), so the player lands on the tile corner, outside the small
-- fuel-cap area (RT-SP 2026-10-31 run 4); setPosition(float, float, float)
-- is the only 3-argument setter and keeps the fractions.
local AREA_OFFSETS = { { 0, 0 }, { 0.2, 0 }, { -0.2, 0 }, { 0, 0.2 }, { 0, -0.2 } }
add({ name = "g06_pump_to_vehicle", timeout = 7000, fn = function(ctx, ticks)
    local pump, v, part = H.pumps[1], H.vehicle, H.tank
    if not (pump and v and part) then R:line("SKIP g06_pump_to_vehicle"); return true end
    if not ctx.queued then
        ctx.try = ctx.try or 0
        if ctx.placedAt == nil then
            ctx.try = ctx.try + 1
            local o = AREA_OFFSETS[ctx.try]
            if o == nil then
                local c = v:getAreaCenter(part:getArea())
                R:line("SKIP g06_pump_to_vehicle: never in the fuel-cap area (player %.2f,%.2f center %.2f,%.2f)",
                    player():getX(), player():getY(), c:getX(), c:getY())
                return true
            end
            local c = v:getAreaCenter(part:getArea())
            ctx.target = { x = c:getX() + o[1], y = c:getY() + o[2] }
            player():teleportTo(math.floor(ctx.target.x), math.floor(ctx.target.y), 0)
            ctx.placedAt = ticks
            return nil
        end
        if ticks - ctx.placedAt == 5 then player():setPosition(ctx.target.x, ctx.target.y, 0) end
        if ticks - ctx.placedAt < 20 then return nil end
        if not v:isInArea(part:getArea(), player()) then ctx.placedAt = nil; return nil end
        R:line("OBS  G06.pump_to_vehicle in area after %d placement(s) at %.2f,%.2f", ctx.try, player():getX(), player():getY())
        ctx.unitsBefore = pump.obj:getPipedFuelAmount()
        hopBegin(ctx, "G06.pump_to_vehicle", "pump", pump.obj, pumpAmount(pump.obj), "vehicle", v, tankAmount(part))
        ctx.empty = part:getContainerContentAmount() <= 1e-6
        ISTimedActionQueue.add(ISRefuelFromGasPump:new(player(), part, pump.obj))
        ctx.queued, ctx.t1 = true, ticks
        return nil
    end
    if ticks - ctx.t1 < 10 or not TLGH.Steps.actionsIdle(player()) then return nil end
    local unitsAfter = pump.obj:getPipedFuelAmount()
    local moved = hopEnd(ctx, ctx.empty)
    R:line("OBS  G06.pump_to_vehicle units %d->%d (-%d) tankL +%.4f litres_per_unit=%.4f", ctx.unitsBefore, unitsAfter,
        ctx.unitsBefore - unitsAfter, moved, (ctx.unitsBefore - unitsAfter) > 0 and moved / (ctx.unitsBefore - unitsAfter) or -1)
    return true
end })

-- G03: an ethanol blend through the vanilla can -> vehicle path.
add(actionStep("g03_blend_can_to_vehicle", function(ctx)
    local v, part = H.vehicle2, H.tank2
    if not (v and part) then return nil end
    local eth = Fluid.Get("TLG_Ethanol")
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Petrol, 6.0 }, { eth, 2.0 } })
    player():setPrimaryHandItem(can)
    local c = v:getAreaCenter(part:getArea())
    player():teleportTo(c:getX(), c:getY(), 0)
    hopBegin(ctx, "G03.blend_can_to_vehicle", "item", can, canAmount(fc), "vehicle", v, tankAmount(part))
    return ISAddGasolineToVehicle:new(player(), part, can, nil)
end, function(ctx) hopEnd(ctx, true) end))

add({ name = "g03_vehicle_idle", timeout = 12000, fn = function(ctx, ticks)
    -- Idle the vehicle that has fuel: vehicle 1 holds station fuel only if
    -- the pump step ran (runs 3-4 idled an empty tank); vehicle 2 holds the
    -- 8 L blend from the G03 pour.
    if not ctx.v then
        ctx.v, ctx.part = H.vehicle, H.tank
        if H.vehicle2 and H.tank2 and (ctx.part == nil
            or ctx.part:getContainerContentAmount() < H.tank2:getContainerContentAmount()) then
            ctx.v, ctx.part = H.vehicle2, H.tank2
        end
    end
    local v, part = ctx.v, ctx.part
    if not (v and part) then return true end
    if not ctx.started then
        ctx.started = true
        R:line("OBS  G03.idle vehicle id=%s tank=%.4f", tostring(v:getId()), part:getContainerContentAmount())
        ctx.view0 = tlgView("vehicle", v)
        R:observe("G03.evaluation_before_start", function()
            local e = TLG.Integration.Vehicles.evaluate(v)
            return string.format("profile=%s grade=%s compatible=%s startFactor=%s reasons=%s",
                tostring(TLG.Integration.Vehicles.profile(v)), tostring(e and e.grade), tostring(e and e.compatible),
                tostring(e and e.startFactor), e and table.concat(e.reasons or {}, ",") or "-")
        end)
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
    if hours() - ctx.h0 >= 0.5 or ticks > 9000 then
        normalSpeed()
        local burned = ctx.fuel0 - part:getContainerContentAmount()
        R:line("OBS  G03.idle %.3f game h: tank %.4f -> %.4f (burn %.4f L) running=%s", hours() - ctx.h0, ctx.fuel0,
            part:getContainerContentAmount(), burned, tostring(v:isEngineRunning()))
        pcall(function() v:shutOff() end)
        pcall(function() v:engineDoShuttingDown() end)
        pcall(function() v:exit(player()) end)
        local view, status = tlgView("vehicle", v)
        R:line("OBS  G03.idle after %s", viewText(view, status))
        if burned > 1e-4 then
            R:check("G03.native_burn_reconciled_proportionally", function()
                if not (ctx.view0 and view) then return false, "missing view" end
                local before = TLG.Domain.Aging.advance(ctx.view0, TLG.World.now(), TLG.World.env())
                local ok, detail = sameFuel(before, view, 1e-3)
                local t = TLG.Domain.Supply.total(view)
                return ok and status == "reconciled" and math.abs(t - part:getContainerContentAmount()) <= 1e-3,
                    string.format("%s status=%s tlg=%.4f native=%.4f", detail, tostring(status), t, part:getContainerContentAmount())
            end)
        end
        return true
    end
end })

add({ name = "g09_two_vehicles", fn = function()
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

add({ name = "g04_generator_burn", timeout = 12000, fn = function(ctx, ticks)
    if not H.gen then return true end
    if not ctx.started then
        ctx.view0 = tlgView("generator", H.gen)
        H.gen:setConnected(true)
        H.gen:setActivated(true)
        ctx.started, ctx.f0, ctx.h0 = true, H.gen:getFuel(), hours()
        speedUp()
        return nil
    end
    if hours() - ctx.h0 >= 0.5 or ticks > 9000 then
        normalSpeed()
        R:line("OBS  G04.burn %.3f game h: fuel %.4f -> %.4f activated=%s powerUsing=%s sandboxConsumption=%s",
            hours() - ctx.h0, ctx.f0, H.gen:getFuel(), tostring(H.gen:isActivated()), tostring(H.gen:getTotalPowerUsing()),
            tostring(SandboxVars.GeneratorFuelConsumption))
        H.gen:setActivated(false)
        H.gen:setConnected(false)
        local view, status = tlgView("generator", H.gen)
        R:line("OBS  G04.burn after %s", viewText(view, status))
        if ctx.f0 - H.gen:getFuel() > 1e-4 then
            R:check("G04.native_burn_reconciled_proportionally", function()
                if not (ctx.view0 and view) then return false, "missing view" end
                local before = TLG.Domain.Aging.advance(ctx.view0, TLG.World.now(), TLG.World.env())
                local ok, detail = sameFuel(before, view, 1e-3)
                return ok and status == "reconciled", detail .. " status=" .. tostring(status)
            end)
        end
        return true
    end
end })

-- G05: pickup and the three Lua drop paths. Each pickup must move the object
-- sidecar onto the item; each drop must move it onto the new object.
local function pickupStep(n)
    return actionStep("g05_pickup_" .. n, function(ctx)
        if not H.gen or H.gen:getObjectIndex() == -1 then R:line("SKIP g05_pickup_%d: no generator object", n); return nil end
        player():setPrimaryHandItem(nil)
        player():setSecondaryHandItem(nil)
        player():teleportTo(H.genSquare.x + 1, H.genSquare.y, 0)
        ctx.objId = H.gen:getModData().tlg and H.gen:getModData().tlg.id
        ctx.fuel = H.gen:getFuel()
        ctx.view = tlgView("generator", H.gen)
        return ISTakeGenerator:new(player(), H.gen)
    end, function(ctx)
        local it = generatorItem()
        H.genItem = it
        local side = it and it:getModData().tlg
        R:line("OBS  G05.pickup_%d item=%s itemFuel=%s side=%s", n, tostring(it and it:getFullType()),
            tostring(it and it:getModData().fuel), sidecar(it and it:getModData()))
        R:check("G05.pickup_" .. n .. ".sidecar_on_item", function()
            return side ~= nil and side.kind == "generator" and side.id ~= nil and side.id == ctx.objId,
                string.format("item=%s object=%s kind=%s", tostring(side and side.id), tostring(ctx.objId), tostring(side and side.kind))
        end)
        R:check("G05.pickup_" .. n .. ".fuel_state_kept", function()
            if not (side and ctx.view) then return false, "missing" end
            local total = 0
            for _, q in pairs(side.q or {}) do total = total + q end
            local ok, detail = sameFuel(ctx.view, { q = side.q or {}, deg = side.deg or {}, mic = side.mic }, 1e-3)
            return ok and math.abs(total - ctx.fuel) <= 1e-3,
                string.format("%s sidecarL=%.4f objectFuel=%.4f", detail, total, ctx.fuel)
        end)
    end)
end

local function dropCheck(n, path, ctx, cx, cy)
    local wantId = ctx.side and ctx.side.id
    local g = findGenerator(cx, cy, 2, wantId)
    local md = g and g:getModData().tlg
    R:line("OBS  G05.drop_%s object=%s at %s fuel=%s side=%s", path, tostring(g ~= nil),
        g and (g:getSquare():getX() .. "," .. g:getSquare():getY()) or "-", tostring(g and g:getFuel()), sidecar(g and g:getModData()))
    R:check("G05.drop_" .. path .. ".sidecar_on_object", function()
        return md ~= nil and wantId ~= nil and md.id == wantId and md.kind == "generator",
            string.format("object=%s item=%s", tostring(md and md.id), tostring(wantId))
    end)
    R:check("G05.drop_" .. path .. ".fuel_kept", function()
        return g ~= nil and math.abs(g:getFuel() - (ctx.fuel or 0)) <= 1e-3,
            string.format("object=%s item=%s", tostring(g and g:getFuel()), tostring(ctx.fuel))
    end)
    if g then
        H.gen = g
        H.genSquare = { x = g:getSquare():getX(), y = g:getSquare():getY() }
    end
end

add(pickupStep(1))
add(actionStep("g05_drop_action", function(ctx)
    local it = H.genItem
    if not it then return nil end
    ctx.side, ctx.fuel = TLG.Tables.deepCopy(it:getModData().tlg), tonumber(it:getModData().fuel) or 0
    ctx.x, ctx.y = H.genSquare.x, H.genSquare.y
    return ISDropWorldItemAction:new(player(), it, sq(ctx.x, ctx.y, 0), 0.5, 0.5, 0, 0, false)
end, function(ctx) dropCheck(1, "action", ctx, ctx.x, ctx.y) end))

add(pickupStep(2))

-- Taking a second generator while carrying the first: vanilla drops the
-- carried one through forceDropHeavyItems inside ISTakeGenerator.complete.
-- Both records must survive (the carried one onto its new object, the taken
-- one onto its new item).
add(actionStep("g05_take_second_while_carrying", function(ctx)
    local carried = H.genItem
    if not (carried and H.gen) then return nil end
    -- The square the first generator was just taken from: pickup 2 proved the
    -- player (one square east, still there) can reach it. Run 3 used x + 2 and
    -- the action never started.
    local s = sq(H.genSquare.x, H.genSquare.y, 0)
    local b = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), s)
    if not b then R:line("SKIP g05_take_second: no second generator"); return nil end
    b:setFuel(4.0)
    local G = TLG.Integration.Generators
    G.writeSidecar(b, (G.read(b, true)))
    H.genB = b
    ctx.bId, ctx.bFuel = b:getModData().tlg.id, b:getFuel()
    ctx.side, ctx.fuel = TLG.Tables.deepCopy(carried:getModData().tlg), tonumber(carried:getModData().fuel) or 0
    local p = player():getCurrentSquare()
    ctx.x, ctx.y = p:getX(), p:getY()
    local action = ISTakeGenerator:new(player(), b)
    R:line("OBS  G05.heavy_item=%s second=%s player=%d,%d canReach=%s index=%s valid=%s", tostring(carried:isForceDropHeavyItem()),
        sidecar(b:getModData()), ctx.x, ctx.y, tostring(p:canReachTo(s)), tostring(b:getObjectIndex()), tostring(action:isValid()))
    return action
end, function(ctx)
    dropCheck(2, "heavy", ctx, ctx.x, ctx.y)
    local it = player():getPrimaryHandItem()
    local side = it and it:getModData().tlg
    R:check("G05.take_second.sidecar_on_new_item", function()
        return side ~= nil and side.id == ctx.bId and side.kind == "generator",
            string.format("item=%s expected=%s hand=%s", tostring(side and side.id), tostring(ctx.bId), tostring(it and it:getFullType()))
    end)
    H.genItemB = it
end))

add(actionStep("g05_drop_floor", function(ctx)
    local it = H.genItemB
    if not it then return nil end
    ctx.side, ctx.fuel = TLG.Tables.deepCopy(it:getModData().tlg), tonumber(it:getModData().fuel) or 0
    local s = player():getCurrentSquare()
    ctx.x, ctx.y = s:getX(), s:getY()
    return ISInventoryTransferAction:new(player(), it, player():getInventory(), ISInventoryPage.GetFloorContainer(0))
end, function(ctx)
    -- Later steps use this (second) generator: it holds 4 L, so the TLG pour
    -- has room (the first one is nearly full; RT-SP run 4 moved only 0.015 L).
    dropCheck(3, "floor", ctx, ctx.x, ctx.y)
end))

-- TLG's own pour action (the menu path for fuels vanilla menus refuse).
add(actionStep("tlg_pour_generator", function(ctx)
    if not H.gen then return nil end
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Petrol, 3.0 } })
    player():setPrimaryHandItem(can)
    player():teleportTo(H.genSquare.x + 1, H.genSquare.y, 0)
    ctx.rev0 = H.gen:getModData().tlg and H.gen:getModData().tlg.rev
    hopBegin(ctx, "TLG.pour_into_generator", "item", can, canAmount(fc), "generator", H.gen, genAmount())
    return ISTLGPourFuel:new(player(), can, TLG.Authority.Resolver.refForObject(H.gen, "generator"), H.gen, false,
        function(reply) ctx.reply = reply end)
end, function(ctx)
    R:line("OBS  TLG.pour_into_generator reply ok=%s reason=%s", tostring(ctx.reply and ctx.reply.ok),
        tostring(ctx.reply and ctx.reply.reason))
    R:check("TLG.pour_into_generator.reply_ok", function() return ctx.reply ~= nil and ctx.reply.ok == true, tostring(ctx.reply and ctx.reply.reason) end)
    hopEnd(ctx, false)
    R:check("TLG.pour_into_generator.revision_advanced", function()
        local rev = H.gen:getModData().tlg and H.gen:getModData().tlg.rev
        return rev ~= nil and ctx.rev0 ~= nil and rev > ctx.rev0, string.format("%s -> %s", tostring(ctx.rev0), tostring(rev))
    end)
end))

add(actionStep("tlg_pour_incompatible", function(ctx)
    if not H.gen then return nil end
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Get("TLG_Ethanol"), 3.0 } })
    player():setPrimaryHandItem(can)
    ctx.fc, ctx.can0, ctx.gen0 = fc, fc:getAmount(), H.gen:getFuel()
    return ISTLGPourFuel:new(player(), can, TLG.Authority.Resolver.refForObject(H.gen, "generator"), H.gen, false,
        function(reply) ctx.reply = reply end)
end, function(ctx)
    local r = ctx.reply
    R:line("OBS  TLG.pour_e100_into_generator reply ok=%s reason=%s", tostring(r and r.ok), tostring(r and r.reason))
    R:check("TLG.pour_e100.refused_without_confirmation_or_moved_exactly", function()
        local dCan, dGen = ctx.can0 - ctx.fc:getAmount(), H.gen:getFuel() - ctx.gen0
        if r and r.ok == false then
            return math.abs(dCan) <= 1e-6 and math.abs(dGen) <= 1e-6, string.format("refused: dCan=%.5f dGen=%.5f", dCan, dGen)
        end
        return r ~= nil and math.abs(dCan - dGen) <= 1e-3, string.format("accepted: dCan=%.5f dGen=%.5f", dCan, dGen)
    end)
end))

------------------------------------------------------------------------------
-- Start gates, stall and TLG pours into a vehicle. Thresholds (Content/
-- Consumers.lua): engine_si_stock accepts ethanol up to 25 %, generator_si_stock
-- up to 15 %. Both gates report refusals through TLG.Log.debug, which the
-- harness wraps for the duration of a step.
------------------------------------------------------------------------------
local function captureTlgDebug(ctx)
    ctx.logged = {}
    local orig = TLG.Log.debug
    ctx.restoreLog = function() TLG.Log.debug = orig end
    TLG.Log.debug = function(fmt, ...)
        local ok, msg = pcall(string.format, fmt, ...)
        ctx.logged[#ctx.logged + 1] = ok and msg or tostring(fmt)
        return orig(fmt, ...)
    end
end

local function loggedMatching(ctx, text)
    for _, m in ipairs(ctx.logged or {}) do
        if string.find(m, text, 1, true) then return m end
    end
    return nil
end

local function evaluationText(e)
    if e == nil then return "nil" end
    return string.format("grade=%s compatible=%s startFactor=%s reasons=%s", tostring(e.grade), tostring(e.compatible),
        tostring(e.startFactor), table.concat(e.reasons or {}, ","))
end

-- Activates a generator through the vanilla action (ISActivateGenerator).
local function generatorGateStep(name, getGen, expectRefused)
    return actionStep(name, function(ctx)
        local g = getGen()
        if not (g and g:getObjectIndex() ~= -1) then R:line("SKIP %s: no generator", name); return nil end
        player():setPrimaryHandItem(nil)
        player():setSecondaryHandItem(nil)
        player():teleportTo(g:getSquare():getX() + 1, g:getSquare():getY(), 0)
        g:setConnected(true)
        ctx.g = g
        R:line("OBS  %s fuel=%.4f %s", name, g:getFuel(), evaluationText((TLG.Integration.Generators.evaluate(g))))
        captureTlgDebug(ctx)
        return ISActivateGenerator:new(player(), g, true)
    end, function(ctx)
        ctx.restoreLog()
        local refusal = loggedMatching(ctx, "generator start refused")
        local activated = ctx.g:isActivated()
        R:line("OBS  %s activated=%s refusal=%s", name, tostring(activated), tostring(refusal))
        if expectRefused then
            R:check(name .. ".refused_by_tlg", function() return refusal ~= nil and not activated, tostring(refusal) end)
        else
            R:check(name .. ".activated", function() return activated and refusal == nil, tostring(refusal) end)
        end
        ctx.g:setActivated(false)
        ctx.g:setConnected(false)
    end)
end

add(generatorGateStep("G04.gate_petrol", function() return H.gen end, false))

-- A third, empty generator receives E100 through the confirmed ("experimental")
-- TLG pour, then must be refused by the start gate.
add(actionStep("tlg_pour_e100_confirmed_generator", function(ctx)
    local base = H.pumps[1] or { x = START.x, y = START.y }
    local s = sq(base.x - 6, base.y + 6, 0)
    local g = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), s)
    if not g then R:line("SKIP tlg_pour_e100_confirmed_generator: no generator"); return nil end
    g:setFuel(0)
    g:getModData().tlg = nil
    H.genC = g
    local can, fc = giveCan("Base.PetrolCan", { { Fluid.Get("TLG_Ethanol"), 3.0 } })
    player():setPrimaryHandItem(can)
    player():teleportTo(s:getX() + 1, s:getY(), 0)
    hopBegin(ctx, "TLG.pour_e100_confirmed_generator", "item", can, canAmount(fc), "generator", g,
        function() return g:getFuel() end)
    return ISTLGPourFuel:new(player(), can, TLG.Authority.Resolver.refForObject(g, "generator"), g, true,
        function(reply) ctx.reply = reply end)
end, function(ctx)
    R:check("TLG.pour_e100_confirmed_generator.reply_ok", function()
        return ctx.reply ~= nil and ctx.reply.ok == true, tostring(ctx.reply and ctx.reply.reason)
    end)
    hopEnd(ctx, true)
end))

add(generatorGateStep("G04.gate_e100", function() return H.genC end, true))

-- TLG pours into a vehicle (default vehicle 2, 8 L E25 from the G03 pour)
-- from a new can with `fills`, or from the can `getCan()` returns. The
-- transfer checks that the player stands in the fuel-cap area, so the step
-- places the player first (see the G06 note on teleportTo).
local function vehiclePourStep(name, fills, experimental, expectOk, getVehicle, getCan)
    return { name = name, timeout = 4000, fn = function(ctx, ticks)
        local v = getVehicle and getVehicle() or H.vehicle2
        local part = v and v:getPartById("GasTank")
        if not (v and part) then R:line("SKIP %s", name); return true end
        if not ctx.placedAt then
            local c = v:getAreaCenter(part:getArea())
            ctx.target = { x = c:getX(), y = c:getY() }
            player():teleportTo(math.floor(ctx.target.x), math.floor(ctx.target.y), 0)
            ctx.placedAt = ticks
            return nil
        end
        if ticks - ctx.placedAt == 5 then player():setPosition(ctx.target.x, ctx.target.y, 0) end
        if ticks - ctx.placedAt < 20 then return nil end
        if not ctx.queued then
            local can, fc
            if getCan then
                can = getCan()
                if can == nil then R:line("SKIP %s: no can", name); return true end
                fc = can:getFluidContainer()
            else
                can, fc = giveCan("Base.PetrolCan", fills)
            end
            player():setPrimaryHandItem(can)
            ctx.fc = fc
            R:line("OBS  %s inArea=%s", name, tostring(v:isInArea(part:getArea(), player())))
            hopBegin(ctx, name, "item", can, canAmount(fc), "vehicle", v, tankAmount(part))
            ISTimedActionQueue.add(ISTLGPourFuel:new(player(), can, { kind = "vehicle", id = v:getId() }, v, experimental,
                function(reply) ctx.reply = reply end))
            ctx.queued, ctx.t1 = true, ticks
            return nil
        end
        if ticks - ctx.t1 < 10 or not TLGH.Steps.actionsIdle(player()) then return nil end
        local r = ctx.reply
        R:line("OBS  %s reply ok=%s reason=%s", name, tostring(r and r.ok), tostring(r and r.reason))
        if expectOk then
            R:check(name .. ".reply_ok", function() return r ~= nil and r.ok == true, tostring(r and r.reason) end)
            hopEnd(ctx, false)
        else
            R:check(name .. ".refused_nothing_moved", function()
                local dCan, dTank = ctx.s0 - ctx.srcAmount(), ctx.dstAmount() - ctx.d0
                return r ~= nil and r.ok == false and r.reason == "incompatible" and math.abs(dCan) <= 1e-6
                    and math.abs(dTank) <= 1e-6, string.format("reason=%s dCan=%.5f dTank=%.5f", tostring(r and r.reason), dCan, dTank)
            end)
        end
        local e = TLG.Integration.Vehicles.evaluate(v)
        R:line("OBS  %s tank now %s", name, evaluationText(e))
        return true
    end }
end

add(vehiclePourStep("TLG.pour_petrol_into_vehicle", { { Fluid.Petrol, 3.0 } }, false, true))
add(vehiclePourStep("TLG.pour_e100_into_vehicle_unconfirmed", { { Fluid.Get("TLG_Ethanol"), 3.0 } }, false, false))
add(vehiclePourStep("TLG.pour_e100_into_vehicle_confirmed", { { Fluid.Get("TLG_Ethanol"), 3.0 } }, true, true))

-- Starts a vehicle through the vanilla action (ISStartVehicleEngine) as its driver.
-- mustRun: the engine has to end up running; like a driver, the step retries
-- up to three times when it does not catch (vanilla start chance, TLG roll).
local function vehicleGateStep(name, getVehicle, expectRefused, mustRun)
    return { name = name, timeout = 1500, fn = function(ctx, ticks)
        local v = getVehicle()
        if not v then R:line("SKIP %s", name); return true end
        if not ctx.t0 then
            pcall(function() v:setHotwired(true) end)
            ctx.entered = v:enter(0, player())
            ctx.t0 = ticks
            return nil
        end
        if not ctx.queued then
            if ticks - ctx.t0 < 30 then return nil end
            local e = TLG.Integration.Vehicles.evaluate(v)
            ctx.grade = e and e.grade
            local battery, engine = "?", "?"
            pcall(function() battery = string.format("%.2f", v:getBatteryCharge()) end)
            pcall(function() engine = tostring(v:getPartById("Engine"):getCondition()) end)
            R:line("OBS  %s driver=%s battery=%s engine=%s %s", name, tostring(v:isDriver(player())), battery, engine,
                evaluationText(e))
            captureTlgDebug(ctx)
            ISTimedActionQueue.add(ISStartVehicleEngine:new(player()))
            ctx.queued, ctx.t1, ctx.attempts = true, ticks, 1
            return nil
        end
        if ticks - ctx.t1 < 180 then return nil end
        if mustRun and not v:isEngineRunning() and ctx.attempts < 3 then
            R:line("OBS  %s attempt %d did not start (state=%s)", name, ctx.attempts, tostring(v:getEngineState()))
            ISTimedActionQueue.add(ISStartVehicleEngine:new(player()))
            ctx.t1, ctx.attempts = ticks, ctx.attempts + 1
            return nil
        end
        ctx.restoreLog()
        local refusal = loggedMatching(ctx, "vehicle start refused")
        local running = v:isEngineRunning()
        R:line("OBS  %s state=%s running=%s attempts=%d refusal=%s", name, tostring(v:getEngineState()), tostring(running),
            ctx.attempts, tostring(refusal))
        if expectRefused then
            R:check(name .. ".refused_by_tlg", function() return refusal ~= nil and not running, tostring(refusal) end)
        elseif mustRun then
            R:check(name .. ".running", function()
                return running, string.format("state=%s attempts=%d refusal=%s", tostring(v:getEngineState()), ctx.attempts,
                    tostring(refusal))
            end)
        else
            -- An empty tank is never refused by TLG, so it proves nothing (run 7).
            R:check(name .. ".not_refused_by_tlg", function()
                return refusal == nil and ctx.grade ~= "empty",
                    string.format("state=%s running=%s grade=%s", tostring(v:getEngineState()), tostring(running),
                        tostring(ctx.grade))
            end)
        end
        pcall(function() v:shutOff() end)
        pcall(function() v:engineDoShuttingDown() end)
        pcall(function() v:exit(player()) end)
        return true
    end }
end

add(vehicleGateStep("G03.gate_e36", function() return H.vehicle2 end, true))

-- Stall: start vehicle 2 directly (bypassing the gate) on the incompatible
-- blend; the per-minute effect handler must stall it.
add({ name = "g03_stall_incompatible", timeout = 8000, fn = function(ctx, ticks)
    local v = H.vehicle2
    if not v then return true end
    if not ctx.t0 then
        pcall(function() v:setHotwired(true) end)
        v:enter(0, player())
        pcall(function() v:tryStartEngine(true) end)
        ctx.t0 = ticks
        return nil
    end
    if not ctx.h0 then
        if ticks - ctx.t0 == 60 then pcall(function() v:engineDoStartingSuccess() end) end
        if v:isEngineRunning() then
            ctx.h0 = hours()
            speedUp()
            return nil
        end
        if ticks - ctx.t0 > 600 then
            R:line("OBS  G03.stall NOT RUN: engine did not start (state=%s)", tostring(v:getEngineState()))
            pcall(function() v:exit(player()) end)
            return true
        end
        return nil
    end
    local elapsed = hours() - ctx.h0
    if not v:isEngineRunning() or elapsed > 0.25 then
        normalSpeed()
        local stopped = not v:isEngineRunning()
        R:line("OBS  G03.stall after %.3f game h state=%s", elapsed, tostring(v:getEngineState()))
        R:check("G03.stall_on_incompatible_fuel", function()
            return stopped, string.format("stopped=%s after %.1f game min", tostring(stopped), elapsed * 60)
        end)
        pcall(function() v:shutOff() end)
        pcall(function() v:exit(player()) end)
        return true
    end
    return nil
end })

add(vehicleGateStep("G03.gate_station_fuel", function() return H.vehicle end, false))

------------------------------------------------------------------------------
-- Renewable loop: ethanol made in the machines runs flex-converted engines.
-- Time fixture: fermentation takes days and conversion work hours, so the
-- harness advances the MOD clock only (TLG.World.now + offset; the game clock
-- does not move). Catch-up and work crediting are domain-tested; this checks
-- the commands, inventory handling, adapters and the effect on engines. The
-- offset only grows and stays until the end of phase A, so this harness
-- world's records end up ahead of its own clock: never reuse its save.
------------------------------------------------------------------------------
local LOOP = { x = 10641, y = 10632 }

local function installClockOffset()
    if H.clockOffset then return end
    H.clockOffset = 0
    local base = TLG.World.now
    TLG.World.now = function() return base() + H.clockOffset end
end

local function brief(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth > 2 then return "{...}" end
    local parts = {}
    for _, k in ipairs(TLG.Tables.sortedKeys(v)) do parts[#parts + 1] = tostring(k) .. "=" .. brief(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Authoritative request (synchronous in single player), logged in full.
local function ask(label, command, args)
    local reply
    TLG.Net.request(command, args, function(r) reply = r end)
    R:line("OBS  %s %s -> ok=%s reason=%s state=%s pause=%s stage=%s blocked=%s missing=%s outputs=%s", label, command,
        tostring(reply and reply.ok), tostring(reply and reply.reason), tostring(reply and reply.state),
        tostring(reply and reply.pause), tostring(reply and reply.stage), brief(reply and reply.blocked),
        brief(reply and reply.missing), brief(reply and reply.outputs))
    return reply or {}
end

local function countType(t) return player():getInventory():getCountTypeRecurse(t) end

-- Advances the mod clock in `step`-hour jumps until the machine has output
-- (or faults); every status is logged, including pause reasons.
local function runUntilReady(label, ref, step, maxHours)
    local s, waited = {}, 0
    while waited < maxHours do
        H.clockOffset = H.clockOffset + step
        waited = waited + step
        s = ask(label, "machine.status", { target = ref })
        if not s.ok or s.state == "OutputReady" or s.state == "Faulted" then break end
    end
    return s, waited
end

------------------------------------------------------------------------------
-- Player path: the loop goes through what a player uses (vanilla crafting,
-- the vanilla drop action, the machine and workshop context menus and the
-- work action they queue). Menu entries are clicked the way ISContextMenu
-- does; the TLG reply and the dialog text are captured.
------------------------------------------------------------------------------
local function currentAction()
    local q = ISTimedActionQueue.getTimedActionQueue(player())
    return q and q.queue and q.queue[1] or nil
end

-- Dialogs the menus open: the text is kept (what the player reads), the
-- windows are closed again at the end of each step.
H.dialogs = H.dialogs or { texts = {}, open = {} }
local function captureDialogs(on)
    if on and not H.dialogs.orig then
        H.dialogs.orig = ISModalRichText.new
        ISModalRichText.new = function(self, x, y, w, h, text, ...)
            local o = H.dialogs.orig(self, x, y, w, h, text, ...)
            H.dialogs.texts[#H.dialogs.texts + 1] = tostring(text)
            H.dialogs.open[#H.dialogs.open + 1] = o
            return o
        end
    elseif not on and H.dialogs.orig then
        ISModalRichText.new, H.dialogs.orig = H.dialogs.orig, nil
    end
end

local function closeDialogs()
    for _, o in ipairs(H.dialogs.open) do pcall(function() o:removeFromUIManager() end) end
    H.dialogs.open = {}
end

local function has(text, part) return text ~= nil and string.find(text, part, 1, true) ~= nil end

-- Runs an option as ISContextMenu does (onSelect(target, param1, ...)) and
-- returns the TLG reply its request got.
local function click(opt)
    local reply
    local orig = TLG.Net.request
    TLG.Net.request = function(command, args, onReply)
        return orig(command, args, function(r)
            reply = r
            if onReply then onReply(r) end
        end)
    end
    local ok, err = pcall(opt.onSelect, opt.target, opt.param1, opt.param2, opt.param3, opt.param4, opt.param5,
        opt.param6, opt.param7, opt.param8, opt.param9, opt.param10)
    TLG.Net.request = orig
    if not ok then R:line("OBS  menu entry %s raised %s", tostring(opt.name), tostring(err)) end
    return reply
end

-- Builds a context menu as a right-click would and clicks one submenu entry.
local function menuClick(label, fill, rootText, text)
    local context = ISContextMenu.get(0, 100, 100)
    fill(context)
    local root = context:getOptionFromName(rootText)
    local sub = root and root.subOption and context:getSubMenu(root.subOption)
    local opt = sub and sub:getOptionFromName(text)
    context:setVisible(false)
    local reply
    if opt == nil then
        reply = { ok = false, reason = "no_menu_entry" }
    elseif opt.notAvailable then
        reply = { ok = false, reason = "entry_disabled" }
    else
        reply = click(opt) or { ok = true, reason = "queued" }
    end
    R:line("OBS  %s menu \"%s\" -> ok=%s reason=%s state=%s stage=%s outputs=%s consumed=%s", label, text,
        tostring(reply.ok), tostring(reply.reason), tostring(reply.state), tostring(reply.stage), brief(reply.outputs),
        brief(reply.consumed))
    return reply
end

local function machineClick(label, item, key)
    return menuClick(label, function(c) TLG.UI.MachineMenu.fill(0, c, { item }) end, getText("ContextMenu_TLG_Machine"),
        getText(key))
end

local function workshopClick(label, rootKey, text)
    return menuClick(label, function(c) TLG.UI.WorkshopMenu.fill(0, c, {}, false) end, getText(rootKey), text)
end

local function takeAway(fullType)
    local it = player():getInventory():getFirstTypeRecurse(fullType)
    if it then it:getContainer():Remove(it) end
    return it
end

local function giveBack(it)
    if it then player():getInventory():AddItem(it) end
end

local function waterCarried()
    local total = 0
    local list = player():getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and fc:isPureFluid(Fluid.Water)
    end)
    for i = 0, list:size() - 1 do total = total + list:get(i):getFluidContainer():getAmount() end
    return total
end

-- Ethanol per carried container: item id -> { item, litres }.
local function ethanolCans()
    local out = {}
    local list = player():getInventory():getAllEvalRecurse(function(it)
        local fc = it:getFluidContainer()
        return fc ~= nil and not fc:isEmpty()
    end)
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        local comp = TLG.Integration.Native.readComposition(it:getFluidContainer())
        if (comp.ethanol or 0) > 0 then out[it:getID()] = { item = it, litres = comp.ethanol } end
    end
    return out
end

-- The container a collect filled: the one whose ethanol grew (and whether it
-- held none before).
local function grownCan(before)
    for id, e in pairs(ethanolCans()) do
        if e.litres > ((before[id] and before[id].litres) or 0) + 1e-6 then return e.item, before[id] == nil end
    end
    return nil, nil
end

local TLG_RECIPES = { "TLG_MakeFermenterVessel", "TLG_MakePotStill", "TLG_MakeRefluxStill", "TLG_MakeDryingColumn",
    "TLG_MakeSampleKit", "TLG_MakeFuelFilter", "TLG_MakeFuelStabilizer" }

-- Recipes the crafting window lists (ISHandcraftWindow.lua:53), by short name.
local function windowRecipes()
    local out = {}
    local list = CraftRecipeManager.queryRecipes("InHandCraft;AnySurfaceCraft")
    for i = 0, list:size() - 1 do
        local r = list:get(i)
        out[string.match(r:getName(), "([^%.]+)$")] = r
    end
    return out
end

-- Whether the inventory "craft" menu offers `recipe` on `item`.
local function offeredFor(item, recipe)
    local list = CraftRecipeManager.getUniqueRecipeItems(item, player(), ISInventoryPaneContextMenu.getContainers(player()))
    for i = 0, list:size() - 1 do
        if list:get(i):getName() == recipe:getName() then return true end
    end
    return false
end

-- The nearest generic crafting surface (table, counter) around (cx, cy) and
-- a free square next to it, as vanilla finds one
-- (IsoObject.isGenericCraftingSurface, AdjacentFreeTileFinder.Find).
local function findSurface(cx, cy, radius)
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local s = getCell():getGridSquare(cx + dx, cy + dy, 0)
                    local objs = s and s:getObjects()
                    for i = 0, (objs and objs:size() or 0) - 1 do
                        if objs:get(i):isGenericCraftingSurface() then
                            local stand = AdjacentFreeTileFinder.Find(s, player())
                            if stand then return objs:get(i), stand end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Carried weight and vanilla's full-inventory flag: a full inventory stops
-- FluidContainer.CanTransfer (BC) and may stop crafting (run 10).
local function loadText()
    local w, m, full = "?", "?", "?"
    pcall(function() w = string.format("%.1f", player():getInventory():getCapacityWeight()) end)
    pcall(function() m = string.format("%.1f", player():getMaxWeight()) end)
    pcall(function() full = tostring(player():hasFullInventory()) end)
    return string.format("load=%s/%s full=%s", w, m, full)
end

local function give(fullType, n)
    for _ = 1, n do player():getInventory():AddItem(fullType) end
end

local function removeAll(fullType)
    local n = 0
    while takeAway(fullType) do n = n + 1 end
    return n
end

-- Every reply the work action gets and why it stops (run 10: both actions
-- stopped about five ticks in, without a report).
local function instrumentWorkAction()
    if H.workInstrumented then return end
    H.workInstrumented = true
    local W = ISTLGConversionWork
    local onReply, stop, perform = W.onReply, W.stop, W.perform
    W.onReply = function(self, r)
        R:line("OBS  WORK.reply ok=%s reason=%s state=%s stage=%s released=%s expired=%s credited=%s done=%s/%s reports=%d",
            tostring(r.ok), tostring(r.reason), tostring(r.state), tostring(r.stage), tostring(r.released),
            tostring(r.expired), tostring(r.credited), tostring(r.doneHours), tostring(r.totalHours), self.reports or -1)
        return onReply(self, r)
    end
    W.stop = function(self)
        local valid = "?"
        pcall(function() valid = tostring(self:isValid()) end)
        R:line("OBS  WORK.stop valid=%s joined=%s ended=%s reports=%d at %.2f,%.2f %s", valid, tostring(self.joined),
            tostring(self.ended), self.reports or -1, player():getX(), player():getY(), loadText())
        return stop(self)
    end
    W.perform = function(self)
        R:line("OBS  WORK.perform ended=%s reports=%d", tostring(self.ended), self.reports or -1)
        return perform(self)
    end
end

-- Each recipe's materials ({ type, count, kept tool }), handed over just
-- before it is crafted: with everything at once the inventory was full and
-- vanilla dropped the outputs on the floor (Actions.addOrDropItem, run 11).
local CRAFTS = {
    { recipe = "TLG_MakeFermenterVessel", via = "Base.Plank", out = "TLG.FermenterVessel",
        mats = { { "Base.Hammer", 1, true }, { "Base.Plank", 6 }, { "Base.Nails", 12 }, { "Base.EmptyJar", 1 } } },
    { recipe = "TLG_MakePotStill", via = "Base.Pot", out = "TLG.PotStill",
        mats = { { "Base.Pot", 1 }, { "Base.MetalPipe", 2 }, { "Base.RubberHose", 1 } } },
    { recipe = "TLG_MakeRefluxStill", via = "TLG.PotStill", out = "TLG.RefluxStill",
        mats = { { "Base.SheetMetal", 2 }, { "Base.MetalPipe", 3 }, { "Base.BlowTorch", 1, true }, { "Base.WeldingMask", 1, true } } },
    { recipe = "TLG_MakeDryingColumn", via = "Base.MetalPipe", out = "TLG.DryingColumn",
        mats = { { "Base.MetalPipe", 1 }, { "Base.EmptyJar", 1 } } },
}

-- Items of a type lying on the floor within `radius` squares of the player.
local function floorCount(fullType, radius)
    local n, ps = 0, player():getSquare()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local s = ps and getCell():getGridSquare(ps:getX() + dx, ps:getY() + dy, ps:getZ())
            local objs = s and s:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == fullType then n = n + 1 end
            end
        end
    end
    return n
end

add({ name = "loop_setup", timeout = 600, fn = function(ctx, ticks)
    if not ctx.done then
        installClockOffset()
        captureDialogs(true)
        instrumentWorkAction()
        local p = player()
        p:setPerkLevelDebug(Perks.Mechanics, 4)
        p:setPerkLevelDebug(Perks.Electricity, 2)
        p:setPerkLevelDebug(Perks.Woodwork, 2)
        p:getKnownRecipes():add("Generator")
        p:getKnownRecipes():add("Basic Mechanics")
        -- Materials are handed over step by step (crafting, production,
        -- conversions) so the character is never overloaded: run 10 carried
        -- them all at once and vanilla refused a can-to-can pour.
        LOOP.gen = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), sq(LOOP.x + 5, LOOP.y, 0))
        if LOOP.gen then
            LOOP.gen:setFuel(0)
            LOOP.gen:getModData().tlg = nil
        end
        local base = H.pumps[1] or { x = START.x, y = START.y }
        LOOP.car = addVehicleDebug(H.vehicleScript or "Base.CarNormal", IsoDirections.N, nil, sq(base.x + 13, base.y + 3, 0))
        -- Takes the vanilla start prerequisites (part condition) out of the
        -- result, as vanilla's debug repair does (SRC ISVehicleMenu.lua:957).
        -- The tank is emptied after this.
        if LOOP.car then pcall(function() LOOP.car:repair() end) end
        ctx.done = true
        return nil
    end
    if ticks < 60 then return nil end
    if LOOP.car then
        local tank = LOOP.car:getPartById("GasTank")
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        LOOP.car:transmitPartModData(tank)
    end
    R:line("OBS  LOOP.setup generator=%s car=%s mechanics=%d electricity=%d woodwork=%d cooking=%d %s",
        tostring(LOOP.gen ~= nil), tostring(LOOP.car and LOOP.car:getId()), player():getPerkLevel(Perks.Mechanics),
        player():getPerkLevel(Perks.Electricity), player():getPerkLevel(Perks.Woodwork), player():getPerkLevel(Perks.Cooking),
        loadText())
    return true
end })

-- Crafting through the inventory "craft" menu path
-- (ISInventoryPaneContextMenu.OnNewCraft), next to a real counter for the
-- AnySurfaceCraft recipes.
add({ name = "loop_craft", timeout = 8000, fn = function(ctx, ticks)
    if not ctx.t0 then
        -- Two recipes keep a screwdriver; it later serves the conversions.
        give("Base.Screwdriver", 1)
        R:line("OBS  LOOP.craft_start %s", loadText())
        ctx.listed = windowRecipes()
        R:check("LOOP.recipes_listed_for_crafting", function()
            local missing = {}
            for _, n in ipairs(TLG_RECIPES) do if not ctx.listed[n] then missing[#missing + 1] = n end end
            return #missing == 0, #missing == 0 and "all 7 TLG recipes listed" or ("not listed: " .. table.concat(missing, ","))
        end)
        local base = H.pumps[1] or { x = START.x, y = START.y }
        ctx.surface, ctx.stand = findSurface(base.x, base.y, 25)
        local spriteName = "?"
        pcall(function() spriteName = ctx.surface:getSprite():getName() end)
        R:line("OBS  LOOP.craft_surface %s", ctx.stand and string.format("%s at %d,%d, standing at %d,%d", spriteName,
            ctx.surface:getSquare():getX(), ctx.surface:getSquare():getY(), ctx.stand:getX(), ctx.stand:getY())
            or "none within 25 tiles of the pumps")
        if ctx.stand then player():teleportTo(ctx.stand:getX(), ctx.stand:getY(), ctx.stand:getZ()) end
        ctx.t0, ctx.i, ctx.stash = ticks, 0, {}
        return nil
    end
    if ticks - ctx.t0 < 30 then return nil end
    if ctx.waiting then
        if ticks - ctx.waitFrom < 10 then return nil end
        if not TLGH.Steps.actionsIdle(player()) and ticks - ctx.waitFrom < 3000 then return nil end
        local c = CRAFTS[ctx.i]
        local made, dropped = countType(c.out) - ctx.before, floorCount(c.out, 2) - ctx.floorBefore
        -- Consumed inputs are gone, kept tools are still there.
        local wrong = {}
        for _, m in ipairs(c.mats) do
            local want = ctx.base[m[1]] + (m[3] and m[2] or 0)
            if countType(m[1]) ~= want then wrong[#wrong + 1] = string.format("%s=%d(want %d)", m[1], countType(m[1]), want) end
        end
        R:check("LOOP.craft_" .. c.out, function()
            return ctx.inList and ctx.offered and made == 1 and #wrong == 0,
                string.format("listed=%s offered=%s made=%d on floor=%d inputs left wrong=[%s] %s", tostring(ctx.inList),
                    tostring(ctx.offered), made, dropped, table.concat(wrong, ","), loadText())
        end)
        -- Keep the load light: crafted machines are set aside (the pot still
        -- is the reflux still's input) and kept tools go back.
        if c.out ~= "TLG.PotStill" and made == 1 then ctx.stash[#ctx.stash + 1] = takeAway(c.out) end
        for _, m in ipairs(c.mats) do
            if m[3] then removeAll(m[1]) end
        end
        ctx.waiting = false
    end
    ctx.i = ctx.i + 1
    local c = CRAFTS[ctx.i]
    if c == nil then
        for _, it in ipairs(ctx.stash) do giveBack(it) end
        -- Later steps need the machines even when a craft failed.
        for _, t in ipairs({ "TLG.FermenterVessel", "TLG.RefluxStill", "TLG.DryingColumn" }) do
            if countType(t) == 0 then
                player():getInventory():AddItem(t)
                R:line("OBS  LOOP.craft fallback: %s added directly", t)
            end
        end
        -- Whatever the recipes did not use goes away (kept tools included),
        -- except the screwdriver.
        local left = {}
        for _, t in ipairs({ "Base.Hammer", "Base.Plank", "Base.Nails", "Base.EmptyJar", "Base.Pot", "Base.MetalPipe",
            "Base.SheetMetal", "Base.BlowTorch", "Base.WeldingMask", "Base.RubberHose", "TLG.PotStill" }) do
            local n = removeAll(t)
            if n > 0 then left[#left + 1] = t .. "=" .. n end
        end
        R:line("OBS  LOOP.craft_leftovers removed %s; %s", table.concat(left, ","), loadText())
        return true
    end
    local recipe = ctx.listed[c.recipe] or getScriptManager():getCraftRecipe(c.recipe)
    if recipe and recipe:isAnySurfaceCraft() and not ctx.stand then
        R:line("SKIP LOOP.craft_%s: no crafting surface found; added directly", c.out)
        player():getInventory():AddItem(c.out)
        return nil
    end
    ctx.base = {}
    for _, m in ipairs(c.mats) do ctx.base[m[1]] = countType(m[1]) end
    for _, m in ipairs(c.mats) do give(m[1], m[2]) end
    local via = player():getInventory():getFirstTypeRecurse(c.via)
    ctx.inList, ctx.before, ctx.floorBefore = ctx.listed[c.recipe] ~= nil, countType(c.out), floorCount(c.out, 2)
    ctx.offered = recipe ~= nil and via ~= nil and offeredFor(via, recipe)
    if recipe and via then ISInventoryPaneContextMenu.OnNewCraft(via, recipe, 0, false) end
    if TLGH.Steps.actionsIdle(player()) then
        -- Nothing queued: say why, from the same logic the menu uses.
        local why = string.format("recipe=%s item=%s", tostring(recipe ~= nil), tostring(via ~= nil))
        if recipe and via then
            -- The gates of BaseCraftingLogic.canPerformCurrentRecipe (BC):
            -- valid for the character, inputs, outputs, workbench range.
            local containers = ISInventoryPaneContextMenu.getContainers(player())
            local logic = HandcraftLogic.new(player(), nil, nil)
            logic:setIsoObject(logic:findCraftSurface(player(), 2))
            logic:setContainers(containers)
            logic:setRecipeFromContextClick(recipe, via)
            local g = { valid = "?", learn = "?", inputs = "?", outputs = "?", range = "?" }
            pcall(function() g.valid = tostring(CraftRecipeManager.isValidRecipeForCharacter(recipe, player(), nil, containers)) end)
            pcall(function() g.learn = tostring(recipe:needToBeLearn()) .. "/" .. tostring(player():isRecipeKnown(recipe, true)) end)
            pcall(function() g.inputs = tostring(logic:getRecipeData():areAllInputItemsSatisfied()) end)
            pcall(function() g.outputs = tostring(logic:getRecipeData():canCreateOutputs(ArrayList.new(), player())) end)
            pcall(function() g.range = tostring(logic:isCharacterInRangeOfWorkbench()) end)
            local unmet = {}
            pcall(function()
                local inputs = recipe:getInputs()
                for i = 0, inputs:size() - 1 do
                    local d = logic:getRecipeData():getDataForInputScript(inputs:get(i))
                    if d and not d:isInputItemsSatisfied() then unmet[#unmet + 1] = tostring(i + 1) end
                end
            end)
            why = string.format("canPerform=%s surface=%s valid=%s learn/known=%s inputs=%s unmet=[%s] outputs=%s range=%s %s",
                tostring(logic:canPerformCurrentRecipe()), tostring(logic:getIsoObject() ~= nil), g.valid, g.learn, g.inputs,
                table.concat(unmet, ","), g.outputs, g.range, loadText())
        end
        R:line("OBS  LOOP.craft_%s not queued: %s", c.out, why)
    end
    ctx.waiting, ctx.waitFrom = true, ticks
    return nil
end })

-- The machines go on the ground with the vanilla drop action.
add({ name = "loop_place", timeout = 3000, fn = function(ctx, ticks)
    if not ctx.t0 then
        player():teleportTo(LOOP.x + 1, LOOP.y + 1, 0)
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 20 then return nil end
    if not ctx.queued then
        LOOP.items = {}
        for i, t in ipairs({ "TLG.FermenterVessel", "TLG.RefluxStill", "TLG.DryingColumn" }) do
            local it = player():getInventory():getFirstTypeRecurse(t)
            LOOP.items[i] = it
            if it then
                ISTimedActionQueue.add(ISDropWorldItemAction:new(player(), it, sq(LOOP.x + i - 1, LOOP.y, 0), 0.5, 0.5, 0, 0, false))
            end
        end
        LOOP.fermenter, LOOP.still, LOOP.dryer = LOOP.items[1], LOOP.items[2], LOOP.items[3]
        ctx.queued, ctx.t1 = true, ticks
        return nil
    end
    if ticks - ctx.t1 < 10 or (not TLGH.Steps.actionsIdle(player()) and ticks - ctx.t1 < 2000) then return nil end
    R:check("LOOP.machines_placed_with_the_drop_action", function()
        local parts, ok = {}, true
        for i = 1, 3 do
            local it = LOOP.items[i]
            local s = it and TLG.Integration.Machines.square(it)
            ok = ok and s ~= nil and s:getX() == LOOP.x + i - 1 and s:getY() == LOOP.y
            parts[#parts + 1] = string.format("%s at %s", it and it:getFullType() or "missing",
                s and (s:getX() .. "," .. s:getY()) or "-")
        end
        return ok, table.concat(parts, " ")
    end)
    return true
end })

add({ name = "loop_production", timeout = 600, fn = function(ctx, ticks)
    if not (LOOP.fermenter and LOOP.still and LOOP.dryer) then R:line("SKIP loop_production: a machine is missing"); return true end
    if not ctx.t0 then
        player():teleportTo(LOOP.x + 1, LOOP.y + 1, 0)
        give("Base.Sugar", 6); give("Base.Yeast", 1); give("Base.Log", 2); give("Base.Quicklime", 2)
        -- 32 L of water: more than the 30 L a 6 kg mash takes, so a default
        -- that ignores the sugar shows.
        for _, litres in ipairs({ 10, 10, 10, 2 }) do
            local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
            fc:Empty()
            fc:addFluid(Fluid.Water, litres)
        end
        R:line("OBS  LOOP.production_materials %s", loadText())
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 20 then return nil end
    local M = TLG.Integration.Machines
    local fRef, sRef, dRef = M.refFor(LOOP.fermenter), M.refFor(LOOP.still), M.refFor(LOOP.dryer)
    local dialogs0 = #H.dialogs.texts

    -- Fermentation through the menu, which sends no amounts: 6 kg of sugar
    -- and 32 L of water carried, so the default has to take 30 L (5 L per kg).
    local sugar0, yeast0, water0 = countType("Base.Sugar"), countType("Base.Yeast"), waterCarried()
    local r = machineClick("LOOP.ferment", LOOP.fermenter, "ContextMenu_TLG_LoadFerment")
    R:check("LOOP.ferment_loaded_from_menu", function()
        return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6 and math.abs((r.waterL or 0) - 30) < 1e-6
            and math.abs(waterCarried() - (water0 - 30)) < 1e-3
            and countType("Base.Sugar") == sugar0 - 6 and countType("Base.Yeast") == yeast0 - 1,
            string.format("sugar=%s water=%s carried %.2f->%.2f sugarItems %d->%d yeast %d->%d", tostring(r.sugarKg),
                tostring(r.waterL), water0, waterCarried(), sugar0, countType("Base.Sugar"), yeast0, countType("Base.Yeast"))
    end)
    local f, fh = runUntilReady("LOOP.fermenting", fRef, 24, 400)
    local fEth = (f.outputs or {}).ethanol or 0
    R:check("LOOP.ferment_completed", function()
        return f.state == "OutputReady" and fEth >= 3.2 and fEth <= 3.7,
            string.format("state=%s after %d h of mod time outputs=%s", tostring(f.state), fh, brief(f.outputs))
    end)

    -- Reflux still through the menu: all carried wood goes into the firebox,
    -- the wash comes from the fermenter (a yeast starter comes back).
    local logs0 = countType("Base.Log")
    local fuel = machineClick("LOOP.firebox", LOOP.still, "ContextMenu_TLG_AddFirewood")
    local wash = machineClick("LOOP.load_wash", LOOP.still, "ContextMenu_TLG_LoadWash")
    R:check("LOOP.wash_loaded_yeast_starter_returned", function()
        return fuel.ok == true and math.abs((fuel.firebox or 0) - 18) < 1e-6 and countType("Base.Log") == logs0 - 2
            and wash.ok == true and countType("TLG.YeastStarter") >= 1,
            string.format("firebox ok=%s kg=%s logs %d->%d wash ok=%s L=%s starter=%d", tostring(fuel.ok),
                tostring(fuel.firebox), logs0, countType("Base.Log"), tostring(wash.ok), tostring(wash.washL),
                countType("TLG.YeastStarter"))
    end)
    local s, sh = runUntilReady("LOOP.distilling", sRef, 2, 48)
    local sEth, sWater = (s.outputs or {}).ethanol or 0, (s.outputs or {}).water or 0
    R:check("LOOP.distill_completed", function()
        return s.state == "OutputReady" and sEth > 2.5 and sWater / math.max(1e-9, sEth + sWater) < 0.07,
            string.format("state=%s after %d h ethanol=%.4f water=%.4f", tostring(s.state), sh, sEth, sWater)
    end)
    -- Collect through the menu: it has to choose an empty can.
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    local c1 = machineClick("LOOP.collect_still", LOOP.still, "ContextMenu_TLG_CollectEthanol")
    local can1, wasEmpty = grownCan(before)
    local v1 = can1 and tlgView("item", can1)
    R:check("LOOP.hydrous_ethanol_bottled", function()
        local q = v1 and v1.q or {}
        return c1.ok == true and wasEmpty == true and math.abs((q.ethanol or 0) - sEth) < 1e-3
            and math.abs((q.water or 0) - sWater) < 1e-3,
            string.format("into %s (no ethanol before=%s) %s fluids=%s", can1 and can1:getFullType() or "nothing",
                tostring(wasEmpty), viewText(v1, "can"), can1 and TLGH.fluidSummary(can1:getFluidContainer()) or "-")
    end)
    if can1 == nil then return true end

    -- Fixture: give the spirit an ageing history so drying can show that it
    -- keeps the degradation (fresh distillate has none).
    local C = TLG.Integration.Containers
    local aged = C.read(can1, "item", true)
    aged.deg.ethanol = 0.8
    C.writeSidecar(can1, "item", aged)

    -- Drying column through the menu: it picks the can holding only ethanol
    -- and water.
    local lime0 = countType("Base.Quicklime")
    local d = machineClick("LOOP.load_dry", LOOP.dryer, "ContextMenu_TLG_LoadDry")
    R:check("LOOP.dry_loaded", function()
        return d.ok == true and countType("Base.Quicklime") == lime0 - 1 and can1:getFluidContainer():getAmount() < 1e-3,
            string.format("ethanol=%s water=%s lime=%s lime items %d->%d can left=%.4f", tostring(d.ethanolL),
                tostring(d.waterL), tostring(d.limeKg), lime0, countType("Base.Quicklime"), can1:getFluidContainer():getAmount())
    end)
    local dr, dh = runUntilReady("LOOP.drying", dRef, 4, 48)
    giveCan("Base.JerryCan")
    before = ethanolCans()
    local c2 = machineClick("LOOP.collect_dry", LOOP.dryer, "ContextMenu_TLG_CollectEthanol")
    local can2, wasEmpty2 = grownCan(before)
    local v2 = can2 and tlgView("item", can2)
    R:check("LOOP.dried_ethanol_keeps_degradation", function()
        local q = v2 and v2.q or {}
        local e, w = q.ethanol or 0, q.water or 0
        return dr.state == "OutputReady" and c2.ok == true and wasEmpty2 == true and e > 2.5 and w <= e * 0.005 + 1e-4
            and v2 ~= nil and math.abs((v2.deg.ethanol or 0) - 0.8) < 0.01,
            string.format("after %d h into %s (no ethanol before=%s): %s", dh, can2 and can2:getFullType() or "nothing",
                tostring(wasEmpty2), viewText(v2, "can"))
    end)
    if can2 == nil then return true end

    -- Split through the wrapped FluidContainer.Transfer: one can per engine.
    -- Vanilla refuses it when the inventory is full (CanTransfer, BC).
    local can3 = giveCan("Base.JerryCan")
    R:line("OBS  LOOP.split %s canTransfer=%s", loadText(),
        tostring(FluidContainer.CanTransfer(can2:getFluidContainer(), can3:getFluidContainer())))
    FluidContainer.Transfer(can2:getFluidContainer(), can3:getFluidContainer(), can2:getFluidContainer():getAmount() / 2)
    local va, vb = tlgView("item", can2), tlgView("item", can3)
    R:check("LOOP.split_keeps_state", function()
        if not (va and vb) then return false, "missing view" end
        local ok, detail = sameFuel(va, vb, 1e-3)
        return ok and math.abs(TLG.Domain.Supply.total(va) - TLG.Domain.Supply.total(vb)) < 1e-3,
            detail .. string.format(" a=%.4f b=%.4f", TLG.Domain.Supply.total(va), TLG.Domain.Supply.total(vb))
    end)
    LOOP.canGen, LOOP.canCar = can2, can3

    -- Status through the menu; every result dialog in plain words.
    local st = machineClick("LOOP.status", LOOP.fermenter, "ContextMenu_TLG_MachineStatus")
    R:check("LOOP.menu_dialogs_translated", function()
        local n, raw = 0, {}
        for i = dialogs0 + 1, #H.dialogs.texts do
            n = n + 1
            local t = H.dialogs.texts[i]
            if has(t, "IGUI_") or has(t, "ContextMenu_") then raw[#raw + 1] = t end
        end
        return st.ok == true and n >= 7 and #raw == 0, string.format("dialogs=%d untranslated=[%s] last=%s", n,
            table.concat(raw, " | "), tostring(H.dialogs.texts[#H.dialogs.texts]))
    end)
    closeDialogs()
    return true
end })

-- Conversion work runs as the timed action ISTLGConversionWork. The harness
-- moves the mod clock CLOCK_PER_TICK hours per tick while it runs, so the
-- action's quarter-hour reports come every few ticks.
local CLOCK_PER_TICK = 0.05

local function projectOf(device, kind)
    local md = kind == "vehicle" and device:getPartById("Engine"):getModData() or device:getModData()
    return md.tlgConv
end

local function sumOf(t)
    local s = 0
    for _, v in pairs(t or {}) do s = s + v end
    return s
end

local function hoursOf(device, kind)
    local p = projectOf(device, kind)
    return p and sumOf(p.hours) or 0
end

-- The conversion work action, while it is the character's current action.
local function workAction()
    local a = currentAction()
    if a and a.Type == "ISTLGConversionWork" then return a end
    return nil
end

local GEN_MENU, CAR_MENU = "ContextMenu_TLG_ConvGenerator", "ContextMenu_TLG_ConvVehicle"
local function startText(conversion)
    return getText("ContextMenu_TLG_ConvBegin", getText("IGUI_TLG_Conversion_" .. conversion))
end

-- Generator through the workshop menu. The first "Work on it" is refused
-- because the wrench is put away; the second runs to Commissioned.
add({ name = "loop_convert_generator", timeout = 4000, fn = function(ctx, ticks)
    local g = LOOP.gen
    if not g then R:line("SKIP loop_convert_generator"); return true end
    if not ctx.t0 then
        player():teleportTo(g:getSquare():getX() + 1, g:getSquare():getY(), 0)
        -- Parts and tools for both conversions (the screwdriver came with crafting).
        give("Base.Wrench", 1); give("Base.Pliers", 1); give("Base.RubberHose", 3); give("Base.Screws", 10)
        give("Base.ElectricWire", 3); give("Base.EngineParts", 2)
        if countType("Base.Screwdriver") == 0 then give("Base.Screwdriver", 1) end
        R:line("OBS  LOOP.conversion_materials %s", loadText())
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 20 then return nil end
    if not ctx.phase then
        local ref = TLG.Authority.Resolver.refForObject(g, "generator")
        ctx.b = workshopClick("LOOP.gen_begin", GEN_MENU, startText("flex_generator"))
        ctx.d = workshopClick("LOOP.gen_deliver", GEN_MENU, getText("ContextMenu_TLG_ConvDeliver"))
        -- A bare report three hours later, without the work action: at most
        -- the 1 h worker timeout is credited and the assignment ends.
        H.clockOffset = H.clockOffset + 3
        local late = ask("LOOP.gen_late_report", "conversion.work", { device = ref })
        R:check("LOOP.late_report_credits_at_most_the_timeout", function()
            return late.ok == true and late.expired == true and late.released == true
                and math.abs((late.credited or -1) - 1) < 1e-9,
                string.format("credited=%s expired=%s released=%s", tostring(late.credited), tostring(late.expired),
                    tostring(late.released))
        end)
        -- The project now stands at "prepare", which needs the wrench.
        ctx.wrench = takeAway("Base.Wrench")
        ctx.dialogs0, ctx.hours0 = #H.dialogs.texts, hoursOf(g, "generator")
        workshopClick("LOOP.gen_work_without_wrench", GEN_MENU, getText("ContextMenu_TLG_ConvJoin"))
        ctx.phase, ctx.t1 = "refused", ticks
        return nil
    end
    if ctx.phase == "refused" then
        if ticks - ctx.t1 < 30 or (not TLGH.Steps.actionsIdle(player()) and ticks - ctx.t1 < 600) then return nil end
        local text = H.dialogs.texts[ctx.dialogs0 + 1]
        R:check("LOOP.work_refused_without_the_tool", function()
            return has(text, getText("IGUI_TLG_ConvReason_missing_tool")) and has(text, getItemNameFromFullType("Base.Wrench"))
                and TLGH.Steps.actionsIdle(player()) and math.abs(hoursOf(g, "generator") - ctx.hours0) < 1e-9,
                string.format("dialog=%s idle=%s hours %.4f->%.4f", tostring(text), tostring(TLGH.Steps.actionsIdle(player())),
                    ctx.hours0, hoursOf(g, "generator"))
        end)
        giveBack(ctx.wrench)
        ctx.dialogs1 = #H.dialogs.texts
        workshopClick("LOOP.gen_work", GEN_MENU, getText("ContextMenu_TLG_ConvJoin"))
        ctx.phase, ctx.t2 = "working", ticks
        return nil
    end
    local a = workAction()
    if a then
        H.clockOffset = H.clockOffset + CLOCK_PER_TICK
        ctx.reports = a.reports
    end
    local p = projectOf(g, "generator")
    local done = p ~= nil and p.state == "Commissioned" and TLGH.Steps.actionsIdle(player())
    if not done and ticks - ctx.t2 < 3000 then return nil end
    local prof, text = TLG.Integration.Generators.profile(g), H.dialogs.texts[ctx.dialogs1 + 1]
    R:check("LOOP.flex_generator_commissioned", function()
        return done and prof == "generator_si_flex" and math.abs(sumOf(p.credit) - 7.5) < 1e-6
            and has(text, getText("IGUI_TLG_ConvState_Commissioned")),
            string.format("begin=%s deliver=%s consumed=%s reports=%s state=%s credit=%.4f profile=%s dialog=%s",
                tostring(ctx.b.ok), tostring(ctx.d.ok), brief(ctx.d.consumed), tostring(ctx.reports), tostring(p and p.state),
                p and sumOf(p.credit) or -1, tostring(prof), tostring(text))
    end)
    closeDialogs()
    return true
end })

-- The car through the workshop menu, in three sessions. "Work on it" walks
-- to the engine area. Session 1: after two credited hours the character is
-- moved 12 tiles away and three hours pass. Session 2: at six hours the
-- screwdriver is put away and the next report blocks. Session 3 finishes.
add({ name = "loop_convert_car", timeout = 8000, fn = function(ctx, ticks)
    local v = LOOP.car
    if not v then R:line("SKIP loop_convert_car"); return true end
    local near = { x = math.floor(v:getX()) + 2, y = math.floor(v:getY()) }
    if not ctx.t0 then
        player():teleportTo(near.x, near.y, 0)
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 20 then return nil end
    if not ctx.phase then
        ctx.b = workshopClick("LOOP.car_begin", CAR_MENU, startText("flex_car_normal"))
        ctx.d = workshopClick("LOOP.car_deliver", CAR_MENU, getText("ContextMenu_TLG_ConvDeliver"))
        ctx.clickedAt = { x = player():getX(), y = player():getY() }
        workshopClick("LOOP.car_work_1", CAR_MENU, getText("ContextMenu_TLG_ConvJoin"))
        ctx.phase, ctx.t1 = "session1", ticks
        return nil
    end
    local a = workAction()
    if a then H.clockOffset = H.clockOffset + CLOCK_PER_TICK end
    if ctx.phase == "session1" then
        if a and not ctx.walk then
            local engine = v:getPartById("Engine")
            local dx, dy = player():getX() - ctx.clickedAt.x, player():getY() - ctx.clickedAt.y
            ctx.walk = { moved = math.sqrt(dx * dx + dy * dy), inArea = engine ~= nil and v:isInArea(engine:getArea(), player()) }
        end
        if a and hoursOf(v, "vehicle") >= 2 then
            ctx.action, ctx.hoursAtLeave = a, hoursOf(v, "vehicle")
            player():teleportTo(near.x - 12, near.y, 0)
            ctx.phase, ctx.t2 = "away", ticks
        elseif ticks - ctx.t1 > 2500 then
            R:check("LOOP.car_first_session", function()
                return false, string.format("no two hours of work: working=%s hours=%.4f walk=%s", tostring(a ~= nil),
                    hoursOf(v, "vehicle"), brief(ctx.walk))
            end)
            return true
        end
        return nil
    end
    if ctx.phase == "away" then
        -- The clock stands still while the action notices; then three hours
        -- pass away from the car and the character comes back.
        if ticks - ctx.t2 < 60 then return nil end
        ctx.away = { stopped = ctx.action.stopped == true, ended = ctx.action.ended == true,
            idle = TLGH.Steps.actionsIdle(player()) }
        H.clockOffset = H.clockOffset + 3
        player():teleportTo(near.x, near.y, 0)
        ctx.phase, ctx.t3 = "back", ticks
        return nil
    end
    if ctx.phase == "back" then
        if ticks - ctx.t3 < 20 then return nil end
        R:check("LOOP.work_walks_to_the_engine", function()
            return ctx.walk ~= nil and ctx.walk.inArea == true,
                string.format("in engine area when work began=%s moved %.2f tiles", tostring(ctx.walk and ctx.walk.inArea),
                    ctx.walk and ctx.walk.moved or -1)
        end)
        local hoursBack = hoursOf(v, "vehicle")
        R:check("LOOP.leaving_stops_the_work", function()
            return ctx.away.idle and (ctx.away.stopped or ctx.away.ended) and math.abs(hoursBack - ctx.hoursAtLeave) < 1e-9,
                string.format("stopped=%s ended=%s idle=%s hours at leave=%.4f after 3 h away=%.4f",
                    tostring(ctx.away.stopped), tostring(ctx.away.ended), tostring(ctx.away.idle), ctx.hoursAtLeave, hoursBack)
        end)
        workshopClick("LOOP.car_work_2", CAR_MENU, getText("ContextMenu_TLG_ConvJoin"))
        ctx.phase, ctx.t4 = "session2", ticks
        return nil
    end
    if ctx.phase == "session2" then
        if a and a.joined and not ctx.hoursAtRejoin then ctx.hoursAtRejoin = hoursOf(v, "vehicle") end
        if a and hoursOf(v, "vehicle") >= 6 then
            -- The install stage (hours 3-9) needs the screwdriver.
            ctx.screwdriver = takeAway("Base.Screwdriver")
            ctx.dialogsBlock, ctx.hoursAtBlock = #H.dialogs.texts, hoursOf(v, "vehicle")
            ctx.phase, ctx.t5 = "blocked", ticks
        elseif ticks - ctx.t4 > 2500 then
            R:check("LOOP.car_second_session", function() return false, "never reached six hours" end)
            return true
        end
        return nil
    end
    if ctx.phase == "blocked" then
        if not TLGH.Steps.actionsIdle(player()) and ticks - ctx.t5 < 600 then return nil end
        local text, hoursEnd = H.dialogs.texts[ctx.dialogsBlock + 1], hoursOf(v, "vehicle")
        -- An hour without the tool: nothing may accrue.
        H.clockOffset = H.clockOffset + 1
        R:check("LOOP.work_ends_on_a_block", function()
            return TLGH.Steps.actionsIdle(player()) and has(text, getText("IGUI_TLG_ConvReason_missing_tool"))
                and has(text, getItemNameFromFullType("Base.Screwdriver")) and math.abs(hoursEnd - ctx.hoursAtBlock) < 1e-9
                and math.abs(hoursOf(v, "vehicle") - hoursEnd) < 1e-9,
                string.format("dialog=%s hours at block=%.4f when it ended=%.4f an hour later=%.4f", tostring(text),
                    ctx.hoursAtBlock, hoursEnd, hoursOf(v, "vehicle"))
        end)
        giveBack(ctx.screwdriver)
        ctx.dialogsFinal = #H.dialogs.texts
        workshopClick("LOOP.car_work_3", CAR_MENU, getText("ContextMenu_TLG_ConvJoin"))
        ctx.phase, ctx.t6 = "session3", ticks
        return nil
    end
    local p = projectOf(v, "vehicle")
    local done = p ~= nil and p.state == "Commissioned" and TLGH.Steps.actionsIdle(player())
    if not done and ticks - ctx.t6 < 3000 then return nil end
    local prof, text = TLG.Integration.Vehicles.profile(v), H.dialogs.texts[ctx.dialogsFinal + 1]
    R:check("LOOP.flex_car_commissioned", function()
        return done and prof == "engine_si_flex" and math.abs(sumOf(p.credit) - 13) < 1e-6
            and ctx.hoursAtRejoin ~= nil and math.abs(ctx.hoursAtRejoin - ctx.hoursAtLeave) < 1e-9
            and has(text, getText("IGUI_TLG_ConvState_Commissioned")),
            string.format("begin=%s deliver=%s consumed=%s state=%s credit=%.4f hours at rejoin=%s profile=%s dialog=%s",
                tostring(ctx.b.ok), tostring(ctx.d.ok), brief(ctx.d.consumed), tostring(p and p.state),
                p and sumOf(p.credit) or -1, tostring(ctx.hoursAtRejoin), tostring(prof), tostring(text))
    end)
    closeDialogs()
    captureDialogs(false)
    return true
end })

add(actionStep("LOOP.flex_generator_pour", function(ctx)
    local g, can = LOOP.gen, LOOP.canGen
    if not (g and can) then return nil end
    player():setPrimaryHandItem(can)
    player():teleportTo(g:getSquare():getX() + 1, g:getSquare():getY(), 0)
    hopBegin(ctx, "LOOP.flex_generator_pour", "item", can, canAmount(can:getFluidContainer()), "generator", g,
        function() return g:getFuel() end)
    return ISTLGPourFuel:new(player(), can, TLG.Authority.Resolver.refForObject(g, "generator"), g, false,
        function(reply) ctx.reply = reply end)
end, function(ctx)
    R:check("LOOP.flex_generator_pour.accepted_without_confirmation", function()
        return ctx.reply ~= nil and ctx.reply.ok == true, tostring(ctx.reply and ctx.reply.reason)
    end)
    hopEnd(ctx, true)
end))

add(generatorGateStep("LOOP.flex_generator_start", function() return LOOP.gen end, false))
add(vehiclePourStep("LOOP.flex_car_pour", nil, false, true, function() return LOOP.car end, function() return LOOP.canCar end))
add(vehicleGateStep("LOOP.flex_car_start", function() return LOOP.car end, false, true))

add({ name = "tlg_ui", fn = function()
    local can = giveCan("Base.PetrolCan", { { Fluid.Petrol, 2.0 } })
    R:check("UI.fuel_context_menu_entry", function()
        local context = ISContextMenu.get(0, 100, 100)
        TLG.UI.FuelMenu.fill(0, context, { can })
        local opt = context:getOptionFromName(getText("ContextMenu_TLG_Fuel"))
        local sub = opt and opt.subOption and context:getSubMenu(opt.subOption)
        local n = sub and #sub.options or 0
        context:setVisible(false)
        return opt ~= nil and n > 0, string.format("root=%s suboptions=%d", tostring(opt ~= nil), n)
    end)
    local reply
    TLG.Net.request("sample", { target = { kind = "item", id = can:getID() }, method = "visual" }, function(r) reply = r end)
    R:check("UI.sample_request_round_trip", function()
        return reply ~= nil and reply.ok == true and reply.observation ~= nil,
            string.format("ok=%s reason=%s", tostring(reply and reply.ok), tostring(reply and reply.reason))
    end)
    pcall(function() ISContextMenu.get(0, 0, 0):setVisible(false) end)
    return true
end })

add({ name = "g02_world_container_and_expectations", fn = function()
    local eth = Fluid.Get("TLG_Ethanol")
    local base = H.pumps[1] or { x = START.x, y = START.y }
    local s = sq(base.x + 1, base.y - 2, 0)
    local canA = instanceItem("Base.JerryCan")
    local fcA = canA:getFluidContainer()
    fcA:Empty(); fcA:addFluid(Fluid.Petrol, 12.5); fcA:addFluid(eth, 3.25)
    canA:getModData().tlgProbe = { id = "CAN-A", deg = { gasoline = 1.25, ethanol = 0.5 }, nested = { k = "v" } }
    s:AddWorldInventoryItem(canA, 0.5, 0.5, 0, false)
    local machine = instanceItem("TLG.FermenterVessel")
    machine:getModData().tlgProbe = { id = "MACH-A", n = 4.25 }
    s:AddWorldInventoryItem(machine, 0.3, 0.3, 0, false)
    local canB, fcB = giveCan("Base.PetrolCan", { { Fluid.Petrol, 4.0 }, { eth, 1.0 } })
    canB:getModData().tlgProbe = { id = "CAN-B", deg = { gasoline = 2.0 } }
    -- A TLG-tracked can left on the ground (its record must still be found
    -- after reload, when the fluid may sit on the world object).
    local canT, fcT = giveCan("Base.PetrolCan", { { Fluid.Petrol, 5.0 } })
    local C = TLG.Integration.Containers
    C.writeSidecar(canT, "item", (C.read(canT, "item", true)))
    player():getInventory():Remove(canT)
    s:AddWorldInventoryItem(canT, 0.7, 0.7, 0, false)
    local lines = {
        "canA.x=" .. s:getX(), "canA.y=" .. s:getY(),
        "canA.fluids=" .. TLGH.fluidSummary(fcA),
        "canB.fluids=" .. TLGH.fluidSummary(fcB),
        "canT.fluids=" .. TLGH.fluidSummary(fcT),
        "canT.id=" .. tostring(canT:getModData().tlg and canT:getModData().tlg.id),
        "machine.type=" .. tostring(machine:getFullType()),
        "world=" .. tostring(getWorld():getWorld()),
        "hours=" .. string.format("%.4f", hours()),
    }
    if H.can1 then lines[#lines + 1] = "can1.side=" .. sidecar(H.can1:getModData()) end
    if H.vehicle and H.tank then
        lines[#lines + 1] = "veh.x=" .. math.floor(H.vehicle:getX())
        lines[#lines + 1] = "veh.y=" .. math.floor(H.vehicle:getY())
        lines[#lines + 1] = "veh.tank=" .. string.format("%.4f", H.tank:getContainerContentAmount())
        lines[#lines + 1] = "veh.side=" .. sidecar(H.tank:getModData())
    end
    if H.gen then
        lines[#lines + 1] = "gen.x=" .. H.genSquare.x
        lines[#lines + 1] = "gen.y=" .. H.genSquare.y
        lines[#lines + 1] = "gen.fuel=" .. string.format("%.4f", H.gen:getFuel())
        lines[#lines + 1] = "gen.side=" .. sidecar(H.gen:getModData())
    end
    if H.pump then
        lines[#lines + 1] = "pump.x=" .. H.pump.x
        lines[#lines + 1] = "pump.y=" .. H.pump.y
        lines[#lines + 1] = "pump.units=" .. H.pump.obj:getPipedFuelAmount()
        lines[#lines + 1] = "pump.side=" .. sidecar(H.pump.obj:getModData())
    end
    if LOOP.gen then
        lines[#lines + 1] = "loop.gen.x=" .. LOOP.gen:getSquare():getX()
        lines[#lines + 1] = "loop.gen.y=" .. LOOP.gen:getSquare():getY()
    end
    if LOOP.car then
        lines[#lines + 1] = "loop.car.x=" .. math.floor(LOOP.car:getX())
        lines[#lines + 1] = "loop.car.y=" .. math.floor(LOOP.car:getY())
    end
    if LOOP.items then
        lines[#lines + 1] = "loop.mach.x=" .. LOOP.x
        lines[#lines + 1] = "loop.mach.y=" .. LOOP.y
        for i, it in ipairs(LOOP.items) do
            local p = it:getModData().tlgProc
            lines[#lines + 1] = string.format("loop.mach.%d=%s:%s:%s", i, it:getFullType(), tostring(p and p.state),
                tostring(p and p.batches))
        end
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

local function worldItemWithProbe(x, y, id)
    local s = sq(x, y, 0)
    if not s then return nil, "square not loaded" end
    local wobjs = s:getWorldObjects()
    for i = 0, wobjs:size() - 1 do
        local it = wobjs:get(i):getItem()
        local md = it and it:getModData().tlgProbe
        if md and md.id == id then return it end
    end
    return nil, "not found among " .. wobjs:size()
end

addB({ name = "g08_reload_checks", fn = function()
    local e = H.expect
    R:check("G08.same_world", function() return tostring(getWorld():getWorld()) == e.world, tostring(getWorld():getWorld()) end)
    R:check("G08.world_item_fluids_and_moddata", function()
        local it, why = worldItemWithProbe(tonumber(e["canA.x"]), tonumber(e["canA.y"]), "CAN-A")
        if not it then return false, why end
        local md = it:getModData().tlgProbe
        -- On the ground the fluid may sit on the world object (run 4: the
        -- item's own container was nil after reload).
        local fc = it:getFluidContainerFromSelfOrWorldItem()
        local owner = fc and fc:getOwner()
        local fl = TLGH.fluidSummary(fc)
        return fl == e["canA.fluids"] and md.deg.gasoline == 1.25 and md.nested.k == "v",
            string.format("%s deg=%s itemOwnContainer=%s ownerIsWorldObject=%s", fl, tostring(md.deg.gasoline),
                tostring(it:getFluidContainer() ~= nil), tostring(owner ~= nil and instanceof(owner, "IsoWorldInventoryObject")))
    end)
    R:check("G08.ground_can_tlg_record_found", function()
        local s = sq(tonumber(e["canA.x"]), tonumber(e["canA.y"]), 0)
        local wobjs = s and s:getWorldObjects()
        for i = 0, (wobjs and wobjs:size() or 0) - 1 do
            local it = wobjs:get(i):getItem()
            local side = it and it:getModData().tlg
            if side and tostring(side.id) == e["canT.id"] then
                local C = TLG.Integration.Containers
                local fc = it:getFluidContainerFromSelfOrWorldItem()
                local owner, kind = C.ownerOf(fc)
                local rec, status = C.read(owner, kind, false)
                local fl = TLGH.fluidSummary(fc)
                return rec ~= nil and kind == "item" and tostring(rec.id) == e["canT.id"] and status == "ok"
                    and fl == e["canT.fluids"],
                    string.format("kind=%s status=%s id=%s fluids=%s", tostring(kind), tostring(status), tostring(rec and rec.id), fl)
            end
        end
        return false, "tracked can not found on the ground"
    end)
    R:check("G08.mod_machine_world_item_moddata", function()
        local it, why = worldItemWithProbe(tonumber(e["canA.x"]), tonumber(e["canA.y"]), "MACH-A")
        if not it then return false, why end
        return it:getFullType() == e["machine.type"] and it:getModData().tlgProbe.n == 4.25, it:getFullType()
    end)
    R:check("G08.inventory_item_fluids_and_moddata", function()
        local items = player():getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local md = it:getModData().tlgProbe
            if md and md.id == "CAN-B" then
                local fl = TLGH.fluidSummary(it:getFluidContainer())
                return fl == e["canB.fluids"], fl
            end
        end
        return false, "CAN-B not in inventory"
    end)
    if e["can1.side"] then
        R:check("G08.inventory_can_sidecar", function()
            local items = player():getInventory():getItems()
            for i = 0, items:size() - 1 do
                local s = sidecar(items:get(i):getModData())
                if s == e["can1.side"] then return true, s end
            end
            return false, "no inventory item with " .. e["can1.side"]
        end)
    end
    if e["veh.x"] then
        R:check("G08.vehicle_tank_sidecar_and_amount", function()
            -- Match by record id: the other vehicle's body can reach into the
            -- search window (run 5 picked vehicle 2, whose record was intact).
            local wantId = string.match(e["veh.side"] or "", "^id=(%S+)")
            local v
            for dx = -4, 4 do
                for dy = -4, 4 do
                    local s = sq(tonumber(e["veh.x"]) + dx, tonumber(e["veh.y"]) + dy, 0)
                    local c = s and s:getVehicleContainer()
                    local side = c and c:getPartById("GasTank") and c:getPartById("GasTank"):getModData().tlg
                    if side and tostring(side.id) == wantId then v = c end
                end
            end
            if not v then return false, "vehicle with tank record " .. tostring(wantId) .. " not found" end
            local part = v:getPartById("GasTank")
            local s = sidecar(part:getModData())
            local amount = string.format("%.4f", part:getContainerContentAmount())
            return s == e["veh.side"] and amount == e["veh.tank"], s .. " tank=" .. amount
        end)
    end
    if e["gen.x"] then
        R:check("G08.generator_sidecar_and_fuel", function()
            -- Both generators can share a square (run 5); match by record id.
            local wantId = string.match(e["gen.side"] or "", "^id=(%S+)")
            local g = findGenerator(tonumber(e["gen.x"]), tonumber(e["gen.y"]), 1, wantId)
            if not (g and g:getModData().tlg and tostring(g:getModData().tlg.id) == wantId) then
                return false, "generator with record " .. tostring(wantId) .. " not found"
            end
            local s = sidecar(g:getModData())
            local fuel = string.format("%.4f", g:getFuel())
            return s == e["gen.side"] and fuel == e["gen.fuel"], s .. " fuel=" .. fuel
        end)
    end
    if e["pump.x"] then
        R:check("G08.pump_sidecar_and_units", function()
            local s = sq(tonumber(e["pump.x"]), tonumber(e["pump.y"]), 0)
            local objs = s:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if TLG.Integration.Stations.isPump(o) then
                    local side = sidecar(o:getModData())
                    return side == e["pump.side"] and tostring(o:getPipedFuelAmount()) == e["pump.units"],
                        side .. " units=" .. tostring(o:getPipedFuelAmount())
                end
            end
            return false, "pump not found"
        end)
    end
    if e["loop.gen.x"] then
        R:check("G08.flex_generator_conversion_persists", function()
            local g = findGenerator(tonumber(e["loop.gen.x"]), tonumber(e["loop.gen.y"]), 0, nil)
            if not g then return false, "no generator object" end
            local p = g:getModData().tlgConv
            local prof = TLG.Integration.Generators.profile(g)
            return prof == "generator_si_flex" and p ~= nil and p.state == "Commissioned",
                string.format("profile=%s state=%s fuel=%.4f", tostring(prof), tostring(p and p.state), g:getFuel())
        end)
    end
    if e["loop.car.x"] then
        R:check("G08.flex_car_conversion_persists", function()
            for dx = -4, 4 do
                for dy = -4, 4 do
                    local s = sq(tonumber(e["loop.car.x"]) + dx, tonumber(e["loop.car.y"]) + dy, 0)
                    local v = s and s:getVehicleContainer()
                    local engine = v and v:getPartById("Engine")
                    local p = engine and engine:getModData().tlgConv
                    if p and p.conversion == "flex_car_normal" then
                        local prof = TLG.Integration.Vehicles.profile(v)
                        return prof == "engine_si_flex" and p.state == "Commissioned",
                            string.format("profile=%s state=%s", tostring(prof), tostring(p.state))
                    end
                end
            end
            return false, "no vehicle with a flex conversion near " .. e["loop.car.x"] .. "," .. e["loop.car.y"]
        end)
    end
    if e["loop.mach.x"] then
        R:check("G08.machine_records_persist", function()
            local got, allOk = {}, true
            for i = 1, 3 do
                local want = e["loop.mach." .. i]
                local fullType = string.match(want or "", "^([^:]+):")
                local s = sq(tonumber(e["loop.mach.x"]) + i - 1, tonumber(e["loop.mach.y"]), 0)
                local found = "missing"
                local wobjs = s and s:getWorldObjects()
                for j = 0, (wobjs and wobjs:size() or 0) - 1 do
                    local it = wobjs:get(j):getItem()
                    if it and it:getFullType() == fullType then
                        local p = it:getModData().tlgProc
                        found = string.format("%s:%s:%s", it:getFullType(), tostring(p and p.state), tostring(p and p.batches))
                    end
                end
                got[#got + 1] = found
                if found ~= want then allOk = false end
            end
            return allOk, table.concat(got, " ")
        end)
    end
    R:check("G08.global_moddata_sp", function()
        local g = ModData.get("TLGHarnessSP")
        return g ~= nil and g.marker == "phaseA" and g.nested.a == 1.5, tostring(g and g.marker)
    end)
    R:check("G08.tlg_world_record", function()
        local w = ModData.get("TLG_World")
        return w ~= nil and w.v ~= nil, tostring(w and w.v)
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
-- Real game clock (request "sp-rt"): the ethanol loop with time passing on
-- the game clock and no mod-clock offset. Machines wait at a debug
-- multiplier (the debug panel's Game Speed slider uses the same call,
-- ISGameDebugPanel.lua:42); conversion work runs at vanilla's fastest speed,
-- x40 (SpeedControlsHandler.lua:37); walking and teleports at x1. The
-- machines' chunk is unloaded for 24 game hours during fermentation (G12).
------------------------------------------------------------------------------
local stepsRT = {}
local RT = { x = LOOP.x, y = LOOP.y, waitSpeed = 100, workSpeed = 40, away = 400,
    genAt = { x = LOOP.x + 5, y = LOOP.y }, carAt = { x = 10649, y = 10625 } }

function RT.add(step)
    stepsRT[#stepsRT + 1] = step
    return step
end

function RT.speed(m)
    pcall(function() getGameTime():setMultiplier(m) end)
end

function RT.trueSpeed()
    local m = "?"
    pcall(function() m = string.format("%.1f", getGameTime():getTrueMultiplier()) end)
    return m
end

-- 150 game hours idle: needs are reset so the character neither starves
-- nor falls asleep (it is invulnerable and invisible meanwhile).
function RT.keepFit()
    local st = player():getStats()
    for _, k in ipairs({ "HUNGER", "THIRST", "FATIGUE", "BOREDOM", "UNHAPPINESS", "STRESS" }) do
        pcall(function() st:reset(CharacterStat[k]) end)
    end
end

function RT.temp()
    local t
    pcall(function() t = getClimateManager():getTemperature() end)
    return t
end

function RT.statusOf(item)
    local reply
    TLG.Net.request("machine.status", { target = TLG.Integration.Machines.refFor(item) }, function(r) reply = r end)
    return reply or {}
end

-- Work done on the current batch, in stage hours (rate-weighted).
function RT.doneHours(item)
    local p = item and item:getModData().tlgProc
    if not (p and p.recipe) then return 0 end
    local done = 0
    for i, st in ipairs(p.recipe.params.stages) do
        if i < p.stage then done = done + (st.hours or 0) elseif i == p.stage then done = done + (p.stageDone or 0) end
    end
    return done
end

-- After a chunk reload every Lua reference is stale: find the machines again.
function RT.refind()
    for i, t in ipairs({ "TLG.FermenterVessel", "TLG.RefluxStill", "TLG.DryingColumn" }) do
        local s = sq(RT.x + i - 1, RT.y, 0)
        local objs = s and s:getWorldObjects()
        for j = 0, (objs and objs:size() or 0) - 1 do
            local it = objs:get(j):getItem()
            if it and it:getFullType() == t then RT.items[i] = it end
        end
    end
    RT.fermenter, RT.still, RT.dryer = RT.items[1], RT.items[2], RT.items[3]
end

function RT.skip(name)
    if RT.abort then R:line("SKIP %s: %s", name, RT.abort); return true end
    return false
end

RT.waitWorld = RT.add({ name = "rt_wait_world", timeout = 3000, fn = function(ctx, ticks)
    if player() and ticks > 120 then
        R:line("worldName=%s hours=%.4f DayLength=%s", tostring(getWorld():getWorld()), hours(),
            tostring(SandboxVars and SandboxVars.DayLength))
        return true
    end
end })

RT.setup = RT.add({ name = "rt_setup", timeout = 3000, fn = function(ctx, ticks)
    if not ctx.t0 then
        local p = player()
        p:setGodMod(true)
        p:setInvisible(true)
        pcall(function() p:setUnlimitedCarry(true) end)
        p:setPerkLevelDebug(Perks.Mechanics, 4)
        p:setPerkLevelDebug(Perks.Electricity, 2)
        p:getKnownRecipes():add("Generator")
        p:getKnownRecipes():add("Basic Mechanics")
        captureDialogs(true)
        instrumentWorkAction()
        p:teleportTo(RT.x + 1, RT.y + 1, 0)
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 30 then return nil end
    if not ctx.placed then
        RT.items = {}
        for i, t in ipairs({ "TLG.FermenterVessel", "TLG.RefluxStill", "TLG.DryingColumn" }) do
            local it = instanceItem(t)
            sq(RT.x + i - 1, RT.y, 0):AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            RT.items[i] = it
        end
        RT.fermenter, RT.still, RT.dryer = RT.items[1], RT.items[2], RT.items[3]
        give("Base.Sugar", 6); give("Base.Yeast", 1); give("Base.Log", 2); give("Base.Quicklime", 2)
        for _ = 1, 3 do
            local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
            fc:Empty()
            fc:addFluid(Fluid.Water, 10)
        end
        RT.h0 = hours()
        -- Measure the speed-up before relying on it.
        RT.speed(RT.waitSpeed)
        ctx.placed, ctx.h0, ctx.tick0 = true, hours(), ticks
        return nil
    end
    RT.speed(RT.waitSpeed)
    if ticks - ctx.tick0 < 300 then return nil end
    local gh, trueSpeed = hours() - ctx.h0, RT.trueSpeed()
    RT.speed(1)
    R:line("OBS  RT.speed multiplier=%d true=%s game hours in 300 ticks=%.4f (about 0.02 at x1) %s", RT.waitSpeed,
        trueSpeed, gh, loadText())
    R:check("RT.game_clock_runs_fast", function() return gh >= 0.2, string.format("%.4f game h in 300 ticks", gh) end)
    if gh < 0.2 then RT.abort = "the game clock did not speed up" end
    return true
end })

-- Fermentation on the game clock, with a 24 game hour trip far enough away
-- for the machines' chunk to unload.
RT.add({ name = "rt_ferment", timeout = 120000, fn = function(ctx, ticks)
    if not ctx.t0 and RT.skip("rt_ferment") then return true end
    if not ctx.t0 then
        local r = machineClick("RT.ferment", RT.fermenter, "ContextMenu_TLG_LoadFerment")
        R:check("RT.ferment_loaded", function()
            return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6 and math.abs((r.waterL or 0) - 30) < 1e-6,
                string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
        end)
        ctx.t0, ctx.h0, ctx.next, ctx.tmin, ctx.tmax = ticks, hours(), hours() + 1, 99, -99
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    if not ctx.trip and hours() - ctx.h0 >= 12 then
        RT.statusOf(RT.fermenter)
        ctx.trip = { before = RT.doneHours(RT.fermenter), from = hours(), tick = ticks }
        RT.speed(1)
        player():teleportTo(RT.x, RT.y - RT.away, 0)
        return nil
    end
    if ctx.trip and not ctx.trip.back then
        if ticks - ctx.trip.tick < 120 then RT.speed(1); return nil end
        if ctx.trip.awayFrom == nil then
            ctx.trip.awayFrom, ctx.trip.landed = hours(), player():getSquare() ~= nil
        end
        if sq(RT.x, RT.y, 0) == nil then ctx.trip.unloaded = true end
        RT.speed(RT.waitSpeed)
        if hours() - ctx.trip.awayFrom < 24 then return nil end
        RT.speed(1)
        player():teleportTo(RT.x + 1, RT.y + 1, 0)
        ctx.trip.back, ctx.trip.backTick = hours(), ticks
        return nil
    end
    if ctx.trip and not ctx.trip.checked then
        if ticks - ctx.trip.backTick < 120 then RT.speed(1); return nil end
        RT.refind()
        local s = RT.statusOf(RT.fermenter)
        -- Between the two status reads (run 13 measured to the return
        -- teleport instead and missed the 120 settling ticks).
        local after, gone = RT.doneHours(RT.fermenter), hours() - ctx.trip.from
        R:line("OBS  RT.trip landed=%s machines' square unloaded=%s gone %.2f game h, done %.2f -> %.2f h, state=%s pause=%s",
            tostring(ctx.trip.landed), tostring(ctx.trip.unloaded == true), gone, ctx.trip.before, after,
            tostring(s.state), tostring(s.pause))
        if ctx.trip.unloaded then
            R:check("RT.unloaded_machine_catches_up", function()
                local d = after - ctx.trip.before
                return d > 0 and d <= gone + 1e-6, string.format("progress %.2f h over %.2f game h away", d, gone)
            end)
        else
            R:line("OBS  RT.unloaded_machine_catches_up INCONCLUSIVE: the machines' square stayed loaded")
        end
        ctx.trip.checked = true
        return nil
    end
    RT.speed(RT.waitSpeed)
    local t = RT.temp()
    if t then ctx.tmin, ctx.tmax = math.min(ctx.tmin, t), math.max(ctx.tmax, t) end
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 1
    local s = RT.statusOf(RT.fermenter)
    local elapsed = hours() - ctx.h0
    if math.floor(elapsed) % 12 == 0 then
        R:line("OBS  RT.fermenting %.0f h state=%s pause=%s done=%.2f h temp=%.1f", elapsed, tostring(s.state),
            tostring(s.pause), RT.doneHours(RT.fermenter), t or -99)
    end
    if s.ok ~= false and s.state ~= "OutputReady" and s.state ~= "Faulted" and elapsed < 300 then return nil end
    RT.speed(1)
    local eth = (s.outputs or {}).ethanol or 0
    R:check("RT.ferment_completed_on_game_clock", function()
        return s.state == "OutputReady" and elapsed >= 96.5 and eth >= 3.2 and eth <= 3.7,
            string.format("after %.1f game h (97 h at full rate), temperature %.1f..%.1f C, state=%s outputs=%s", elapsed,
                ctx.tmin, ctx.tmax, tostring(s.state), brief(s.outputs))
    end)
    if s.state ~= "OutputReady" then RT.abort = "fermentation did not finish" end
    return true
end })

RT.add({ name = "rt_distill", timeout = 30000, fn = function(ctx, ticks)
    if not ctx.t0 and RT.skip("rt_distill") then return true end
    if not ctx.t0 then
        local fuel = machineClick("RT.firebox", RT.still, "ContextMenu_TLG_AddFirewood")
        local wash = machineClick("RT.load_wash", RT.still, "ContextMenu_TLG_LoadWash")
        R:check("RT.wash_loaded", function()
            return fuel.ok == true and wash.ok == true, string.format("firebox=%s wash=%s", tostring(fuel.firebox), tostring(wash.washL))
        end)
        ctx.t0, ctx.h0, ctx.next = ticks, hours(), hours() + 0.25
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 0.25
    local s = RT.statusOf(RT.still)
    local elapsed = hours() - ctx.h0
    if s.ok ~= false and s.state ~= "OutputReady" and s.state ~= "Faulted" and elapsed < 24 then return nil end
    RT.speed(1)
    local eth, water = (s.outputs or {}).ethanol or 0, (s.outputs or {}).water or 0
    R:check("RT.distill_completed_on_game_clock", function()
        return s.state == "OutputReady" and eth > 2.5 and water / math.max(1e-9, eth + water) < 0.07 and elapsed >= 3.5,
            string.format("after %.2f game h (about 3.8 h expected) ethanol=%.4f water=%.4f state=%s", elapsed, eth, water,
                tostring(s.state))
    end)
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    machineClick("RT.collect_still", RT.still, "ContextMenu_TLG_CollectEthanol")
    RT.can1 = grownCan(before)
    local v = RT.can1 and tlgView("item", RT.can1)
    R:check("RT.hydrous_ethanol_bottled", function()
        local q = v and v.q or {}
        return v ~= nil and math.abs((q.ethanol or 0) - eth) < 1e-3 and math.abs((q.water or 0) - water) < 1e-3,
            viewText(v, "can")
    end)
    if not RT.can1 then RT.abort = "no hydrous ethanol" end
    return true
end })

RT.add({ name = "rt_dry", timeout = 40000, fn = function(ctx, ticks)
    if not ctx.t0 and RT.skip("rt_dry") then return true end
    if not ctx.t0 then
        local v = tlgView("item", RT.can1)
        ctx.deg0 = v and v.deg.ethanol or 0
        local d = machineClick("RT.load_dry", RT.dryer, "ContextMenu_TLG_LoadDry")
        R:check("RT.dry_loaded", function() return d.ok == true, string.format("lime=%s", tostring(d.limeKg)) end)
        ctx.t0, ctx.h0, ctx.next = ticks, hours(), hours() + 0.5
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 0.5
    local s = RT.statusOf(RT.dryer)
    local elapsed = hours() - ctx.h0
    if s.ok ~= false and s.state ~= "OutputReady" and s.state ~= "Faulted" and elapsed < 48 then return nil end
    RT.speed(1)
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    machineClick("RT.collect_dry", RT.dryer, "ContextMenu_TLG_CollectEthanol")
    local can = grownCan(before)
    local v = can and tlgView("item", can)
    R:check("RT.dried_on_game_clock", function()
        local q = v and v.q or {}
        local e, w = q.ethanol or 0, q.water or 0
        return s.state == "OutputReady" and elapsed >= 11.5 and e > 2.5 and w <= e * 0.005 + 1e-4
            and math.abs((v.deg.ethanol or 0) - ctx.deg0) < 0.01,
            string.format("after %.2f game h (12 h): %s; degradation before drying %.4f", elapsed, viewText(v, "can"), ctx.deg0)
    end)
    return true
end })

-- Conversion work on the game clock: x40 while the work action runs, x1
-- while walking. A conversion that ends unfinished fails at once.
function RT.convert(name, kind, menu, conversion, hoursNeeded, getDevice)
    return { name = name, timeout = 60000, fn = function(ctx, ticks)
        if not ctx.t0 and RT.skip(name) then return true end
        local device = getDevice(ctx, ticks)
        if not ctx.t0 then ctx.t0 = ticks; return nil end
        if ticks - ctx.t0 < 60 then RT.speed(1); return nil end
        if not ctx.started then
            ctx.b = workshopClick(name .. ".begin", menu, startText(conversion))
            ctx.d = workshopClick(name .. ".deliver", menu, getText("ContextMenu_TLG_ConvDeliver"))
            ctx.dialogs = #H.dialogs.texts
            workshopClick(name .. ".work", menu, getText("ContextMenu_TLG_ConvJoin"))
            ctx.started, ctx.h0, ctx.t1 = true, hours(), ticks
            return nil
        end
        if ticks % 30 == 0 then RT.keepFit() end
        local a = workAction()
        if a then
            RT.speed(RT.workSpeed)
            if not ctx.measured and ticks - ctx.t1 > 300 then
                ctx.measured = true
                R:line("OBS  %s working at multiplier %d, true %s", name, RT.workSpeed, RT.trueSpeed())
            end
        else
            RT.speed(1)
        end
        local p = projectOf(device, kind)
        local done = p ~= nil and p.state == "Commissioned" and TLGH.Steps.actionsIdle(player())
        local stopped = not done and a == nil and ticks - ctx.t1 > 600 and TLGH.Steps.actionsIdle(player())
        if not done and not stopped and ticks - ctx.t1 < 55000 then return nil end
        RT.speed(1)
        local elapsed, text = hours() - ctx.h0, H.dialogs.texts[ctx.dialogs + 1]
        R:check(name .. "_on_game_clock", function()
            return done and math.abs(sumOf(p.credit) - hoursNeeded) < 1e-6 and elapsed >= hoursNeeded - 1e-6
                and has(text, getText("IGUI_TLG_ConvState_Commissioned")),
                string.format("%.2f game h from the click (%.1f h of work) credit=%.4f state=%s dialog=%s", elapsed,
                    hoursNeeded, p and sumOf(p.credit) or -1, tostring(p and p.state), tostring(text))
        end)
        return true
    end }
end

RT.add(RT.convert("RT.generator", "generator", GEN_MENU, "flex_generator", 7.5, function(ctx)
    if not RT.generator then
        RT.generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), sq(RT.genAt.x, RT.genAt.y, 0))
        RT.generator:setFuel(0)
        RT.generator:getModData().tlg = nil
        give("Base.Screwdriver", 1); give("Base.Wrench", 1); give("Base.Pliers", 1); give("Base.RubberHose", 3)
        give("Base.Screws", 10); give("Base.ElectricWire", 3); give("Base.EngineParts", 2)
        player():teleportTo(RT.genAt.x + 1, RT.genAt.y, 0)
    end
    return RT.generator
end))

RT.add(RT.convert("RT.car", "vehicle", CAR_MENU, "flex_car_normal", 13, function(ctx, ticks)
    if not RT.car then
        RT.car = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, sq(RT.carAt.x, RT.carAt.y, 0))
        pcall(function() RT.car:repair() end)
        player():teleportTo(RT.carAt.x + 2, RT.carAt.y, 0)
    end
    -- Emptied once the vehicle has settled (as in loop_setup), before work.
    if ctx.t0 and not ctx.emptied and ticks - ctx.t0 >= 40 then
        local tank = RT.car:getPartById("GasTank")
        tank:setContainerContentAmount(0)
        tank:getModData().tlg = nil
        RT.car:transmitPartModData(tank)
        ctx.emptied = true
    end
    return RT.car
end))

RT.finish = RT.add({ name = "rt_finish", timeout = 600, fn = function(ctx, ticks)
    if not ctx.done then
        RT.speed(1)
        closeDialogs()
        captureDialogs(false)
        R:line("OBS  RT.summary game hours %.2f -> %.2f", RT.h0 or -1, hours())
        TLGH.writeFile("TLG_harness_request.txt", { "done" })
        R:finish(true)
        ctx.done = true
        return nil
    end
    if ticks == 60 then getCore():quitToDesktop() end
    return nil
end })

------------------------------------------------------------------------------
-- Winter (request "sp-rtw"): where the machines stand (D-021). From 15
-- January with the grid off, three fermenters within reach of one spot are
-- loaded in the same hour: outdoors, in a room, and in a room on a tile
-- warmed by a heat source added from Lua (IsoHeatSource, radius 1: that tile
-- only; vanilla's fires, fireplaces and barbecues register the same kind,
-- BC). Every game hour the harness reads the game's air at the three tiles:
-- the room tile must match the room formula derived from the bytecode
-- (Climate.roomAir) and the outdoor tile the air temperature. Before every
-- status read, the readings the mod filed must equal the harness's own;
-- after it, the day temperature the status reports must be the mean of the
-- harness's readings with the site's unheated value for hours without one,
-- and the work since the last read must follow the stage rules of
-- ethanol_ferment (full rate 18-32 C, 0.4 between 8 and 18 C, paused below
-- 8 C, spoiled after 72 h paused) fed by that temperature. A 12 game hour
-- trip on day 2 unloads the tiles: nothing is filed meanwhile, and the
-- readings resume on return.
------------------------------------------------------------------------------
function RT.fermentRate(c)
    if c < 8 or c > 38 then return 0 end
    if c < 18 or c > 32 then return 0.4 end
    return 1
end

-- Game calendar day (getMonth/getDay are 0-based).
function RT.dayKey()
    local gt = getGameTime()
    return string.format("%02d-%02d", gt:getMonth() + 1, gt:getDay() + 1)
end

-- tag prefixes the checks; warm is the machine that must never pause on a
-- day read throughout; home (set once found) is where the character stands.
RT.W = { names = { "outdoors", "room", "heated" }, tripAt = 30, tripHours = 12, heatC = 35, tag = "RTW", warm = 3 }

function RT.W.free(s)
    if s == nil then return false end
    local ok, r = pcall(function() return s:getFloor() ~= nil and s:isFree(false) end)
    return ok and r == true
end

function RT.W.inRoom(s)
    local ok, r = pcall(function() return s:isInARoom() end)
    return ok and r == true
end

-- A free room tile with a free room neighbour and a free outdoor neighbour,
-- searched outwards from (x0, y0): all three are within the authority's 2.5
-- tiles of the middle one, where the character stands.
function RT.W.findSpots(x0, y0)
    local W = RT.W
    for r = 1, 80 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local s = sq(x0 + dx, y0 + dy, 0)
                    if W.free(s) and W.inRoom(s) then
                        local room, out
                        for ox = -1, 1 do
                            for oy = -1, 1 do
                                local n = (ox ~= 0 or oy ~= 0) and sq(s:getX() + ox, s:getY() + oy, 0) or nil
                                if W.free(n) then
                                    if W.inRoom(n) then room = room or n else out = out or n end
                                end
                            end
                        end
                        if room and out then return { out, s, room } end
                    end
                end
            end
        end
    end
    return nil
end

-- The heat source on the third tile (again after a reload: a Lua heat source
-- is not saved, and IsoCell.updateHeatSources drops it once out of bounds).
function RT.W.heat()
    local W = RT.W
    local h = W.spots[3]
    if W.hs then pcall(function() getCell():removeHeatSource(W.hs) end) end
    W.hs = nil
    return pcall(function()
        W.hs = IsoHeatSource.new(h.x, h.y, 0, 1, W.heatC)
        getCell():addHeatSource(W.hs)
    end)
end

function RT.W.air(i)
    local p = RT.W.spots[i]
    local s = sq(p.x, p.y, 0)
    if s == nil then return nil end
    local ok, t = pcall(function() return getClimateManager():getAirTemperatureForSquare(s) end)
    return ok and t or nil
end

-- The fermenter standing on (x, y), if any.
local function fermenterOn(x, y)
    local s = sq(x, y, 0)
    local objs = s and s:getWorldObjects()
    for j = 0, (objs and objs:size() or 0) - 1 do
        local it = objs:get(j):getItem()
        if it and it:getFullType() == "TLG.FermenterVessel" then return it end
    end
    return nil
end

function RT.W.refind()
    local W = RT.W
    for i, p in ipairs(W.spots) do W.items[i] = fermenterOn(p.x, p.y) or W.items[i] end
end

-- Back from the trip: the Lua heat source again.
function RT.W.onReturn()
    return "heat source again=" .. tostring(RT.W.heat())
end

-- Every game hour: the game's air at the three tiles, filed by hour like the
-- mod files its readings, and the room formula checked against the game.
function RT.W.onHour()
    local W = RT.W
    if not W.active then return end
    local slot = math.floor(hours() - 0.5)
    local cm = getClimateManager()
    local t = cm:getTemperature()
    local dl, power
    pcall(function() dl = cm:getClimateValuesCopy():getDayLightLagged() end)
    pcall(function() power = getWorld():isHydroPowerOn() end)
    for i = 1, 3 do
        local air = W.air(i)
        if air == nil then W.unloaded[slot] = true else W.readings[i][slot] = air end
    end
    local room, out = W.readings[2][slot], W.readings[1][slot]
    if room and type(dl) == "number" then
        local f = TLG.Domain.Climate.roomAir(t, false, dl, power == true)
        W.formula.n = W.formula.n + 1
        if math.abs(f - room) >= W.formula.worst then
            W.formula.worst = math.abs(f - room)
            W.formula.where = string.format("air %.3f daylight %.3f power %s: formula %.4f, game %.4f", t, dl,
                tostring(power), f, room)
        end
    end
    if out then
        W.outside.n = W.outside.n + 1
        W.outside.worst = math.max(W.outside.worst, math.abs(out - t))
    end
end

RT.sitesSetup = { name = "rtw_sites", timeout = 3000, fn = function(ctx, ticks)
    local W = RT.W
    if not ctx.t0 and RT.skip("rtw_sites") then return true end
    if not ctx.t0 then
        local here = player():getSquare()
        local spots = W.findSpots(here:getX(), here:getY())
        if spots == nil then
            RT.abort = "no free room tile with a room and an outdoor neighbour nearby"
            R:line("OBS  RTW.spots none found")
            return true
        end
        W.spots, W.items, W.readings, W.unloaded = {}, {}, { {}, {}, {} }, {}
        W.formula, W.outside = { n = 0, worst = 0, where = "none" }, { n = 0, worst = 0 }
        for i, s in ipairs(spots) do
            W.spots[i] = { x = s:getX(), y = s:getY() }
            local it = instanceItem("TLG.FermenterVessel")
            s:AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            W.items[i] = it
        end
        W.home = W.spots[2]
        local ok, err = W.heat()
        player():setPosition(W.spots[2].x + 0.5, W.spots[2].y + 0.5, 0)
        local power
        pcall(function() power = getWorld():isHydroPowerOn() end)
        R:line("OBS  RTW.spots outdoors %d,%d room %d,%d heated %d,%d; heat source %d C added=%s %s; grid power=%s",
            W.spots[1].x, W.spots[1].y, W.spots[2].x, W.spots[2].y, W.spots[3].x, W.spots[3].y, W.heatC, tostring(ok),
            tostring(err or ""), tostring(power))
        R:check("RTW.grid_is_off", function() return power == false, "isHydroPowerOn=" .. tostring(power) end)
        if not W.hooked then
            Events.EveryHours.Add(RT.W.onHour)
            W.hooked = true
        end
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 60 then return nil end
    local seen = {}
    for i, p in ipairs(W.spots) do seen[i] = TLG.Integration.Machines.siteOf(sq(p.x, p.y, 0)).room end
    R:check("RTW.sites_seen", function()
        return seen[1] == false and seen[2] == true and seen[3] == true,
            string.format("in a room: outdoors=%s room=%s heated=%s", tostring(seen[1]), tostring(seen[2]), tostring(seen[3]))
    end)
    return true
end }

-- The helpers below serve the winter and the fireplace scenario alike: S is
-- RT.W or RT.F (items, readings and names per machine, unloaded hours).

-- Compares the readings the mod filed for machine i since the last
-- comparison with the harness's own (before the status read, which drops
-- the previous day's).
local function compareFiled(S, m, i, item)
    local p = item and item:getModData().tlgProc
    local running = p and (p.state == "Processing" or p.state == "Paused")
    for _, s in ipairs(TLG.Tables.sortedKeys(S.readings[i])) do
        if s > m.compared then
            m.compared = s
            if running then
                local filed = p.temps and p.temps[s]
                local diff = filed and math.abs(filed - S.readings[i][s]) or 999
                m.filed.n = m.filed.n + 1
                if s >= (S.resumeFrom or math.huge) and filed then m.afterTrip = m.afterTrip + 1 end
                if diff >= m.filed.worst then
                    m.filed.worst = diff
                    m.filed.where = string.format("hour %d: filed %s, game %.4f", s, tostring(filed), S.readings[i][s])
                end
            end
        end
    end
end

-- Compares the fire notes the mod took for machine i (D-022) since the last
-- comparison with the harness's own, where the scenario takes them.
local function compareNotes(S, m, i, item)
    local p = item and item:getModData().tlgProc
    local mine = S.fires and S.fires[i]
    if not (p and mine) then return end
    for _, h in ipairs(TLG.Tables.sortedKeys(mine)) do
        if h > m.notesCompared then
            m.notesCompared = h
            local a, b = mine[h], p.fires and p.fires[h]
            local same
            if a == false then
                same = b == false
            else
                same = type(b) == "table" and b.f == a.f and b.x == a.x and b.y == a.y and b.r == a.r and b.c == a.c
                    and b.rad == nil and math.abs(b.t - a.t) < 1e-6
            end
            m.notes.n = m.notes.n + 1
            if a then m.notes.fire = m.notes.fire + 1 end
            if not same then
                m.notes.off = m.notes.off + 1
                m.notes.where = m.notes.where or string.format("hour %d: harness %s, mod %s", h, brief(a), brief(b))
            end
        end
    end
end

-- Whether any hour of `day` went unread because the tiles were unloaded.
local function unloadedOn(S, env, day)
    for s in pairs(S.unloaded) do
        if env:dayIndex(s + 0.5) == day then return true end
    end
    return false
end

-- One status read of machine i: the reported day temperature against the
-- harness's readings, the work against the stage rule fed by it.
local function readMachine(S, ctx, i, env, now, day)
    local m, item = ctx.m[i], S.items[i]
    compareFiled(S, m, i, item)
    compareNotes(S, m, i, item)
    local s = RT.statusOf(item)
    local done = RT.doneHours(item)
    local p = m.prev
    local dt, dd = now - p.h, done - p.done
    local running = s.state == "Processing" or s.state == "Paused"
    local rec = item:getModData().tlgProc
    if running and type(s.siteC) == "number" and rec and rec.site then
        local want = env:siteDayMean(day, { room = rec.site.room, z = rec.site.z, temps = S.readings[i],
            fires = S.fires and S.fires[i], from = rec.startedAt }, now)
        m.mean.n = m.mean.n + 1
        if math.abs(want - s.siteC) >= m.mean.worst then
            m.mean.worst = math.abs(want - s.siteC)
            m.mean.where = string.format("%s: status %.4f, readings %.4f", RT.dayKey(), s.siteC, want)
        end
    end
    if p.day == day and p.stage == "ferment" and s.stage == "ferment" and running and type(s.siteC) == "number" then
        local rate = RT.fermentRate(s.siteC)
        m.rule.n = m.rule.n + 1
        if math.abs(dd - rate * dt) >= m.rule.worst then
            m.rule.worst = math.abs(dd - rate * dt)
            m.rule.where = string.format("%s, %.1f h in at %.2f C: did %.4f h, rule %.4f h", RT.dayKey(), now - ctx.h0,
                s.siteC, dd, rate * dt)
        end
    end
    local d = m.days[day]
    if not d then
        d = { label = RT.dayKey(), work = 0, paused = 0, siteC = nil }
        m.days[day] = d
    end
    d.work = d.work + math.max(0, dd)
    if s.state == "Paused" then d.paused = d.paused + dt end
    if type(s.siteC) == "number" then d.siteC = s.siteC end
    if s.state == "Paused" then m.pausedTally = m.pausedTally + dt end
    -- Run 17: the warmed machine paused after every midnight (no reading yet
    -- for the new day). On days read throughout it must not pause.
    if i == S.warm and s.state == "Paused" and not unloadedOn(S, env, day) then
        m.readPauses = (m.readPauses or 0) + 1
        m.readPauseAt = m.readPauseAt or string.format("%s, %.1f h in: %s", RT.dayKey(), now - ctx.h0, tostring(s.pause))
    end
    if running and s.stage == "ferment" and not m.dialog then
        local before = #H.dialogs.texts
        machineClick(S.tag .. ".status_" .. S.names[i], item, "ContextMenu_TLG_MachineStatus")
        m.dialog = H.dialogs.texts[before + 1] or "none"
        closeDialogs()
    end
    m.prev = { h = now, done = done, day = day, stage = s.stage }
    m.last = s
end

-- The 12 game hour trip: true while it is under way. S.onLeave (optional)
-- runs before the character leaves, S.onReturn once it is back and the
-- machines are found again; it returns a note for the log.
local function tripStep(S, ctx, ticks)
    if not ctx.trip then
        if hours() - ctx.h0 < S.tripAt then return false end
        ctx.trip = { from = hours(), tick = ticks }
        if S.onLeave then S.onLeave(ctx) end
        RT.speed(1)
        player():teleportTo(S.home.x, S.home.y - RT.away, 0)
        return true
    end
    if not ctx.trip.back then
        if ticks - ctx.trip.tick < 120 then RT.speed(1); return true end
        ctx.trip.awayFrom = ctx.trip.awayFrom or hours()
        if sq(S.home.x, S.home.y, 0) == nil then ctx.trip.unloaded = true end
        RT.speed(RT.waitSpeed)
        if hours() - ctx.trip.awayFrom < S.tripHours then return true end
        RT.speed(1)
        player():teleportTo(S.home.x, S.home.y, 0)
        ctx.trip.back, ctx.trip.backTick = hours(), ticks
        return true
    end
    if not ctx.trip.checked then
        if ticks - ctx.trip.backTick < 120 then RT.speed(1); return true end
        player():setPosition(S.home.x + 0.5, S.home.y + 0.5, 0)
        S.refind()
        local note = S.onReturn(ctx)
        -- Before any access: nothing filed for the hours the tiles were unloaded.
        local rec = S.items[S.warm] and S.items[S.warm]:getModData().tlgProc
        local filed, gap = 0, 0
        for _, s in ipairs(TLG.Tables.sortedKeys(S.unloaded)) do
            gap = gap + 1
            if rec and rec.temps and rec.temps[s] then filed = filed + 1 end
        end
        R:line("OBS  %s.trip away %.2f game h, tiles unloaded=%s, hours unread %d, filed for them %d, %s", S.tag,
            ctx.trip.back - ctx.trip.from, tostring(ctx.trip.unloaded == true), gap, filed, note)
        if ctx.trip.unloaded then
            R:check(S.tag .. ".nothing_filed_while_unloaded", function()
                return gap >= 8 and filed == 0, string.format("%d hours unloaded, %d filed", gap, filed)
            end)
        else
            R:line("OBS  %s.nothing_filed_while_unloaded INCONCLUSIVE: the tiles stayed loaded", S.tag)
        end
        S.resumeFrom = math.floor(hours() - 0.5) + 1
        ctx.trip.checked = true
        ctx.next = hours()
        return true
    end
    return false
end

RT.sitesFerment = { name = "rtw_ferment", timeout = 120000, fn = function(ctx, ticks)
    local W = RT.W
    if not ctx.t0 and RT.skip("rtw_ferment") then return true end
    if not ctx.t0 then
        -- One load at a time: the menu takes all the sugar carried.
        removeAll("Base.Sugar"); removeAll("Base.Yeast")
        for i, name in ipairs(W.names) do
            give("Base.Sugar", 6); give("Base.Yeast", 1)
            for _ = 1, 3 do
                local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
                fc:Empty()
                fc:addFluid(Fluid.Water, 10)
            end
            local r = machineClick("RTW.load_" .. name, W.items[i], "ContextMenu_TLG_LoadFerment")
            R:check("RTW.loaded_" .. name, function()
                return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6 and math.abs((r.waterL or 0) - 30) < 1e-6,
                    string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
            end)
        end
        W.active = true
        local env = TLG.World.env()
        ctx.t0, ctx.h0, ctx.next = ticks, hours(), hours() + 1
        ctx.m = {}
        for i = 1, 3 do
            ctx.m[i] = { prev = { h = hours(), done = RT.doneHours(W.items[i]), day = env:dayIndex(hours()), stage = "prepare" },
                rule = { n = 0, worst = 0, where = "none" }, mean = { n = 0, worst = 0, where = "none" },
                filed = { n = 0, worst = 0, where = "none" }, compared = -math.huge, afterTrip = 0, days = {},
                pausedTally = 0 }
        end
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    if tripStep(W, ctx, ticks) then return nil end
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 1
    local env, now = TLG.World.env(), hours()
    local day = env:dayIndex(now)
    for i = 1, 3 do readMachine(W, ctx, i, env, now, day) end
    local elapsed = now - ctx.h0
    local outS, heatS = ctx.m[1].last, ctx.m[3].last
    local over = heatS.state == "OutputReady" and (outS.state == "Faulted" or outS.state == "OutputReady")
    if not over and elapsed < 200 then return nil end

    RT.speed(1)
    W.active = false
    if W.hs then pcall(function() getCell():removeHeatSource(W.hs) end) end
    -- Per TLG day: the mean of the readings at each tile, what TLG recorded
    -- (outdoor air t, unheated room r0), each machine's day temperature,
    -- work and pauses.
    local log = TLG.World.get().climateLog or {}
    local daysSeen = {}
    for _, i in ipairs({ 1, 2, 3 }) do
        for d in pairs(ctx.m[i].days) do daysSeen[d] = true end
    end
    local roomOverOut = { n = 0, worst = math.huge, where = "none" }
    for _, d in ipairs(TLG.Tables.sortedKeys(daysSeen)) do
        local means = {}
        for i = 1, 3 do
            local sum, n = 0, 0
            for s, v in pairs(W.readings[i]) do
                if env:dayIndex(s + 0.5) == d then sum, n = sum + v, n + 1 end
            end
            means[i] = n > 0 and string.format("%.1f (%d h)", sum / n, n) or "-"
        end
        local rec = log[d] or {}
        local parts = {}
        for i = 1, 3 do
            local x = ctx.m[i].days[d]
            parts[i] = x and string.format("%s %s C work %.2f h paused %.2f h", W.names[i],
                x.siteC and string.format("%.2f", x.siteC) or "-", x.work, x.paused) or (W.names[i] .. " -")
        end
        local label = (ctx.m[1].days[d] or ctx.m[2].days[d] or {}).label or tostring(d)
        R:line("OBS  RTW.day %s: air read outdoors %s, room %s, heated %s; recorded t %s r0 %s; %s; %s; %s", label,
            means[1], means[2], means[3], rec.t and string.format("%.2f", rec.t) or "-",
            rec.r0 and string.format("%.2f", rec.r0) or "-", parts[1], parts[2], parts[3])
        local o, r = ctx.m[1].days[d], ctx.m[2].days[d]
        if o and r and o.siteC and r.siteC and o.siteC < 22 then
            roomOverOut.n = roomOverOut.n + 1
            if r.siteC - o.siteC < roomOverOut.worst then
                roomOverOut.worst, roomOverOut.where = r.siteC - o.siteC, label
            end
        end
    end
    for i = 1, 3 do
        local s, rec = ctx.m[i].last, W.items[i]:getModData().tlgProc or {}
        R:line("OBS  RTW.end %s state=%s pause=%s pausedFor %.2f h, after %.1f game h; status: %s", W.names[i],
            tostring(s.state), tostring(s.pause), rec.pausedFor or -1, elapsed, tostring(ctx.m[i].dialog))
    end
    R:check("RTW.room_air_is_the_formula", function()
        return W.formula.n >= 24 and W.formula.worst <= 0.01,
            string.format("%d hours, worst %.5f C (%s)", W.formula.n, W.formula.worst, W.formula.where)
    end)
    R:check("RTW.outdoor_air_is_the_air", function()
        return W.outside.n >= 24 and W.outside.worst <= 1e-4, string.format("%d hours, worst %.6f C", W.outside.n, W.outside.worst)
    end)
    local warmer, both = 0, 0
    for s, v in pairs(W.readings[3]) do
        local r = W.readings[2][s]
        if r then
            both = both + 1
            if v >= r + 10 then warmer = warmer + 1 end
        end
    end
    R:check("RTW.heated_tile_is_warmer", function()
        return both >= 24 and warmer >= both - 2, string.format("%d of %d hours at least 10 C over the room tile", warmer, both)
    end)
    R:check("RTW.room_warmer_than_outdoors", function()
        return roomOverOut.n >= 2 and roomOverOut.worst >= 3,
            string.format("%d days, smallest gap %.2f C (%s)", roomOverOut.n, roomOverOut.worst, roomOverOut.where)
    end)
    for i, name in ipairs(W.names) do
        local m = ctx.m[i]
        R:check("RTW.readings_filed_" .. name, function()
            return m.filed.n >= 24 and m.filed.worst <= 1e-6,
                string.format("%d hours, worst %.6f (%s)", m.filed.n, m.filed.worst, m.filed.where)
        end)
        R:check("RTW.day_temperature_from_readings_" .. name, function()
            return m.mean.n >= 24 and m.mean.worst <= 1e-6,
                string.format("%d reads, worst %.6f (%s)", m.mean.n, m.mean.worst, m.mean.where)
        end)
        R:check("RTW.progress_follows_site_temperature_" .. name, function()
            return m.rule.n >= 24 and m.rule.worst <= 0.01,
                string.format("%d hours, worst %.4f h (%s)", m.rule.n, m.rule.worst, m.rule.where)
        end)
    end
    if ctx.trip and ctx.trip.unloaded then
        R:check("RTW.readings_resume_after_return", function()
            return ctx.m[3].afterTrip >= 6, string.format("%d hours filed after the return", ctx.m[3].afterTrip)
        end)
    end
    R:check("RTW.status_names_the_site", function()
        return has(ctx.m[1].dialog, getText("IGUI_TLG_Site_outdoors")) and has(ctx.m[2].dialog, getText("IGUI_TLG_Site_room"))
            and has(ctx.m[3].dialog, getText("IGUI_TLG_Site_room")), string.format("%s | %s | %s",
            tostring(ctx.m[1].dialog), tostring(ctx.m[2].dialog), tostring(ctx.m[3].dialog))
    end)
    R:check("RTW.heated_batch_finishes", function()
        return heatS.state == "OutputReady", string.format("state=%s after %.1f game h", tostring(heatS.state), elapsed)
    end)
    R:check("RTW.heated_never_paused_on_days_read_throughout", function()
        return (ctx.m[3].readPauses or 0) == 0, string.format("%d paused reads (first: %s)", ctx.m[3].readPauses or 0,
            tostring(ctx.m[3].readPauseAt or "none"))
    end)
    local outRec = W.items[1]:getModData().tlgProc or {}
    if outS.state == "Faulted" then
        R:check("RTW.outdoors_spoils_after_72_paused_hours", function()
            return outS.pause == "batch_spoiled" and math.abs((outRec.pausedFor or 0) - 72) < 1e-6,
                string.format("pause=%s pausedFor %.2f", tostring(outS.pause), outRec.pausedFor or -1)
        end)
    else
        R:line("OBS  RTW.outdoors_spoils NOT REACHED: state=%s pausedFor %.2f", tostring(outS.state), outRec.pausedFor or -1)
    end
    return true
end }

RT.winterSteps = { RT.waitWorld, RT.setup, RT.sitesSetup, RT.sitesFerment, RT.finish }

------------------------------------------------------------------------------
-- Fireplace (request "sp-rtf"): a fireplace of the map beside a fermenter
-- (D-021), in the same January world with the grid off. Only the tiles
-- fixtures_fireplaces_01_0..5 carry container=fireplace
-- (newtiledefinitions.tiles), from which BC CellLoader makes an
-- IsoFireplace, and none lies near the start: run 20 scanned 49 windows up
-- to 288 tiles around it and found two campfires and two braziers only. So
-- the harness scans the map cells whose .lotheader lists one of those tiles,
-- nearest first, and keeps every fireplace of the first cell that has one
-- with a free room tile beside it. It lights it with a log through the calls the vanilla
-- actions make (ISBBQAddFuel:complete addFuel and sendObjectChange,
-- ISBBQLightFromLiterature:complete turnOn), not through the actions, and
-- compares the air on every tile within 9 of it with the heat formula of the
-- bytecode: unlit, then lit at four fuel levels, set as vanilla's
-- fireplace.setFuel command does (SRC ClientCommands.lua:428). A fermenter
-- then runs one batch on a room tile about two tiles from the fire, which
-- the harness tends as a player can (a log adds 6 h and only goes in once it
-- fits under the 8 h cap), with the winter run's readings, day temperature,
-- work and trip checks. Away for 12 game hours, the fire burns all the same:
-- on reload IsoFireplace.update uses up the minutes since its saved
-- lastUpdateTime in one step (BC), so it must be out on the return. Since
-- D-022 the mod notes the fire warming the machine every ten minutes and
-- credits that warmth to the hours away while the noted fuel lasts: the
-- harness takes its own notes at the same ticks and compares them, feeds
-- the fire a quarter hour before leaving (so a note sees it), and checks the
-- work over the trip against the day temperatures with the credit.
------------------------------------------------------------------------------
-- cells: 256-tile map cells (x, y) whose .lotheader lists a working
-- fireplace tile, nearest the start first (checked 2026-11-01 for cells
-- 39-43 by 37-43); each is scanned in nine windows of reach 48.
RT.F = { names = { "fireplace" }, tripAt = 30, tripHours = 12, tag = "RTF", warm = 1, srcC = 35, reach = 48,
    cells = { { 41, 40 }, { 41, 39 }, { 42, 39 }, { 41, 38 }, { 42, 38 }, { 41, 37 } }, fuels = { 40, 20, 5 },
    tol = 1e-3, logs = 0 }

-- Heat radius of a lit fireplace from its fuel in minutes (BC
-- IsoFireplace.calcLightRadius: GameTime.Lerp(1, 8, min(fuel, 60) / 60), truncated).
function RT.F.radius(fuel)
    return math.floor(1 + 7 * math.min(fuel, 60) / 60)
end

-- The air the game gives a tile from its unwarmed air t with one heat source
-- dx, dy away (BC IsoCell.getHeatSourceHighestTemperature, source 35 C:
-- IsoFireplace.updateHeatSource). The line of sight is not modelled here.
function RT.F.warmed(t, dx, dy, radius, srcInRoom)
    local dsq = dx * dx + dy * dy
    if dsq >= radius * radius then return t end
    local adj
    if srcInRoom then adj = math.max(-7, math.min(7, t - 30)) else adj = math.max(-15, math.min(5, t - 30)) end
    return math.max(t, t + (1 - math.sqrt(dsq) / radius) * (RT.F.srcC + adj - t))
end

function RT.F.climate()
    local cm = getClimateManager()
    local c = { t = cm:getTemperature(), dl = 0.5 }
    pcall(function() c.dl = cm:getClimateValuesCopy():getDayLightLagged() end)
    pcall(function() c.power = getWorld():isHydroPowerOn() end)
    return c
end

-- A tile's air without heat sources: the room formula in a room, else the air.
function RT.F.unwarmed(s, c)
    if RT.W.inRoom(s) then return TLG.Domain.Climate.roomAir(c.t, s:getZ() > 0, c.dl, c.power == true) end
    return c.t
end

-- The fireplace on its tile (again after a reload: Lua references go stale).
function RT.F.fireplace()
    local p = RT.F.fp
    local s = p and sq(p.x, p.y, 0)
    local objs = s and s:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoFireplace") then return o end
    end
    return nil
end

function RT.F.refind()
    local F = RT.F
    F.items[1] = fermenterOn(F.home.x, F.home.y) or F.items[1]
end

-- Tends the fire as a player can: a log only once it fits under the cap
-- (ISCampingMenu offers none past getCampingFuelMax), lit when it is out.
-- Same calls as ISBBQAddFuel:complete and ISBBQLightFromLiterature:complete.
function RT.F.tend(fp)
    local F = RT.F
    local added = false
    if fp:getFuelAmount() + F.perLog <= F.cap and takeAway("Base.Log") then
        fp:addFuel(F.perLog)
        fp:sendObjectChange(IsoObjectChange.STATE)
        F.logs = F.logs + 1
        added = true
        if F.logDays then
            local day = TLG.World.env():dayIndex(hours())
            F.logDays[day] = (F.logDays[day] or 0) + 1
        end
    end
    if fp:hasFuel() and not fp:isLit() then
        fp:turnOn()
        fp:sendObjectChange(IsoObjectChange.STATE)
    end
    return added
end

-- A free room tile within two tiles of (x, y): where a fermenter can stand.
function RT.F.nearFree(x, y)
    for _, d in ipairs({ { 0, 2 }, { 2, 0 }, { 0, -2 }, { -2, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
        local s = sq(x + d[1], y + d[2], 0)
        if RT.W.free(s) and RT.W.inRoom(s) then return { x = s:getX(), y = s:getY() } end
    end
    return nil
end

-- IsoFireplace objects on the loaded ground-floor tiles within reach of
-- (cx, cy), and how many of those tiles were loaded.
function RT.F.scan(cx, cy)
    local F, found, loaded = RT.F, {}, 0
    for x = cx - F.reach, cx + F.reach do
        for y = cy - F.reach, cy + F.reach do
            local s = sq(x, y, 0)
            if s then
                loaded = loaded + 1
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoFireplace") then
                        local c, spr = o:getContainer(), o:getSprite()
                        found[#found + 1] = { x = x, y = y, kind = c and c:getType() or "-",
                            sprite = spr and spr:getName() or "-" }
                    end
                end
            end
        end
    end
    return found, loaded
end

-- The air on every loaded floor tile within 9 of the fire against the heat
-- formula at its present fuel: warm or cold as the formula says, blocked when
-- in range but not warmed (no clear line of sight), mismatch otherwise.
function RT.F.snapshot(fp)
    local F, c = RT.F, RT.F.climate()
    local lit, fuel = fp:isLit(), fp:getFuelAmount()
    local radius = F.radius(fuel)
    local snap = { lit = lit, fuel = fuel, radius = radius, warm = 0, cold = 0, blocked = 0, mismatch = 0,
        where = "none", tiles = {} }
    for dx = -9, 9 do
        for dy = -9, 9 do
            local s = (dx ~= 0 or dy ~= 0) and sq(F.fp.x + dx, F.fp.y + dy, 0) or nil
            if s and s:getFloor() then
                local air = getClimateManager():getAirTemperatureForSquare(s)
                local t0 = F.unwarmed(s, c)
                local want = t0
                if lit then want = F.warmed(t0, dx, dy, radius, F.srcInRoom) end
                local class
                if math.abs(air - want) <= F.tol then
                    class = (want > t0 + F.tol) and "warm" or "cold"
                elseif want > t0 + F.tol and math.abs(air - t0) <= F.tol then
                    class = "blocked"
                else
                    class = "mismatch"
                    snap.where = string.format("%d,%d: game %.4f, formula %.4f, unwarmed %.4f", F.fp.x + dx,
                        F.fp.y + dy, air, want, t0)
                end
                snap[class] = snap[class] + 1
                snap.tiles[#snap.tiles + 1] = { x = F.fp.x + dx, y = F.fp.y + dy, dsq = dx * dx + dy * dy,
                    class = class, free = RT.W.free(s), room = RT.W.inRoom(s) }
            end
        end
    end
    return snap
end

function RT.F.snapText(snap)
    return string.format("lit=%s fuel %d min radius %d: warm %d, cold %d, blocked %d, mismatch %d (%s)",
        tostring(snap.lit), snap.fuel, snap.radius, snap.warm, snap.cold, snap.blocked, snap.mismatch, snap.where)
end

function RT.F.classOf(snap, x, y)
    for _, tl in ipairs(snap.tiles) do
        if tl.x == x and tl.y == y then return tl.class end
    end
    return "none"
end

-- Every game hour while the batch runs: the game's air at the machine, filed
-- by hour like the mod's readings, against the heat formula at the fire's
-- fuel of the moment; then the fire is tended.
function RT.F.onHour()
    local F = RT.F
    if not F.active then return end
    local slot = math.floor(hours() - 0.5)
    local s, fp = sq(F.home.x, F.home.y, 0), F.fireplace()
    if s == nil or fp == nil then
        F.unloaded[slot] = true
        return
    end
    local air = getClimateManager():getAirTemperatureForSquare(s)
    F.readings[1][slot] = air
    local t0 = F.unwarmed(s, F.climate())
    local lit, fuel = fp:isLit(), fp:getFuelAmount()
    local want = t0
    if lit then want = F.warmed(t0, F.home.x - F.fp.x, F.home.y - F.fp.y, F.radius(fuel), F.srcInRoom) end
    local h = F.hourly
    h.n = h.n + 1
    if math.abs(air - want) >= h.worst then
        h.worst = math.abs(air - want)
        h.where = string.format("%s hour %d: lit=%s fuel %d: game %.4f, formula %.4f", RT.dayKey(), slot,
            tostring(lit), fuel, air, want)
    end
    if lit then
        h.lit = h.lit + 1
        h.minFuel = math.min(h.minFuel, fuel)
        h.minGain = math.min(h.minGain, air - t0)
        h.minAir = math.min(h.minAir, air)
    end
    if F.tending then F.tend(fp) end
end

-- Every ten game minutes while the batch runs: the harness's own note of the
-- fire warming the machine, as Machines.observeFires takes it (under the
-- hour, the last one wins; false when the fire does not give the air).
function RT.F.onTenMinutes()
    local F = RT.F
    if not F.active then return end
    local s, fp = sq(F.home.x, F.home.y, 0), F.fireplace()
    if s == nil or fp == nil then return end
    local air = getClimateManager():getAirTemperatureForSquare(s)
    local t0 = F.unwarmed(s, F.climate())
    local dx, dy, fuel = F.fp.x - F.home.x, F.fp.y - F.home.y, fp:getFuelAmount()
    local note = false
    if fp:isLit() and fuel > 0 and air > t0 + F.tol
        and math.abs(F.warmed(t0, dx, dy, F.radius(fuel), F.srcInRoom) - air) <= F.tol then
        note = { t = hours(), f = fuel, x = dx, y = dy, r = F.srcInRoom, c = F.srcC }
    end
    F.fires[1][math.floor(hours())] = note
end

function RT.F.onLeave(ctx)
    local fp = RT.F.fireplace()
    ctx.trip.fire = { fuel = fp and fp:getFuelAmount() or -1, lit = fp ~= nil and fp:isLit() }
end

-- The work done over the trip against the stage rule fed by each day's
-- temperature from the harness's readings and notes (the mod advances each
-- day at its mean computed up to the read).
function RT.F.checkWork(ctx, before, env, now)
    local F, m = RT.F, ctx.m[1]
    local rec = F.items[1]:getModData().tlgProc
    local site = { room = rec.site.room, z = rec.site.z, temps = F.readings[1], fires = F.fires[1],
        from = rec.startedAt }
    local want, t = 0, before.h
    while t < now - 1e-9 do
        local d = env:dayIndex(t)
        local stop = math.min(now, env:dayStart(d + 1))
        want = want + RT.fermentRate((env:siteDayMean(d, site, now))) * (stop - t)
        t = stop
    end
    local did = RT.doneHours(F.items[1]) - before.done
    R:check("RTF.work_over_the_trip", function()
        return before.stage == "ferment" and m.last.stage == "ferment" and math.abs(did - want) <= 0.01,
            string.format("%.2f to %.2f h in: did %.4f h, rule with the credit %.4f h", before.h - ctx.h0,
                now - ctx.h0, did, want)
    end)
end

-- Back from the trip: the fire as the reload left it, then lit again.
function RT.F.onReturn(ctx)
    local F, before = RT.F, ctx.trip.fire
    local fp = F.fireplace()
    if fp == nil then return "fireplace not found again" end
    local fuel, lit = fp:getFuelAmount(), fp:isLit()
    local awayMin = (ctx.trip.back - ctx.trip.from) * 60
    local want = math.max(0, before.fuel - awayMin)
    if ctx.trip.unloaded then
        R:check("RTF.fire_burned_while_away", function()
            return before.lit and math.abs(fuel - want) <= 15 and lit == (fuel > 0),
                string.format("left lit=%s with %d min; back after %.0f min: lit=%s with %d min (burning on: %.0f)",
                    tostring(before.lit), before.fuel, awayMin, tostring(lit), fuel, want)
        end)
        -- D-022: no note in an hour spent wholly away; the note standing last
        -- before leaving covers the trip while its fuel lasts.
        local rec = F.items[1] and F.items[1]:getModData().tlgProc or {}
        local noted, last = 0, nil
        for h in pairs(rec.fires or {}) do
            if F.unloaded[h - 1] and F.unloaded[h] then noted = noted + 1 end
        end
        for _, h in ipairs(TLG.Tables.sortedKeys(F.fires[1])) do
            if h <= ctx.trip.from then last = h end
        end
        local note = last and F.fires[1][last]
        local credited = type(note) == "table" and math.max(0, math.min(ctx.trip.back, note.t + note.f / 60)
            - ctx.trip.from) or 0
        R:line("OBS  RTF.credit last note before leaving: %s; covers %.2f of %.2f h away", brief(note), credited,
            ctx.trip.back - ctx.trip.from)
        R:check("RTF.no_notes_while_unloaded", function()
            return noted == 0, string.format("%d notes in hours spent away", noted)
        end)
        R:check("RTF.away_hours_credited", function()
            return credited >= 1, string.format("%.2f h of the trip covered by the fire's noted fuel", credited)
        end)
    end
    local added = F.tend(fp)
    return string.format("fire on return lit=%s fuel %d min (left lit=%s with %d), log added=%s, lit now=%s",
        tostring(lit), fuel, tostring(before.lit), before.fuel, tostring(added), tostring(fp:isLit()))
end

RT.fireFind = { name = "rtf_find", timeout = 90000, fn = function(ctx, ticks)
    local F = RT.F
    if not ctx.hops and RT.skip("rtf_find") then return true end
    RT.speed(1)
    if not ctx.hops then
        ctx.hops, ctx.n, ctx.seen = {}, 0, {}
        F.candidates = {}
        for c, cell in ipairs(F.cells) do
            for i = 0, 2 do
                for j = 0, 2 do
                    ctx.hops[#ctx.hops + 1] = { x = cell[1] * 256 + 48 + 96 * i, y = cell[2] * 256 + 48 + 96 * j,
                        cell = cell, last = i == 2 and j == 2 }
                end
            end
        end
    end
    if not ctx.at then
        ctx.n = ctx.n + 1
        ctx.at = ctx.hops[ctx.n]
        if ctx.at == nil then
            RT.abort = string.format("no fireplace with a free room tile beside it in %d windows", #ctx.hops)
            R:line("OBS  RTF.find %s", RT.abort)
            return true
        end
        player():teleportTo(ctx.at.x, ctx.at.y, 0)
        ctx.tick, ctx.loaded = ticks, -1
        return nil
    end
    local waited = ticks - ctx.tick
    if waited < 120 or waited % 60 ~= 0 then return nil end
    local found, loaded = F.scan(ctx.at.x, ctx.at.y)
    -- Still loading: scan again until the count stops growing.
    if loaded < (2 * F.reach + 1) ^ 2 and loaded > ctx.loaded and waited < 1200 then
        ctx.loaded = loaded
        return nil
    end
    local listed, picks = {}, 0
    for k, f in ipairs(found) do
        if k <= 8 then listed[#listed + 1] = string.format("%s %s at %d,%d", f.kind, f.sprite, f.x, f.y) end
        local key = f.x .. "," .. f.y
        if (f.kind == "fireplace" or string.find(f.sprite, "fireplace", 1, true)) and not ctx.seen[key] then
            ctx.seen[key] = true
            f.near = F.nearFree(f.x, f.y)
            if f.near then
                F.candidates[#F.candidates + 1] = f
                picks = picks + 1
            end
        end
    end
    R:line("OBS  RTF.hop %d (cell %d_%d) at %d,%d: %d tiles loaded after %d ticks; %d fire objects [%s]; new fireplaces with a free room tile beside them %d",
        ctx.n, ctx.at.cell[1], ctx.at.cell[2], ctx.at.x, ctx.at.y, loaded, waited, #found, table.concat(listed, "; "), picks)
    -- The first cell with a usable fireplace is scanned to its end.
    local done = ctx.at.last and #F.candidates > 0
    ctx.at = nil
    return done or nil
end }

RT.fireLight = { name = "rtf_light", timeout = 30000, fn = function(ctx, ticks)
    local F = RT.F
    if not ctx.i and RT.skip("rtf_light") then return true end
    RT.speed(1)
    if not ctx.i then
        if not F.candidates or #F.candidates == 0 then
            RT.abort = "no fireplace found"
            return true
        end
        F.perLog = math.floor(ISCampingMenu.getFuelDurationForItem(instanceItem("Base.Log")) + 1e-6)
        local ok, cap = pcall(getCampingFuelMax)
        F.cap = ok and cap or 480
        removeAll("Base.Log")
        give("Base.Log", 40)
        R:line("OBS  RTF.fuel a log adds %d min (ISCampingMenu.getFuelDurationForItem), cap %s min (getCampingFuelMax ok=%s)",
            F.perLog, tostring(F.cap), tostring(ok))
        ctx.i, ctx.phase = 0, "next"
    end
    if ctx.phase == "next" then
        ctx.i = ctx.i + 1
        local c = F.candidates[ctx.i]
        if c == nil then
            RT.abort = "no fireplace warmed a free room tile within two tiles"
            R:line("OBS  RTF.light %s", RT.abort)
            return true
        end
        F.fp = { x = c.x, y = c.y, kind = c.kind, sprite = c.sprite }
        player():teleportTo(c.near.x, c.near.y, 0)
        ctx.phase, ctx.tick, ctx.snaps = "arrive", ticks, {}
        return nil
    end
    if ctx.phase == "arrive" then
        if ticks - ctx.tick < 120 then return nil end
        player():setPosition(F.candidates[ctx.i].near.x + 0.5, F.candidates[ctx.i].near.y + 0.5, 0)
        local fp = F.fireplace()
        F.srcInRoom = RT.W.inRoom(sq(F.fp.x, F.fp.y, 0))
        R:line("OBS  RTF.fireplace %s %s at %d,%d, its tile in a room=%s, lit=%s fuel %d", F.fp.kind, F.fp.sprite,
            F.fp.x, F.fp.y, tostring(F.srcInRoom), tostring(fp:isLit()), fp:getFuelAmount())
        ctx.unlit = F.snapshot(fp)
        R:line("OBS  RTF.snapshot unlit %s", F.snapText(ctx.unlit))
        F.tend(fp)
        ctx.phase, ctx.tick = "lit", ticks
        return nil
    end
    if ticks - ctx.tick < 30 then return nil end
    local fp = F.fireplace()
    local snap = F.snapshot(fp)
    ctx.snaps[#ctx.snaps + 1] = snap
    R:line("OBS  RTF.snapshot %s", F.snapText(snap))
    if #ctx.snaps == 1 then
        -- The machine's tile: free, in a room, warmed as the formula says,
        -- two tiles from the fire if possible.
        local spot
        for _, d in ipairs({ 4, 5, 1, 2 }) do
            for _, tl in ipairs(snap.tiles) do
                if spot == nil and tl.dsq == d and tl.free and tl.room and tl.class == "warm" then spot = tl end
            end
        end
        if spot == nil then
            fp:setFuelAmount(0)
            fp:extinguish()
            fp:sendObjectChange(IsoObjectChange.STATE)
            ctx.phase = "next"
            return nil
        end
        F.home = { x = spot.x, y = spot.y }
    end
    local f = F.fuels[#ctx.snaps]
    if f then
        fp:setFuelAmount(f)
        fp:sendObjectChange(IsoObjectChange.STATE)
        ctx.tick = ticks
        return nil
    end
    local s1, s2, s3, s4 = ctx.snaps[1], ctx.snaps[2], ctx.snaps[3], ctx.snaps[4]
    R:check("RTF.unlit_tiles_unwarmed", function()
        local u = ctx.unlit
        return u.cold >= 20 and u.warm == 0 and u.blocked == 0 and u.mismatch == 0, F.snapText(u)
    end)
    local off = 0
    for _, sn in ipairs(ctx.snaps) do off = off + sn.mismatch end
    R:check("RTF.tiles_follow_the_heat_formula", function()
        return off == 0 and s1.warm >= 3, string.format("%d tiles off the formula in %d lit snapshots; %d warmed at %d min",
            off, #ctx.snaps, s1.warm, s1.fuel)
    end)
    R:check("RTF.radius_follows_fuel", function()
        return s1.radius == 8 and s2.radius == 5 and s3.radius == 3 and s4.radius == 1 and s1.warm >= s2.warm
            and s2.warm >= s3.warm and s3.warm >= 1 and s4.warm == 0,
            string.format("warmed tiles at %d min (radius %d) %d, %d min (%d) %d, %d min (%d) %d, %d min (%d) %d",
                s1.fuel, s1.radius, s1.warm, s2.fuel, s2.radius, s2.warm, s3.fuel, s3.radius, s3.warm, s4.fuel,
                s4.radius, s4.warm)
    end)
    local cls = {}
    for k, sn in ipairs(ctx.snaps) do cls[k] = F.classOf(sn, F.home.x, F.home.y) end
    R:check("RTF.machine_tile_warmed_while_fuel_lasts", function()
        return cls[1] == "warm" and cls[2] == "warm" and cls[3] == "warm" and cls[4] == "cold", table.concat(cls, ", ")
    end)
    F.tend(fp)
    local dx, dy = F.home.x - F.fp.x, F.home.y - F.fp.y
    R:line("OBS  RTF.machine tile %d,%d, %.2f tiles from the fire; fire lit=%s with %d min, logs so far %d",
        F.home.x, F.home.y, math.sqrt(dx * dx + dy * dy), tostring(fp:isLit()), fp:getFuelAmount(), F.logs)
    return true
end }

-- Places a fermenter on the chosen tile and a second later loads it from the
-- menu; true once its batch runs.
function RT.F.placeAndLoad(ctx, ticks)
    local F = RT.F
    if not ctx.t0 then
        local it = instanceItem("TLG.FermenterVessel")
        sq(F.home.x, F.home.y, 0):AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
        F.items, F.readings, F.unloaded, F.logDays, F.fires = { it }, { {} }, {}, {}, { {} }
        player():setPosition(F.home.x + 0.5, F.home.y + 0.5, 0)
        ctx.t0 = ticks
        return false
    end
    if ticks - ctx.t0 < 60 then return false end
    local site = TLG.Integration.Machines.siteOf(sq(F.home.x, F.home.y, 0))
    R:check("RTF.site_seen", function()
        return site.room == true and site.z == 0, string.format("room=%s z=%s", tostring(site.room), tostring(site.z))
    end)
    removeAll("Base.Sugar"); removeAll("Base.Yeast")
    give("Base.Sugar", 6); give("Base.Yeast", 1)
    for _ = 1, 3 do
        local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
        fc:Empty()
        fc:addFluid(Fluid.Water, 10)
    end
    local r = machineClick("RTF.load", F.items[1], "ContextMenu_TLG_LoadFerment")
    R:check("RTF.loaded", function()
        return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6 and math.abs((r.waterL or 0) - 30) < 1e-6,
            string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
    end)
    F.logs0 = F.logs
    return true
end

-- Starts the batch's bookkeeping from the batch start h0: hooks, the hourly
-- read and the machine's tallies. After a reload (F.resumed) the readings and
-- notes of before the save were compared then and are not compared again,
-- and the first read comes at once.
function RT.F.startAccounting(ctx, h0)
    local F = RT.F
    F.active, F.tending = true, true
    F.hourly = { n = 0, worst = 0, where = "none", lit = 0, minFuel = math.huge, minGain = math.huge, minAir = math.huge }
    if not F.hooked then
        Events.EveryHours.Add(RT.F.onHour)
        Events.EveryTenMinutes.Add(RT.F.onTenMinutes)
        F.hooked = true
    end
    local env = TLG.World.env()
    local function last(t)
        local keys = TLG.Tables.sortedKeys(t)
        return keys[#keys] or -math.huge
    end
    ctx.h0, ctx.next = h0, F.resumed and hours() or hours() + 1
    ctx.m = { { prev = { h = hours(), done = RT.doneHours(F.items[1]), day = env:dayIndex(hours()),
        stage = (not F.resumed) and "prepare" or nil },
        rule = { n = 0, worst = 0, where = "none" }, mean = { n = 0, worst = 0, where = "none" },
        filed = { n = 0, worst = 0, where = "none" }, compared = F.resumed and last(F.readings[1]) or -math.huge,
        afterTrip = 0, days = {}, pausedTally = 0, notes = { n = 0, fire = 0, off = 0 },
        notesCompared = F.resumed and last(F.fires[1]) or -math.huge } }
end

RT.fireFerment = { name = "rtf_ferment", timeout = 120000, fn = function(ctx, ticks)
    local F = RT.F
    if not ctx.h0 and not ctx.t0 and RT.skip("rtf_ferment") then return true end
    if not ctx.h0 then
        if F.resumed then
            F.startAccounting(ctx, F.h0)
            return nil
        end
        if not F.home then
            RT.abort = "no machine tile beside a fireplace"
            return true
        end
        if F.placeAndLoad(ctx, ticks) then F.startAccounting(ctx, hours()) end
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    -- A quarter hour before leaving the fire gets what a log can add, so a
    -- ten-minute note sees the fuel it leaves with.
    if not ctx.fed and hours() - ctx.h0 >= F.tripAt - 0.25 then
        local fp = F.fireplace()
        ctx.fed = { added = fp and F.tend(fp), fuel = fp and fp:getFuelAmount() or -1 }
    end
    if tripStep(F, ctx, ticks) then return nil end
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 1
    local env, now = TLG.World.env(), hours()
    local m = ctx.m[1]
    -- The first read after the trip: the work over it is checked.
    local before = ctx.trip and ctx.trip.checked and not ctx.workChecked
        and { h = m.prev.h, done = m.prev.done, stage = m.prev.stage } or nil
    readMachine(F, ctx, 1, env, now, env:dayIndex(now))
    if before then
        ctx.workChecked = true
        F.checkWork(ctx, before, env, now)
    end
    local elapsed = now - ctx.h0
    local st = m.last
    if st.state ~= "OutputReady" and st.state ~= "Faulted" and elapsed < 200 then return nil end

    RT.speed(1)
    F.active, F.tending = false, false
    -- Per TLG day: the mean of the readings at the machine, what TLG recorded
    -- (outdoor air t, unheated room r0), the day temperature, work, pauses
    -- and the logs put on the fire.
    local log = TLG.World.get().climateLog or {}
    for _, d in ipairs(TLG.Tables.sortedKeys(m.days)) do
        local x, sum, n = m.days[d], 0, 0
        for s, v in pairs(F.readings[1]) do
            if env:dayIndex(s + 0.5) == d then sum, n = sum + v, n + 1 end
        end
        local rec = log[d] or {}
        R:line("OBS  RTF.day %s: air read at the machine %s; recorded t %s r0 %s; day temperature %s C, work %.2f h, paused %.2f h; logs %d",
            x.label, n > 0 and string.format("%.1f (%d h)", sum / n, n) or "-",
            rec.t and string.format("%.2f", rec.t) or "-", rec.r0 and string.format("%.2f", rec.r0) or "-",
            x.siteC and string.format("%.2f", x.siteC) or "-", x.work, x.paused, F.logDays[d] or 0)
    end
    local rec, h = F.items[1]:getModData().tlgProc or {}, F.hourly
    R:line("OBS  RTF.end state=%s pause=%s pausedFor %.2f h, after %.1f game h; logs put on during the batch %d (%d min each, cap %s); status: %s",
        tostring(st.state), tostring(st.pause), rec.pausedFor or -1, elapsed, F.logs - F.logs0, F.perLog,
        tostring(F.cap), tostring(m.dialog))
    R:line("OBS  RTF.hours read %d, fire lit at %d of them: lowest fuel %s min, lowest air %s C, smallest warming %s C",
        h.n, h.lit, tostring(h.minFuel), h.minAir < math.huge and string.format("%.2f", h.minAir) or "-",
        h.minGain < math.huge and string.format("%.2f", h.minGain) or "-")
    R:check("RTF.machine_air_is_the_formula", function()
        return h.n >= 24 and h.worst <= F.tol, string.format("%d hours, worst %.5f C (%s)", h.n, h.worst, h.where)
    end)
    R:check("RTF.readings_filed_fireplace", function()
        return m.filed.n >= 24 and m.filed.worst <= 1e-6,
            string.format("%d hours, worst %.6f (%s)", m.filed.n, m.filed.worst, m.filed.where)
    end)
    -- After a reload only the hours since the save are compared here.
    local noted = F.resumed and 40 or 80
    R:check("RTF.notes_filed_fireplace", function()
        return m.notes.n >= noted and m.notes.fire >= noted * 3 / 4 and m.notes.off == 0,
            string.format("%d hours noted, %d with the fire, %d off (%s); fed before leaving: %s", m.notes.n,
                m.notes.fire, m.notes.off, tostring(m.notes.where or "none"), brief(ctx.fed))
    end)
    R:check("RTF.day_temperature_from_readings_fireplace", function()
        return m.mean.n >= 24 and m.mean.worst <= 1e-6,
            string.format("%d reads, worst %.6f (%s)", m.mean.n, m.mean.worst, m.mean.where)
    end)
    R:check("RTF.progress_follows_site_temperature_fireplace", function()
        return m.rule.n >= 24 and m.rule.worst <= 0.01,
            string.format("%d hours, worst %.4f h (%s)", m.rule.n, m.rule.worst, m.rule.where)
    end)
    if ctx.trip and ctx.trip.unloaded then
        R:check("RTF.readings_resume_after_return", function()
            return m.afterTrip >= 6, string.format("%d hours filed after the return", m.afterTrip)
        end)
    end
    R:check("RTF.status_names_the_site", function()
        return has(m.dialog, getText("IGUI_TLG_Site_room")), tostring(m.dialog)
    end)
    R:check("RTF.batch_finishes", function()
        return st.state == "OutputReady", string.format("state=%s after %.1f game h", tostring(st.state), elapsed)
    end)
    R:check("RTF.never_paused_on_days_read_throughout", function()
        return (m.readPauses or 0) == 0, string.format("%d paused reads (first: %s)", m.readPauses or 0,
            tostring(m.readPauseAt or "none"))
    end)
    return true
end }

RT.fireplaceSteps = { RT.waitWorld, RT.setup, RT.fireFind, RT.fireLight, RT.fireFerment, RT.finish }

------------------------------------------------------------------------------
-- Fireplace across a save (requests "sp-rtfs", then "sp-rtfb"). Phase 1 runs
-- the batch beside the fire, tended for 14 game hours, then leaves the fire
-- to burn out with the character beside it until two hours of notes say no
-- fire warms the machine; it writes the record, the harness's own readings
-- and notes and the fire to the expectations file, saves and exits to the
-- menu. Phase 2 continues the save: before any access the record must hold
-- every reading and note of the save, "no fire" notes included (item mod
-- data saves booleans, BC KahluaTableImpl.save), its batch, site and place
-- in the world's hourly list, and the fire must be as left. Then the fire is
-- lit again and the batch runs on with the trip and every check of the
-- fireplace run.
------------------------------------------------------------------------------
-- Readings and notes as text (tostring gives numbers back exactly).
function RT.F.encodeTemps(t)
    local parts = {}
    for _, k in ipairs(TLG.Tables.sortedKeys(t or {})) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(t[k]) end
    return table.concat(parts, ";")
end

function RT.F.encodeNotes(n)
    local parts = {}
    for _, k in ipairs(TLG.Tables.sortedKeys(n or {})) do
        local v, text = n[k], "false"
        if v then
            text = table.concat({ tostring(v.t), tostring(v.f), tostring(v.x), tostring(v.y), tostring(v.r),
                tostring(v.c), tostring(v.rad) }, ",")
        end
        parts[#parts + 1] = tostring(k) .. "=" .. text
    end
    return table.concat(parts, ";")
end

local function entries(s)
    local out = {}
    for part in string.gmatch(s or "", "([^;]+)") do
        local k, v = string.match(part, "^([^=]+)=(.*)$")
        if k then out[#out + 1] = { tonumber(k), v } end
    end
    return out
end

function RT.F.decodeTemps(s)
    local t = {}
    for _, e in ipairs(entries(s)) do t[e[1]] = tonumber(e[2]) end
    return t
end

function RT.F.decodeNotes(s)
    local n = {}
    for _, e in ipairs(entries(s)) do
        if e[2] == "false" then
            n[e[1]] = false
        else
            local a = {}
            for p in string.gmatch(e[2], "([^,]+)") do a[#a + 1] = p end
            n[e[1]] = { t = tonumber(a[1]), f = tonumber(a[2]), x = tonumber(a[3]), y = tonumber(a[4]),
                r = a[5] == "true", c = tonumber(a[6]), rad = tonumber(a[7]) }
        end
    end
    return n
end

RT.fireBeforeSave = { name = "rtfs_before_save", timeout = 120000, fn = function(ctx, ticks)
    local F = RT.F
    if not ctx.h0 and not ctx.t0 and RT.skip("rtfs_before_save") then return true end
    if not ctx.h0 then
        if not F.home then
            RT.abort = "no machine tile beside a fireplace"
            return true
        end
        if F.placeAndLoad(ctx, ticks) then F.startAccounting(ctx, hours()) end
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    RT.speed(RT.waitSpeed)
    if F.tending and hours() - ctx.h0 >= 14 then F.tending = false end
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 1
    local env, now = TLG.World.env(), hours()
    readMachine(F, ctx, 1, env, now, env:dayIndex(now))
    local h = math.floor(now)
    local out = F.fires[1][h] == false and F.fires[1][h - 1] == false
    if not out and now - ctx.h0 < 26 then return nil end
    RT.speed(1)
    F.active = false
    local item, fp = F.items[1], F.fireplace()
    local rec = item:getModData().tlgProc
    local cold = 0
    for _, v in pairs(rec.fires or {}) do
        if v == false then cold = cold + 1 end
    end
    R:check("RTFS.fire_out_noted", function()
        return out and cold >= 2, string.format("fire lit=%s with %d min; %d notes without a fire in the record",
            tostring(fp:isLit()), fp:getFuelAmount(), cold)
    end)
    TLGH.writeFile(EXPECT, {
        "rtfs.fp=" .. F.fp.x .. "," .. F.fp.y, "rtfs.home=" .. F.home.x .. "," .. F.home.y,
        "rtfs.room=" .. tostring(F.srcInRoom), "rtfs.sprite=" .. tostring(F.fp.sprite),
        "rtfs.perLog=" .. tostring(F.perLog), "rtfs.cap=" .. tostring(F.cap), "rtfs.h0=" .. tostring(ctx.h0),
        "rtfs.logs=" .. tostring(F.logs), "rtfs.logs0=" .. tostring(F.logs0), "rtfs.hours=" .. tostring(now),
        "rtfs.id=" .. tostring(rec.id), "rtfs.state=" .. tostring(rec.state), "rtfs.stage=" .. tostring(rec.stage),
        "rtfs.stageDone=" .. tostring(rec.stageDone), "rtfs.pausedFor=" .. tostring(rec.pausedFor),
        "rtfs.startedAt=" .. tostring(rec.startedAt), "rtfs.site=" .. tostring(rec.site.room) .. "," .. tostring(rec.site.z),
        "rtfs.temps=" .. F.encodeTemps(rec.temps), "rtfs.fires=" .. F.encodeNotes(rec.fires),
        "rtfs.readings=" .. F.encodeTemps(F.readings[1]), "rtfs.notes=" .. F.encodeNotes(F.fires[1]),
        "rtfs.fuel=" .. tostring(fp:getFuelAmount()), "rtfs.lit=" .. tostring(fp:isLit()),
    })
    R:line("OBS  RTFS.saving at %.2f h in: %d readings and %d notes (%d without a fire) in the record; %s stage %s, %.4f stage h done",
        now - ctx.h0, #TLG.Tables.sortedKeys(rec.temps or {}), #TLG.Tables.sortedKeys(rec.fires or {}), cold,
        tostring(rec.state), tostring(rec.stage), RT.doneHours(item))
    return true
end }

RT.saveAndExit = { name = "rtfs_save_and_exit", timeout = 1200, fn = function(ctx, ticks)
    if not ctx.saved then
        RT.speed(1)
        R:finish(false)
        TLGH.writeFile("TLG_harness_request.txt", { "sp-rtfb" })
        saveGame()
        ctx.saved = true
        return nil
    end
    if ticks == 180 then
        R:line("EXIT phase 1 -> main menu")
        getCore():exitToMenu()
    end
    return nil
end }

RT.fireReload = { name = "rtfb_reload", timeout = 3000, fn = function(ctx, ticks)
    local F = RT.F
    if not (player() and ticks > 120) then return nil end
    local e = TLGH.readKeyValues(EXPECT)
    if e["rtfs.home"] == nil then
        RT.abort = "no expectations from phase 1"
        R:line("OBS  RTFB.%s", RT.abort)
        return true
    end
    local fx, fy = string.match(e["rtfs.fp"], "^([^,]+),([^,]+)$")
    local hx, hy = string.match(e["rtfs.home"], "^([^,]+),([^,]+)$")
    F.fp = { x = tonumber(fx), y = tonumber(fy), kind = "fireplace", sprite = e["rtfs.sprite"] }
    F.home = { x = tonumber(hx), y = tonumber(hy) }
    F.srcInRoom, F.perLog, F.cap = e["rtfs.room"] == "true", tonumber(e["rtfs.perLog"]), tonumber(e["rtfs.cap"])
    F.h0, F.logs, F.logs0 = tonumber(e["rtfs.h0"]), tonumber(e["rtfs.logs"]), tonumber(e["rtfs.logs0"])
    F.readings, F.fires = { F.decodeTemps(e["rtfs.readings"]) }, { F.decodeNotes(e["rtfs.notes"]) }
    F.unloaded, F.logDays = {}, {}
    local p = player()
    p:setGodMod(true)
    p:setInvisible(true)
    pcall(function() p:setUnlimitedCarry(true) end)
    captureDialogs(true)
    give("Base.Log", 30)
    p:setPosition(F.home.x + 0.5, F.home.y + 0.5, 0)
    local item = fermenterOn(F.home.x, F.home.y)
    F.items = { item }
    local rec = item and item:getModData().tlgProc
    R:line("OBS  RTFB.continued at world hour %.4f (saved at %s); machine found=%s", hours(), tostring(e["rtfs.hours"]),
        tostring(rec ~= nil))
    R:check("RTFB.machine_found", function() return rec ~= nil, tostring(item) end)
    if rec == nil then
        RT.abort = "machine not found after the reload"
        return true
    end
    -- The saved hours, read back from the record before any access.
    local temps, notes, cold = {}, {}, 0
    for k in pairs(F.decodeTemps(e["rtfs.temps"])) do temps[k] = rec.temps and rec.temps[k] end
    for k, v in pairs(F.decodeNotes(e["rtfs.fires"])) do
        if rec.fires then notes[k] = rec.fires[k] end
        if v == false then cold = cold + 1 end
    end
    R:check("RTFB.readings_survive", function()
        local got = F.encodeTemps(temps)
        return got == e["rtfs.temps"] and got ~= "", string.format("%d hours", #TLG.Tables.sortedKeys(temps))
    end)
    R:check("RTFB.notes_survive", function()
        local got = F.encodeNotes(notes)
        return got == e["rtfs.fires"] and cold >= 2,
            string.format("%d hours, %d of them without a fire%s", #TLG.Tables.sortedKeys(notes), cold,
                got == e["rtfs.fires"] and "" or (": got " .. got))
    end)
    R:check("RTFB.batch_survives", function()
        local same = tostring(rec.id) == e["rtfs.id"] and tostring(rec.state) == e["rtfs.state"]
            and tostring(rec.stage) == e["rtfs.stage"] and tostring(rec.stageDone) == e["rtfs.stageDone"]
            and tostring(rec.pausedFor) == e["rtfs.pausedFor"] and tostring(rec.startedAt) == e["rtfs.startedAt"]
            and (tostring(rec.site and rec.site.room) .. "," .. tostring(rec.site and rec.site.z)) == e["rtfs.site"]
        return same, string.format("%s stage %s, %s stage h, paused %s h, started %s, site %s,%s", tostring(rec.state),
            tostring(rec.stage), tostring(rec.stageDone), tostring(rec.pausedFor), tostring(rec.startedAt),
            tostring(rec.site and rec.site.room), tostring(rec.site and rec.site.z))
    end)
    R:check("RTFB.hourly_list_survives", function()
        local s = (TLG.World.get().machineSites or {})[rec.id]
        return s ~= nil and s.x == F.home.x and s.y == F.home.y and s.z == 0, brief(s)
    end)
    local fp = F.fireplace()
    R:check("RTFB.fire_as_left", function()
        return fp ~= nil and tostring(fp:getFuelAmount()) == e["rtfs.fuel"] and tostring(fp:isLit()) == e["rtfs.lit"],
            string.format("lit=%s with %s min (left lit=%s with %s)", tostring(fp and fp:isLit()),
                tostring(fp and fp:getFuelAmount()), e["rtfs.lit"], e["rtfs.fuel"])
    end)
    if fp then F.tend(fp) end
    R:line("OBS  RTFB.fire lit again=%s with %s min", tostring(fp and fp:isLit()), tostring(fp and fp:getFuelAmount()))
    F.resumed = true
    return true
end }

RT.fireSaveSteps = { RT.waitWorld, RT.setup, RT.fireFind, RT.fireLight, RT.fireBeforeSave, RT.saveAndExit }
RT.fireReloadSteps = { RT.fireReload, RT.fireFerment, RT.finish }

------------------------------------------------------------------------------
-- Pickup (request "sp-rtp"): running fermenters picked up and put down
-- again (D-015, release gate 6). Summer with the grid on (ElecShutModifier
-- 30, as vanilla's Multiplayer debug scenario sets it): four fermenters on
-- free room tiles around the character's tile, where a powered room holds
-- 22 C (Climate.roomAir), so every placed hour is a full stage hour. All
-- four are loaded in the same tick. Three game hours later A is picked up
-- with the world menu's Grab (ISWorldObjectContextMenu.onGrabWItem, which
-- queues ISGrabItemAction in single player), B with the loot window's Grab
-- (ISInventoryPaneContextMenu.onGrabItems: ISInventoryTransferAction from
-- the floor), and D with the calls ISGrabItemAction's single-player branch
-- makes but not through it: a grab no Lua sees, as the server's Java item
-- transaction is in multiplayer. C stays, the control. A's Status is read
-- while carried. Three game hours later A is put down with
-- ISDropWorldItemAction (what the place cursor queues), B and D with the
-- inventory menu's Drop (onDropItems: ISInventoryTransferAction to the
-- floor). D-015: processing advances only while placed, so A and B must
-- have done the work of their placed hours (the RTP.D015_ checks), and D
-- the work up to the last time the mod found it placed (at most ten
-- minutes before the grab) and from its put-down. Two game hours later,
-- with no Status in between, the readings at the new tiles are compared;
-- then all four are read, and two hours later read again.
------------------------------------------------------------------------------
RT.P = { names = { "A", "B", "C", "D" }, carryAt = 3, carryHours = 3, settleHours = 2, afterHours = 2, tol = 0.01,
    seenBound = 1 / 6 }

function RT.P.free(s) return RT.W.free(s) and RT.W.inRoom(s) end

-- A free room tile with five free room neighbours it can reach, searched
-- outwards from (x0, y0): { the character's tile, A, B, C, D, A's new
-- place }, all within the authority's 2.5 tiles of the first. B and D are
-- dropped where the character stands.
function RT.P.findSpots(x0, y0)
    for r = 0, 80 do
        for dx = -r, r do
            for dy = -r, r do
                local s = math.max(math.abs(dx), math.abs(dy)) == r and sq(x0 + dx, y0 + dy, 0) or nil
                if s and RT.P.free(s) then
                    local out = { s }
                    for ox = -1, 1 do
                        for oy = -1, 1 do
                            local n = (ox ~= 0 or oy ~= 0) and sq(s:getX() + ox, s:getY() + oy, 0) or nil
                            if #out < 6 and RT.P.free(n) and s:canReachTo(n) and not s:isBlockedTo(n) then
                                out[#out + 1] = n
                            end
                        end
                    end
                    if #out == 6 then return out end
                end
            end
        end
    end
    return nil
end

-- The fermenter whose record has process id `pid`, on the character's tile
-- or a neighbour (looked up again after it is put down).
function RT.P.placedById(pid)
    local here = player():getSquare()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = here and sq(here:getX() + dx, here:getY() + dy, 0)
            local objs = s and s:getWorldObjects()
            for j = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(j):getItem()
                local rec = it and it:getModData().tlgProc
                if type(rec) == "table" and rec.id == pid then return it end
            end
        end
    end
    return nil
end

function RT.P.carried(item)
    return item ~= nil and item:getWorldItem() == nil and player():getInventory():getItemWithIDRecursiv(item:getID()) ~= nil
end

-- A grab no Lua sees: the calls of ISGrabItemAction's single-player branch
-- (SRC client/TimedActions/ISGrabItemAction.lua:129-137), made directly.
function RT.P.liftUnseen(item)
    local wi = item:getWorldItem()
    wi:getSquare():transmitRemoveItemFromSquare(wi)
    wi:removeFromWorld()
    wi:removeFromSquare()
    wi:setSquare(nil)
    item:setWorldItem(nil)
    item:setJobDelta(0.0)
    player():getInventory():AddItem(item)
end

function RT.P.maxKey(t)
    local keys = TLG.Tables.sortedKeys(t or {})
    return keys[#keys] or -1
end

-- Hours of readings or notes after hour `h`.
function RT.P.after(t, h)
    local n = 0
    for k in pairs(t or {}) do
        if k > h then n = n + 1 end
    end
    return n
end

-- Readings and notes filed for the moved machines (A, B, D) since their
-- pickups.
function RT.P.newHours(ctx)
    local n = 0
    for _, i in ipairs({ 1, 2, 4 }) do
        local p = RT.P.items[i]:getModData().tlgProc or {}
        n = n + RT.P.after(p.temps, ctx.keys[i].temps) + RT.P.after(p.fires, ctx.keys[i].fires)
    end
    return n
end

-- Whether `after` is the same batch as `before` with every reading and note
-- of `before` unchanged (the hourly reading and the fire notes may add
-- hours); `fields` are compared too.
function RT.P.sameBatch(before, after, fields)
    if type(before) ~= "table" or type(after) ~= "table" then return false, "no record" end
    for _, k in ipairs(fields) do
        if before[k] ~= after[k] then return false, string.format("%s: %s -> %s", k, tostring(before[k]), tostring(after[k])) end
    end
    if brief(before.inputs) ~= brief(after.inputs) then
        return false, string.format("inputs: %s -> %s", brief(before.inputs), brief(after.inputs))
    end
    local n = 0
    for _, f in ipairs({ "temps", "fires" }) do
        for k, v in pairs(before[f] or {}) do
            n = n + 1
            local w = (after[f] or {})[k]
            if brief(v) ~= brief(w) then return false, string.format("%s[%s]: %s -> %s", f, tostring(k), brief(v), brief(w)) end
        end
    end
    return true, string.format("id=%s state=%s pause=%s done=%.4f t=%.4f, %d readings and notes kept", tostring(after.id),
        tostring(after.state), tostring(after.pause), RT.P.work(after), after.t or -1, n)
end

RT.P.BATCH = { "id", "machine", "startedAt", "pausedFor" }
RT.P.WHOLE = { "id", "machine", "startedAt", "pausedFor", "rev", "state", "pause", "stage", "stageDone", "t" }

-- Stage hours done (RT.doneHours on a record).
function RT.P.work(p)
    local done = 0
    for i, st in ipairs(p and p.recipe and p.recipe.params.stages or {}) do
        if i < p.stage then done = done + (st.hours or 0) elseif i == p.stage then done = done + (p.stageDone or 0) end
    end
    return done
end

-- The machine menu on a carried machine: Status offered, everything else
-- replaced by "Place it on the ground to operate it" (greyed).
function RT.P.menuWhileCarried(item)
    local context = ISContextMenu.get(0, 100, 100)
    TLG.UI.MachineMenu.fill(0, context, { item })
    local root = context:getOptionFromName(getText("ContextMenu_TLG_Machine"))
    local sub = root and root.subOption and context:getSubMenu(root.subOption)
    local status = sub and sub:getOptionFromName(getText("ContextMenu_TLG_MachineStatus"))
    local place = sub and sub:getOptionFromName(getText("ContextMenu_TLG_PlaceFirst"))
    local load = sub and sub:getOptionFromName(getText("ContextMenu_TLG_LoadFerment"))
    context:setVisible(false)
    return status ~= nil and not status.notAvailable, place ~= nil and place.notAvailable == true, load == nil
end

-- Every game hour: the game's air at each placed fermenter, filed by hour as
-- the mod files its readings.
function RT.P.onHour()
    local P = RT.P
    if not P.active then return end
    local slot = math.floor(hours() - 0.5)
    for i = 1, #P.names do
        local s = P.items[i] and TLG.Integration.Machines.square(P.items[i])
        local ok, t = pcall(function() return getClimateManager():getAirTemperatureForSquare(s) end)
        if s and ok and type(t) == "number" then P.readings[i][slot] = t end
    end
end

function RT.P.listed(ctx)
    local sites = TLG.World.get().machineSites or {}
    local out = {}
    for i, name in ipairs(RT.P.names) do out[i] = name .. " " .. tostring(sites[ctx.pid[i]] ~= nil) end
    return sites, table.concat(out, ", ")
end

RT.pickSetup = { name = "rtp_sites", timeout = 3000, fn = function(ctx, ticks)
    local P = RT.P
    if not ctx.t0 and RT.skip("rtp_sites") then return true end
    if not ctx.t0 then
        local here = player():getSquare()
        local spots = P.findSpots(here:getX(), here:getY())
        if spots == nil then
            RT.abort = "no free room tile with five free room neighbours nearby"
            R:line("OBS  RTP.spots none found")
            return true
        end
        P.spots, P.items, P.readings = {}, {}, { {}, {}, {}, {} }
        for i, s in ipairs(spots) do P.spots[i] = { x = s:getX(), y = s:getY() } end
        for i = 1, 4 do
            local it = instanceItem("TLG.FermenterVessel")
            spots[i + 1]:AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            P.items[i] = it
        end
        player():setPosition(P.spots[1].x + 0.5, P.spots[1].y + 0.5, 0)
        -- The prepare stage is shortened by Cooking (Process stageHours): at
        -- 0 every stage hour is a game hour.
        player():setPerkLevelDebug(Perks.Cooking, 0)
        local power
        pcall(function() power = getWorld():isHydroPowerOn() end)
        local p = P.spots
        R:line("OBS  RTP.spots character %d,%d; A %d,%d B %d,%d C %d,%d D %d,%d; A goes back down at %d,%d; grid power=%s",
            p[1].x, p[1].y, p[2].x, p[2].y, p[3].x, p[3].y, p[4].x, p[4].y, p[5].x, p[5].y, p[6].x, p[6].y, tostring(power))
        R:check("RTP.grid_is_on", function() return power == true, "isHydroPowerOn=" .. tostring(power) end)
        if not P.hooked then
            Events.EveryHours.Add(RT.P.onHour)
            P.hooked = true
        end
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 60 then return nil end
    local seen = {}
    for i = 1, 6 do seen[i] = tostring(TLG.Integration.Machines.siteOf(sq(P.spots[i].x, P.spots[i].y, 0)).room) end
    R:check("RTP.all_in_a_room", function()
        return table.concat(seen, ",") == "true,true,true,true,true,true", "in a room: " .. table.concat(seen, ",")
    end)
    return true
end }

-- The phases of rtp_run, in order; each returns true to end the step.
RT.P.phases = {}

function RT.P.phases.load(ctx)
    local P = RT.P
    removeAll("Base.Sugar"); removeAll("Base.Yeast")
    for i, name in ipairs(P.names) do
        give("Base.Sugar", 6); give("Base.Yeast", 1)
        for _ = 1, 3 do
            local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
            fc:Empty()
            fc:addFluid(Fluid.Water, 10)
        end
        local r = machineClick("RTP.load_" .. name, P.items[i], "ContextMenu_TLG_LoadFerment")
        R:check("RTP.loaded_" .. name, function()
            return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6,
                string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
        end)
    end
    closeDialogs()
    P.active = true
    ctx.h0, ctx.pid, ctx.keys, ctx.rec0, ctx.tPick, ctx.tDrop = hours(), {}, {}, {}, {}, {}
    for i = 1, 4 do
        local rec = P.items[i]:getModData().tlgProc or {}
        ctx.pid[i] = rec.id
    end
    local recA = P.items[1]:getModData().tlgProc or {}
    R:line("OBS  RTP.loaded at %.4f game h: process ids %s %s %s %s; skill in the record %s", ctx.h0, tostring(ctx.pid[1]),
        tostring(ctx.pid[2]), tostring(ctx.pid[3]), tostring(ctx.pid[4]), tostring(recA.skill))
    ctx.phase = "wait"
end

function RT.P.phases.wait(ctx)
    RT.speed(RT.waitSpeed)
    if hours() - ctx.h0 < RT.P.carryAt then return end
    RT.speed(1)
    ctx.phase = "grabA"
end

-- Queues a pickup or drop once, then waits for the character to be idle;
-- `seen` reports the moment the item changed place (first tick seen).
function RT.P.action(ctx, ticks, key, start, seen)
    local a = ctx[key]
    if not a then
        ctx[key] = { tick = ticks }
        start()
        return false
    end
    RT.speed(1)
    if not a.at and seen() then a.at = hours() end
    return ticks - a.tick >= 10 and TLGH.Steps.actionsIdle(player())
end

function RT.P.before(ctx, i)
    local rec = TLG.Tables.deepCopy(RT.P.items[i]:getModData().tlgProc)
    ctx.rec0[i] = rec
    ctx.keys[i] = { temps = RT.P.maxKey(rec.temps), fires = RT.P.maxKey(rec.fires) }
end

function RT.P.phases.grabA(ctx, ticks)
    local P, A = RT.P, RT.P.items[1]
    local idle = P.action(ctx, ticks, "grabA", function()
        P.before(ctx, 1)
        ISWorldObjectContextMenu.onGrabWItem(nil, A:getWorldItem(), 0)
    end, function() return A:getWorldItem() == nil end)
    if idle then ctx.phase = "grabB" end
end

function RT.P.phases.grabB(ctx, ticks)
    local P, B = RT.P, RT.P.items[2]
    local idle = P.action(ctx, ticks, "grabB", function()
        P.before(ctx, 2)
        -- The loot window lists the floor items around the character
        -- (ISInventoryPage.refreshBackpacks); its Grab takes them from there.
        pcall(function() getPlayerLoot(0):refreshBackpacks() end)
        ctx.lootListed = B:getContainer() == ISInventoryPage.GetFloorContainer(0)
        R:line("OBS  RTP.grab_B the loot window lists B on the floor=%s", tostring(ctx.lootListed))
        if ctx.lootListed then
            ISInventoryPaneContextMenu.onGrabItems({ B }, 0)
        else
            ISWorldObjectContextMenu.onGrabWItem(nil, B:getWorldItem(), 0)
        end
    end, function() return B:getWorldItem() == nil end)
    if idle then ctx.phase = "grabD" end
end

function RT.P.phases.grabD(ctx)
    local P = RT.P
    P.before(ctx, 4)
    local ok, err = pcall(P.liftUnseen, P.items[4])
    ctx.tPick[4] = hours()
    R:line("OBS  RTP.grab_D lifted without the game's Lua: ok=%s %s", tostring(ok), tostring(err or ""))
    ctx.phase = "carried"
end

function RT.P.phases.carried(ctx)
    local P = RT.P
    local A, B, D = P.items[1], P.items[2], P.items[4]
    ctx.tPick[1], ctx.tPick[2] = ctx.grabA.at, ctx.grabB.at
    R:line("OBS  RTP.picked up A at %s, B at %s, D at %s game h (load %.4f)", tostring(ctx.tPick[1]), tostring(ctx.tPick[2]),
        tostring(ctx.tPick[4]), ctx.h0)
    R:check("RTP.picked_up_A_world_menu_grab", function()
        return P.carried(A) and ctx.tPick[1] ~= nil, "carried=" .. tostring(P.carried(A))
    end)
    R:check("RTP.picked_up_B_loot_window_grab", function()
        return P.carried(B) and ctx.tPick[2] ~= nil and ctx.lootListed == true,
            string.format("carried=%s listed in the loot window=%s", tostring(P.carried(B)), tostring(ctx.lootListed))
    end)
    R:check("RTP.picked_up_D_unseen", function() return P.carried(D), "carried=" .. tostring(P.carried(D)) end)
    if not (P.carried(A) and P.carried(B) and P.carried(D) and ctx.tPick[1] and ctx.tPick[2]) then
        RT.abort = "a fermenter was not picked up"
        return true
    end
    -- A and B: counted up to the pickup, then paused; D: the mod did not see it.
    for i = 1, 2 do
        local p = P.items[i]:getModData().tlgProc
        R:check("RTP.pickup_pauses_" .. P.names[i], function()
            local ok, detail = P.sameBatch(ctx.rec0[i], p, P.BATCH)
            return ok and p.state == "Paused" and p.pause == "not_placed" and math.abs((p.t or 0) - ctx.tPick[i]) <= P.tol,
                string.format("%s; picked up at %.4f", detail, ctx.tPick[i])
        end)
    end
    R:check("RTP.D015_B_placed_hours_before_pickup_count", function()
        local done, want = P.work(B:getModData().tlgProc), ctx.tPick[2] - ctx.h0
        return math.abs(done - want) <= P.tol, string.format("done %.4f h at the pickup, placed %.4f h", done, want)
    end)
    R:check("RTP.unseen_pickup_changes_nothing_yet", function()
        return P.sameBatch(ctx.rec0[4], D:getModData().tlgProc, P.WHOLE)
    end)
    local sites, listed = P.listed(ctx)
    R:check("RTP.hourly_list_at_pickup", function()
        return sites[ctx.pid[1]] == nil and sites[ctx.pid[2]] == nil and sites[ctx.pid[3]] ~= nil and sites[ctx.pid[4]] ~= nil,
            "listed: " .. listed
    end)
    local status, place, noLoad = P.menuWhileCarried(A)
    R:check("RTP.menu_while_carried", function()
        return status and place and noLoad,
            string.format("status offered=%s place first greyed=%s load mash gone=%s", tostring(status), tostring(place),
                tostring(noLoad))
    end)
    local before = #H.dialogs.texts
    local r = machineClick("RTP.status_A_carried", A, "ContextMenu_TLG_MachineStatus")
    local text = H.dialogs.texts[before + 1]
    closeDialogs()
    ctx.doneA1 = RT.doneHours(A)
    R:check("RTP.carried_status_paused", function()
        return r.ok == true and r.state == "Paused" and r.pause == "not_placed" and has(text, getText("IGUI_TLG_Pause_not_placed")),
            string.format("state=%s pause=%s dialog=%s", tostring(r.state), tostring(r.pause), tostring(text))
    end)
    -- D-015: the hours A stood placed before it was picked up count.
    R:check("RTP.D015_A_placed_hours_before_pickup_count", function()
        local want = ctx.tPick[1] - ctx.h0
        return math.abs(ctx.doneA1 - want) <= P.tol, string.format("done %.4f h after the carried status, placed %.4f h", ctx.doneA1,
            want)
    end)
    ctx.phase = "carry"
end

function RT.P.phases.carry(ctx)
    local P = RT.P
    local last = math.max(ctx.tPick[1], ctx.tPick[2], ctx.tPick[4])
    RT.speed(RT.waitSpeed)
    -- The first hourly reading after the pickups finds D's tile empty.
    if not ctx.listChecked and hours() >= math.floor(last) + 1.05 then
        local sites, listed = P.listed(ctx)
        R:check("RTP.hourly_list_drops_unseen_machine", function()
            return sites[ctx.pid[4]] == nil and sites[ctx.pid[3]] ~= nil, "listed: " .. listed
        end)
        ctx.listChecked = true
    end
    if hours() - last < P.carryHours then return end
    RT.speed(1)
    R:check("RTP.nothing_filed_while_carried", function()
        local n = P.newHours(ctx)
        return n == 0, string.format("%d readings or notes after the pickups, %.2f game h carried", n, hours() - last)
    end)
    ctx.phase = "dropA"
end

function RT.P.phases.dropA(ctx, ticks)
    local P = RT.P
    local A = P.items[1]
    local idle = P.action(ctx, ticks, "dropA", function()
        ctx.rec1 = { TLG.Tables.deepCopy(A:getModData().tlgProc) }
        local p = P.spots[6]
        ISTimedActionQueue.add(ISDropWorldItemAction:new(player(), A, sq(p.x, p.y, 0), 0.5, 0.5, 0, 0, false))
    end, function()
        local it = P.placedById(ctx.pid[1])
        if it then P.items[1] = it end
        return it ~= nil
    end)
    if idle then ctx.phase = "dropB" end
end

-- The inventory menu's Drop for machine i, onto the character's tile.
function RT.P.drop(ctx, ticks, i, key, nextPhase)
    local P = RT.P
    local item = P.items[i]
    local idle = P.action(ctx, ticks, key, function()
        ctx.rec1[i] = TLG.Tables.deepCopy(item:getModData().tlgProc)
        ISInventoryPaneContextMenu.onDropItems({ item }, 0)
    end, function()
        local it = P.placedById(ctx.pid[i])
        if it then P.items[i] = it end
        return it ~= nil
    end)
    if idle then ctx.phase = nextPhase end
end

function RT.P.phases.dropB(ctx, ticks) RT.P.drop(ctx, ticks, 2, "dropB", "dropD") end

function RT.P.phases.dropD(ctx, ticks) RT.P.drop(ctx, ticks, 4, "dropD", "dropped") end

function RT.P.phases.dropped(ctx)
    local P, M = RT.P, TLG.Integration.Machines
    ctx.tDrop[1], ctx.tDrop[2], ctx.tDrop[4] = ctx.dropA.at, ctx.dropB.at, ctx.dropD.at
    local function at(s) return s and string.format("%d,%d", s:getX(), s:getY()) or "-" end
    local tile = {}
    for _, i in ipairs({ 1, 2, 4 }) do tile[i] = M.square(P.items[i]) end
    R:line("OBS  RTP.put down A at %s (%s game h), B at %s (%s), D at %s (%s)", at(tile[1]), tostring(ctx.tDrop[1]), at(tile[2]),
        tostring(ctx.tDrop[2]), at(tile[4]), tostring(ctx.tDrop[4]))
    R:check("RTP.put_down_A_place_action", function()
        return tile[1] ~= nil and ctx.tDrop[1] ~= nil and tile[1]:getX() == P.spots[6].x and tile[1]:getY() == P.spots[6].y, "at " .. at(tile[1])
    end)
    R:check("RTP.put_down_B_inventory_drop", function()
        return tile[2] ~= nil and ctx.tDrop[2] ~= nil and (tile[2]:getX() ~= P.spots[3].x or tile[2]:getY() ~= P.spots[3].y),
            "at " .. at(tile[2])
    end)
    R:check("RTP.put_down_D_inventory_drop", function()
        return tile[4] ~= nil and ctx.tDrop[4] ~= nil and (tile[4]:getX() ~= P.spots[5].x or tile[4]:getY() ~= P.spots[5].y),
            "at " .. at(tile[4])
    end)
    if not (tile[1] and tile[2] and tile[4] and ctx.tDrop[1] and ctx.tDrop[2] and ctx.tDrop[4]) then
        RT.abort = "a fermenter was not put down"
        return true
    end
    -- A and B start again from the put-down, the work they had kept, listed
    -- at their new tiles at once.
    local sites = TLG.World.get().machineSites or {}
    for _, i in ipairs({ 1, 2 }) do
        local p = P.items[i]:getModData().tlgProc
        R:check("RTP.put_down_resumes_" .. P.names[i], function()
            local ok, detail = P.sameBatch(ctx.rec1[i], p, { "id", "machine", "startedAt", "pausedFor", "stage", "stageDone" })
            local e = sites[ctx.pid[i]]
            return ok and p.state == "Processing" and p.pause == nil and math.abs((p.t or 0) - ctx.tDrop[i]) <= P.tol
                and p.site and p.site.x == tile[i]:getX() and p.site.y == tile[i]:getY() and e ~= nil and e.x == tile[i]:getX()
                and e.y == tile[i]:getY(), string.format("%s; site %s,%s; listed %s", detail, tostring(p.site and p.site.x),
                tostring(p.site and p.site.y), e and (e.x .. "," .. e.y) or "-")
        end)
    end
    -- D: found moved at its put-down; counted up to the last time it was
    -- found placed before the grab, then from the put-down.
    local seenD = ctx.rec1[4] and ctx.rec1[4].seen
    local pD = P.items[4]:getModData().tlgProc
    local e = sites[ctx.pid[4]]
    ctx.seenD = seenD
    R:check("RTP.unseen_pickup_credited_up_to_last_seen", function()
        local done = P.work(pD)
        local short = ctx.tPick[4] - (seenD or -99)
        return seenD ~= nil and short >= -1e-6 and short <= P.seenBound + P.tol and math.abs(done - (seenD - ctx.h0)) <= 1e-6
            and pD.state == "Processing" and math.abs((pD.t or 0) - ctx.tDrop[4]) <= P.tol and e ~= nil and e.x == tile[4]:getX(),
            string.format("last seen %s, %.4f h before the grab; done %.4f h, seen - load %.4f h; state=%s t=%.4f listed %s",
                tostring(seenD), short, done, (seenD or 0) - ctx.h0, tostring(pD.state), pD.t or -1, e and (e.x .. "," .. e.y) or "-")
    end)
    ctx.doneDrop = {}
    for i = 1, 4 do ctx.doneDrop[i] = RT.doneHours(P.items[i]) end
    ctx.phase = "settle"
end

function RT.P.phases.settle(ctx)
    local P = RT.P
    RT.speed(RT.waitSpeed)
    if hours() - math.max(ctx.tDrop[1], ctx.tDrop[2], ctx.tDrop[4]) < P.settleHours then return end
    RT.speed(1)
    -- No Status since the put-down: the hourly reading and the notes found
    -- them at their new tiles anyway.
    local n, worst, where, notes = 0, 0, "none", {}
    for _, i in ipairs({ 1, 2, 4 }) do
        local rec = P.items[i]:getModData().tlgProc or {}
        local from = math.floor(ctx.tDrop[i])
        for _, s in ipairs(TLG.Tables.sortedKeys(P.readings[i])) do
            if s >= from then
                local filed = rec.temps and rec.temps[s]
                local d = filed and math.abs(filed - P.readings[i][s]) or 999
                n = n + 1
                if d >= worst then
                    worst, where = d, string.format("%s hour %d: filed %s, game %.4f", P.names[i], s, tostring(filed),
                        P.readings[i][s])
                end
            end
        end
        notes[#notes + 1] = string.format("%s %d", P.names[i], P.after(rec.fires, from - 1))
    end
    R:check("RTP.read_hourly_after_put_down", function()
        return n >= 6 and worst <= 1e-6, string.format("%d hours, worst %.6f (%s)", n, worst, where)
    end)
    R:check("RTP.fire_notes_after_put_down", function()
        local ok = true
        for _, i in ipairs({ 1, 2, 4 }) do
            local rec = P.items[i]:getModData().tlgProc or {}
            ok = ok and P.after(rec.fires, math.floor(ctx.tDrop[i]) - 1) >= 2
        end
        return ok, "hours noted since the put-down: " .. table.concat(notes, ", ")
    end)
    ctx.phase = "read"
end

function RT.P.phases.read(ctx)
    local P = RT.P
    local replies, texts, done = {}, {}, {}
    for i, name in ipairs(P.names) do
        local before = #H.dialogs.texts
        replies[i] = machineClick("RTP.status_" .. name, P.items[i], "ContextMenu_TLG_MachineStatus")
        texts[i] = H.dialogs.texts[before + 1]
        done[i] = RT.doneHours(P.items[i])
    end
    closeDialogs()
    local now = hours()
    ctx.tEnd, ctx.doneEnd = now, done
    R:line("OBS  RTP.read at %.4f game h, %.4f h after the load: done A %.4f B %.4f C %.4f D %.4f h; carried A %.4f B %.4f D %.4f h",
        now, now - ctx.h0, done[1], done[2], done[3], done[4], ctx.tDrop[1] - ctx.tPick[1], ctx.tDrop[2] - ctx.tPick[2],
        ctx.tDrop[4] - ctx.tPick[4])
    R:check("RTP.control_C_full_rate", function()
        return math.abs(done[3] - (now - ctx.h0)) <= P.tol, string.format("done %.4f h in %.4f game h", done[3], now - ctx.h0)
    end)
    R:check("RTP.D015_A_placed_hours_after_put_down_count", function()
        local want = now - ctx.tDrop[1]
        return math.abs(done[1] - ctx.doneA1 - want) <= P.tol,
            string.format("done %.4f h since the carried status, placed %.4f h since put down", done[1] - ctx.doneA1, want)
    end)
    R:check("RTP.D015_B_carried_hours_do_not_count", function()
        local placed = (ctx.tPick[2] - ctx.h0) + (now - ctx.tDrop[2])
        return math.abs(done[2] - placed) <= P.tol, string.format("done %.4f h, placed %.4f h, carried %.4f h", done[2], placed,
            ctx.tDrop[2] - ctx.tPick[2])
    end)
    R:check("RTP.unseen_move_carried_hours_do_not_count", function()
        local want = (ctx.seenD - ctx.h0) + (now - ctx.tDrop[4])
        return math.abs(done[4] - want) <= P.tol, string.format("done %.4f h: %.4f h up to the last seen and %.4f h since put down",
            done[4], ctx.seenD - ctx.h0, now - ctx.tDrop[4])
    end)
    R:check("RTP.processing_after_put_down", function()
        local ok, parts = true, {}
        for i, name in ipairs(P.names) do
            ok = ok and replies[i].state == "Processing"
            parts[i] = name .. " " .. tostring(replies[i].state)
        end
        return ok, table.concat(parts, " ")
    end)
    R:line("OBS  RTP.status A: %s | B: %s | C: %s | D: %s", tostring(texts[1]), tostring(texts[2]), tostring(texts[3]),
        tostring(texts[4]))
    ctx.phase = "after"
end

function RT.P.phases.after(ctx)
    local P = RT.P
    RT.speed(RT.waitSpeed)
    if hours() - ctx.tEnd < P.afterHours then return end
    RT.speed(1)
    P.active = false
    local d = {}
    for i = 1, 4 do
        RT.statusOf(P.items[i])
        d[i] = RT.doneHours(P.items[i]) - ctx.doneEnd[i]
    end
    R:check("RTP.progress_like_the_control_after_the_move", function()
        return math.abs(d[1] - d[3]) <= 1e-6 and math.abs(d[2] - d[3]) <= 1e-6 and math.abs(d[4] - d[3]) <= 1e-6,
            string.format("in %.4f game h: A %.4f B %.4f C %.4f D %.4f h", hours() - ctx.tEnd, d[1], d[2], d[3], d[4])
    end)
    return true
end

RT.pickRun = { name = "rtp_run", timeout = 60000, fn = function(ctx, ticks)
    if not ctx.phase and RT.skip("rtp_run") then return true end
    if ticks % 30 == 0 then RT.keepFit() end
    return RT.P.phases[ctx.phase or "load"](ctx, ticks) == true
end }

RT.pickupSteps = { RT.waitWorld, RT.setup, RT.pickSetup, RT.pickRun, RT.finish }

------------------------------------------------------------------------------
-- Pot still (request "sp-rtpot"): the ethanol loop through the pot still
-- (gate 1). Summer with the grid on: a fermenter, a pot still and a drying
-- column on room tiles around the character (RT.P.findSpots), so the batch
-- ferments at full rate for 97 h. 12 kg of sugar and 60 L of water make
-- 66.6 L of wash, more than the pot still's 60 L: "Load wash" twice, the
-- first leaving the rest in the fermenter, the second run short enough for
-- the stage's 1 h minimum. The firebox gets one log first, which runs out
-- mid-distillation; an hour later four logs are offered and three fit.
-- Every quantity is checked against the definitions (Content/Production:
-- recovery 0.88, purity 0.80, 8 L/h, 6 kW from wood at 4.2 kWh/kg and 45 %,
-- the efficiency of the still's condition before each batch). Both runs'
-- spirit goes into one can, which is evaluated against every spark-ignition
-- profile with Consumers.evaluate, the function the start gates call; then
-- it is dried with quicklime and evaluated again.
------------------------------------------------------------------------------
RT.D = { names = { "fermenter", "pot still", "drying column" }, sugar = 12, water = 60, tol = 1e-6,
    sparks = { "engine_si_stock", "engine_si_flex", "generator_si_stock", "generator_si_flex" } }

-- The pot still and the heat its stages draw, from the definitions.
function RT.D.def()
    local m = TLG.Registry.need("machine", "pot_still")
    local heat = TLG.Registry.need("recipe", "ethanol_distill").stages[1].heatKW
    return m, heat / (m.firebox.kwhPerKg * m.firebox.efficiency)
end

function RT.D.rec(i) return RT.D.items[i]:getModData().tlgProc or {} end

-- What a run of `wash` (ethanol, water) gives in a still at condition `cond`
-- (Process.converters.distill and completeBatch).
function RT.D.expected(eth, water, cond)
    local m, burn = RT.D.def()
    local out = eth * m.recovery * (1 - 0.3 * (1 - cond))
    return { hours = 1 + math.max(1, (eth + water) / m.throughputLph), ethanol = out,
        water = out * (1 - m.purity) / m.purity, burn = burn }
end

function RT.D.near(a, b, tol) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or RT.D.tol) end

-- Status through the menu, with the dialog text the player reads.
function RT.D.statusText(i)
    local before = #H.dialogs.texts
    local r = machineClick("RTPOT.status_" .. string.gsub(RT.D.names[i], " ", "_"), RT.D.items[i], "ContextMenu_TLG_MachineStatus")
    local text = H.dialogs.texts[before + 1]
    closeDialogs()
    return r, text
end

-- The start gates' verdict on a can, per spark-ignition profile.
function RT.D.verdicts(can)
    local v = tlgView("item", can)
    local out, parts = {}, {}
    for _, id in ipairs(RT.D.sparks) do
        local e = v and TLG.Domain.Consumers.evaluate(id, v) or { compatible = false, reasons = { "no_record" } }
        out[id] = e
        parts[#parts + 1] = string.format("%s %s (%s)", id, e.compatible and "fit" or "unfit", table.concat(e.reasons, ","))
    end
    return out, table.concat(parts, "; "), v
end

-- A finished machine's Status: its kind's own state line and no stage (run
-- 28 showed "Stage: fermenting" on finished wash).
function RT.D.finishedText(text, stateKey)
    return has(text, getText(stateKey)) and not has(text, getText("IGUI_TLG_Stage", ""))
end

function RT.D.hasReason(e, code)
    for _, r in ipairs(e.reasons or {}) do
        if r == code then return true end
    end
    return false
end

RT.potSetup = { name = "rtpot_sites", timeout = 3000, fn = function(ctx, ticks)
    local D = RT.D
    if not ctx.t0 and RT.skip("rtpot_sites") then return true end
    if not ctx.t0 then
        local here = player():getSquare()
        local spots = RT.P.findSpots(here:getX(), here:getY())
        if spots == nil then
            RT.abort = "no free room tile with free room neighbours nearby"
            R:line("OBS  RTPOT.spots none found")
            return true
        end
        D.spots, D.items = {}, {}
        for i, s in ipairs(spots) do D.spots[i] = { x = s:getX(), y = s:getY() } end
        for i, t in ipairs({ "TLG.FermenterVessel", "TLG.PotStill", "TLG.DryingColumn" }) do
            local it = instanceItem(t)
            spots[i + 1]:AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            D.items[i] = it
        end
        player():setPosition(D.spots[1].x + 0.5, D.spots[1].y + 0.5, 0)
        -- Purity and the prepare stage follow Cooking (Process): at 0, 0.80 and 1 h.
        player():setPerkLevelDebug(Perks.Cooking, 0)
        local power
        pcall(function() power = getWorld():isHydroPowerOn() end)
        local p = D.spots
        R:line("OBS  RTPOT.spots character %d,%d; fermenter %d,%d pot still %d,%d drying column %d,%d; grid power=%s", p[1].x,
            p[1].y, p[2].x, p[2].y, p[3].x, p[3].y, p[4].x, p[4].y, tostring(power))
        R:check("RTPOT.grid_is_on", function() return power == true, "isHydroPowerOn=" .. tostring(power) end)
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 60 then return nil end
    local seen = {}
    for i = 1, 4 do seen[i] = tostring(TLG.Integration.Machines.siteOf(sq(D.spots[i].x, D.spots[i].y, 0)).room) end
    R:check("RTPOT.all_in_a_room", function()
        return table.concat(seen, ",") == "true,true,true,true", "in a room: " .. table.concat(seen, ",")
    end)
    return true
end }

RT.D.phases = {}

function RT.D.phases.ferment(ctx)
    local D = RT.D
    for _, t in ipairs({ "Base.Sugar", "Base.Yeast", "Base.Log", "Base.Quicklime" }) do removeAll(t) end
    give("Base.Sugar", D.sugar); give("Base.Yeast", 1)
    -- RT.setup gave three 10 L buckets; three more make the 60 L the load takes.
    for _ = 1, 3 do
        local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
        fc:Empty()
        fc:addFluid(Fluid.Water, 10)
    end
    local r = machineClick("RTPOT.load_mash", D.items[1], "ContextMenu_TLG_LoadFerment")
    R:check("RTPOT.mash_loaded", function()
        return r.ok == true and D.near(r.sugarKg, D.sugar) and D.near(r.waterL, D.water),
            string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
    end)
    closeDialogs()
    ctx.h0 = hours()
    ctx.phase = "fermenting"
end

function RT.D.phases.fermenting(ctx)
    local D = RT.D
    RT.speed(RT.waitSpeed)
    if hours() - ctx.h0 < 97.05 then return end
    RT.speed(1)
    local s = RT.statusOf(D.items[1])
    local rec = D.rec(1)
    local f = TLG.Registry.need("recipe", "ethanol_ferment").params
    ctx.eth0 = D.sugar * f.ethanolYieldLPerKg
    R:check("RTPOT.fermented_full_rate", function()
        return s.state == "OutputReady" and D.near(rec.completedAt, ctx.h0 + 97) and D.near((rec.outputs or {}).ethanol, ctx.eth0)
            and D.near((rec.outputs or {}).water, D.water), string.format("state=%s done at %.4f h after loading; outputs %s",
            tostring(s.state), (rec.completedAt or -1) - ctx.h0, brief(rec.outputs))
    end)
    if s.state ~= "OutputReady" then
        RT.abort = "the fermentation did not finish"
        return true
    end
    ctx.phase = "load1"
end

-- Feeds the firebox through the menu with `logs` logs carried (all wood
-- removed first).
function RT.D.feed(label, logs)
    removeAll("Base.Log")
    give("Base.Log", logs)
    return machineClick(label, RT.D.items[2], "ContextMenu_TLG_AddFirewood")
end

function RT.D.phases.load1(ctx)
    local D = RT.D
    local m = D.def()
    local fuel = D.feed("RTPOT.feed_one_log", 1)
    R:check("RTPOT.firebox_one_log", function()
        return fuel.ok == true and D.near(fuel.addedKg, 9), "added kg " .. tostring(fuel.addedKg)
    end)
    ctx.starters = countType("TLG.YeastStarter")
    ctx.cond1 = D.rec(2).cond or 1
    local w = machineClick("RTPOT.load_wash_1", D.items[2], "ContextMenu_TLG_LoadWash")
    ctx.t1 = hours()
    closeDialogs()
    local frac = m.capacity / (ctx.eth0 + D.water)
    ctx.wash1 = { ethanol = ctx.eth0 * frac, water = D.water * frac }
    local fr = D.rec(1)
    local left = fr.outputs or {}
    R:check("RTPOT.first_load_fills_the_still", function()
        return w.ok == true and D.near(w.washL, m.capacity) and fr.state == "OutputReady" and fr.pause == "output_full"
            and D.near(left.ethanol, ctx.eth0 - ctx.wash1.ethanol) and D.near(left.water, D.water - ctx.wash1.water),
            string.format("wash %s L; fermenter %s/%s keeps %s", tostring(w.washL), tostring(fr.state), tostring(fr.pause), brief(left))
    end)
    R:check("RTPOT.no_starter_before_the_last_wash", function()
        return countType("TLG.YeastStarter") == ctx.starters, string.format("%d -> %d", ctx.starters, countType("TLG.YeastStarter"))
    end)
    local _, text = D.statusText(1)
    R:check("RTPOT.fermenter_status_with_wash_left", function()
        return D.finishedText(text, "IGUI_TLG_MachineState_OutputReady_fermenter")
            and has(text, getText("IGUI_TLG_Pause_output_full_fermenter")), tostring(text)
    end)
    ctx.next, ctx.phase = hours() + 0.1, "run1"
end

-- Status every 0.1 game hours until the still's batch is ready; `onPoll`
-- may act on each reply.
function RT.D.poll(ctx, onPoll)
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return nil end
    ctx.next = hours() + 0.1
    local s = RT.statusOf(RT.D.items[2])
    if onPoll then onPoll(s) end
    return s
end

function RT.D.phases.run1(ctx)
    local D = RT.D
    local e = D.expected(ctx.wash1.ethanol, ctx.wash1.water, ctx.cond1)
    local s = D.poll(ctx, function(s)
        if s.pause == "no_heat" and not ctx.tOut then
            ctx.tOut = hours()
            RT.speed(1)
            local r, text = D.statusText(2)
            ctx.outText = text
            R:check("RTPOT.firebox_runs_out_mid_run", function()
                local due = ctx.t1 + 9 / e.burn
                return r.state == "Paused" and r.pause == "no_heat" and has(text, getText("IGUI_TLG_Pause_no_heat"))
                    and ctx.tOut >= due - D.tol and ctx.tOut <= due + 0.1 + 0.01,
                    string.format("seen %.4f h after loading (fuel for %.4f h); dialog=%s", ctx.tOut - ctx.t1, 9 / e.burn, tostring(text))
            end)
        end
        if ctx.tOut and not ctx.tRefeed and hours() >= ctx.tOut + 1 then
            RT.speed(1)
            local fuel = D.feed("RTPOT.feed_four_logs", 4)
            ctx.tRefeed = hours()
            R:check("RTPOT.firebox_takes_what_fits", function()
                return fuel.ok == true and D.near(fuel.addedKg, 27) and countType("Base.Log") == 1,
                    string.format("added kg %s, logs left %d", tostring(fuel.addedKg), countType("Base.Log"))
            end)
        end
    end)
    if s == nil or (s.state ~= "OutputReady" and s.state ~= "Faulted" and hours() - ctx.t1 < 30) then return end
    RT.speed(1)
    local rec = D.rec(2)
    local o = rec.outputs or {}
    local fed = 9 + 27
    R:check("RTPOT.run1_paused_only_without_fuel", function()
        local want = (ctx.tRefeed or 0) - (ctx.t1 + 9 / e.burn)
        return ctx.tRefeed ~= nil and D.near(rec.pausedFor, want), string.format("paused %.6f h, out of fuel %.6f h",
            rec.pausedFor or -1, want)
    end)
    R:check("RTPOT.run1_hours", function()
        return D.near(rec.completedAt, ctx.t1 + e.hours + (rec.pausedFor or 0)),
            string.format("done %.6f h after loading: %.4f h of stages + %.6f h paused", (rec.completedAt or -1) - ctx.t1, e.hours,
                rec.pausedFor or -1)
    end)
    R:check("RTPOT.run1_firebox", function()
        return D.near(rec.firebox, fed - e.hours * e.burn), string.format("left %.6f kg, expected %.6f (%.4f kg/h)", rec.firebox or -1,
            fed - e.hours * e.burn, e.burn)
    end)
    R:check("RTPOT.run1_spirit", function()
        return rec.state == "OutputReady" and D.near(o.ethanol, e.ethanol) and D.near(o.water, e.water),
            string.format("ethanol %.6f (%.6f) water %.6f (%.6f); condition %.4f", o.ethanol or -1, e.ethanol, o.water or -1, e.water,
                rec.cond or -1)
    end)
    local _, text = D.statusText(2)
    R:check("RTPOT.still_status_when_finished", function()
        return D.finishedText(text, "IGUI_TLG_MachineState_OutputReady_still"), tostring(text)
    end)
    ctx.run1 = e
    ctx.phase = "collect1"
end

function RT.D.phases.collect1(ctx)
    local D = RT.D
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    machineClick("RTPOT.collect_1", D.items[2], "ContextMenu_TLG_CollectEthanol")
    closeDialogs()
    ctx.can = grownCan(before)
    local v = ctx.can and tlgView("item", ctx.can)
    R:check("RTPOT.run1_bottled", function()
        local q = v and v.q or {}
        return v ~= nil and D.near(q.ethanol, ctx.run1.ethanol, 1e-3) and D.near(q.water, ctx.run1.water, 1e-3)
            and D.rec(2).state == "Ready", string.format("%s; still %s", viewText(v, "can"), tostring(D.rec(2).state))
    end)
    if not ctx.can then
        RT.abort = "the first run was not bottled"
        return true
    end
    ctx.phase = "load2"
end

function RT.D.phases.load2(ctx)
    local D = RT.D
    ctx.cond2 = D.rec(2).cond or 1
    ctx.fire2 = D.rec(2).firebox or 0
    ctx.wash2 = { ethanol = ctx.eth0 - ctx.wash1.ethanol, water = D.water - ctx.wash1.water }
    local before = countType("TLG.YeastStarter")
    local w = machineClick("RTPOT.load_wash_2", D.items[2], "ContextMenu_TLG_LoadWash")
    ctx.t2 = hours()
    closeDialogs()
    local fr = D.rec(1)
    R:check("RTPOT.second_load_takes_the_rest", function()
        return w.ok == true and D.near(w.washL, ctx.wash2.ethanol + ctx.wash2.water) and fr.state == "Ready"
            and countType("TLG.YeastStarter") == before + 1, string.format("wash %s L; fermenter %s; yeast starters %d -> %d",
            tostring(w.washL), tostring(fr.state), before, countType("TLG.YeastStarter"))
    end)
    R:check("RTPOT.firebox_carries_over", function()
        return D.near(D.rec(2).firebox, ctx.fire2) and D.near(ctx.cond2, 1 - D.def().wearPerBatch),
            string.format("firebox %.6f kg (%.6f before); condition %.4f", D.rec(2).firebox or -1, ctx.fire2, ctx.cond2)
    end)
    ctx.next, ctx.phase = hours() + 0.1, "run2"
end

function RT.D.phases.run2(ctx)
    local D = RT.D
    local e = D.expected(ctx.wash2.ethanol, ctx.wash2.water, ctx.cond2)
    local s = D.poll(ctx)
    if s == nil or (s.state ~= "OutputReady" and s.state ~= "Faulted" and hours() - ctx.t2 < 10) then return end
    RT.speed(1)
    local rec = D.rec(2)
    local o = rec.outputs or {}
    R:check("RTPOT.run2_minimum_hour", function()
        return D.near(e.hours, 2) and D.near(rec.completedAt, ctx.t2 + 2) and D.near(rec.pausedFor, 0),
            string.format("done %.6f h after loading (%.4f L of wash at 8 L/h, at least 1 h), paused %.6f", (rec.completedAt or -1) - ctx.t2,
                ctx.wash2.ethanol + ctx.wash2.water, rec.pausedFor or -1)
    end)
    R:check("RTPOT.run2_spirit_after_wear", function()
        return D.near(o.ethanol, e.ethanol) and D.near(o.water, e.water) and D.near(rec.firebox, ctx.fire2 - 2 * e.burn)
            and D.near(rec.cond, ctx.cond2 - D.def().wearPerBatch), string.format(
            "ethanol %.6f (%.6f at condition %.2f) water %.6f (%.6f); firebox %.6f kg; condition %.4f", o.ethanol or -1, e.ethanol,
            ctx.cond2, o.water or -1, e.water, rec.firebox or -1, rec.cond or -1)
    end)
    ctx.run2 = e
    ctx.phase = "collect2"
end

function RT.D.phases.collect2(ctx)
    local D = RT.D
    machineClick("RTPOT.collect_2", D.items[2], "ContextMenu_TLG_CollectEthanol")
    closeDialogs()
    local verdicts, text, v = D.verdicts(ctx.can)
    local q = v and v.q or {}
    ctx.potEth, ctx.potWater = ctx.run1.ethanol + ctx.run2.ethanol, ctx.run1.water + ctx.run2.water
    R:check("RTPOT.both_runs_in_one_can", function()
        return D.near(q.ethanol, ctx.potEth, 1e-3) and D.near(q.water, ctx.potWater, 1e-3),
            string.format("%s; expected ethanol %.6f water %.6f", viewText(v, "can"), ctx.potEth, ctx.potWater)
    end)
    R:check("RTPOT.pot_spirit_unfit_for_spark_engines", function()
        local ok = true
        for _, id in ipairs(D.sparks) do ok = ok and verdicts[id].compatible == false end
        return ok and D.hasReason(verdicts.engine_si_flex, "water") and D.hasReason(verdicts.generator_si_flex, "water"), text
    end)
    ctx.phase = "dry"
end

function RT.D.phases.dry(ctx)
    local D = RT.D
    removeAll("Base.Quicklime")
    give("Base.Quicklime", 5)
    local r = machineClick("RTPOT.load_dry", D.items[3], "ContextMenu_TLG_LoadDry")
    ctx.tDry = hours()
    closeDialogs()
    R:check("RTPOT.dry_loaded", function()
        return r.ok == true and D.near(r.limeKg, 5) and D.near(r.ethanolL, ctx.potEth, 1e-3) and D.near(r.waterL, ctx.potWater, 1e-3),
            string.format("lime %s kg, ethanol %s L, water %s L", tostring(r.limeKg), tostring(r.ethanolL), tostring(r.waterL))
    end)
    ctx.next, ctx.phase = hours() + 0.5, "drying"
end

function RT.D.phases.drying(ctx)
    local D = RT.D
    RT.speed(RT.waitSpeed)
    if hours() < ctx.next then return end
    ctx.next = hours() + 0.5
    local s = RT.statusOf(D.items[3])
    if s.state ~= "OutputReady" and s.state ~= "Faulted" and hours() - ctx.tDry < 30 then return end
    RT.speed(1)
    local rec = D.rec(3)
    R:check("RTPOT.dried_in_12_hours", function()
        return s.state == "OutputReady" and D.near(rec.completedAt, ctx.tDry + 12),
            string.format("state=%s done %.6f h after loading", tostring(s.state), (rec.completedAt or -1) - ctx.tDry)
    end)
    local _, text = D.statusText(3)
    R:check("RTPOT.dryer_status_when_finished", function()
        return D.finishedText(text, "IGUI_TLG_MachineState_OutputReady_dryer"), tostring(text)
    end)
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    machineClick("RTPOT.collect_dry", D.items[3], "ContextMenu_TLG_CollectEthanol")
    closeDialogs()
    local can = grownCan(before)
    local verdicts, text, v = D.verdicts(can)
    local q = v and v.q or {}
    local target = TLG.Registry.need("recipe", "ethanol_dry").params.targetWater
    R:check("RTPOT.dried_spirit", function()
        return v ~= nil and D.near(q.ethanol, ctx.potEth, 1e-3) and D.near(q.water, ctx.potEth * target, 1e-3),
            string.format("%s; expected water %.6f", viewText(v, "can"), ctx.potEth * target)
    end)
    R:check("RTPOT.dried_spirit_fits_flex_engines", function()
        return verdicts.engine_si_flex.compatible == true and verdicts.generator_si_flex.compatible == true
            and D.hasReason(verdicts.engine_si_stock, "too_much_ethanol") and D.hasReason(verdicts.generator_si_stock, "too_much_ethanol"),
            text
    end)
    return true
end

RT.potRun = { name = "rtpot_run", timeout = 120000, fn = function(ctx, ticks)
    if not ctx.phase and RT.skip("rtpot_run") then return true end
    if ticks % 30 == 0 then RT.keepFit() end
    return RT.D.phases[ctx.phase or "ferment"](ctx, ticks) == true
end }

RT.potSteps = { RT.waitWorld, RT.setup, RT.potSetup, RT.potRun, RT.finish }

------------------------------------------------------------------------------
-- Machine controls (request "sp-rtc"): Pause, Resume and Abort batch from
-- the machine menu. Summer with the grid on, room tiles (RT.P.findSpots):
-- three fermenters, a drying column and a pot still, the batches loaded in
-- the same tick at full rate. F1 is paused 5 h in, resumed 6 h later and
-- read 4 h after, then aborted twice; Pause, Resume and Abort are also
-- pressed where they do not apply. F2 is aborted 5 h in, its wash taken by
-- the pot still, and loaded again. The drying column, loaded from a can of
-- 4 L ethanol and 1 L water, is aborted 6 h in and its ethanol collected.
-- F3 is paused 5 h in and left until it spoils (the player guide: a batch
-- stopped for 3 days in all spoils), then emptied with Abort and reloaded.
-- The RTC.design_ checks hold Abort to keeping what the batch made and
-- listing what it throws away (Process.abort), and a spoiled batch to a way
-- out from the menu; run 31 failed them before the fix. Abort on a running
-- still is left to the domain tests (its spirit kept, the rest of the wash
-- listed, every litre accounted).
------------------------------------------------------------------------------
RT.C = { names = { "F1", "F2", "F3", "column", "still" }, tol = 1e-6 }

function RT.C.rec(i) return RT.C.items[i]:getModData().tlgProc or {} end

-- A menu entry for machine i, clicked, with the dialog the player reads.
function RT.C.click(i, key, label)
    local before = #H.dialogs.texts
    local r = machineClick("RTC." .. label .. "_" .. RT.C.names[i], RT.C.items[i], key)
    local text = H.dialogs.texts[before + 1]
    closeDialogs()
    return r, text
end

-- The machine menu's entry names for machine i as offered now.
function RT.C.offered(i)
    local context = ISContextMenu.get(0, 100, 100)
    TLG.UI.MachineMenu.fill(0, context, { RT.C.items[i] })
    local root = context:getOptionFromName(getText("ContextMenu_TLG_Machine"))
    local sub = root and root.subOption and context:getSubMenu(root.subOption)
    local out = {}
    for j = 1, (sub and sub.numOptions or 1) - 1 do
        local o = sub.options[j]
        if o then out[#out + 1] = tostring(o.name) .. (o.notAvailable and " (greyed)" or "") end
    end
    context:setVisible(false)
    return out
end

-- Which of Pause, Resume and Abort batch the menu offers machine i, as
-- "pause,resume,abort" true/false.
function RT.C.controls(i, label)
    local names = RT.C.offered(i)
    R:line("OBS  RTC.menu %s %s: %s", RT.C.names[i], label, table.concat(names, ", "))
    local set = {}
    for _, n in ipairs(names) do set[n] = true end
    return string.format("%s,%s,%s", tostring(set[getText("ContextMenu_TLG_Pause")] == true),
        tostring(set[getText("ContextMenu_TLG_Resume")] == true), tostring(set[getText("ContextMenu_TLG_Abort")] == true))
end

function RT.C.checkControls(i, label, want)
    local got = RT.C.controls(i, label)
    R:check("RTC.menu_" .. label .. "_" .. RT.C.names[i], function()
        return got == want, string.format("pause,resume,abort offered %s (want %s)", got, want)
    end)
end

function RT.C.loadMash(i)
    give("Base.Sugar", 6); give("Base.Yeast", 1)
    for _ = 1, 3 do
        local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
        fc:Empty()
        fc:addFluid(Fluid.Water, 10)
    end
    return RT.C.click(i, "ContextMenu_TLG_LoadFerment", "load_mash")
end

-- The record fields a refused command must leave as they were.
function RT.C.key(p)
    return string.format("state=%s pause=%s stage=%s done=%.6f t=%.6f pausedFor=%.6f manual=%s rev=%s", tostring(p.state),
        tostring(p.pause), tostring(p.stage), p.stageDone or -1, p.t or -1, p.pausedFor or -1, tostring(p.manualPause),
        tostring(p.rev))
end

-- A press the menu no longer offers there (run 32: "no menu entry"), sent as
-- a menu deciding on a stale copy of the record would: refused, the record
-- unchanged, and the menu has a sentence for the reason (run 31 showed "Not
-- possible right now (not_processing).").
function RT.C.refused(i, command, label, reason)
    local before = RT.C.key(RT.C.rec(i))
    local r = ask("RTC." .. label .. "_" .. RT.C.names[i], command, { target = TLG.Integration.Machines.refFor(RT.C.items[i]) })
    local after = RT.C.key(RT.C.rec(i))
    local key = "IGUI_TLG_MachineFail_" .. tostring(r.reason)
    local text = getText(key)
    R:check("RTC." .. label .. "_refused_" .. RT.C.names[i], function()
        return r.ok == false and r.reason == reason and before == after and text ~= key,
            string.format("reason %s (want %s); record %s; the menu shows \"%s\"", tostring(r.reason), reason,
                before == after and "unchanged" or ("changed: " .. before .. " -> " .. after), tostring(text))
    end)
end

-- Whether a dialog names each component of `t` with its amount.
function RT.C.lists(text, t)
    if text == nil then return false end
    for _, id in ipairs(TLG.Tables.sortedKeys(t or {})) do
        if not has(text, TLG.UI.Format.componentName(id)) or not has(text, string.format("%.2f", t[id])) then return false end
    end
    return true
end

function RT.C.near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= RT.C.tol end

function RT.C.same(a, b)
    for _, id in ipairs({ "ethanol", "water", "sugar_eq" }) do
        if not RT.C.near((a or {})[id] or 0, (b or {})[id] or 0) then return false end
    end
    return true
end

RT.controlSetup = { name = "rtc_sites", timeout = 3000, fn = function(ctx, ticks)
    local C = RT.C
    if not ctx.t0 and RT.skip("rtc_sites") then return true end
    if not ctx.t0 then
        local here = player():getSquare()
        local spots = RT.P.findSpots(here:getX(), here:getY())
        if spots == nil then
            RT.abort = "no free room tile with free room neighbours nearby"
            R:line("OBS  RTC.spots none found")
            return true
        end
        C.items = {}
        for i, t in ipairs({ "TLG.FermenterVessel", "TLG.FermenterVessel", "TLG.FermenterVessel", "TLG.DryingColumn", "TLG.PotStill" }) do
            local it = instanceItem(t)
            spots[i + 1]:AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            C.items[i] = it
        end
        player():setPosition(spots[1]:getX() + 0.5, spots[1]:getY() + 0.5, 0)
        player():setPerkLevelDebug(Perks.Cooking, 0)
        local power
        pcall(function() power = getWorld():isHydroPowerOn() end)
        R:line("OBS  RTC.spots character %d,%d; F1 %d,%d F2 %d,%d F3 %d,%d column %d,%d still %d,%d; grid power=%s",
            spots[1]:getX(), spots[1]:getY(), spots[2]:getX(), spots[2]:getY(), spots[3]:getX(), spots[3]:getY(), spots[4]:getX(),
            spots[4]:getY(), spots[5]:getX(), spots[5]:getY(), spots[6]:getX(), spots[6]:getY(), tostring(power))
        R:check("RTC.grid_is_on", function() return power == true, "isHydroPowerOn=" .. tostring(power) end)
        ctx.t0 = ticks
        return nil
    end
    return ticks - ctx.t0 >= 60
end }

RT.C.phases = {}

function RT.C.phases.load(ctx)
    local C = RT.C
    for _, t in ipairs({ "Base.Sugar", "Base.Yeast", "Base.Quicklime" }) do removeAll(t) end
    for i = 1, 3 do
        local r = C.loadMash(i)
        R:check("RTC.loaded_" .. C.names[i], function() return r.ok == true, string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL)) end)
    end
    give("Base.Quicklime", 4)
    -- Water in fuel is the mod's own fluid (Content/Fuels: TLG_FuelWater); run
    -- 30 used vanilla water, which never registered in the can.
    giveCan("Base.JerryCan", { { Fluid.Get("TLG_Ethanol"), 4 }, { Fluid.Get("TLG_FuelWater"), 1 } })
    local d = C.click(4, "ContextMenu_TLG_LoadDry", "load_dry")
    local left = 0
    for _, e in pairs(ethanolCans()) do left = left + e.litres end
    ctx.dry = { eth = d.ethanolL or 0, water = d.waterL or 0, lime = d.limeKg or 0 }
    R:check("RTC.loaded_column", function()
        return d.ok == true and math.abs(ctx.dry.eth - 4) < 0.01 and math.abs(ctx.dry.water - 1) < 0.01 and C.near(ctx.dry.lime, 4)
            and left < 1e-3, string.format("ethanol %s water %s lime %s; ethanol left in carried cans %.4f L", tostring(d.ethanolL),
            tostring(d.waterL), tostring(d.limeKg), left)
    end)
    ctx.h0 = hours()
    C.checkControls(1, "working", "true,false,true")
    C.checkControls(5, "idle", "false,false,false")
    ctx.phase = "to5"
end

-- Waits at x100 until `t`, then runs the next phase at x1.
function RT.C.waitUntil(ctx, t, nextPhase)
    if hours() < t then
        RT.speed(RT.waitSpeed)
        return
    end
    RT.speed(1)
    ctx.phase = nextPhase
end

function RT.C.phases.to5(ctx) RT.C.waitUntil(ctx, ctx.h0 + 5, "at5") end

-- The wash a fermenter has made `done` hours into the 6 kg batch.
function RT.C.wash(done)
    local frac = done / 97
    return { ethanol = 3.3 * frac, water = 30, sugar_eq = 6 * (1 - frac) }
end

function RT.C.phases.at5(ctx)
    local C = RT.C
    -- F1: Pause, and Pause again.
    local r, text = C.click(1, "ContextMenu_TLG_Pause", "pause")
    ctx.tPause, ctx.doneP = hours(), RT.doneHours(C.items[1])
    R:check("RTC.pause_F1", function()
        return r.ok == true and r.state == "Paused" and r.pause == "paused_by_player" and has(text, getText("IGUI_TLG_Pause_paused_by_player")),
            string.format("state=%s pause=%s dialog=%s", tostring(r.state), tostring(r.pause), tostring(text))
    end)
    C.checkControls(1, "paused_by_hand", "false,true,true")
    C.refused(1, "machine.pause", "pause_again", "not_processing")
    -- F2: Abort 5 h in: the wash so far stays for a still.
    local a, atext = C.click(2, "ContextMenu_TLG_Abort", "abort")
    local want, p2 = C.wash(hours() - ctx.h0), C.rec(2)
    R:line("OBS  RTC.abort_F2 kept=%s discarded=%s; dialog=%s", brief(a.kept), brief(a.discarded), tostring(atext))
    R:check("RTC.abort_keeps_the_wash_F2", function()
        return a.ok == true and C.same(a.kept, want) and TLG.Tables.isEmpty(a.discarded or {}) and p2.state == "OutputReady"
            and p2.stoppedEarly == true and C.same(p2.outputs, want),
            string.format("kept %s, discarded %s; vessel %s holding %s; expected %s", brief(a.kept), brief(a.discarded),
                tostring(p2.state), brief(p2.outputs), brief(want))
    end)
    R:check("RTC.design_abort_lists_what_it_kept_F2", function()
        return a.ok == true and has(atext, getText("IGUI_TLG_Aborted")) and has(atext,
            getText("IGUI_TLG_MachineState_OutputReady_stopped_fermenter")) and C.lists(atext, p2.outputs)
            and has(atext, getText("IGUI_TLG_AbortAgain")), "dialog: " .. tostring(atext)
    end)
    C.checkControls(2, "stopped_early", "false,false,true")
    -- The pot still takes that wash, sugar and all; the vessel is free again.
    local w = C.click(5, "ContextMenu_TLG_LoadWash", "load_wash")
    local s = C.rec(5)
    R:check("RTC.still_takes_the_stopped_wash", function()
        return w.ok == true and C.near(w.washL, want.ethanol + want.water) and C.same(s.inputs, want) and C.rec(2).state == "Ready",
            string.format("wash %s L; still inputs %s; vessel %s", tostring(w.washL), brief(s.inputs), tostring(C.rec(2).state))
    end)
    C.refused(2, "machine.abort", "abort_again", "nothing_to_abort")
    local again = C.loadMash(2)
    R:check("RTC.loads_again_after_abort_F2", function() return again.ok == true, "reason " .. tostring(again.reason) end)
    -- F3: Pause and leave it.
    local r3 = C.click(3, "ContextMenu_TLG_Pause", "pause")
    ctx.tPause3 = hours()
    R:check("RTC.pause_F3", function() return r3.ok == true and r3.state == "Paused", "state " .. tostring(r3.state) end)
    ctx.phase = "to6"
end

function RT.C.phases.to6(ctx) RT.C.waitUntil(ctx, ctx.h0 + 6, "at6") end

function RT.C.phases.at6(ctx)
    local C = RT.C
    local a, atext = C.click(4, "ContextMenu_TLG_Abort", "abort")
    local frac = (hours() - ctx.h0) / 12
    local p = C.rec(4)
    -- Process.converters.dry at the share done.
    local dry, target = ctx.dry, TLG.Registry.need("recipe", "ethanol_dry").params
    local removed = math.min(dry.water - dry.eth * target.targetWater, dry.lime * target.waterPerKgLime) * frac
    local water = dry.water - removed
    R:line("OBS  RTC.abort_column kept=%s discarded=%s; dialog=%s", brief(a.kept), brief(a.discarded), tostring(atext))
    R:check("RTC.abort_keeps_the_ethanol_in_the_column", function()
        local k = a.kept or {}
        return a.ok == true and C.near(k.ethanol, dry.eth) and C.near(k.water, water) and p.state == "OutputReady"
            and C.near((a.discarded or {}).spent_lime, dry.lime + removed),
            string.format("kept %s, discarded %s; column %s; expected ethanol %.6f water %.6f (%.4f done)", brief(a.kept),
                brief(a.discarded), tostring(p.state), dry.eth, water, frac)
    end)
    R:check("RTC.design_abort_lists_what_is_lost_column", function()
        return a.ok == true and C.lists(atext, p.outputs) and has(atext, getText("IGUI_TLG_MachineState_OutputReady_stopped"))
            and C.lists(atext, a.discarded), "dialog: " .. tostring(atext)
    end)
    giveCan("Base.JerryCan")
    local before = ethanolCans()
    C.click(4, "ContextMenu_TLG_CollectEthanol", "collect")
    local can = grownCan(before)
    local v = can and tlgView("item", can)
    R:check("RTC.design_abort_keeps_the_ethanol", function()
        local q = v and v.q or {}
        return math.abs((q.ethanol or 0) - dry.eth) < 1e-3 and math.abs((q.water or 0) - water) < 1e-3 and C.rec(4).state == "Ready",
            string.format("%s; column %s", viewText(v, "can"), tostring(C.rec(4).state))
    end)
    ctx.phase = "toResume"
end

function RT.C.phases.toResume(ctx) RT.C.waitUntil(ctx, ctx.tPause + 6, "resume") end

function RT.C.phases.resume(ctx)
    local C = RT.C
    RT.statusOf(C.items[1])
    local p = C.rec(1)
    R:check("RTC.paused_hours_do_no_work_F1", function()
        return C.near(RT.doneHours(C.items[1]), ctx.doneP) and C.near(p.pausedFor, hours() - ctx.tPause),
            string.format("done %.6f h (%.6f at the pause); paused for %.6f h of %.6f", RT.doneHours(C.items[1]), ctx.doneP,
                p.pausedFor or -1, hours() - ctx.tPause)
    end)
    local r, text = C.click(1, "ContextMenu_TLG_Resume", "resume")
    ctx.tResume = hours()
    R:check("RTC.resume_F1", function()
        return r.ok == true and r.state == "Processing", string.format("state=%s dialog=%s", tostring(r.state), tostring(text))
    end)
    C.refused(1, "machine.resume", "resume_again", "not_paused")
    ctx.phase = "toRead"
end

function RT.C.phases.toRead(ctx) RT.C.waitUntil(ctx, ctx.tResume + 4, "read") end

function RT.C.phases.read(ctx)
    local C = RT.C
    RT.statusOf(C.items[1])
    local p, done = C.rec(1), RT.doneHours(C.items[1])
    R:check("RTC.resume_continues_F1", function()
        local want = ctx.doneP + (hours() - ctx.tResume)
        return C.near(done, want) and C.near(p.pausedFor, ctx.tResume - ctx.tPause) and p.state == "Processing",
            string.format("done %.6f h (want %.6f); paused %.6f h; state %s", done, want, p.pausedFor or -1, tostring(p.state))
    end)
    -- F1: Abort keeps the wash; Abort again throws it away; a new mash goes in.
    local a = C.click(1, "ContextMenu_TLG_Abort", "abort")
    local kept = C.rec(1).outputs
    local b, btext = C.click(1, "ContextMenu_TLG_Abort", "abort_again")
    R:check("RTC.second_abort_throws_it_away_F1", function()
        return a.ok == true and b.ok == true and C.rec(1).state == "Ready" and C.same(b.discarded, kept)
            and has(btext, getText("IGUI_TLG_MachineState_Ready")) and C.lists(btext, b.discarded),
            string.format("kept %s, then thrown away %s; vessel %s; dialog %s", brief(kept), brief(b.discarded), tostring(C.rec(1).state),
                tostring(btext))
    end)
    local again = C.loadMash(1)
    R:check("RTC.loads_again_after_throwing_away_F1", function() return again.ok == true, "reason " .. tostring(again.reason) end)
    ctx.phase = "toSpoil"
end

function RT.C.phases.toSpoil(ctx) RT.C.waitUntil(ctx, ctx.tPause3 + 72.5, "spoiled") end

function RT.C.phases.spoiled(ctx)
    local C = RT.C
    local s = RT.statusOf(C.items[3])
    local p = C.rec(3)
    R:check("RTC.hand_pause_counts_towards_spoiling", function()
        return s.state == "Faulted" and s.pause == "batch_spoiled" and C.near(p.pausedFor, 72),
            string.format("state=%s pause=%s paused for %.6f h", tostring(s.state), tostring(s.pause), p.pausedFor or -1)
    end)
    C.checkControls(3, "spoiled", "false,false,true")
    local l, ltext = C.loadMash(3)
    R:check("RTC.spoiled_load_refused_F3", function()
        return l.ok == false and l.reason == "batch_spoiled" and ltext == getText("IGUI_TLG_MachineFail_batch_spoiled"),
            string.format("reason %s; dialog %s", tostring(l.reason), tostring(ltext))
    end)
    local a, atext = C.click(3, "ContextMenu_TLG_Abort", "abort")
    local q = C.rec(3)
    R:check("RTC.design_spoiled_batch_can_be_cleared", function()
        return a.ok == true and q.state == "Ready" and has(atext, getText("IGUI_TLG_AbortedSpoiled"))
            and C.same(a.discarded, { sugar_eq = 6, water = 30 }) and C.lists(atext, a.discarded),
            string.format("state %s; thrown away %s; dialog %s", tostring(q.state), brief(a.discarded), tostring(atext))
    end)
    local again = C.loadMash(3)
    R:check("RTC.loads_again_after_spoiling_F3", function() return again.ok == true, "reason " .. tostring(again.reason) end)
    return true
end

RT.controlRun = { name = "rtc_run", timeout = 120000, fn = function(ctx, ticks)
    if not ctx.phase and RT.skip("rtc_run") then return true end
    if ticks % 30 == 0 then RT.keepFit() end
    return RT.C.phases[ctx.phase or "load"](ctx, ticks) == true
end }

RT.controlSteps = { RT.waitWorld, RT.setup, RT.controlSetup, RT.controlRun, RT.finish }

------------------------------------------------------------------------------
-- Open fires (request "sp-rtof"): a fermenter beside a campfire and one
-- beside a barbecue (D-021, D-022), outdoors in the January world with the
-- grid off, the two sites 24 tiles apart so that neither fire reaches the
-- other's tiles. In 42.21 a campfire is not an IsoFireplace: SCampfireSystem
-- keeps it as a Lua global object over a plain IsoObject "Campfire" (fuel in
-- minutes, `fuelAmt`, lowered by one on every EveryOneMinute event, loaded
-- or not: SRC Camping/SCampfireSystem.lua lowerFuelAmount), and its warmth
-- comes from the permanent IsoFire it adds while lit, a heat source of 35 C
-- whose radius is the fire's light radius (BC IsoFire.update). The campfire
-- sets that radius from its fuel (SCampfireGlobalObject:fireRadius,
-- max(2, 10 x min(fuel, 360) / 360) outdoors, a number handed to
-- setLightRadius(int)); how it is made whole is read off the IsoFire here.
-- A barbecue is an IsoBarbecue: 25 C, radius 3 (BC updateHeatSource), its
-- fuel burned by game time, also while unloaded (BC update; lastUpdateTime
-- is saved). The campfire is built with the call its build action makes
-- (SCampfireSystem.instance:addCampfire, SRC campingCampfire:create), the
-- charcoal barbecue created as vanilla's own tests do (IsoBarbecue.new with
-- appliances_cooking_01_35 and AddTileObject, SRC Tests/TimedActionsTests.lua)
-- where a player would set one down. Each is fed a log and lit from its own
-- menu (Add fuel, Light: a sheet of paper and matches), the actions walking
-- the character there. The air on every tile around each fire is compared
-- with the heat formula, the campfire's at four fuel levels, and a fermenter
-- is loaded on a warmed tile beside each. Then the winter run's hourly
-- readings, the harness's own ten-minute notes of the fire warming each
-- machine, the fires tended with the calls the add-fuel actions' complete
-- makes, a 12 game hour trip that unloads both sites, and on return the
-- fuel burned away, the hours away the notes cover and the work over the
-- trip. The day temperature with that credit is the harness's own (the
-- D-022 rule with the radius each fire has in game), not Climate.siteDayMean.
------------------------------------------------------------------------------
RT.O = { names = { "campfire", "barbecue" }, tripAt = 30, tripHours = 12, afterHours = 12, tag = "RTO", warm = 1,
    tol = 1e-3, heatC = { 35, 25 }, bbqRadius = 3, bbqSprite = "appliances_cooking_01_35", apart = 24,
    campFuels = { 200, 100, 30 }, minutes = 0 }

-- Free outdoor floor with nothing lying on it.
function RT.O.outdoorFree(s)
    if not RT.W.free(s) or RT.W.inRoom(s) then return false end
    local ok, r = pcall(function() return s:isOutside() and s:getWorldObjects():size() == 0 end)
    return ok and r == true
end

-- Room for a fire at (x, y): it and the eight tiles around it free outdoor
-- floor, so a machine tile beside it has nothing in between.
function RT.O.open(x, y)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not RT.O.outdoorFree(sq(x + dx, y + dy, 0)) then return false end
        end
    end
    return true
end

-- The open spot nearest (x0, y0) at least `away` tiles from `avoid`.
function RT.O.findOpen(x0, y0, avoid, away)
    for r = 0, 60 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = x0 + dx, y0 + dy
                    local far = avoid == nil or (x - avoid.x) * (x - avoid.x) + (y - avoid.y) * (y - avoid.y) >= away * away
                    if far and RT.O.open(x, y) then return { x = x, y = y } end
                end
            end
        end
    end
    return nil
end

-- The campfire as the server keeps it (SCampfireSystem: fuelAmt, isLit,
-- exterior), loaded or not.
function RT.O.campLua()
    local p = RT.O.site[1]
    local ok, o = pcall(function() return SCampfireSystem.instance:getLuaObjectAt(p.x, p.y, 0) end)
    return ok and o or nil
end

-- The object of class `cls` on fire k's tile (the campfire's permanent
-- IsoFire, the IsoBarbecue), found again on every call: references go stale
-- when the tile reloads.
function RT.O.object(k, cls)
    local p = RT.O.site[k]
    local s = sq(p.x, p.y, 0)
    local objs = s and s:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if instanceof(o, cls) and (cls ~= "IsoFire" or o:isPermanent()) then return o end
    end
    return nil
end

-- Fire k as the game has it now (nil while its tile is not loaded): lit,
-- fuel in minutes, heat radius.
function RT.O.state(k)
    local O, p = RT.O, RT.O.site[k]
    if sq(p.x, p.y, 0) == nil then return nil end
    if k == 1 then
        local c, f = O.campLua(), O.object(1, "IsoFire")
        if c == nil then return nil end
        return { lit = c.isLit == true, fuel = c.fuelAmt or 0, radius = f and f:getLightRadius() or 0 }
    end
    local b = O.object(2, "IsoBarbecue")
    if b == nil then return nil end
    return { lit = b:isLit(), fuel = b:getFuelAmount(), radius = O.bbqRadius }
end

-- The air the game gives a tile whose air without heat sources is t, with a
-- heat source of c at offset dx, dy and radius R in clear line of sight
-- (BC IsoCell.getHeatSourceHighestTemperature; RT.F.warmed for any heat).
function RT.O.warmed(t, dx, dy, radius, srcInRoom, c)
    local dsq = dx * dx + dy * dy
    if dsq >= radius * radius then return t end
    local adj
    if srcInRoom then adj = math.max(-7, math.min(7, t - 30)) else adj = math.max(-15, math.min(5, t - 30)) end
    return math.max(t, t + (1 - math.sqrt(dsq) / radius) * (c + adj - t))
end

-- The campfire's radius at `fuel` minutes (SCampfireGlobalObject:fireRadius,
-- outdoors), made whole as the run found the game does (O.law).
function RT.O.campRadius(fuel)
    local r = math.max(2, 10 * math.min(math.max(fuel, 0), 360) / 360)
    if RT.O.law == "round" then return math.floor(r + 0.5) end
    return math.floor(r)
end

-- How many (fuel, radius) pairs read off the campfire fit its radius made
-- whole by truncation, and by rounding.
function RT.O.lawCount()
    local fl, rd = 0, 0
    for _, p in ipairs(RT.O.pairs) do
        local r = math.max(2, 10 * math.min(p.f, 360) / 360)
        if math.floor(r) == p.r then fl = fl + 1 end
        if math.floor(r + 0.5) == p.r then rd = rd + 1 end
    end
    return fl, rd
end

function RT.O.pairsText()
    local parts = {}
    for n, p in ipairs(RT.O.pairs) do
        if n <= 12 then parts[#parts + 1] = string.format("%.1f->%d", p.f, p.r) end
    end
    return table.concat(parts, " ")
end

-- The air on every loaded floor tile within reach of fire k against the
-- heat formula at its state now (as RT.F.snapshot): warm or cold as the
-- formula says, blocked when in range but not warmed (no clear line of
-- sight), mismatch otherwise.
function RT.O.snapshot(k)
    local O, c = RT.O, RT.F.climate()
    local p, st = O.site[k], O.state(k)
    local reach = k == 1 and 11 or O.bbqRadius + 1
    local srcRoom = RT.W.inRoom(sq(p.x, p.y, 0))
    local snap = { lit = st.lit, fuel = st.fuel, radius = st.radius, warm = 0, cold = 0, blocked = 0, mismatch = 0,
        where = "none", tiles = {} }
    for dx = -reach, reach do
        for dy = -reach, reach do
            local s = (dx ~= 0 or dy ~= 0) and sq(p.x + dx, p.y + dy, 0) or nil
            if s and s:getFloor() then
                local air = getClimateManager():getAirTemperatureForSquare(s)
                local t0 = RT.F.unwarmed(s, c)
                local want = st.lit and O.warmed(t0, dx, dy, st.radius, srcRoom, O.heatC[k]) or t0
                local class
                if math.abs(air - want) <= O.tol then
                    class = (want > t0 + O.tol) and "warm" or "cold"
                elseif want > t0 + O.tol and math.abs(air - t0) <= O.tol then
                    class = "blocked"
                else
                    class = "mismatch"
                    snap.where = string.format("%d,%d: game %.4f, formula %.4f, unwarmed %.4f", p.x + dx, p.y + dy,
                        air, want, t0)
                end
                snap[class] = snap[class] + 1
                snap.tiles[#snap.tiles + 1] = { x = p.x + dx, y = p.y + dy, class = class }
            end
        end
    end
    return snap
end

function RT.O.snapText(snap)
    return string.format("lit=%s fuel %.1f min radius %s: warm %d, cold %d, blocked %d, mismatch %d (%s)",
        tostring(snap.lit), snap.fuel, tostring(snap.radius), snap.warm, snap.cold, snap.blocked, snap.mismatch,
        snap.where)
end

-- The first entry of a context menu, its submenus included, that `pred`
-- accepts.
function RT.O.findOption(menu, pred, seen)
    seen = seen or {}
    if menu == nil or seen[menu] then return nil end
    seen[menu] = true
    for j = 1, (menu.numOptions or 1) - 1 do
        local o = menu.options[j]
        if o and pred(o) then return o end
        local found = o and o.subOption and RT.O.findOption(menu:getSubMenu(o.subOption), pred, seen)
        if found then return found end
    end
    return nil
end

-- Builds fire k's menu as a right-click on its tile does and presses the
-- entry `pred` picks, as ISContextMenu does: an actions entry, so the
-- character walks there and works. False when the menu has no such entry
-- or greys it out.
function RT.O.press(k, label, pred)
    local O, p = RT.O, RT.O.site[k]
    local objs, list = sq(p.x, p.y, 0):getObjects(), {}
    for i = 0, objs:size() - 1 do list[#list + 1] = objs:get(i) end
    local context = ISContextMenu.get(0, 100, 100)
    if k == 1 then
        ISCampingMenu.doCampingMenu(0, context, list, false)
    else
        ISBBQMenu.OnFillWorldObjectContextMenu(0, context, list, false)
    end
    local opt = O.findOption(context, pred)
    context:setVisible(false)
    local why = (opt == nil and "no menu entry") or (opt.notAvailable and "entry greyed out") or nil
    if why == nil then click(opt) end
    R:line("OBS  RTO.menu %s %s: %s", O.names[k], label, why or ("pressed \"" .. tostring(opt.name) .. "\""))
    return why == nil
end

-- Add fuel > Log > One (ISCampingMenu.doAddFuelOption, for the barbecue too).
function RT.O.isAddLog(o)
    return o.onSelect == ISTimedActionQueue.queueActions and o.param1 == ISCampingMenu.onAddFuel and o.param3 == "Base.Log"
end

-- Light > sheet of paper + matches (ISCampingMenu.doLightFireOption).
function RT.O.isLightPaper(o)
    return o.onSelect == ISTimedActionQueue.queueActions and o.param1 == ISCampingMenu.onLightFromLiterature
        and o.param2 == "Base.SheetPaper2"
end

-- Tends fire k as a player can, with the calls the vanilla actions' complete
-- makes (ISAddFuelAction, ISBBQAddFuel; lighting as ISLightFromLiterature,
-- ISBBQLightFromLiterature): a log only once it fits under the cap the menu
-- keeps to, lit again when out.
function RT.O.tend(k)
    local O, st = RT.O, RT.O.state(k)
    if st == nil then return false end
    local added = false
    if st.fuel + O.perLog <= O.cap and takeAway("Base.Log") then
        if k == 1 then
            O.campLua():addFuel(O.perLog)
        else
            local b = O.object(2, "IsoBarbecue")
            b:addFuel(O.perLog)
            b:sendObjectChange(IsoObjectChange.STATE)
        end
        O.logs[k], added = O.logs[k] + 1, true
    end
    if k == 1 then
        local c = O.campLua()
        if not c.isLit and (c.fuelAmt or 0) > 0 then c:lightFire() end
    else
        local b = O.object(2, "IsoBarbecue")
        if b:hasFuel() and not b:isLit() then
            b:turnOn()
            b:sendObjectChange(IsoObjectChange.STATE)
        end
    end
    return added
end

-- Every game hour while the batches run: the game's air at each machine,
-- filed by hour like the mod's readings, against the heat formula at its
-- fire's state now (a campfire radius changed in the tick before may not
-- have reached its heat source yet: counted apart), then the fires tended.
function RT.O.onHour()
    local O = RT.O
    if not O.active then return end
    local slot, c = math.floor(hours() - 0.5), RT.F.climate()
    for i = 1, 2 do
        local m = O.mach[i]
        local s, st = sq(m.x, m.y, 0), O.state(i)
        if s == nil or st == nil then
            O.unloaded[slot] = true
        else
            local air = getClimateManager():getAirTemperatureForSquare(s)
            O.readings[i][slot] = air
            local t0 = RT.F.unwarmed(s, c)
            local want = st.lit and O.warmed(t0, m.dx, m.dy, st.radius, O.srcRoom[i], O.heatC[i]) or t0
            local h = O.hourly[i]
            h.n = h.n + 1
            if i == 1 and st.lit and math.abs(air - want) > O.tol
                and math.abs(air - O.warmed(t0, m.dx, m.dy, O.campRadius(st.fuel + 1), O.srcRoom[i], O.heatC[i])) <= O.tol then
                h.lagged = h.lagged + 1
            elseif math.abs(air - want) >= h.worst then
                h.worst = math.abs(air - want)
                h.where = string.format("%s hour %d: lit=%s fuel %.1f radius %d: game %.4f, formula %.4f", RT.dayKey(),
                    slot, tostring(st.lit), st.fuel, st.radius, air, want)
            end
            if st.lit then
                h.lit = h.lit + 1
                h.minGain, h.maxGain, h.minAir = math.min(h.minGain, air - t0), math.max(h.maxGain, air - t0),
                    math.min(h.minAir, air)
            end
            if i == 1 and st.lit then O.pairs[#O.pairs + 1] = { f = st.fuel, r = st.radius } end
        end
    end
    if O.tending then
        for k = 1, 2 do O.tend(k) end
    end
end

-- Every ten game minutes while the batches run: the harness's own note of
-- the fire warming each machine, as Machines.observeFires takes it (the
-- hour's last note wins; false when the fire does not give the air there).
function RT.O.onTenMinutes()
    local O = RT.O
    if not O.active then return end
    local c = RT.F.climate()
    for i = 1, 2 do
        local m = O.mach[i]
        local s, st = sq(m.x, m.y, 0), O.state(i)
        if s ~= nil and st ~= nil then
            local air = getClimateManager():getAirTemperatureForSquare(s)
            local t0 = RT.F.unwarmed(s, c)
            local note = false
            if st.lit and st.fuel > 0 and air > t0 + O.tol
                and math.abs(O.warmed(t0, m.dx, m.dy, st.radius, O.srcRoom[i], O.heatC[i]) - air) <= O.tol then
                note = { t = hours(), f = st.fuel, x = -m.dx, y = -m.dy, r = O.srcRoom[i], c = O.heatC[i],
                    rad = i == 2 and O.bbqRadius or nil }
            end
            O.notes[i][math.floor(hours())] = note
        end
    end
end

-- The campfire burns a minute of fuel per EveryOneMinute event, which the
-- game fires once per tick however many game minutes the tick spans (BC
-- GameTime.update): counted here.
function RT.O.onMinute()
    RT.O.minutes = RT.O.minutes + 1
end

-- Machine i's day temperature by the D-022 rule on the harness's own
-- readings and notes: an hour without a reading takes the note standing
-- last before it, its warmth from the start of the noted hour while the
-- noted fuel lasts, with the radius its fire has in game at the fuel left
-- at the start of each hour (the campfire's by O.campRadius, the
-- barbecue's 3); the site's unheated value (Climate:siteBase) elsewhere.
function RT.O.dayMean(i, day, upto)
    local O, env = RT.O, TLG.World.env()
    local rec = O.items[i]:getModData().tlgProc or {}
    local site = rec.site or { room = false, z = 0 }
    local base = env:siteBase(day, { room = site.room, z = site.z })
    local from = math.max(env:dayStart(day), rec.startedAt or -math.huge)
    local to = math.min(env:dayStart(day + 1), upto)
    local span = to - from
    if span <= 1e-9 then return base end
    local temps, notes = O.readings[i], O.notes[i]
    local current = math.floor(to)
    local carried = current < to and temps[current] == nil and temps[current - 1] or nil
    local keys = TLG.Tables.sortedKeys(notes)
    local ki, sum, covered = 0, 0, 0
    for s = math.floor(from), math.ceil(to) - 1 do
        local a, b = math.max(from, s), math.min(to, s + 1)
        local v = temps[s]
        if v == nil and s == current then v = carried end
        if b > a and v ~= nil then
            sum, covered = sum + (b - a) * v, covered + (b - a)
        elseif b > a then
            while ki < #keys and keys[ki + 1] <= s do ki = ki + 1 end
            local note = ki > 0 and notes[keys[ki]] or nil
            if type(note) == "table" then
                local stop = math.min(b, note.t + note.f / 60)
                if stop > a then
                    local left = note.f - (a - note.t) * 60
                    local radius = i == 1 and O.campRadius(left) or O.bbqRadius
                    local w = O.warmed(base, note.x, note.y, radius, note.r, note.c)
                    sum, covered = sum + (stop - a) * w, covered + (stop - a)
                end
            end
        end
    end
    return (sum + (span - covered) * base) / span
end

-- The notes the mod took for machine i since the last comparison against
-- the harness's: no fire where the harness saw none; where it saw the fire,
-- the same time, fuel, offset, heat, room and fixed radius. Further fields
-- of the mod's note are not compared.
function RT.O.compareNotes(m, i, item)
    local p, mine = item and item:getModData().tlgProc, RT.O.notes[i]
    if not p then return end
    for _, h in ipairs(TLG.Tables.sortedKeys(mine)) do
        if h > m.notesCompared then
            m.notesCompared = h
            local a, b = mine[h], p.fires and p.fires[h]
            local same
            if a == false then
                same = b == false
            else
                same = type(b) == "table" and b.f == a.f and b.x == a.x and b.y == a.y and b.r == a.r and b.c == a.c
                    and b.rad == a.rad and math.abs(b.t - a.t) < 1e-6
            end
            m.notes.n = m.notes.n + 1
            if a then m.notes.fire = m.notes.fire + 1 end
            if not same then
                m.notes.off = m.notes.off + 1
                m.notes.where = m.notes.where or string.format("hour %d: harness %s, mod %s", h, brief(a), brief(b))
            end
        end
    end
end

-- One status read of machine i with the character beside it: readings and
-- notes compared, the reported day temperature against the harness's, the
-- work against the stage rule fed by the reported one.
function RT.O.read(ctx, i, env, now, day)
    local O, m, item = RT.O, ctx.m[i], RT.O.items[i]
    compareFiled(O, m, i, item)
    O.compareNotes(m, i, item)
    local s = RT.statusOf(item)
    if s.ok ~= true then
        m.refused = m.refused + 1
        m.refusedWhy = m.refusedWhy or tostring(s.reason)
    end
    local done = RT.doneHours(item)
    local p = m.prev
    local dt, dd = now - p.h, done - p.done
    local running = s.state == "Processing" or s.state == "Paused"
    if running and type(s.siteC) == "number" then
        local want = O.dayMean(i, day, now)
        local tally = (ctx.trip and ctx.trip.checked) and m.meanAfter or m.meanBefore
        tally.n = tally.n + 1
        if math.abs(want - s.siteC) >= tally.worst then
            tally.worst = math.abs(want - s.siteC)
            tally.where = string.format("%s, %.1f h in: status %.4f, harness %.4f", RT.dayKey(), now - ctx.h0,
                s.siteC, want)
        end
    end
    if p.day == day and p.stage == "ferment" and s.stage == "ferment" and running and type(s.siteC) == "number" then
        local rate = RT.fermentRate(s.siteC)
        m.rule.n = m.rule.n + 1
        if math.abs(dd - rate * dt) >= m.rule.worst then
            m.rule.worst = math.abs(dd - rate * dt)
            m.rule.where = string.format("%s, %.1f h in at %.2f C: did %.4f h, rule %.4f h", RT.dayKey(), now - ctx.h0,
                s.siteC, dd, rate * dt)
        end
    end
    local d = m.days[day]
    if not d then
        d = { label = RT.dayKey(), work = 0, paused = 0 }
        m.days[day] = d
    end
    d.work = d.work + math.max(0, dd)
    if s.state == "Paused" then d.paused = d.paused + dt end
    if type(s.siteC) == "number" then d.siteC = s.siteC end
    if running and s.stage == "ferment" and not m.dialog then
        local before = #H.dialogs.texts
        machineClick(O.tag .. ".status_" .. O.names[i], item, "ContextMenu_TLG_MachineStatus")
        m.dialog = H.dialogs.texts[before + 1] or "none"
        closeDialogs()
    end
    m.prev = { h = now, done = done, day = day, stage = s.stage }
    m.last = s
end

-- Hours of the trip the last note at or before leaving covers (D-022: the
-- noted fuel, a minute a minute), and that note.
function RT.O.covered(notes, tr)
    local last
    for _, h in ipairs(TLG.Tables.sortedKeys(notes or {})) do
        if h <= tr.from then last = h end
    end
    local note = last and notes[last]
    if type(note) ~= "table" then return 0, note end
    return math.max(0, math.min(tr.back, note.t + note.f / 60) - tr.from), note
end

-- Back from the trip, before any access: the hours away the mod's notes
-- cover against the harness's.
function RT.O.checkCredit(ctx, i)
    local O, tr = RT.O, ctx.trip
    local rec = O.items[i] and O.items[i]:getModData().tlgProc or {}
    local want, mine = O.covered(O.notes[i], tr)
    local got, theirs = O.covered(rec.fires, tr)
    R:line("OBS  RTO.credit %s last note before leaving: harness %s, mod %s", O.names[i], brief(mine), brief(theirs))
    R:check("RTO.away_hours_credited_" .. O.names[i], function()
        return want >= 1 and math.abs(got - want) < 1e-6,
            string.format("the mod's notes cover %.2f h of the %.2f h away, the harness's %.2f h", got,
                tr.back - tr.from, want)
    end)
end

-- The work done over the trip against the stage rule fed by each day's
-- temperature by the harness's rule (the mod advances each day at its mean
-- computed up to the read).
function RT.O.checkWork(ctx, i, before, env, now)
    local O, m = RT.O, ctx.m[i]
    local want, t = 0, before.h
    while t < now - 1e-9 do
        local d = env:dayIndex(t)
        local stop = math.min(now, env:dayStart(d + 1))
        want = want + RT.fermentRate(O.dayMean(i, d, now)) * (stop - t)
        t = stop
    end
    local did = RT.doneHours(O.items[i]) - before.done
    R:check("RTO.work_over_the_trip_" .. O.names[i], function()
        return before.stage == "ferment" and m.last.stage == "ferment" and math.abs(did - want) <= 0.01,
            string.format("%.2f to %.2f h in: did %.4f h, rule with the credit %.4f h", before.h - ctx.h0, now - ctx.h0,
                did, want)
    end)
end

function RT.O.refind()
    local O = RT.O
    for i = 1, 2 do O.items[i] = fermenterOn(O.mach[i].x, O.mach[i].y) or O.items[i] end
end

function RT.O.onLeave(ctx)
    local O = RT.O
    ctx.trip.fires, ctx.trip.minutes = {}, O.minutes
    for k = 1, 2 do
        local st = O.state(k)
        ctx.trip.fires[k] = { fuel = st and st.fuel or -1, lit = st ~= nil and st.lit }
    end
end

-- Back from the trip: each fire as the reload left it (the campfire burned
-- a minute per minute event, the barbecue by game time), the hours away
-- credited, then the fires tended again.
function RT.O.onReturn(ctx)
    local O, tr = RT.O, ctx.trip
    local awayMin, events = (tr.back - tr.from) * 60, O.minutes - tr.minutes
    local parts = {}
    for k = 1, 2 do
        local st, before = O.state(k), tr.fires[k]
        local want = math.max(0, before.fuel - (k == 1 and events or awayMin))
        if tr.unloaded then
            R:check("RTO.fire_burned_while_away_" .. O.names[k], function()
                if st == nil then return false, "not found again" end
                return before.lit and math.abs(st.fuel - want) <= (k == 1 and 2 or 15) and st.lit == (st.fuel > 0),
                    string.format("left lit=%s with %.1f min; back after %.0f game min (%d minute events): lit=%s with %.1f min (burning on: %.1f)",
                        tostring(before.lit), before.fuel, awayMin, events, tostring(st.lit), st.fuel, want)
            end)
        end
        parts[#parts + 1] = st and string.format("%s back lit=%s with %.1f min", O.names[k], tostring(st.lit), st.fuel)
            or (O.names[k] .. " not found again")
    end
    if tr.unloaded then
        for i = 1, 2 do O.checkCredit(ctx, i) end
    end
    for k = 1, 2 do parts[#parts + 1] = string.format("%s log added=%s", O.names[k], tostring(O.tend(k))) end
    return string.format("%d minute events in %.0f game min; %s", events, awayMin, table.concat(parts, "; "))
end

-- After fire k's snapshots: the checks on them, the machine's tile (free,
-- outdoors, beside the fire, warmed in every snapshot) and a log on.
function RT.O.settle(ctx, k)
    local O, snaps = RT.O, ctx.snaps
    local off = 0
    for _, sn in ipairs(snaps) do off = off + sn.mismatch end
    R:check("RTO.unlit_tiles_unwarmed_" .. O.names[k], function()
        local u = ctx.unlit
        return u.cold >= 20 and u.warm == 0 and u.blocked == 0 and u.mismatch == 0, O.snapText(u)
    end)
    R:check("RTO.tiles_follow_the_heat_formula_" .. O.names[k], function()
        return off == 0 and snaps[1].warm >= 3, string.format("%d tiles off the formula in %d lit snapshots; %d warmed at %.1f min",
            off, #snaps, snaps[1].warm, snaps[1].fuel)
    end)
    if k == 1 then
        local fl, rd = O.lawCount()
        O.law = (fl == #O.pairs and "floor") or (rd == #O.pairs and "round") or "neither"
        R:check("RTO.campfire_radius_follows_fuel", function()
            return #O.pairs >= 4 and O.law ~= "neither",
                string.format("fuel->radius %s; truncation fits %d, rounding %d of %d: %s", O.pairsText(), fl, rd,
                    #O.pairs, O.law)
        end)
    end
    local spot
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local x, y = O.site[k].x + d[1], O.site[k].y + d[2]
        local warm = spot == nil and O.outdoorFree(sq(x, y, 0))
        for _, sn in ipairs(snaps) do
            if warm and RT.F.classOf(sn, x, y) ~= "warm" then warm = false end
        end
        if warm then spot = { x = x, y = y } end
    end
    if spot == nil then
        RT.abort = "no warmed free tile beside the " .. O.names[k]
        R:line("OBS  RTO.machine tile %s", RT.abort)
        return
    end
    O.mach[k] = { x = spot.x, y = spot.y, dx = spot.x - O.site[k].x, dy = spot.y - O.site[k].y }
    O.srcRoom[k] = RT.W.inRoom(sq(O.site[k].x, O.site[k].y, 0))
    O.tend(k)
    local st = O.state(k)
    R:line("OBS  RTO.machine tile %s %d,%d beside the fire at %d,%d; fire lit=%s with %.1f min, radius %d; logs so far %d",
        O.names[k], spot.x, spot.y, O.site[k].x, O.site[k].y, tostring(st.lit), st.fuel, st.radius, O.logs[k])
end

RT.openSites = { name = "rto_sites", timeout = 3000, fn = function(ctx, ticks)
    local O = RT.O
    if not ctx.t0 and RT.skip("rto_sites") then return true end
    if not ctx.t0 then
        local here = player():getSquare()
        local camp = O.findOpen(here:getX(), here:getY())
        local bbq = camp and O.findOpen(camp.x, camp.y + O.apart, camp, O.apart)
        if bbq == nil then
            RT.abort = "no two open outdoor spots 24 tiles apart"
            R:line("OBS  RTO.sites %s (campfire spot %s)", RT.abort, brief(camp))
            return true
        end
        O.site, O.mach, O.srcRoom, O.logs, O.pairs = { camp, bbq }, {}, {}, { 0, 0 }, {}
        local okC, errC = pcall(function() SCampfireSystem.instance:addCampfire(sq(camp.x, camp.y, 0)) end)
        local okB, errB = pcall(function()
            local s = sq(bbq.x, bbq.y, 0)
            s:AddTileObject(IsoBarbecue.new(getCell(), s, getSprite(O.bbqSprite)))
        end)
        O.perLog = math.floor(ISCampingMenu.getFuelDurationForItem(instanceItem("Base.Log")) + 1e-6)
        O.paper = ISCampingMenu.getFuelDurationForItem(instanceItem("Base.SheetPaper2"))
        local ok, cap = pcall(getCampingFuelMax)
        O.cap = ok and cap or 480
        removeAll("Base.Log")
        give("Base.Log", 40); give("Base.SheetPaper2", 4); give("Base.Matches", 1)
        if not O.hooked then
            Events.EveryHours.Add(RT.O.onHour)
            Events.EveryTenMinutes.Add(RT.O.onTenMinutes)
            Events.EveryOneMinute.Add(RT.O.onMinute)
            O.hooked = true
        end
        local power
        pcall(function() power = getWorld():isHydroPowerOn() end)
        local ax, ay = bbq.x - camp.x, bbq.y - camp.y
        R:line("OBS  RTO.sites campfire %d,%d (built=%s %s), barbecue %d,%d (placed=%s %s), %.1f tiles apart; a log %d min, a sheet of paper %.2f min, cap %s min; grid power=%s",
            camp.x, camp.y, tostring(okC), tostring(errC or ""), bbq.x, bbq.y, tostring(okB), tostring(errB or ""),
            math.sqrt(ax * ax + ay * ay), O.perLog, O.paper, tostring(O.cap), tostring(power))
        R:check("RTO.grid_is_off", function() return power == false, "isHydroPowerOn=" .. tostring(power) end)
        ctx.t0 = ticks
        return nil
    end
    if ticks - ctx.t0 < 60 then return nil end
    local c, b, cl = O.campLua(), O.object(2, "IsoBarbecue"), nil
    pcall(function() cl = CCampfireSystem.instance:getLuaObjectAt(O.site[1].x, O.site[1].y, 0) end)
    R:check("RTO.fires_in_place", function()
        return c ~= nil and cl ~= nil and c.exterior == true and not c.isLit and b ~= nil and not b:isPropaneBBQ()
            and not b:isLit(), string.format("campfire server=%s client=%s exterior=%s lit=%s; barbecue=%s propane=%s lit=%s",
            tostring(c ~= nil), tostring(cl ~= nil), tostring(c and c.exterior), tostring(c and c.isLit),
            tostring(b ~= nil), tostring(b and b:isPropaneBBQ()), tostring(b and b:isLit()))
    end)
    if c == nil or b == nil then RT.abort = "a fire was not placed" end
    return true
end }

-- Per fire: the character beside it, the air around it unlit, Add fuel and
-- Light pressed from its menu (each waited out), the air around it lit (the
-- campfire's at three more fuel levels, set as vanilla's setFuel command
-- does, SRC SCampfireSystemCommands.lua), then the checks and the machine's
-- tile (RT.O.settle).
RT.openLight = { name = "rto_light", timeout = 30000, fn = function(ctx, ticks)
    local O = RT.O
    if not ctx.k and RT.skip("rto_light") then return true end
    RT.speed(1)
    if not ctx.k then ctx.k, ctx.phase = 1, "go" end
    local k, p = ctx.k, O.site[ctx.k]
    if ctx.phase == "go" then
        player():setPosition(p.x - 1 + 0.5, p.y + 0.5, 0)
        ctx.phase, ctx.tick = "fuel", ticks
        return nil
    end
    if ctx.phase == "fuel" then
        if ticks - ctx.tick < 60 then return nil end
        ctx.unlit = O.snapshot(k)
        R:line("OBS  RTO.snapshot %s unlit %s", O.names[k], O.snapText(ctx.unlit))
        ctx.pressedFuel = O.press(k, "add fuel", O.isAddLog)
        ctx.phase, ctx.tick = "fueling", ticks
        return nil
    end
    if ctx.phase == "fueling" or ctx.phase == "lighting" then
        if ticks - ctx.tick < 30 or (not TLGH.Steps.actionsIdle(player()) and ticks - ctx.tick < 3000) then return nil end
        local st = O.state(k)
        if ctx.phase == "fueling" then
            ctx.fueled = st and st.fuel or -1
            R:line("OBS  RTO.%s after Add fuel: lit=%s with %.1f min", O.names[k], tostring(st and st.lit), ctx.fueled)
            ctx.pressedLight = O.press(k, "light", O.isLightPaper)
            ctx.phase, ctx.tick = "lighting", ticks
            return nil
        end
        R:check("RTO.lit_from_menu_" .. O.names[k], function()
            return ctx.pressedFuel and ctx.pressedLight and st ~= nil and st.lit and ctx.fueled >= O.perLog - 1
                and st.fuel >= O.perLog - 1, string.format("Add fuel pressed=%s (then %.1f min), Light pressed=%s; now lit=%s with %.1f min, radius %s",
                tostring(ctx.pressedFuel), ctx.fueled, tostring(ctx.pressedLight), tostring(st and st.lit),
                st and st.fuel or -1, tostring(st and st.radius))
        end)
        -- Not lit from the menu: the run goes on with the actions' own calls.
        if not (st and st.lit) then O.tend(k) end
        ctx.phase, ctx.snaps, ctx.tick = "snap", {}, ticks
        return nil
    end
    if ticks - ctx.tick < 30 then return nil end
    local snap = O.snapshot(k)
    ctx.snaps[#ctx.snaps + 1] = snap
    R:line("OBS  RTO.snapshot %s %s", O.names[k], O.snapText(snap))
    if k == 1 then
        O.pairs[#O.pairs + 1] = { f = snap.fuel, r = snap.radius }
        local f = O.campFuels[#ctx.snaps]
        if f then
            O.campLua():setFuel(f)
            ctx.tick = ticks
            return nil
        end
    end
    O.settle(ctx, k)
    if RT.abort then return true end
    ctx.k, ctx.phase = k + 1, "go"
    return ctx.k > 2 or nil
end }

-- Places both fermenters on their tiles, then loads each from its menu with
-- the character beside it (its square follows a few ticks after the move);
-- true once both batches run.
function RT.O.placeAndLoad(ctx, ticks)
    local O = RT.O
    if not ctx.t0 then
        O.items, O.readings, O.notes, O.unloaded = {}, { {}, {} }, { {}, {} }, {}
        for i = 1, 2 do
            local it = instanceItem("TLG.FermenterVessel")
            sq(O.mach[i].x, O.mach[i].y, 0):AddWorldInventoryItem(it, 0.5, 0.5, 0, false)
            O.items[i] = it
        end
        O.home = O.mach[1]
        removeAll("Base.Sugar"); removeAll("Base.Yeast")
        ctx.t0, ctx.li = ticks, 0
        return false
    end
    if ctx.at then
        if ticks - ctx.at < 3 then return false end
        local i = ctx.li
        give("Base.Sugar", 6); give("Base.Yeast", 1)
        for _ = 1, 3 do
            local fc = player():getInventory():AddItem("Base.BucketEmpty"):getFluidContainer()
            fc:Empty()
            fc:addFluid(Fluid.Water, 10)
        end
        local r = machineClick("RTO.load_" .. O.names[i], O.items[i], "ContextMenu_TLG_LoadFerment")
        R:check("RTO.loaded_" .. O.names[i], function()
            return r.ok == true and math.abs((r.sugarKg or 0) - 6) < 1e-6 and math.abs((r.waterL or 0) - 30) < 1e-6,
                string.format("sugar=%s water=%s", tostring(r.sugarKg), tostring(r.waterL))
        end)
        ctx.at = nil
        if i < 2 then return false end
        player():setPosition(O.home.x + 0.5, O.home.y + 0.5, 0)
        return true
    end
    if ticks - ctx.t0 < 60 then return false end
    ctx.li = ctx.li + 1
    local i = ctx.li
    local site = TLG.Integration.Machines.siteOf(sq(O.mach[i].x, O.mach[i].y, 0))
    R:check("RTO.site_seen_outdoors_" .. O.names[i], function()
        return site.room == false and site.z == 0, string.format("room=%s z=%s", tostring(site.room), tostring(site.z))
    end)
    player():setPosition(O.mach[i].x + 0.5, O.mach[i].y + 0.5, 0)
    ctx.at = ticks
    return false
end

function RT.O.startAccounting(ctx)
    local O, env = RT.O, TLG.World.env()
    O.active, O.tending, O.hourly = true, true, {}
    ctx.h0, ctx.next, ctx.m = hours(), hours() + 1, {}
    for i = 1, 2 do
        O.hourly[i] = { n = 0, worst = 0, where = "none", lit = 0, lagged = 0, minGain = math.huge,
            maxGain = -math.huge, minAir = math.huge }
        ctx.m[i] = { prev = { h = hours(), done = RT.doneHours(O.items[i]), day = env:dayIndex(hours()),
            stage = "prepare" }, rule = { n = 0, worst = 0, where = "none" },
            meanBefore = { n = 0, worst = 0, where = "none" }, meanAfter = { n = 0, worst = 0, where = "none" },
            filed = { n = 0, worst = 0, where = "none" }, compared = -math.huge, afterTrip = 0, days = {},
            notes = { n = 0, fire = 0, off = 0 }, notesCompared = -math.huge, refused = 0 }
    end
end

-- One hourly round: the character is set beside each machine in turn (the
-- authority answers within 2.5 tiles) and reads it, then goes back; the
-- first round after the trip checks the work over it. True when it is over.
function RT.O.round(ctx, ticks)
    local O, r = RT.O, ctx.round
    if r.i <= 2 then
        if not r.at then
            player():setPosition(O.mach[r.i].x + 0.5, O.mach[r.i].y + 0.5, 0)
            r.at = ticks
        elseif ticks - r.at >= 3 then
            local env, now = TLG.World.env(), hours()
            r.when[r.i] = now
            O.read(ctx, r.i, env, now, env:dayIndex(now))
            r.i, r.at = r.i + 1, nil
        end
        return false
    end
    player():setPosition(O.home.x + 0.5, O.home.y + 0.5, 0)
    if r.before then
        ctx.workChecked = true
        local env = TLG.World.env()
        for i = 1, 2 do O.checkWork(ctx, i, r.before[i], env, r.when[i]) end
    end
    return true
end

function RT.O.finish(ctx, env, now)
    local O = RT.O
    O.active, O.tending = false, false
    local log = TLG.World.get().climateLog or {}
    for i = 1, 2 do
        local m, h = ctx.m[i], O.hourly[i]
        for _, d in ipairs(TLG.Tables.sortedKeys(m.days)) do
            local x, sum, n = m.days[d], 0, 0
            for s, v in pairs(O.readings[i]) do
                if env:dayIndex(s + 0.5) == d then sum, n = sum + v, n + 1 end
            end
            local rec = log[d] or {}
            R:line("OBS  RTO.day %s %s: air read at the machine %s; recorded outdoor mean %s; day temperature %s C, work %.2f h, paused %.2f h",
                O.names[i], x.label, n > 0 and string.format("%.1f (%d h)", sum / n, n) or "-",
                rec.t and string.format("%.2f", rec.t) or "-", x.siteC and string.format("%.2f", x.siteC) or "-",
                x.work, x.paused)
        end
        local st, rec = m.last or {}, O.items[i]:getModData().tlgProc or {}
        R:line("OBS  RTO.end %s state=%s pause=%s pausedFor %.2f h after %.1f game h; logs on its fire %d; hours read %d, the fire lit at %d warming the machine %s to %s C (lowest air %s C), heat radius a minute behind at %d; refused reads %d (%s); status: %s",
            O.names[i], tostring(st.state), tostring(st.pause), rec.pausedFor or -1, now - ctx.h0, O.logs[i], h.n,
            h.lit, h.lit > 0 and string.format("%.2f", h.minGain) or "-",
            h.lit > 0 and string.format("%.2f", h.maxGain) or "-", h.lit > 0 and string.format("%.2f", h.minAir) or "-",
            h.lagged, m.refused, tostring(m.refusedWhy or "none"), tostring(m.dialog))
    end
    local fl, rd = O.lawCount()
    R:line("OBS  RTO.campfire radius over the run: %d (fuel, radius) readings, truncation fits %d, rounding %d; %d minute events",
        #O.pairs, fl, rd, O.minutes)
    R:check("RTO.campfire_radius_law_holds", function()
        return (O.law == "floor" and fl == #O.pairs) or (O.law == "round" and rd == #O.pairs),
            string.format("%s: truncation fits %d, rounding %d of %d", tostring(O.law), fl, rd, #O.pairs)
    end)
    for i = 1, 2 do
        local m, h, name = ctx.m[i], O.hourly[i], O.names[i]
        R:check("RTO.reads_answered_" .. name, function()
            return m.refused == 0, string.format("%d refused (%s)", m.refused, tostring(m.refusedWhy or "none"))
        end)
        R:check("RTO.machine_air_is_the_formula_" .. name, function()
            return h.n >= 24 and h.lit >= 24 and h.worst <= O.tol,
                string.format("%d hours (%d lit, %d with the radius of a minute before), worst %.5f C (%s)", h.n, h.lit,
                    h.lagged, h.worst, h.where)
        end)
        R:check("RTO.readings_filed_" .. name, function()
            return m.filed.n >= 24 and m.filed.worst <= 1e-6,
                string.format("%d hours, worst %.6f (%s)", m.filed.n, m.filed.worst, m.filed.where)
        end)
        R:check("RTO.notes_filed_" .. name, function()
            return m.notes.n >= 30 and m.notes.fire >= m.notes.n * 3 / 4 and m.notes.off == 0,
                string.format("%d hours noted, %d with the fire, %d off (%s)", m.notes.n, m.notes.fire, m.notes.off,
                    tostring(m.notes.where or "none"))
        end)
        R:check("RTO.day_temperature_before_the_trip_" .. name, function()
            return m.meanBefore.n >= 20 and m.meanBefore.worst <= 1e-6,
                string.format("%d reads, worst %.6f (%s)", m.meanBefore.n, m.meanBefore.worst, m.meanBefore.where)
        end)
        R:check("RTO.day_temperature_after_the_trip_" .. name, function()
            return m.meanAfter.n >= 6 and m.meanAfter.worst <= 1e-6,
                string.format("%d reads, worst %.6f (%s)", m.meanAfter.n, m.meanAfter.worst, m.meanAfter.where)
        end)
        R:check("RTO.progress_follows_site_temperature_" .. name, function()
            return m.rule.n >= 24 and m.rule.worst <= 0.01,
                string.format("%d hours, worst %.4f h (%s)", m.rule.n, m.rule.worst, m.rule.where)
        end)
        R:check("RTO.status_names_the_site_" .. name, function()
            return has(m.dialog, getText("IGUI_TLG_Site_outdoors")), tostring(m.dialog)
        end)
    end
    if ctx.trip and ctx.trip.unloaded then
        R:check("RTO.readings_resume_after_return", function()
            return ctx.m[1].afterTrip >= 6 and ctx.m[2].afterTrip >= 6,
                string.format("%d and %d hours filed after the return", ctx.m[1].afterTrip, ctx.m[2].afterTrip)
        end)
    end
end

RT.openFerment = { name = "rto_ferment", timeout = 150000, fn = function(ctx, ticks)
    local O = RT.O
    if not ctx.h0 and not ctx.t0 and RT.skip("rto_ferment") then return true end
    if not ctx.h0 then
        if O.placeAndLoad(ctx, ticks) then O.startAccounting(ctx) end
        return nil
    end
    if ticks % 30 == 0 then RT.keepFit() end
    -- A quarter hour before leaving each fire gets what a log can add, so a
    -- ten-minute note sees the fuel it leaves with.
    if not ctx.fed and hours() - ctx.h0 >= O.tripAt - 0.25 then
        ctx.fed = {}
        for k = 1, 2 do
            local added, st = O.tend(k), O.state(k)
            ctx.fed[k] = string.format("%s log added=%s, %.1f min", O.names[k], tostring(added), st and st.fuel or -1)
        end
        R:line("OBS  RTO.fed before leaving: %s", table.concat(ctx.fed, "; "))
    end
    if not ctx.round and tripStep(O, ctx, ticks) then return nil end
    RT.speed(RT.waitSpeed)
    if not ctx.round then
        if hours() < ctx.next then return nil end
        ctx.next = hours() + 1
        ctx.round = { i = 1, when = {} }
        if ctx.trip and ctx.trip.checked and not ctx.workChecked then
            ctx.round.before = {}
            for i = 1, 2 do
                local p = ctx.m[i].prev
                ctx.round.before[i] = { h = p.h, done = p.done, stage = p.stage }
            end
        end
    end
    if not O.round(ctx, ticks) then return nil end
    ctx.round = nil
    local now = hours()
    local back = ctx.trip and ctx.trip.back
    if (back == nil or now - back < O.afterHours) and now - ctx.h0 < 120 then return nil end
    RT.speed(1)
    O.finish(ctx, TLG.World.env(), now)
    return true
end }

RT.openFireSteps = { RT.waitWorld, RT.setup, RT.openSites, RT.openLight, RT.openFerment, RT.finish }

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

if REQUEST == "sp-a" or REQUEST == "sp-rt" or REQUEST == "sp-rtw" or REQUEST == "sp-rtf" or REQUEST == "sp-rtfs"
    or REQUEST == "sp-rtp" or REQUEST == "sp-rtpot" or REQUEST == "sp-rtc" or REQUEST == "sp-rtof" then
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", true)
    debugScenarios = debugScenarios or {}
    debugScenarios.TLGHarnessA = {
        name = (REQUEST == "sp-a") and "TLG harness phase A" or "TLG harness, real game clock",
        forceLaunch = true,
        startLoc = START,
        setSandbox = function()
            -- Called right before createWorld. The debug-scenario path does not
            -- give the new world any mods (vanilla says so in
            -- MainScreen.resetLuaIfNeeded), so its mods.txt was empty and the
            -- continued save loaded neither mod (RT-SP 2026-10-31 run 3). Same
            -- copy as the Solo path (SRC MainScreen.lua:1400).
            ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
            SandboxVars.Zombies = 6
            SandboxVars.FuelStationGasEmptyChance = 0
            SandboxVars.FuelStationGasInfinite = false
            if REQUEST == "sp-rtw" or REQUEST == "sp-rtf" or REQUEST == "sp-rtfs" or REQUEST == "sp-rtof" then
                -- Mid-January, as vanilla scenarios set the date
                -- (SRC DebugUIs/Scenarios/AiteronScenario.lua:16-18).
                SandboxVars.StartMonth = 1
                SandboxVars.StartDay = 15
                SandboxVars.StartTime = 2
                -- Grid off from the start: power exists while the world's
                -- age in days is at most ElecShutModifier (BC
                -- SandboxOptions.doesPowerGridExist), and a powered room
                -- holds 22 C. ElecShut 1 is the preset without a random day
                -- (BC SandboxOptions.randomElectricityShut).
                SandboxVars.ElecShut = 1
                SandboxVars.ElecShutModifier = -1
            elseif REQUEST == "sp-rtp" or REQUEST == "sp-rtpot" or REQUEST == "sp-rtc" then
                -- Grid on for 30 days, as vanilla's Multiplayer debug scenario
                -- sets it (SRC DebugUIs/Scenarios/Multiplayer.lua:23).
                SandboxVars.ElecShutModifier = 30
            end
        end,
        onStart = function()
            if REQUEST == "sp-rt" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock")
                TLGH.Steps.run(R, stepsRT, H, nil)
            elseif REQUEST == "sp-rtw" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, winter")
                TLGH.Steps.run(R, RT.winterSteps, H, nil)
            elseif REQUEST == "sp-rtf" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, fireplace")
                TLGH.Steps.run(R, RT.fireplaceSteps, H, nil)
            elseif REQUEST == "sp-rtfs" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, fireplace, before the save")
                TLGH.Steps.run(R, RT.fireSaveSteps, H, nil)
            elseif REQUEST == "sp-rtp" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, pickup")
                TLGH.Steps.run(R, RT.pickupSteps, H, nil)
            elseif REQUEST == "sp-rtpot" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, pot still")
                TLGH.Steps.run(R, RT.potSteps, H, nil)
            elseif REQUEST == "sp-rtc" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, machine controls")
                TLGH.Steps.run(R, RT.controlSteps, H, nil)
            elseif REQUEST == "sp-rtof" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock, open fires")
                TLGH.Steps.run(R, RT.openFireSteps, H, nil)
            else
                R = TLGH.Report.new(RESULTS, "TLG single-player harness phase A")
                TLGH.Steps.run(R, stepsA, H, nil)
            end
        end,
    }
else
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", false)
end

if REQUEST == "sp-b" or REQUEST == "sp-rtfb" then
    Events.OnMainMenuEnter.Add(function()
        if TLGH.continued then return end
        TLGH.continued = true
        MainScreen.instance:getLatestSave()
        print("[TLGH] continuing " .. tostring(MainScreen.latestSaveWorld))
        MainScreen.continueLatestSave(MainScreen.latestSaveGameMode, MainScreen.latestSaveWorld)
    end)
    Events.OnGameStart.Add(function()
        if REQUEST == "sp-rtfb" then
            R = TLGH.Report.new(RESULTS, "TLG single-player harness, fireplace, after the reload", true)
            TLGH.Steps.run(R, RT.fireReloadSteps, H, nil)
        else
            R = TLGH.Report.new(RESULTS, "TLG single-player harness phase B", true)
            TLGH.Steps.run(R, stepsB, H, nil)
        end
    end)
end
