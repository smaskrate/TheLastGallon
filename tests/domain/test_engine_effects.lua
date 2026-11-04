require "support/fixtures"
require "TLG/Domain/EngineEffects"
local E = TLG.Domain.EngineEffects

T.case("engine effects: the power to run at follows the factor, floored at half", function()
    T.eq(E.targetPower(1000, 1), 1000, "fuel that costs nothing")
    T.eq(E.targetPower(1000, 1.2), 1000, "never above the engine's own")
    T.eq(E.targetPower(1000, 0.851429), 851, "rounded to the game's whole units")
    T.eq(E.targetPower(1000, 0.3), 500, "a car that runs can still move")
    T.eq(E.targetPower(1000, 0), 500, "fuel the engine cannot take, with stalls off")
    T.eq(E.targetPower(1, 0.5), 1, "at least one unit")
    T.eq(E.targetPower(0, 0.5), 0, "no engine power to lower")
end)

T.case("engine effects: power is lowered once while running and given back", function()
    -- Poor fuel, minute after minute: lowered once, never again on the lowered value.
    local s, set = E.powerStep(nil, 1000, 0.85, true)
    T.eq(set, 850)
    T.eq(s.base, 1000)
    T.eq(s.applied, 850)
    local s2, set2 = E.powerStep(s, 850, 0.85, true)
    T.eq(set2, nil, "nothing to set the next minute")
    T.eq(s2.base, 1000, "the base kept")
    -- Worse fuel lowers it further from the same base.
    local s3, set3 = E.powerStep(s2, 850, 0.7, true)
    T.eq(set3, 700)
    T.eq(s3.base, 1000)
    -- Stopped: the engine's own power back, nothing kept.
    local s4, set4 = E.powerStep(s3, 700, 0.7, false)
    T.eq(set4, 1000)
    T.eq(s4, nil)
    -- Running on good fuel again: the same.
    local s5, set5 = E.powerStep(s3, 700, 1, true)
    T.eq(set5, 1000)
    T.eq(s5, nil)
    -- Nothing done for an engine the mod never lowered.
    local s6, set6 = E.powerStep(nil, 1000, 1, true)
    T.eq(set6, nil)
    T.eq(s6, nil)
    local s7, set7 = E.powerStep(nil, 1000, 0.5, false)
    T.eq(set7, nil)
    T.eq(s7, nil)
end)

T.case("engine effects: a power the game set becomes the new base", function()
    local s = E.powerStep(nil, 1000, 0.85, true)
    -- A repair or an engine swap while running on poor fuel (VehiclePart.repair).
    local s2, set2 = E.powerStep(s, 1200, 0.85, true)
    T.eq(set2, 1020, "lowered from the new power")
    T.eq(s2.base, 1200)
    local s3, set3 = E.powerStep(s2, 1020, 0.85, false)
    T.eq(set3, 1200, "and the new power back when it stops")
    T.eq(s3, nil)
    -- The game's change while the fuel is fine is left alone.
    local s4, set4 = E.powerStep(s, 1100, 1, true)
    T.eq(set4, nil)
    T.eq(s4, nil)
end)

T.case("engine effects: wear is carried as a fraction until a whole point is due", function()
    local c, w = E.accrue(0, 2, 1.742857, 0.15)
    T.near(c, 2 * 0.742857 * 0.15, 1e-12)
    T.eq(w, 0)
    c, w = E.accrue(c, 7, 1.742857, 0.15)
    T.eq(w, 1, "9 L at that factor and rate: 1.0029 points")
    T.near(c, 9 * 0.742857 * 0.15 - 1, 1e-9)
    c, w = E.accrue(0.4, 10, 1, 0.15)
    T.eq(w, 0, "fuel that wears nothing extra")
    T.near(c, 0.4, 1e-12, "the carry kept")
    c, w = E.accrue(0.4, -3, 2, 0.15)
    T.eq(w, 0, "a rise in the tank is no burn")
    T.near(c, 0.4, 1e-12)
    c, w = E.accrue(nil, 20, 2, 0.15)
    T.eq(w, 3)
    T.near(c, 0, 1e-9, "exactly three points")
    c, w = E.accrue(0.5, 1, 2, 0.5)
    T.eq(w, 1)
    T.near(c, 0, 1e-12, "a carry that reaches one exactly")
end)

T.case("engine effects: the rates per litre", function()
    T.near(E.vehicleWearPerLitre(1), 0.15, 1e-12)
    T.near(E.vehicleWearPerLitre(nil), 0.15, 1e-12)
    T.near(E.vehicleWearPerLitre(2), 0.075, 1e-12, "the same wear per hour when cars burn twice as much")
    -- Vanilla's own generator wear at a fridge's load: 1.5 points in N hours,
    -- 0.15 L an hour.
    T.near(E.generatorWearPerLitre(30, 1), 1.5 / 30 / 0.15, 1e-12)
    T.near(E.generatorWearPerLitre(nil, nil), 1.5 / 30 / 0.15, 1e-12, "Base.Generator's 30 when unknown")
    T.near(E.generatorWearPerLitre(24, 2), 1.5 / 24 / 0.3, 1e-12)
    -- At wearFactor 2 a litre adds what vanilla takes for the hours it lasts.
    local hours = 1 / 0.15
    T.near(1 * E.generatorWearPerLitre(30, 1), hours * 1.5 / 30, 1e-12)
end)
