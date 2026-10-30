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
    T.ok(not e50.compatible, "fresh E50 incompatible with stock engine")
    T.ok(C.evaluate("engine_si_flex", blend(17, 0)).compatible, "E85 fine after conversion")
    local agedGas = C.evaluate("engine_si_stock", blend(0, 2.5))
    T.ok(agedGas.compatible and agedGas.grade == "poor" and agedGas.startFactor < 0.9, "aged but usable")
    T.ok(not C.evaluate("engine_si_stock", blend(0, 3.6)).compatible, "past maxDeg")
    local diesel = F.supply({ storage = "jerrycan_steel", q = { diesel = 18, gasoline = 2 }, deg = { diesel = 0, gasoline = 0 } })
    T.ok(not C.evaluate("engine_ci_stock", diesel).compatible, "gasoline in a diesel engine")
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

T.case("consumers: wood gas derates a gas generator, propane does not", function()
    local C = TLG.Domain.Consumers
    local wood = F.supply({ storage = "gas_holder", cap = 20, q = { woodgas = 5 } })
    local propane = F.supply({ storage = "propane_cylinder", q = { propane = 2 } })
    T.near(C.evaluate("generator_gas", wood).powerFactor, 0.6, 1e-12)
    T.near(C.evaluate("generator_gas", propane).powerFactor, 1.0, 1e-12)
end)