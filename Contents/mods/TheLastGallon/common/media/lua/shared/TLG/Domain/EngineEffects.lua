-- Engine effects of the fuel an engine burns (D-031): what the adapters apply
-- of ConsumerService.evaluate's powerFactor and wearFactor. Pure functions;
-- the adapters own the game calls.
--
--   power  a car's engine power while it runs: its own power times the
--          power factor, never below POWER_FLOOR, back to its own power when
--          it stops or the fuel is fine. Generators have no power to lower.
--   wear   engine condition owed for each litre burned: (wearFactor - 1)
--          times the engine's rate per litre, a fraction carried until a
--          whole point is due.
--
-- Rates are game values, first estimates (docs/balance.md).
TLG.Domain.EngineEffects = TLG.Domain.EngineEffects or {}
local E = TLG.Domain.EngineEffects

-- Only fuel an engine cannot take has power factor 0; with stalls on it stalls
-- within a game minute anyway. With the sandbox option off a car still moves.
E.POWER_FLOOR = 0.5

-- Car engines do not wear from running in vanilla, so the rate is the mod's
-- own: 0.15 condition per litre at wearFactor 2, about half a point per hour
-- of driving at 25 km/h (3.3 L an hour, RT-SP run 176).
E.VEHICLE_WEAR_PER_LITRE = 0.15

-- Generators: vanilla takes 1-2 condition (1.5 on average) once in N running
-- hours, N being the item's ConditionLowerChanceOneIn (30 for Base.Generator),
-- and burns 0.15 L an hour with a fridge on it (0.02 base + 0.13 fridge, BC
-- IsoGenerator). At wearFactor 2 the extra wear per litre equals vanilla's
-- own at that load.
E.GENERATOR_MEAN_LOSS = 1.5
E.GENERATOR_DEFAULT_ONE_IN = 30
E.GENERATOR_REFERENCE_LPH = 0.15

local function positive(x, default)
    if type(x) == "number" and x > 0 then return x end
    return default
end

-- Condition per litre at wearFactor 2 for a car, the sandbox's fuel
-- consumption multiplier taken out so the rate per hour of driving holds.
function E.vehicleWearPerLitre(consumption)
    return E.VEHICLE_WEAR_PER_LITRE / positive(consumption, 1)
end

-- The same for a generator whose item loses condition once in `oneIn` hours.
function E.generatorWearPerLitre(oneIn, consumption)
    return E.GENERATOR_MEAN_LOSS / positive(oneIn, E.GENERATOR_DEFAULT_ONE_IN)
        / (E.GENERATOR_REFERENCE_LPH * positive(consumption, 1))
end

-- The power to run at: `base` times the factor, floored and rounded to the
-- game's whole units; `base` itself when the factor is 1 or more.
function E.targetPower(base, factor)
    if type(base) ~= "number" or base <= 0 then return base end
    local f = factor or 1
    if f >= 1 then return base end
    if f < E.POWER_FLOOR then f = E.POWER_FLOOR end
    local p = math.floor(base * f + 0.5)
    if p < 1 then p = 1 end
    return p
end

-- One minute of power bookkeeping. `state` is { base, applied } while the mod
-- has lowered the engine's power, nil otherwise; `current` is the engine's
-- power now. The reduction is the mod's while `current` still equals what it
-- applied; any other value was set by the game (a repair, an engine swap) and
-- becomes the new base. Returns the new state and the power to set, or nil to
-- leave it as it is.
function E.powerStep(state, current, factor, running)
    local base = current
    if state ~= nil and state.applied == current and state.base ~= nil then base = state.base end
    local target = base
    if running then target = E.targetPower(base, factor) end
    if target == base then
        if current ~= base then return nil, base end
        return nil, nil
    end
    if current ~= target then return { base = base, applied = target }, target end
    return { base = base, applied = target }, nil
end

-- The odds that an engine with a failure chance of `perLitre` for each litre
-- fails while burning `litres` (D-037). The chance, like the exhaust's wear,
-- is given for a car's litre at the sandbox's normal consumption: an hour's
-- driving burns VEHICLE_REFERENCE_LPH of them (run 176).
E.VEHICLE_REFERENCE_LPH = 3.3
function E.failureOdds(perLitre, litres)
    if type(perLitre) ~= "number" or perLitre <= 0 or type(litres) ~= "number" or litres <= 0 then return 0 end
    if perLitre >= 1 then return 1 end
    return 1 - math.exp(litres * math.log(1 - perLitre))
end

-- A car's litres as reference litres: the sandbox's consumption multiplier
-- taken out, so the odds for an hour of driving hold.
function E.vehicleReferenceLitres(litres, consumption)
    return litres / positive(consumption, 1)
end

-- A generator burns far less than a car, and how much depends on the
-- sandbox (0.1 by default): its litres count as the hours they lasted at the
-- reference load, each hour as an hour of a car's driving. The odds of a
-- failure in an hour are then the same for both.
function E.generatorReferenceLitres(litres, consumption)
    return litres / (E.GENERATOR_REFERENCE_LPH * positive(consumption, 1)) * E.VEHICLE_REFERENCE_LPH
end

-- Wear owed for `litres` burned at `wearFactor`, `perLitre` condition per
-- litre at factor 2. Returns the fraction carried on and the whole points to
-- take off now.
function E.accrue(carry, litres, wearFactor, perLitre)
    local add = 0
    if type(litres) == "number" and litres > 0 and type(wearFactor) == "number" and wearFactor > 1
        and type(perLitre) == "number" and perLitre > 0 then
        add = litres * (wearFactor - 1) * perLitre
    end
    local total = add
    if type(carry) == "number" and carry > 0 then total = total + carry end
    local whole = math.floor(total + 1e-9)
    local rest = total - whole
    if rest < 0 then rest = 0 end
    return rest, whole
end

return E
