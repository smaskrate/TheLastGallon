require "support/fixtures"
local Treatment, Inspection, Supply = TLG.Domain.Treatment, TLG.Domain.Inspection, TLG.Domain.Supply

local function sum(t)
    local s = 0
    for _, v in pairs(t or {}) do s = s + v end
    return s
end

T.case("treatment: filtering removes only eligible contamination and accounts for it", function()
    local s = F.supply({ storage = "drum_steel", cap = 200, q = { diesel = 100, water = 0.5, sediment = 0.2 },
        deg = { diesel = 1.4 }, mic = 0.6 })
    local r = Treatment.filter(s, { sedimentEff = 0.9, waterCapacity = 0.2, holdup = 0.1 })
    T.ok(r.ok)
    T.near(Supply.total(r.supply) + sum(r.removed), Supply.total(s), 1e-9, "accounted")
    T.near(r.supply.deg.diesel, 1.4, 1e-12, "oxidation not reversed")
    T.ok(r.supply.q.sediment < 0.03, "sediment mostly removed")
    T.ok(r.supply.mic < 0.6, "biomass partially removed")
    T.ok(r.removed.diesel > 0 and r.removed.diesel < 0.11, "carrier holdup is small and recorded")
end)

T.case("treatment: water separation in a phase-separated E10 blend takes ethanol too", function()
    local s = F.supply({ storage = "drum_steel", cap = 200, q = { gasoline = 90, ethanol = 10, water = 1.5 },
        deg = { gasoline = 0.2, ethanol = 0.1 } })
    T.ok(Supply.isPhaseSeparated(s), "separated")
    local r = Treatment.separateWater(s, 1.0)
    T.ok(r.ok)
    T.ok(r.removed.ethanol > 0, "ethanol left with the water phase")
    T.ok(Supply.freeWater(r.supply) <= 1e-7, "no free water left")
    T.near(Supply.total(r.supply) + sum(r.removed), Supply.total(s), 1e-9)
    local plain = F.supply({ storage = "drum_steel", cap = 200, q = { gasoline = 100, water = 0.5 }, deg = { gasoline = 0 } })
    local r2 = Treatment.separateWater(plain, 1.0)
    T.eq(r2.removed.ethanol, nil, "no ethanol in plain gasoline")
end)

T.case("treatment: stabilizer is bounded, cleaning needs an empty vessel, repair keeps contents", function()
    local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 }, deg = { gasoline = 0.5 } })
    local r = Treatment.stabilize(s, 10)
    T.ok(r.ok); T.near(r.supply.stab, Treatment.MAX_STAB, 1e-12); T.near(r.used, 2, 1e-12, "only needed doses used")
    T.eq(Treatment.stabilize(r.supply, 1).reason, "already_saturated")
    T.eq(Treatment.clean(s).reason, "not_empty")
    local damaged = F.supply({ storage = "jerrycan_steel", q = { gasoline = 5 }, deg = { gasoline = 2 }, cond = 0.4 })
    local fixed = Treatment.repair(damaged, 0.3).supply
    T.near(fixed.cond, 0.7, 1e-12)
    F.assertSupplyClose(fixed, damaged, 0, "contents unchanged by repair")
    T.eq(Treatment.setSealed(F.supply({ storage = "vehicle_tank", cap = 40 }), true).reason, "not_sealable")
end)

T.case("inspection: unknown condition is not the same as known bad condition", function()
    local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 }, deg = { gasoline = 2.5 } })
    T.eq(Inspection.knowledge(s, nil).state, "unknown")
    local k = Inspection.knowledge(s, Inspection.sample(s, "lab", 0, TLG.Rng.new(1)))
    T.eq(k.state, "current"); T.eq(k.grade, "poor")
    s.rev = s.rev + 1
    T.eq(Inspection.knowledge(s, k.observation).state, "stale", "stale after the supply changed")
end)

T.case("inspection: grade hysteresis prevents flicker near a boundary", function()
    local g = Inspection.grade(0.99, nil)
    T.eq(g, "good")
    g = Inspection.grade(1.01, g); T.eq(g, "weathered")
    g = Inspection.grade(0.97, g); T.eq(g, "weathered", "stays within hysteresis band")
    g = Inspection.grade(0.90, g); T.eq(g, "good", "returns once clearly below")
end)

