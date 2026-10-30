require "support/fixtures"
local Aging, Supply = TLG.Domain.Aging, TLG.Domain.Supply

local function mixed(storage, sealed)
    return F.supply({ storage = storage or "open_vessel", cap = 200, sealed = sealed,
        q = { gasoline = 60, ethanol = 10, diesel = 50, biodiesel = 20, water = 0.05, sediment = 0.02 },
        deg = { gasoline = 0.3, ethanol = 0.1, diesel = 0.2, biodiesel = 0.6 }, mic = 0.05, stab = 0.4 })
end

T.case("aging: closed form matches fine numerical integration", function()
    local a, k, deg0, dt = 0.35, 3e-4, 0.4, 0.01
    local d = deg0
    for _ = 1, 500000 do d = d + k * (1 + a * d) * dt end
    T.near(Aging.oxidize(deg0, k * 5000, a), d, 1e-5)
    T.near(Aging.oxidize(0.5, 2.0, 0), 2.5, 1e-12, "linear when a = 0")
end)

T.case("aging: one large advance equals many random smaller advances", function()
    local env = F.env()
    local rng = TLG.Rng.new(TEST_SEED)
    for trial = 1, 6 do
        local s = mixed(trial % 2 == 0 and "open_vessel" or "drum_steel", trial % 3 ~= 0)
        local horizon = 24 * (30 + rng:int(0, 300))
        local whole = Aging.advance(s, horizon, env)
        local stepped = s
        local t = 0
        while t < horizon do
            t = math.min(horizon, t + rng:range(0.01, 400))
            stepped = Aging.advance(stepped, t, env)
        end
        F.assertSupplyClose(whole, stepped, 1e-9, "trial " .. trial)
        F.noViolations(whole, "whole")
    end
end)

T.case("aging: microbial switch from dry to wet is time-split exactly", function()
    local env = F.env()
    -- Diesel just below its water capacity in an open vessel: free water appears mid-run.
    local s = F.supply({ storage = "open_vessel", cap = 100, q = { diesel = 80, water = 0.0159 }, deg = { diesel = 0 } })
    T.ok(Supply.freeWater(s) == 0, "starts dry")
    local whole = Aging.advance(s, 24 * 400, env)
    T.ok(Supply.freeWater(whole) > 0, "wet at the end")
    T.ok(whole.mic > 0.01, "microbes grew")
    local stepped, t = s, 0
    while t < 24 * 400 do
        t = t + 17.3
        stepped = Aging.advance(stepped, math.min(t, 24 * 400), env)
    end
    F.assertSupplyClose(whole, stepped, 1e-9, "microbial")
end)

T.case("aging: profile changes apply only from their start time", function()
    local history = {
        { from = -math.huge, id = "default", agingMul = 1, breathingMul = 1, microbialMul = 1 },
        { from = 24 * 60, id = "fast", agingMul = 2, breathingMul = 1.5, microbialMul = 1.5 },
    }
    local envChanged = F.env(history)
    local envDefault = F.env()
    local s = mixed("drum_steel", true)
    local a = Aging.advance(s, 24 * 60, envChanged)
    local b = Aging.advance(s, 24 * 60, envDefault)
    F.assertSupplyClose(a, b, 1e-12, "history before change")
    local full = Aging.advance(s, 24 * 120, envChanged)
    local split = Aging.advance(a, 24 * 120, envChanged)
    F.assertSupplyClose(full, split, 1e-9, "split at change")
    local slower = Aging.advance(s, 24 * 120, envDefault)
    T.ok(full.deg.gasoline > slower.deg.gasoline, "faster profile ages faster afterwards")
end)

T.case("aging: clock regression never rejuvenates", function()
    local env = F.env()
    local s = Aging.advance(mixed(), 500, env)
    local back, info = Aging.advance(s, 100, env)
    T.eq(info.reason, "clock_regression")
    F.assertSupplyClose(back, s, 0, "unchanged")
    T.eq(back.t, s.t)
end)

T.case("aging: sealing, stabilizer and cool storage slow oxidation; stabilizer is bounded", function()
    local env = F.env()
    local function deg(o)
        local s = F.supply({ storage = o.storage, cap = 20, sealed = o.sealed, stab = o.stab or 0,
            q = { gasoline = 20 }, deg = { gasoline = 0 } })
        return Aging.advance(s, 24 * 90, env).deg.gasoline
    end
    local sealed = deg({ storage = "jerrycan_steel", sealed = true })
    local unsealed = deg({ storage = "jerrycan_steel", sealed = false })
    local stabilized = deg({ storage = "jerrycan_steel", sealed = true, stab = 1 })
    local overdosed = deg({ storage = "jerrycan_steel", sealed = true, stab = 2 })
    local ground = deg({ storage = "station_ust" })
    local vehicle = deg({ storage = "vehicle_tank" })
    T.ok(unsealed > sealed * 2, "unsealed much faster")
    T.ok(stabilized < sealed * 0.4, "stabilizer slows aging")
    T.near(overdosed, stabilized, 1e-12, "dose above full strength has no extra effect")
    T.ok(ground < sealed, "underground cooler than sheltered in summer")
    T.ok(vehicle > sealed, "vehicle tank faster than sealed can")
end)

T.case("aging: breathing converts fuel volume into water without changing total", function()
    local env = F.env()
    local s = F.supply({ storage = "open_vessel", cap = 50, q = { ethanol = 40 }, deg = { ethanol = 0 } })
    local out, info = Aging.advance(s, 24 * 365, env)
    T.near(Supply.total(out), 40, 1e-9, "total conserved")
    T.ok(info.waterIngress > 0.1, "ethanol picked up water: " .. info.waterIngress)
    T.near(out.q.water, info.waterIngress, 1e-12)
end)

T.case("aging: gas leaks are explicit and accounted", function()
    local env = F.env()
    local s = F.supply({ storage = "gas_holder", cap = 20, q = { biogas = 10 }, cond = 0.5 })
    local out, info = Aging.advance(s, 24 * 10, env)
    T.near(Supply.total(out) + info.leaked, 10, 1e-9)
    T.ok(info.leaked > 0)
end)

T.case("aging: calibration targets for the default campaign (docs/balance.md)", function()
    local env = F.env()
    local function daysTo(storage, sealed, target)
        local s = F.supply({ storage = storage, cap = 20, sealed = sealed, q = { gasoline = 20 }, deg = { gasoline = 0 } })
        for day = 1, 1500 do
            s = Aging.advance(s, day * 24, env)
            if s.deg.gasoline >= target then return day end
        end
        return math.huge
    end
    local ustWeathered = daysTo("station_ust", true, 1.0)
    local ustUnsuitable = daysTo("station_ust", true, 3.5)
    local vehicleWeathered = daysTo("vehicle_tank", true, 1.0)
    local canWeathered = daysTo("jerrycan_steel", true, 1.0)
    T.ok(ustWeathered >= 100 and ustWeathered <= 200, "station weathered day " .. ustWeathered)
    T.ok(ustUnsuitable >= 240 and ustUnsuitable <= 480, "station unsuitable day " .. ustUnsuitable)
    T.ok(vehicleWeathered >= 30 and vehicleWeathered <= 90, "vehicle weathered day " .. vehicleWeathered)
    T.ok(canWeathered >= 60 and canWeathered <= 150, "sealed can weathered day " .. canWeathered)
    print(string.format("      calibration: UST weathered d%d unsuitable d%d; vehicle weathered d%d; can weathered d%d",
        ustWeathered, ustUnsuitable, vehicleWeathered, canWeathered))
end)
