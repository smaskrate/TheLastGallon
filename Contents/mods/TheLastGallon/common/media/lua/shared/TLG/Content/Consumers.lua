-- ConsumerProfile content (docs/balance.md).
--   accepts[fuel] = { soft = fraction without penalty, max = hard limit }
--   foreignMax      tolerated fraction of fuels not listed in accepts
--   maxDeg          blend degradation index at which the fuel is unsuitable
--   waterMax        tolerated free-water fraction before stalling
--   sedimentMax     tolerated sediment fraction before filter clogging
--   coldStart       { fuel = id, above = fraction, belowC = temperature } penalty
--   wrongFuel       rules for fuels the engine is not built for (D-037): each
--                   sums the share of its `fuels` and takes the last band the
--                   share is above. A band: level 1-4, start and power
--                   multipliers, wear multiplier, `exhaust` condition and
--                   `failure` chance per litre burned, and for a band that
--                   does not start, `noStart` with `attempt` = { min, max }
--                   engine condition lost at each try. `extraWear[fuel]`
--                   raises the wear by that share of the fuel in the wrong part.
--   accepts[fuel].over  what an accepted fuel does above its max, in place
--                   of blocking the start; `over.high` above a second share,
--                   where it also does not start below `coldBelowC`.
-- The bands and their numbers are game values, first estimates
-- (docs/balance.md); the order of harm follows real engines.
require "TLG/Domain/Fuel/Defs"
local R = TLG.Registry

-- Diesel or biodiesel in a spark engine: it does not vaporise, fouls the
-- plugs, washes the oil off the bores, and unburned fuel reaches the exhaust.
-- Past 30 % the engine does not fire.
local HEAVY_IN_SPARK = { fuels = { "diesel", "biodiesel" }, extraWear = { biodiesel = 0.2 }, bands = {
    { above = 0.01, level = 1, start = 0.9, power = 0.85, wear = 3 },
    { above = 0.10, level = 2, start = 0.4, power = 0.6, wear = 6, exhaust = 0.5 },
    { above = 0.30, level = 4, noStart = true, wear = 10, exhaust = 1.0, attempt = { 1, 2 } },
} }
-- Petrol in a diesel: it lights too early and does not lubricate the
-- injection pump. The engine keeps running, which is what wrecks it.
local PETROL_IN_DIESEL = { fuels = { "gasoline" }, bands = {
    { above = 0.02, level = 1, start = 0.9, power = 0.9, wear = 3 },
    { above = 0.15, level = 2, start = 0.5, power = 0.7, wear = 8 },
    { above = 0.50, level = 3, start = 0.25, power = 0.5, wear = 15, failure = 0.02 },
} }
-- Ethanol in a diesel: as petrol, one band harsher, and past 30 % it does
-- not ignite.
local ETHANOL_IN_DIESEL = { fuels = { "ethanol" }, bands = {
    { above = 0.02, level = 2, start = 0.5, power = 0.7, wear = 8 },
    { above = 0.10, level = 3, start = 0.25, power = 0.5, wear = 15, failure = 0.02 },
    { above = 0.30, level = 4, noStart = true, wear = 20, failure = 0.04, attempt = { 1, 2 } },
} }
-- Ethanol past a stock petrol engine's limit: the mixture is lean. The
-- start factor continues below the 0.6 a blend reaches at the limit.
local ETHANOL_OVER = { level = 2, start = 0.5, power = 0.75, wear = 4,
    high = { above = 0.60, level = 3, start = 0.3, power = 0.6, wear = 8, coldBelowC = 10 } }

R.define("consumer", {
    id = "engine_si_stock", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 0.15, max = 0.25, over = ETHANOL_OVER } },
    foreignMax = 0.01, maxDeg = 3.5, waterMax = 0.002, sedimentMax = 0.002,
    wrongFuel = { HEAVY_IN_SPARK },
})
R.define("consumer", {
    id = "engine_si_flex", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.01, maxDeg = 3.5, waterMax = 0.004, sedimentMax = 0.002,
    coldStart = { fuel = "ethanol", above = 0.85, belowC = 10 },
    wrongFuel = { HEAVY_IN_SPARK },
})
R.define("consumer", {
    id = "generator_si_stock", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 0.10, max = 0.15, over = ETHANOL_OVER } },
    foreignMax = 0.01, maxDeg = 4.0, waterMax = 0.003, sedimentMax = 0.003,
    wrongFuel = { HEAVY_IN_SPARK },
})
R.define("consumer", {
    id = "generator_si_flex", ignition = "spark", referenceFuel = "gasoline",
    accepts = { gasoline = { soft = 1.0, max = 1.0 }, ethanol = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.01, maxDeg = 4.0, waterMax = 0.005, sedimentMax = 0.003,
    coldStart = { fuel = "ethanol", above = 0.85, belowC = 5 },
    wrongFuel = { HEAVY_IN_SPARK },
})
R.define("consumer", {
    id = "engine_ci_stock", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 0.2, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 3.5, waterMax = 0.001, sedimentMax = 0.0015,
    wrongFuel = { PETROL_IN_DIESEL, ETHANOL_IN_DIESEL },
})
R.define("consumer", {
    id = "engine_ci_bio", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 3.5, waterMax = 0.0015, sedimentMax = 0.0015, fuelHeater = true,
    wrongFuel = { PETROL_IN_DIESEL, ETHANOL_IN_DIESEL },
})
R.define("consumer", {
    id = "generator_ci_stock", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 0.2, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 4.0, waterMax = 0.0015, sedimentMax = 0.002,
    wrongFuel = { PETROL_IN_DIESEL, ETHANOL_IN_DIESEL },
})
-- The mod's diesel generator (TLG.DieselGenerator, D-036): the stock diesel
-- generator's limits, but biodiesel at any share without penalty. The
-- owner's decision of 2026-11-10: the player's own biodiesel is its main
-- fuel. No fuel heater: biodiesel still gels in the cold.
R.define("consumer", {
    id = "generator_ci_bio", ignition = "compression", referenceFuel = "diesel",
    accepts = { diesel = { soft = 1.0, max = 1.0 }, biodiesel = { soft = 1.0, max = 1.0 } },
    foreignMax = 0.02, maxDeg = 4.0, waterMax = 0.0015, sedimentMax = 0.002,
    wrongFuel = { PETROL_IN_DIESEL, ETHANOL_IN_DIESEL },
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