T.case("inspection: precision bounds the observation error; skill helps", function()
    local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 }, deg = { gasoline = 1.5 } })
    local rng = TLG.Rng.new(TEST_SEED)
    local maxLab, maxVisual = 0, 0
    for _ = 1, 300 do
        maxLab = math.max(maxLab, math.abs(Inspection.sample(s, "lab", 0, rng).observedDeg - 1.5))
        maxVisual = math.max(maxVisual, math.abs(Inspection.sample(s, "visual", 0, rng).observedDeg - 1.5))
    end
    T.ok(maxLab < 0.25, "lab error small: " .. maxLab)
    T.ok(maxVisual > maxLab, "visual is coarser")
    T.ok(Inspection.sample(s, "kit", 1, rng).precision > Inspection.sample(s, "kit", 0, rng).precision)
    T.eq(Inspection.sample(s, "visual", 0, rng).composition, nil, "visual cannot tell composition")
end)

T.case("consumers: compatibility is separate from condition and energy", function()
    local function blend(eth, deg)
        return F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 - eth, ethanol = eth },
            deg = { gasoline = deg, ethanol = deg } })
    end
    local C = TLG.Domain.Consumers
    local e10 = C.evaluate("engine_si_stock", blend(2, 0))
    T.ok(e10.compatible); T.eq(#e10.reasons, 0)
    T.ok(e10.energyFactor < 1 and e10.energyFactor > 0.95, "E10 has less energy per litre")
    local e20 = C.evaluate("engine_si_stock", blend(4, 0))
    T.ok(e20.compatible and e20.startFactor < 1, "E20 marginal on stock")
    local e50 = C.evaluate("engine_si_stock", blend(10, 0))
    T.ok(e50.compatible and e50.harmful and e50.wearFactor > 1, "fresh E50 runs a stock engine lean and wears it (D-037)")
    T.ok(not C.evaluate("engine_si_stock", blend(10, 0), { wrongFuelDamage = false }).compatible,
        "with the damage off E50 blocks the start")
    T.ok(C.evaluate("engine_si_flex", blend(17, 0)).compatible, "E85 fine after conversion")
    local agedGas = C.evaluate("engine_si_stock", blend(0, 2.5))
    T.ok(agedGas.compatible and agedGas.grade == "poor" and agedGas.startFactor < 0.9, "aged but usable")
    T.ok(not C.evaluate("engine_si_stock", blend(0, 3.6)).compatible, "past maxDeg")
    local diesel = F.supply({ storage = "jerrycan_steel", q = { diesel = 18, gasoline = 2 }, deg = { diesel = 0, gasoline = 0 } })
    local petrolInDiesel = C.evaluate("engine_ci_stock", diesel)
    T.ok(petrolInDiesel.compatible and petrolInDiesel.harmful, "10 % gasoline in a diesel engine: it runs, and wears (D-037)")
    T.ok(not C.evaluate("engine_ci_stock", diesel, { wrongFuelDamage = false }).compatible, "blocked with the damage off")
    local cold = C.evaluate("engine_si_flex", blend(19, 0), { ambientC = -5 })
    T.ok(cold.startFactor < 0.7, "E95 cold start penalty")
    local b100 = F.supply({ storage = "jerrycan_steel", q = { biodiesel = 20 }, deg = { biodiesel = 0 } })
    T.ok(C.evaluate("engine_ci_stock", b100, { ambientC = -5 }).startFactor < 0.5, "gelling")
    T.ok(C.evaluate("engine_ci_bio", b100, { ambientC = -5 }).startFactor > 0.5, "fuel heater helps")
end)

T.case("world init: late discovery is aged, deterministic and policy dependent", function()
    local W = TLG.Domain.WorldInit
    local env = F.env()
    local world = W.create({ seed = 99, policy = "new_world" })
    local spec = { storage = "vehicle_tank", cap = 50, q = { gasoline = 30 } }
    local early = W.baseline(world, env, "veh:1", spec, 24 * 2)
    local late = W.baseline(world, env, "veh:1", spec, 24 * 200)
    T.ok(late.deg.gasoline > early.deg.gasoline, "later discovery is older")
    T.eq(W.baseline(world, env, "veh:1", spec, 24 * 200).deg.gasoline, late.deg.gasoline, "deterministic")
    T.ok(W.baseline(world, env, "veh:2", spec, 24 * 200).deg.gasoline ~= late.deg.gasoline, "varies by identity")
    local existing = W.create({ seed = 99, policy = "install_now", now = 24 * 150 })
    T.near(W.baseline(existing, env, "veh:1", spec, 24 * 150).deg.gasoline, 0, 1e-12, "fresh at install")
    local transition = W.create({ seed = 99, policy = "transition", now = 24 * 150, transitionHours = 24 * 30 })
    local t0 = W.baseline(transition, env, "veh:1", spec, 24 * 150).deg.gasoline
    local tEnd = W.baseline(transition, env, "veh:1", spec, 24 * 200).deg.gasoline
    local full = W.baseline(world, env, "veh:1", spec, 24 * 200).deg.gasoline
    T.near(t0, 0, 1e-12)
    T.near(tEnd, full, 1e-9, "converged after the transition period")
    T.eq(W.newId(world, "S"), "S99-1"); T.eq(W.newId(world, "S"), "S99-2")
end)

