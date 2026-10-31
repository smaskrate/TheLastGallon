-- Single-player client harness (gates G01 client, G02, G03, G04, G05, G06,
-- G08, G09 and the end-to-end proof). Driven by
-- <cachedir>/Lua/TLG_harness_request.txt:
--   sp-a  -> force-launch a debug scenario at the Muldraugh Gas2Go, run phase A,
--            save, write "sp-b", exit to menu
--   sp-b  -> main menu continues the latest save, run phase B (persistence),
--            write "done", quit to desktop
--   sp-rt -> same scenario, only the ethanol loop on the real game clock,
--            write "done", quit to desktop (no save/reload)
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
if REQUEST == "sp-a" or REQUEST == "sp-b" or REQUEST == "sp-rt" then
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
    local ok, err = pcall(opt.onSelect, opt.target, opt.param1, opt.param2, opt.param3, opt.param4)
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

function RT.add(step) stepsRT[#stepsRT + 1] = step end

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

RT.add({ name = "rt_wait_world", timeout = 3000, fn = function(ctx, ticks)
    if player() and ticks > 120 then
        R:line("worldName=%s hours=%.4f DayLength=%s", tostring(getWorld():getWorld()), hours(),
            tostring(SandboxVars and SandboxVars.DayLength))
        return true
    end
end })

RT.add({ name = "rt_setup", timeout = 3000, fn = function(ctx, ticks)
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

RT.add({ name = "rt_finish", timeout = 600, fn = function(ctx, ticks)
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
-- Wiring
------------------------------------------------------------------------------
-- Diagnostics so a stall before the scenario can be located from the log.
print("[TLGH] SPHarness loaded, request=" .. tostring(REQUEST) .. " debug=" .. tostring(getDebug()))
Events.OnMainMenuEnter.Add(function()
    print("[TLGH] OnMainMenuEnter request=" .. tostring(REQUEST) .. " debug=" .. tostring(getDebug()) ..
        " scenarioA=" .. tostring(debugScenarios ~= nil and debugScenarios.TLGHarnessA ~= nil) ..
        " forceLaunch=" .. tostring(getDebugOptions():getBoolean("DebugScenario.ForceLaunch")))
end)

if REQUEST == "sp-a" or REQUEST == "sp-rt" then
    getDebugOptions():setBoolean("DebugScenario.ForceLaunch", true)
    debugScenarios = debugScenarios or {}
    debugScenarios.TLGHarnessA = {
        name = REQUEST == "sp-rt" and "TLG harness, real game clock" or "TLG harness phase A",
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
        end,
        onStart = function()
            if REQUEST == "sp-rt" then
                R = TLGH.Report.new(RESULTS, "TLG single-player harness, real game clock")
                TLGH.Steps.run(R, stepsRT, H, nil)
            else
                R = TLGH.Report.new(RESULTS, "TLG single-player harness phase A")
                TLGH.Steps.run(R, stepsA, H, nil)
            end
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
