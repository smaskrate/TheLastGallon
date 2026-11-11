require "support/fixtures"
-- Wrong fuel (D-037): what each fuel does in each engine, band by band.
require "TLG/UI/Format"
local C, Tables, E = TLG.Domain.Consumers, TLG.Tables, TLG.Domain.EngineEffects

-- 20 L of fresh fuel, `q` litres by fuel id.
local function tank(q)
    local deg = {}
    for id in pairs(q) do deg[id] = 0 end
    return F.supply({ storage = "vehicle_tank", cap = 50, q = q, deg = deg })
end

local SPARK = { "engine_si_stock", "engine_si_flex", "generator_si_stock", "generator_si_flex" }
local DIESEL = { "engine_ci_stock", "engine_ci_bio", "generator_ci_stock", "generator_ci_bio" }

local function has(e, code) return Tables.contains(e.reasons, code) end

T.case("wrong fuel: each engine's own fuel does no harm", function()
    for _, id in ipairs(SPARK) do
        local e = C.evaluate(id, tank({ gasoline = 20 }))
        T.ok(e.compatible and not e.harmful and e.wearFactor == 1 and e.startFactor == 1, id)
    end
    for _, id in ipairs({ "engine_si_flex", "generator_si_flex" }) do
        local e = C.evaluate(id, tank({ ethanol = 20 }))
        T.ok(e.compatible and not e.harmful and e.wearFactor == 1, id .. " on pure ethanol")
    end
    for _, id in ipairs(DIESEL) do
        local e = C.evaluate(id, tank({ diesel = 20 }))
        T.ok(e.compatible and not e.harmful and e.wearFactor == 1 and e.startFactor == 1, id)
    end
    local e = C.evaluate("generator_ci_bio", tank({ biodiesel = 20 }))
    T.ok(e.compatible and not e.harmful and e.wearFactor == 1, "the Diesel Generator on pure biodiesel")
end)

