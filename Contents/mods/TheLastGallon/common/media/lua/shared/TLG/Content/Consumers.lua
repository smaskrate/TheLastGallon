-- ConsumerProfile content (docs/balance.md).
--   accepts[fuel] = { soft = fraction without penalty, max = hard limit }
--   foreignMax      tolerated fraction of fuels not listed in accepts
--   maxDeg          blend degradation index at which the fuel is unsuitable
--   waterMax        tolerated free-water fraction before stalling
--   sedimentMax     tolerated sediment fraction before filter clogging
--   coldStart       { fuel = id, above = fraction, belowC = temperature } penalty
require "TLG/Domain/Fuel/Defs"
local R = TLG.Registry

R.define("consumer", {
    id = "engine_si_stock", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 0.15, max = 0.25 } },
    foreignMax = 0.01, maxDeg = 3.5, waterMax = 0.002, sedimentMax = 0.002,
})
R.define("consumer", {
    id = "engine_si_flex", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.01, maxDeg = 3.5, waterMax = 0.004, sedimentMax = 0.002,
    coldStart = { fuel = "ethanol", above = 0.85, belowC = 10 },
})
R.define("consumer", {
    id = "generator_si_stock", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 0.10, max = 0.15 } },
    foreignMax = 0.01, maxDeg = 4.0, waterMax = 0.003, sedimentMax = 0.003,
})
R.define("consumer", {
    id = "generator_si_flex", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.01, maxDeg = 4.0, waterMax = 0.005, sedimentMax = 0.003,
    coldStart = { fuel = "ethanol", above = 0.85, belowC = 5 },
})
R.define("consumer", {
    id = "engine_ci_stock", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 0.2, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 3.5, waterMax = 0.001, sedimentMax = 0.0015,
})
R.define("consumer", {
    id = "engine_ci_bio", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 3.5, waterMax = 0.0015, sedimentMax = 0.0015, fuelHeater = true,
})
R.define("consumer", {
    id = "generator_ci_stock", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 0.2, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 4.0, waterMax = 0.0015, sedimentMax = 0.002,
})
R.define("consumer", {
    id = "generator_gas", ignition = "gaseous", referenceFuel = "propane",
    accepts = { propane = { soft = 1.0, max = 1.0 }, biogas = { soft = 1.0, max = 1.0 },
        woodgas = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.0, maxDeg = 10, waterMax = 0, sedimentMax = 0,
    -- Producer gas is lean: engines lose power on it (game value).
    derate = { woodgas = 0.6 },
})

return true
