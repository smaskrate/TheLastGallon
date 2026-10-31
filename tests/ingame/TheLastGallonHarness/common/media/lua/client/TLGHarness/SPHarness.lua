-- Single-player client harness (gates G01 client, G02, G03, G04, G05, G06,
-- G08, G09 and the end-to-end proof). Driven by
-- <cachedir>/Lua/TLG_harness_request.txt:
--   sp-a  -> force-launch a debug scenario at the Muldraugh Gas2Go, run phase A,
--            save, write "sp-b", exit to menu
--   sp-b  -> main menu continues the latest save, run phase B (persistence),
--            write "done", quit to desktop
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
if REQUEST == "sp-a" or REQUEST == "sp-b" then
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

-- TLG pours into vehicle 2 (8 L E25 from the G03 pour). The transfer checks
-- that the player stands in the fuel-cap area, so the step places the
-- player first (see the G06 note on teleportTo).
local function vehiclePourStep(name, fills, experimental, expectOk)
    return { name = name, timeout = 4000, fn = function(ctx, ticks)
        local v, part = H.vehicle2, H.tank2
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
            local can, fc = giveCan("Base.PetrolCan", fills)
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
local function vehicleGateStep(name, getVehicle, expectRefused)
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
            R:line("OBS  %s driver=%s %s", name, tostring(v:isDriver(player())), evaluationText(TLG.Integration.Vehicles.evaluate(v)))
            captureTlgDebug(ctx)
            ISTimedActionQueue.add(ISStartVehicleEngine:new(player()))
            ctx.queued, ctx.t1 = true, ticks
            return nil
        end
        if ticks - ctx.t1 < 180 then return nil end
        ctx.restoreLog()
        local refusal = loggedMatching(ctx, "vehicle start refused")
        local running = v:isEngineRunning()
        R:line("OBS  %s state=%s running=%s refusal=%s", name, tostring(v:getEngineState()), tostring(running), tostring(refusal))
        if expectRefused then
            R:check(name .. ".refused_by_tlg", function() return refusal ~= nil and not running, tostring(refusal) end)
        else
            R:check(name .. ".not_refused_by_tlg", function()
                return refusal == nil, string.format("state=%s running=%s", tostring(v:getEngineState()), tostring(running))
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
