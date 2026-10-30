require "support/fixtures"
local R = TLG.Registry

T.case("registry: shipped content validates without problems", function()
    local problems = R.validate()
    T.eq(#problems, 0, "problems: " .. table.concat(problems, " | "))
end)

T.case("registry: duplicate ids are rejected at definition time", function()
    T.raises(function() R.define("fuel", { id = "gasoline", phase = "liquid", role = "fuel" }) end, "duplicate id")
end)

T.case("registry: validators report bad values and undefined references", function()
    R.define("consumer", { id = "test_bad_consumer", ignition = "spark", referenceFuel = "nope",
        accepts = { unobtainium = { soft = 1, max = 1 }, water = { soft = 1, max = 2 } }, foreignMax = 0, maxDeg = -1 })
    R.define("fuel", { id = "test_bad_fuel", phase = "plasma", role = "fuel", energyMJ = -3,
        aging = { rate = -1, autocat = 0, q10 = 2, unsealed = 1, stabilizerMax = 0.5 } })
    local text = table.concat(R.validate(), "\n")
    T.ok(string.find(text, "accepts unknown fuel unobtainium", 1, true), "unknown fuel reference")
    T.ok(string.find(text, "accepts non-fuel water", 1, true), "non-fuel accepted")
    T.ok(string.find(text, "unknown referenceFuel nope", 1, true), "reference fuel")
    T.ok(string.find(text, "maxDeg must be positive", 1, true), "maxDeg")
    T.ok(string.find(text, "phase must be", 1, true), "phase")
    T.ok(string.find(text, "positive energyMJ", 1, true), "energy")
    T.ok(string.find(text, "invalid aging parameters", 1, true), "aging")
    R.entries.consumer.test_bad_consumer = nil
    R.entries.fuel.test_bad_fuel = nil
    T.eq(#R.validate(), 0, "clean after removing test entries")
end)

T.case("registry: fingerprint is stable and detects changes", function()
    local a = R.fingerprint("consumer", "engine_si_stock")
    T.eq(a, R.fingerprint("consumer", "engine_si_stock"))
    local def = R.get("consumer", "engine_si_stock")
    local old = def.maxDeg
    def.maxDeg = old + 1
    T.ok(a ~= R.fingerprint("consumer", "engine_si_stock"), "changed definition changes fingerprint")
    def.maxDeg = old
    T.eq(a, R.fingerprint("consumer", "engine_si_stock"))
end)