T.case("world init: station water is low at most sites and high at about one in ten", function()
    local W = TLG.Domain.WorldInit
    local SW = W.STATION_WATER
    local stockTolerance = TLG.Registry.get("consumer", "engine_si_stock").waterMax
    T.le(SW.cleanMax, stockTolerance, "clean stations stay within the stock engine's tolerance")
    T.ok(SW.badMin >= stockTolerance, "contaminated stations exceed it")
    local world = W.create({ seed = 4242, policy = "new_world" })
    local n, bad = 0, 0
    -- Station keys as the adapter builds them (pump:x,y,z) on a map-like grid.
    for x = 10000, 10199 do
        for y = 9000, 9019 do
            local c = W.stationContamination(world, string.format("pump:%d,%d,0", x, y), 1000)
            local frac = c.water / 1000
            n = n + 1
            if frac >= SW.badMin then
                bad = bad + 1
                T.ok(frac < SW.badMax, "contaminated station within range")
            else
                T.ok(frac <= SW.cleanMax, "clean station below the cap")
            end
            T.ok(c.sediment >= 0 and c.sediment / 1000 < W.STATION_SEDIMENT_MAX, "sediment range")
        end
    end
    T.ok(bad / n > 0.07 and bad / n < 0.13, string.format("about one in ten contaminated (%d of %d)", bad, n))
    print(string.format("      station water: %d of %d stations contaminated", bad, n))
    local a = W.stationContamination(world, "pump:10636,10622,0", 500)
    local b = W.stationContamination(world, "pump:10636,10622,0", 500)
    T.eq(a.water, b.water, "deterministic per site")
    T.eq(a.sediment, b.sediment, "deterministic per site")
end)

T.case("consumers: wood gas derates a gas generator, propane does not", function()
    local C = TLG.Domain.Consumers
    local wood = F.supply({ storage = "gas_holder", cap = 20, q = { woodgas = 5 } })
    local propane = F.supply({ storage = "propane_cylinder", q = { propane = 2 } })
    T.near(C.evaluate("generator_gas", wood).powerFactor, 0.6, 1e-12)
    T.near(C.evaluate("generator_gas", propane).powerFactor, 1.0, 1e-12)
end)
T.case("inspection: knowledge keeps each test's latest result; a look does not erase a kit's", function()
    local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20, ethanol = 2 }, deg = { gasoline = 0.4 }, t = 10 })
    local kit = Inspection.sample(s, "kit", 0, TLG.Rng.new(2))
    local entry = Inspection.remember(nil, kit)
    T.ok(entry.kit == kit and entry.visual == nil)
    s.t = 13
    local look = Inspection.sample(s, "visual", 0, TLG.Rng.new(3))
    entry = Inspection.remember(entry, look)
    T.ok(entry.kit == kit and entry.visual == look, "both kept")
    local look2 = Inspection.sample(s, "visual", 0, TLG.Rng.new(4))
    entry = Inspection.remember(entry, look2)
    T.ok(entry.kit == kit and entry.visual == look2, "a new look replaces the old look only")
    -- Knowledge saved before held the last observation alone: it reads as
    -- that test's, and the next result adds to it.
    local old = Inspection.tests(kit)
    T.ok(old.kit == kit and old.visual == nil, "an old entry reads as its test")
    local merged = Inspection.remember(kit, look)
    T.ok(merged.kit == kit and merged.visual == look, "an old entry keeps its result when a new one comes")
    local function size(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
    T.eq(size(Inspection.tests(nil)), 0); T.eq(size(Inspection.tests("junk")), 0)
end)

