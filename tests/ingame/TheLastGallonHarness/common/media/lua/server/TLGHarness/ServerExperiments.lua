-- Dedicated-server experiments for gates G01 (packaging), G02 (fluids, item
-- level) and G08 (global ModData persistence across restarts).
-- Results: <cachedir>/Lua/TLG_harness_server.txt (see docs/engine-capabilities.md).
require "TLGHarness/Report"
require "TLGHarness/LuaProbe"

if not isServer() then return end

local function fluidNames(fc)
    local s = fc:createFluidSample()
    local parts = {}
    for i = 0, s:size() - 1 do
        local f = s:getFluid(i)
        parts[#parts + 1] = string.format("%s=%.6f", f:getFluidTypeString(), fc:getSpecificFluidAmount(f))
    end
    s:release()
    return table.concat(parts, ",")
end

local function newEmptyCan(fullType)
    local item = instanceItem(fullType)
    local fc = item:getFluidContainer()
    fc:Empty()
    return item, fc
end

local function runG01(r)
    r:line("## G01 packaging")
    r:check("G01.tlg_namespace_loaded", function() return TLG ~= nil and TLG.VERSION ~= nil, TLG and TLG.VERSION end)
    r:check("G01.script_item_instance", function()
        local item = instanceItem("TLG.FuelSampleKit")
        return item ~= nil, item and (item:getFullType() .. " / " .. tostring(item:getDisplayName()))
    end)
    r:check("G01.translation_IG_UI", function()
        local t = getText("IGUI_TLG_ModName")
        return t == "The Last Gallon", t
    end)
    r:check("G01.translation_ItemName", function()
        local item = instanceItem("TLG.FuelSampleKit")
        local n = item and item:getDisplayName()
        return n == "Fuel Sampling Kit", n
    end)
    r:check("G01.translation_Fluid", function()
        local t = getText("Fluid_Name_TLG_Ethanol")
        return t == "Ethanol", t
    end)
    r:observe("G01.core_version", function() return getCore():getVersion() end)
    r:observe("G01.activated_mods", function()
        local mods = getActivatedMods()
        local out = {}
        for i = 0, mods:size() - 1 do out[#out + 1] = tostring(mods:get(i)) end
        return table.concat(out, ";")
    end)
end

local function runG02(r)
    r:line("## G02 fluids (item level, no world)")
    local eth
    r:check("G02.fluid_lookup_plain_name", function()
        eth = Fluid.Get("TLG_Ethanol")
        return eth ~= nil, eth and eth:getFluidTypeString()
    end)
    r:observe("G02.fluid_lookup_module_qualified", function() return tostring(Fluid.Get("TLG.TLG_Ethanol")) end)
    r:observe("G02.mod_fluids_registered", function()
        local all = Fluid.getAllFluids()
        local out = {}
        for i = 0, all:size() - 1 do
            local f = all:get(i)
            if not f:isVanilla() then out[#out + 1] = f:getFluidTypeString() .. "(" .. tostring(f:getFluidType()) .. ")" end
        end
        return table.concat(out, ",")
    end)
    if not eth then
        r:line("ABORT G02: mod fluid not resolvable")
        return
    end
    r:check("G02.fuel_category", function() return eth:isCategory(FluidCategory.Fuel), "Fuel category" end)
    r:check("G02.blend_petrol_ethanol", function()
        return eth:canBlendWith(Fluid.Petrol) and Fluid.Petrol:canBlendWith(eth),
            tostring(eth:canBlendWith(Fluid.Petrol)) .. "/" .. tostring(Fluid.Petrol:canBlendWith(eth))
    end)
    r:observe("G02.blend_petrol_water", function() return tostring(Fluid.Petrol:canBlendWith(Fluid.Water)) end)

    local canA, fcA = newEmptyCan("Base.PetrolCan")
    r:observe("G02.petrolcan_capacity", function() return fcA:getCapacity() end)
    r:observe("G02.petrolcan_spawn_amount", function()
        local fresh = instanceItem("Base.PetrolCan")
        return fresh:getFluidContainer():getAmount() .. " " .. fluidNames(fresh:getFluidContainer())
    end)
    r:check("G02.add_mixture", function()
        fcA:addFluid(Fluid.Petrol, 6.0)
        fcA:addFluid(eth, 2.0)
        return math.abs(fcA:getAmount() - 8.0) < 1e-4 and fcA:isMixture(), fluidNames(fcA)
    end)
    r:observe("G02.primary_fluid_of_mixture", function() return fcA:getPrimaryFluid():getFluidTypeString() end)
    r:observe("G02.canAddFluid_water_into_petrol", function() return tostring(fcA:canAddFluid(Fluid.Water)) end)

    local canB, fcB = newEmptyCan("Base.PetrolCan")
    r:check("G02.transfer_proportional", function()
        local can = FluidContainer.CanTransfer(fcA, fcB)
        FluidContainer.Transfer(fcA, fcB, 4.0)
        local p = fcB:getSpecificFluidAmount(Fluid.Petrol)
        local e = fcB:getSpecificFluidAmount(eth)
        return can and math.abs(p - 3.0) < 1e-4 and math.abs(e - 1.0) < 1e-4,
            "A[" .. fluidNames(fcA) .. "] B[" .. fluidNames(fcB) .. "]"
    end)
    r:check("G02.adjustAmount_scales_proportionally", function()
        fcB:adjustAmount(2.0)
        local p = fcB:getSpecificFluidAmount(Fluid.Petrol)
        local e = fcB:getSpecificFluidAmount(eth)
        return math.abs(p - 1.5) < 1e-4 and math.abs(e - 0.5) < 1e-4, fluidNames(fcB)
    end)
    r:check("G02.transfer_clamped_to_capacity", function()
        local _, fcC = newEmptyCan("Base.JerryCan")
        fcC:addFluid(Fluid.Petrol, 20.0)
        local _, fcD = newEmptyCan("Base.PetrolCan")
        fcD:addFluid(Fluid.Petrol, 9.0)
        FluidContainer.Transfer(fcC, fcD, 5.0)
        return math.abs(fcD:getAmount() - 10.0) < 1e-4 and math.abs(fcC:getAmount() - 19.0) < 1e-4,
            string.format("src=%.6f dst=%.6f", fcC:getAmount(), fcD:getAmount())
    end)
    r:observe("G02.tiny_transfers_drift", function()
        local _, fcE = newEmptyCan("Base.JerryCan")
        fcE:addFluid(Fluid.Petrol, 10.0)
        fcE:addFluid(eth, 3.0)
        local _, fcF = newEmptyCan("Base.JerryCan")
        for _ = 1, 1000 do FluidContainer.Transfer(fcE, fcF, 0.001) end
        for _ = 1, 1000 do FluidContainer.Transfer(fcF, fcE, 0.001) end
        return string.format("total=%.7f (expected 13) E=%s F=%s", fcE:getAmount() + fcF:getAmount(),
            fluidNames(fcE), fluidNames(fcF))
    end)
    r:observe("G02.item_moddata_roundtrip", function()
        local md = canA:getModData()
        md.tlgProbe = { a = 1.25, nested = { b = "x" } }
        local back = canA:getModData().tlgProbe
        return tostring(back and back.a) .. "/" .. tostring(back and back.nested and back.nested.b)
    end)
    r:check("G02.wrap_FluidContainer_Transfer_from_lua", function()
        local original = FluidContainer.Transfer
        local calls = 0
        FluidContainer.Transfer = function(a, b, amount, ...)
            calls = calls + 1
            return original(a, b, amount, ...)
        end
        local _, fcG = newEmptyCan("Base.PetrolCan")
        fcG:addFluid(Fluid.Petrol, 2.0)
        local _, fcH = newEmptyCan("Base.PetrolCan")
        FluidContainer.Transfer(fcG, fcH, 1.0)
        FluidContainer.Transfer = original
        return calls == 1 and math.abs(fcH:getAmount() - 1.0) < 1e-4, "calls=" .. calls .. " dst=" .. fcH:getAmount()
    end)
    r:observe("G02.propane_tank_api", function()
        local tank = instanceItem("Base.PropaneTank")
        return string.format("uses=%s usedDelta=%s fc=%s", tostring(tank:getCurrentUses()),
            tostring(tank.getUsedDelta and tank:getUsedDelta()), tostring(tank:getFluidContainer()))
    end)
end

-- M2-01 container adapter on real native containers (no world needed).
local function runAdapter(r)
    r:line("## M2-01 container adapter (TLG.Integration.Containers)")
    TLG.Boot.install()
    local World, C, Native = TLG.World, TLG.Integration.Containers, TLG.Integration.Native
    local eth = Fluid.Get("TLG_Ethanol")
    r:check("M2.world_record", function()
        local w = World.ensure()
        return w.v == 1 and w.seed ~= nil, string.format("policy=%s seed=%s epoch=%s installedAt=%s calendar=%s/%s",
            tostring(w.policy), tostring(w.seed), tostring(w.epoch), tostring(w.installedAt),
            tostring(w.calendar and w.calendar.dayOfYear), tostring(w.calendar and w.calendar.hourOfDay))
    end)
    r:check("M2.mod_fluids_all_registered", function()
        local missing = {}
        for _, n in ipairs({ "TLG_FuelWater", "TLG_FuelSediment", "TLG_Methanol", "TLG_Glycerin", "TLG_PlantOil" }) do
            if Fluid.Get(n) == nil then missing[#missing + 1] = n end
        end
        return #missing == 0, "missing=" .. table.concat(missing, ",")
    end)
    r:observe("M2.adjustSpecificFluidAmount_semantics", function()
        local _, fc = newEmptyCan("Base.PetrolCan")
        fc:addFluid(Fluid.Petrol, 5.0)
        fc:adjustSpecificFluidAmount(Fluid.Petrol, 3.0)
        return string.format("after adjust(3) from 5 -> %.4f (3=set, 8=add)", fc:getSpecificFluidAmount(Fluid.Petrol))
    end)
    r:check("M2.native_write_composition", function()
        local _, fc = newEmptyCan("Base.JerryCan")
        fc:addFluid(Fluid.Petrol, 4.0)
        fc:addFluid(eth, 1.0)
        local ok, why = Native.writeComposition(fc, { gasoline = 2.0, ethanol = 3.0, water = 0.1, sediment = 0.02 })
        local comp = Native.readComposition(fc)
        return ok and math.abs((comp.gasoline or 0) - 2) < 1e-4 and math.abs((comp.ethanol or 0) - 3) < 1e-4
            and math.abs((comp.water or 0) - 0.1) < 1e-4 and math.abs((comp.sediment or 0) - 0.02) < 1e-4,
            tostring(why) .. " " .. fluidNames(fc)
    end)
    r:check("M2.transfer_hook_carries_condition", function()
        local canA, fcA = newEmptyCan("Base.JerryCan")
        fcA:addFluid(Fluid.Petrol, 6.0)
        fcA:addFluid(eth, 2.0)
        local now = World.now()
        canA:getModData().tlg = { v = 1, id = "TEST-A", rev = 5, t = now, storage = "jerrycan_steel", sealed = true,
            cond = 1, dirty = 0, stab = 0.5, mic = 0, deg = { gasoline = 1.2, ethanol = 0.3 },
            q = { gasoline = 6.0, ethanol = 2.0 }, prov = {} }
        local canB, fcB = newEmptyCan("Base.PetrolCan")
        FluidContainer.Transfer(fcA, fcB, 4.0)
        local sb = canB:getModData().tlg
        local sa = canA:getModData().tlg
        return sb ~= nil and sa.rev == 6 and math.abs(sb.deg.gasoline - 1.2) < 1e-6 and math.abs(sb.deg.ethanol - 0.3) < 1e-6
            and math.abs(sb.stab - 0.5) < 1e-9 and math.abs(sb.q.gasoline - 3) < 1e-4 and math.abs(sb.q.ethanol - 1) < 1e-4,
            string.format("A.rev=%s B=%s", tostring(sa.rev), sb and string.format("rev=%d deg=%.4f/%.4f q=%.4f/%.4f stab=%.3f prov=%s",
                sb.rev, sb.deg.gasoline, sb.deg.ethanol, sb.q.gasoline, sb.q.ethanol, sb.stab, tostring(sb.prov[1] and sb.prov[1].from)) or "nil")
    end)
    r:check("M2.untracked_inflow_never_fresh", function()
        local can, fc = newEmptyCan("Base.JerryCan")
        fc:addFluid(Fluid.Petrol, 5.0)
        can:getModData().tlg = { v = 1, id = "TEST-U", rev = 0, t = World.now(), storage = "jerrycan_steel", sealed = true,
            cond = 1, dirty = 0, stab = 0, mic = 0, deg = { gasoline = 0.0 }, q = { gasoline = 5.0 }, prov = {} }
        fc:addFluid(Fluid.Petrol, 5.0)
        local rec, status = C.read(can, "item", false)
        local base = C.untrackedDeg()
        return status == "reconciled" and math.abs(rec.deg.gasoline - base / 2) < 1e-6,
            string.format("status=%s deg=%.6f baseline=%.6f", tostring(status), rec.deg.gasoline, base)
    end)
    r:check("M2.many_small_hooked_transfers_conserve", function()
        local canA, fcA = newEmptyCan("Base.JerryCan")
        fcA:addFluid(Fluid.Petrol, 10.0)
        canA:getModData().tlg = { v = 1, id = "TEST-S", rev = 0, t = World.now(), storage = "jerrycan_steel", sealed = true,
            cond = 1, dirty = 0, stab = 0, mic = 0, deg = { gasoline = 2.0 }, q = { gasoline = 10.0 }, prov = {} }
        local canB, fcB = newEmptyCan("Base.JerryCan")
        for _ = 1, 200 do FluidContainer.Transfer(fcA, fcB, 0.01) end
        local sb = canB:getModData().tlg
        local total = fcA:getAmount() + fcB:getAmount()
        return math.abs(total - 10) < 1e-3 and sb and math.abs(sb.deg.gasoline - 2.0) < 1e-6 and sb.rev == 200,
            string.format("total=%.5f B=%.5f deg=%s rev=%s", total, fcB:getAmount(), tostring(sb and sb.deg.gasoline), tostring(sb and sb.rev))
    end)
    r:observe("M2.foreign_fluid_not_tracked", function()
        local bottle = instanceItem("Base.WaterBottle")
        local fc = bottle and bottle:getFluidContainer()
        if not fc then return "no bottle item" end
        local rec, why = C.read(bottle, "item", false)
        return tostring(rec) .. " / " .. tostring(why)
    end)
end

local function runG08(r)
    r:line("## G08 global ModData across restarts")
    local md = ModData.getOrCreate("TLGHarness")
    md.boots = (md.boots or 0) + 1
    md.history = md.history or {}
    md.history[#md.history + 1] = getGameTime():getWorldAgeHours()
    r:observe("G08.boot_count", function() return md.boots end)
    r:observe("G08.world_age_hours_history", function()
        local parts = {}
        for i = 1, #md.history do parts[#parts + 1] = string.format("%.4f", md.history[i]) end
        return table.concat(parts, ",")
    end)
end

local function run()
    local r = TLGH.Report.new("TLG_harness_server.txt", "TLG dedicated-server harness")
    r:line("worldAgeHours=%.4f", getGameTime():getWorldAgeHours())
    TLGH.runLuaProbe(r)
    runG01(r)
    runG02(r)
    runAdapter(r)
    runG08(r)
    r:observe("G08.saveGame_call", function() saveGame(); return "called" end)
    r:finish()
end

Events.OnServerStarted.Add(function()
    local ok, err = pcall(run)
    if not ok then print("[TLGH] harness crashed: " .. tostring(err)) end
end)