T.case("wrong fuel: a trace is tolerated as before", function()
    for _, id in ipairs(SPARK) do
        local e = C.evaluate(id, tank({ gasoline = 19.8, diesel = 0.2 }))
        T.ok(e.compatible and not e.harmful and #e.reasons == 0, id .. " with 1 % diesel")
    end
    for _, id in ipairs(DIESEL) do
        local e = C.evaluate(id, tank({ diesel = 19.6, gasoline = 0.4 }))
        T.ok(e.compatible and not e.harmful and #e.reasons == 0, id .. " with 2 % petrol")
    end
end)

T.case("wrong fuel: diesel in a spark engine, flex engines included", function()
    for _, id in ipairs(SPARK) do
        -- 5 %: it runs, with less power and three times the wear factor.
        local e = C.evaluate(id, tank({ gasoline = 19, diesel = 1 }))
        T.ok(e.compatible and e.harmful and e.wrongLevel == 1 and e.wrongFuel == "diesel", id)
        T.near(e.startFactor, 0.9, 1e-9); T.near(e.powerFactor, 0.85, 1e-9); T.near(e.wearFactor, 3, 1e-9)
        T.ok(has(e, "wrong_fuel_1_diesel") and not has(e, "incompatible_fuel"), table.concat(e.reasons, ","))
        T.eq(e.grade, "weathered", "never good for this engine")
        T.eq(e.exhaustWear, nil); T.eq(e.failureChance, nil); T.eq(e.attemptDamage, nil)
        -- 20 %: hard starts, the exhaust suffers.
        e = C.evaluate(id, tank({ gasoline = 16, diesel = 4 }))
        T.ok(e.compatible and e.harmful and e.wrongLevel == 2, id)
        T.near(e.startFactor, 0.4, 1e-9); T.near(e.powerFactor, 0.6, 1e-9); T.near(e.wearFactor, 6, 1e-9)
        T.near(e.exhaustWear, 0.5, 1e-9)
        T.eq(e.grade, "poor")
        -- 40 %: no start; each try costs condition; the wear stands for an
        -- engine kept running with the stall option off.
        e = C.evaluate(id, tank({ gasoline = 12, diesel = 8 }))
        T.ok(not e.compatible and e.harmful and e.wrongLevel == 4, id)
        T.eq(e.startFactor, 0); T.eq(e.powerFactor, 0); T.eq(e.grade, "unsuitable")
        T.eq(e.attemptDamage[1], 1); T.eq(e.attemptDamage[2], 2)
        T.near(e.wearFactor, 10, 1e-9); T.near(e.exhaustWear, 1.0, 1e-9)
        T.ok(has(e, "wrong_fuel_4_diesel"))
    end
end)

T.case("wrong fuel: biodiesel in a spark engine counts with diesel and wears a little more", function()
    local d = C.evaluate("engine_si_stock", tank({ gasoline = 16, diesel = 4 }))
    local b = C.evaluate("engine_si_stock", tank({ gasoline = 16, biodiesel = 4 }))
    T.eq(b.wrongLevel, 2); T.eq(b.wrongFuel, "biodiesel")
    T.near(b.wearFactor, d.wearFactor * 1.2, 1e-9, "a fifth more wear, all of it biodiesel")
    T.near(b.startFactor, d.startFactor, 1e-12); T.near(b.powerFactor, d.powerFactor, 1e-12)
    -- Half and half: the shares add up, the extra wear is halved.
    local m = C.evaluate("engine_si_stock", tank({ gasoline = 16, diesel = 2, biodiesel = 2 }))
    T.eq(m.wrongLevel, 2)
    T.near(m.wearFactor, 6 * 1.1, 1e-9)
    -- 6 % of each is 12 %: the second band, which neither reaches alone.
    m = C.evaluate("engine_si_stock", tank({ gasoline = 17.6, diesel = 1.2, biodiesel = 1.2 }))
    T.eq(m.wrongLevel, 2, "the shares of diesel and biodiesel are summed")
end)

T.case("wrong fuel: petrol in a diesel keeps it running and wears it out", function()
    for _, id in ipairs(DIESEL) do
        local e = C.evaluate(id, tank({ diesel = 18, gasoline = 2 }))
        T.ok(e.compatible and e.harmful and e.wrongLevel == 1 and e.wrongFuel == "gasoline", id)
        T.near(e.startFactor, 0.9, 1e-9); T.near(e.powerFactor, 0.9, 1e-9); T.near(e.wearFactor, 3, 1e-9)
        e = C.evaluate(id, tank({ diesel = 14, gasoline = 6 }))
        T.ok(e.compatible and e.wrongLevel == 2, id)
        T.near(e.startFactor, 0.5, 1e-9); T.near(e.powerFactor, 0.7, 1e-9); T.near(e.wearFactor, 8, 1e-9)
        T.eq(e.failureChance, nil)
        -- A tank of petrol: it still runs, and can fail.
        e = C.evaluate(id, tank({ gasoline = 20 }))
        T.ok(e.compatible and e.harmful and e.wrongLevel == 3, id .. " on pure petrol still runs")
        T.near(e.startFactor, 0.25, 1e-9); T.near(e.powerFactor, 0.5, 1e-9); T.near(e.wearFactor, 15, 1e-9)
        T.near(e.failureChance, 0.02, 1e-12)
        T.eq(e.attemptDamage, nil)
        T.ok(has(e, "wrong_fuel_3_gasoline") and not has(e, "incompatible_fuel"))
    end
end)

T.case("wrong fuel: ethanol in a diesel is one band harsher than petrol and ends in no start", function()
    for _, id in ipairs(DIESEL) do
        local e = C.evaluate(id, tank({ diesel = 19, ethanol = 1 }))
        T.ok(e.compatible and e.wrongLevel == 2 and e.wrongFuel == "ethanol", id)
        T.near(e.wearFactor, 8, 1e-9); T.near(e.startFactor, 0.5, 1e-9)
        e = C.evaluate(id, tank({ diesel = 16, ethanol = 4 }))
        T.ok(e.compatible and e.wrongLevel == 3, id)
        T.near(e.wearFactor, 15, 1e-9); T.near(e.failureChance, 0.02, 1e-12)
        e = C.evaluate(id, tank({ diesel = 12, ethanol = 8 }))
        T.ok(not e.compatible and e.wrongLevel == 4, id)
        T.eq(e.attemptDamage[1], 1); T.eq(e.attemptDamage[2], 2)
        T.near(e.wearFactor, 20, 1e-9); T.near(e.failureChance, 0.04, 1e-12)
    end
end)

T.case("wrong fuel: with petrol and ethanol both in a diesel the worst decides, nothing multiplies", function()
    -- 20 % petrol (second band) and 5 % ethanol (also the second band's numbers).
    local e = C.evaluate("engine_ci_stock", tank({ diesel = 15, gasoline = 4, ethanol = 1 }))
    T.ok(e.compatible and e.wrongLevel == 2)
    T.near(e.wearFactor, 8, 1e-9, "not 64")
    T.near(e.startFactor, 0.5, 1e-9); T.near(e.powerFactor, 0.7, 1e-9)
    -- 60 % petrol and 35 % ethanol: the ethanol stops it.
    e = C.evaluate("engine_ci_stock", tank({ diesel = 1, gasoline = 12, ethanol = 7 }))
    T.ok(not e.compatible and e.wrongLevel == 4 and e.wrongFuel == "ethanol")
    T.near(e.wearFactor, 20, 1e-9); T.near(e.failureChance, 0.04, 1e-12)
end)

T.case("wrong fuel: ethanol past a stock petrol engine's limit runs lean instead of blocking", function()
    for _, spec in ipairs({ { "engine_si_stock", 0.25 }, { "generator_si_stock", 0.15 } }) do
        local id, max = spec[1], spec[2]
        local at = C.evaluate(id, tank({ gasoline = 20 * (1 - max), ethanol = 20 * max }))
        T.ok(at.compatible and not at.harmful, id .. " at its limit")
        -- 40 %: over the limit.
        local e = C.evaluate(id, tank({ gasoline = 12, ethanol = 8 }), { ambientC = 20 })
        T.ok(e.compatible and e.harmful and has(e, "too_much_ethanol"), id)
        T.near(e.startFactor, 0.5, 1e-9); T.near(e.powerFactor, 0.75, 1e-9); T.near(e.wearFactor, 4, 1e-9)
        T.eq(e.grade, "poor")
        -- Just past the limit it does not start better than just before it.
        local before = C.evaluate(id, tank({ gasoline = 20 * (1 - max + 0.001), ethanol = 20 * (max - 0.001) }))
        local after = C.evaluate(id, tank({ gasoline = 20 * (1 - max - 0.001), ethanol = 20 * (max + 0.001) }))
        T.ok(after.startFactor <= before.startFactor and after.powerFactor <= before.powerFactor
            and after.wearFactor >= before.wearFactor, string.format("%s: start %.3f -> %.3f", id, before.startFactor, after.startFactor))
        -- Pure ethanol, warm: harder still.
        e = C.evaluate(id, tank({ ethanol = 20 }), { ambientC = 20 })
        T.ok(e.compatible and e.harmful, id)
        T.near(e.startFactor, 0.3, 1e-9); T.near(e.powerFactor, 0.6, 1e-9); T.near(e.wearFactor, 8, 1e-9)
        -- Pure ethanol below 10 C: no start, and no damage for trying.
        e = C.evaluate(id, tank({ ethanol = 20 }), { ambientC = 5 })
        T.ok(e.compatible and e.startFactor == 0 and has(e, "cold_start"), id .. " in the cold")
        T.eq(e.attemptDamage, nil)
        -- 40 % in the cold starts as when warm.
        e = C.evaluate(id, tank({ gasoline = 12, ethanol = 8 }), { ambientC = 5 })
        T.near(e.startFactor, 0.5, 1e-9)
    end
end)

T.case("wrong fuel: diesel and too much ethanol in a stock petrol engine do not multiply either", function()
    -- 20 % diesel (the second band: 0.4, 0.6, wear 6) and 40 % ethanol (past
    -- the limit: 0.5, 0.75, wear 4).
    local e = C.evaluate("engine_si_stock", tank({ gasoline = 8, diesel = 4, ethanol = 8 }))
    T.ok(e.compatible and e.harmful and e.wrongLevel == 2)
    T.near(e.startFactor, 0.4, 1e-9); T.near(e.powerFactor, 0.6, 1e-9); T.near(e.wearFactor, 6, 1e-9)
    T.near(e.exhaustWear, 0.5, 1e-9)
    T.ok(has(e, "too_much_ethanol") and has(e, "wrong_fuel_2_diesel"), table.concat(e.reasons, ","))
    -- Petrol and ethanol in a diesel: one line for each.
    e = C.evaluate("engine_ci_stock", tank({ diesel = 15, gasoline = 4, ethanol = 1 }))
    T.ok(has(e, "wrong_fuel_2_gasoline") and has(e, "wrong_fuel_2_ethanol"), table.concat(e.reasons, ","))
end)

T.case("wrong fuel: a fuel no rule covers still blocks, and a ruled trace still counts with it", function()
    local e = C.evaluate("engine_ci_bio", tank({ biodiesel = 19, methanol = 1 }))
    T.ok(not e.compatible and has(e, "incompatible_fuel") and not e.harmful, "5 % methanol")
    T.eq(e.attemptDamage, nil, "a blocked start that damages nothing")
    -- 0.8 % diesel is a trace for a spark engine; with 0.8 % methanol the
    -- foreign share passes its 1 %.
    e = C.evaluate("engine_si_stock", tank({ gasoline = 19.68, diesel = 0.16, methanol = 0.16 }))
    T.ok(not e.compatible and has(e, "incompatible_fuel"))
end)

T.case("wrong fuel: with the damage switched off such fuel blocks the start, as before 0.3.0", function()
    local off = { wrongFuelDamage = false }
    local e = C.evaluate("engine_si_stock", tank({ gasoline = 19, diesel = 1 }), off)
    T.ok(not e.compatible and has(e, "incompatible_fuel") and not e.harmful)
    T.eq(e.wearFactor, 1); T.eq(e.attemptDamage, nil); T.eq(e.failureChance, nil)
    e = C.evaluate("engine_ci_stock", tank({ gasoline = 20 }), off)
    T.ok(not e.compatible and has(e, "incompatible_fuel") and not e.harmful)
    e = C.evaluate("engine_si_stock", tank({ gasoline = 12, ethanol = 8 }), off)
    T.ok(not e.compatible and has(e, "too_much_ethanol") and not e.harmful)
    -- The switch the adapters set is asked when the state says nothing.
    local saved = C.damageEnabled
    C.damageEnabled = function() return false end
    local ok, err = pcall(function()
        T.ok(not C.evaluate("engine_ci_stock", tank({ gasoline = 20 })).compatible)
        T.ok(C.evaluate("engine_ci_stock", tank({ gasoline = 20 }), { wrongFuelDamage = true }).compatible)
    end)
    C.damageEnabled = saved
    if not ok then error(err, 0) end
end)

T.case("wrong fuel: wrong-fuel wear multiplies with the wear of stale fuel", function()
    local stale = F.supply({ storage = "vehicle_tank", cap = 50, q = { diesel = 18, gasoline = 2 }, deg = { diesel = 2.6, gasoline = 2.6 } })
    local fresh = C.evaluate("engine_ci_stock", tank({ diesel = 18, gasoline = 2 }))
    local aged = C.evaluate("engine_ci_stock", F.supply({ storage = "vehicle_tank", cap = 50, q = { diesel = 20 }, deg = { diesel = 2.6 } }))
    local both = C.evaluate("engine_ci_stock", stale)
    T.ok(aged.wearFactor > 1 and fresh.wearFactor == 3)
    T.near(both.wearFactor, fresh.wearFactor * aged.wearFactor, 1e-9)
end)

T.case("wrong fuel: the odds of a failure grow with the litres burned", function()
    T.eq(E.failureOdds(0, 5), 0); T.eq(E.failureOdds(0.02, 0), 0); T.eq(E.failureOdds(nil, 3), 0)
    T.near(E.failureOdds(0.02, 1), 0.02, 1e-12)
    T.near(E.failureOdds(0.02, 2), 1 - 0.98 * 0.98, 1e-12)
    T.near(E.failureOdds(0.02, 40), 1 - 0.98 ^ 40, 1e-12, "a 40 L tank: a little over half")
    T.ok(E.failureOdds(0.02, 40) > 0.55 and E.failureOdds(0.02, 40) < 0.56)
    T.eq(E.failureOdds(1, 0.5), 1)
    -- A car's litres with the sandbox's consumption taken out; a generator's
    -- as the hours they lasted, an hour worth an hour's driving.
    T.near(E.vehicleReferenceLitres(6.6, 2), 3.3, 1e-12)
    T.near(E.generatorReferenceLitres(0.15, 1), 3.3, 1e-12, "an hour at the reference load")
    T.near(E.generatorReferenceLitres(0.015, 0.1), 3.3, 1e-12, "the same hour at the default sandbox value")
    T.near(E.failureOdds(0.02, E.generatorReferenceLitres(0.015, 0.1)), 1 - 0.98 ^ 3.3, 1e-12, "6.4 % an hour")
end)

T.case("wrong fuel: what the status text says", function()
    local Fmt = TLG.UI.Format
    local saved = Fmt.translate
    Fmt.translate = function(key, a) return a and (key .. "(" .. tostring(a) .. ")") or key end
    local ok, err = pcall(function()
        local text = Fmt.evaluation(C.evaluate("engine_ci_stock", tank({ diesel = 14, gasoline = 6 })))
        T.ok(string.find(text, "IGUI_TLG_Harmful", 1, true) ~= nil, text)
        T.ok(string.find(text, "IGUI_TLG_Compatible", 1, true) == nil, text)
        T.ok(string.find(text, "IGUI_TLG_Reason_Wrong_2(IGUI_TLG_Fuel_gasoline)", 1, true) ~= nil, text)
        text = Fmt.evaluation(C.evaluate("engine_si_stock", tank({ gasoline = 12, diesel = 8 })))
        T.ok(string.find(text, "IGUI_TLG_NotCompatible", 1, true) ~= nil, text)
        T.ok(string.find(text, "IGUI_TLG_Reason_Wrong_4(IGUI_TLG_Fuel_diesel)", 1, true) ~= nil, text)
        text = Fmt.evaluation(C.evaluate("engine_si_stock", tank({ gasoline = 20 })))
        T.ok(string.find(text, "IGUI_TLG_Compatible", 1, true) ~= nil, text)
    end)
    Fmt.translate = saved
    if not ok then error(err, 0) end
end)