T.case("inspection: what I know lists the tests most precise first, with their age and whether the fuel changed", function()
    local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 }, deg = { gasoline = 0.4 }, t = 10 })
    local entry = Inspection.remember(nil, Inspection.sample(s, "visual", 0, TLG.Rng.new(5)))
    s.t = 12
    entry = Inspection.remember(entry, Inspection.sample(s, "kit", 0, TLG.Rng.new(6)))
    s.t = 15.5
    local k = Inspection.known(s, entry)
    T.eq(#k, 2); T.eq(k[1].method, "kit"); T.eq(k[2].method, "visual")
    T.near(k[1].ageHours, 3.5, 1e-9); T.near(k[2].ageHours, 5.5, 1e-9)
    T.ok(not k[1].changed and not k[2].changed, "ageing alone changes nothing")
    s.rev = s.rev + 1
    k = Inspection.known(s, entry)
    T.ok(k[1].changed and k[2].changed, "poured or treated since: both")
    T.eq(#Inspection.known(s, nil), 0, "nothing known")
end)

T.case("format: what I know names each test, how long ago, its findings, and notes a change and an open container", function()
    require "TLG/UI/Format"
    local Fmt = TLG.UI.Format
    local saved = Fmt.translate
    Fmt.translate = function(key, ...)
        local args = { ... }
        if #args == 0 then return "<" .. key .. ">" end
        return "<" .. key .. ":" .. table.concat(args, "|") .. ">"
    end
    local ok, err = pcall(function()
        T.eq(Fmt.ago(0), "<IGUI_TLG_Ago_Now>")
        T.eq(Fmt.ago(1 / 60 + 1e-9), "<IGUI_TLG_Ago_Minute>")
        T.eq(Fmt.ago(0.5), "<IGUI_TLG_Ago_Minutes:30>")
        T.eq(Fmt.ago(1.2), "<IGUI_TLG_Ago_Hour>")
        T.eq(Fmt.ago(5.9), "<IGUI_TLG_Ago_Hours:5>")
        T.eq(Fmt.ago(24), "<IGUI_TLG_Ago_Day>")
        T.eq(Fmt.ago(24 * 9 + 3), "<IGUI_TLG_Ago_Days:9>")
        local s = F.supply({ storage = "jerrycan_steel", q = { gasoline = 20 }, deg = { gasoline = 0.4 }, t = 10 })
        local kit = Inspection.sample(s, "kit", 0, TLG.Rng.new(7))
        local look = Inspection.sample(s, "visual", 0, TLG.Rng.new(8))
        local text = Fmt.known({ sealed = true, tests = {
            { method = "kit", observation = kit, ageHours = 3, changed = true },
            { method = "visual", observation = look, ageHours = 0, changed = false } } })
        T.ok(string.find(text, "<IGUI_TLG_KnownTitle>", 1, true) == 1, "the title first")
        local kitAt = string.find(text, "<IGUI_TLG_KnownTest:<IGUI_TLG_TestName_kit>|<IGUI_TLG_Ago_Hours:3>>", 1, true)
        local lookAt = string.find(text, "<IGUI_TLG_KnownTest:<IGUI_TLG_TestName_visual>|<IGUI_TLG_Ago_Now>>", 1, true)
        T.ok(kitAt ~= nil and lookAt ~= nil and kitAt < lookAt, "the kit, then the look, each with its age")
        T.ok(string.find(text, "IGUI_TLG_Composition", 1, true) ~= nil, "the kit's composition is shown")
        local _, changes = string.gsub(text, "IGUI_TLG_KnownChanged", "")
        T.eq(changes, 1, "changed since the kit only")
        T.ok(string.find(text, "IGUI_TLG_Method_", 1, true) == nil, "the test is named above its findings")
        T.ok(string.find(text, "IGUI_TLG_KnownOpen", 1, true) == nil, "sealed: no note")
        local open = Fmt.known({ sealed = false, tests = { { method = "visual", observation = look, ageHours = 30 } } })
        T.ok(string.find(open, "<IGUI_TLG_KnownOpen>", 1, true) ~= nil, "open: the note")
        local none = Fmt.known({ sealed = false, tests = {} })
        T.ok(string.find(none, "<IGUI_TLG_ConditionUnknown>", 1, true) ~= nil, "nothing known: unknown")
        T.ok(string.find(none, "IGUI_TLG_KnownOpen", 1, true) == nil, "no note on nothing")
        -- The result of a single test, as Look and smell shows it, keeps its method line.
        T.ok(string.find(Fmt.observation(look), "<IGUI_TLG_Method_visual>", 1, true) ~= nil)
    end)
    Fmt.translate = saved
    if not ok then error(err, 0) end
end)
