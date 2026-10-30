require "support/fixtures"
require "TLG/Content/Energy"
local R, Tables = TLG.Registry, TLG.Tables
local E = TLG.Domain.Energy
local Battery, Gen, Dispatch = E.Battery, E.Generation, E.Dispatch
local ES = TLG.EnergyService

-- Relative tolerance of the exactness and conservation checks (docs/balance.md).
local REL = 1e-9

local function close(a, b, label, rel)
    T.ok(type(a) == "number" and type(b) == "number" and F.close(a, b, rel or REL),
        tostring(label) .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

-- Network from a node list where every node hangs off junction "J".
local function star(nodes, policy, t)
    local list, edges = { Dispatch.junction("J") }, {}
    for _, n in ipairs(nodes) do
        list[#list + 1] = n
        edges[#edges + 1] = { "J", n.id }
    end
    local g = Dispatch.graph(list, edges)
    T.ok(g.ok, "graph: " .. tostring(g.reason))
    local n = Dispatch.network(g.graph, Dispatch.component(g.graph, "J"), t or 0, policy)
    T.ok(n.ok, "network: " .. tostring(n.reason))
    return n.network
end

local function run(net, t1, ps, demand)
    local r = ES.dispatch(net, { t0 = net.t, t1 = t1 }, ps or {}, demand or {})
    T.ok(r.ok, "dispatch: " .. tostring(r.reason))
    return r
end

local function conserved(rep, label)
    local t = rep.totals
    close(t.energyInKWh, t.deliveredKWh + t.storedDeltaKWh + t.lossesKWh + t.curtailedKWh, label .. " network balance")
    for _, id in ipairs(Tables.sortedKeys(rep.generators)) do
        local g = rep.generators[id]
        close(g.fuelKWh, g.electricKWh + g.heatUsedKWh + g.heatUnusedKWh + g.lossKWh, label .. " generator budget " .. id)
    end
    for _, id in ipairs(Tables.sortedKeys(rep.batteries)) do
        local b = rep.batteries[id]
        close(b.chargedKWh - b.dischargedKWh, (b.e1 - b.e0) + b.chargeLossKWh + b.dischargeLossKWh + b.selfDischargeKWh,
            label .. " battery balance " .. id)
    end
end

local function sameNetwork(a, b, label)
    close(a.t, b.t, label .. " t")
    for _, id in ipairs(Tables.sortedKeys(a.batteries)) do
        local x, y = a.batteries[id], b.batteries[id]
        close(x.e, y.e, label .. " battery " .. id .. " e")
        T.eq(x.lvd, y.lvd, label .. " battery " .. id .. " lvd")
    end
    for _, id in ipairs(Tables.sortedKeys(a.producers)) do
        local x, y = a.producers[id], b.producers[id]
        T.eq(x.running, y.running, label .. " producer " .. id .. " running")
        T.eq(x.stopReason, y.stopReason, label .. " producer " .. id .. " stopReason")
        close(x.runFor or 0, y.runFor or 0, label .. " producer " .. id .. " runFor")
    end
end

local SECTIONS = { "producers", "generators", "consumers", "batteries", "fuelUsed" }

local function sameReport(a, b, label)
    for _, s in ipairs(SECTIONS) do
        local keys = {}
        for k in pairs(a[s]) do keys[k] = true end
        for k in pairs(b[s]) do keys[k] = true end
        for _, id in ipairs(Tables.sortedKeys(keys)) do
            local x, y = a[s][id], b[s][id]
            T.ok(x ~= nil and y ~= nil, label .. " " .. s .. "." .. id .. " present in both")
            for _, f in ipairs(Tables.sortedKeys(x)) do
                if type(x[f]) == "number" then
                    close(x[f], y[f], label .. " " .. s .. "." .. id .. "." .. f)
                else
                    T.eq(x[f], y[f], label .. " " .. s .. "." .. id .. "." .. f)
                end
            end
        end
    end
    for _, f in ipairs(Tables.sortedKeys(a.totals)) do close(a.totals[f], b.totals[f], label .. " totals." .. f) end
    T.eq(#a.events, #b.events, label .. " event count")
    for i = 1, math.min(#a.events, #b.events) do
        local x, y = a.events[i], b.events[i]
        T.ok(x.kind == y.kind and x.id == y.id and x.reason == y.reason,
            label .. " event " .. i .. ": " .. tostring(x.kind) .. "/" .. tostring(x.id) .. " vs " .. tostring(y.kind) .. "/" .. tostring(y.id))
        close(x.t, y.t, label .. " event " .. i .. " time")
    end
end

-- Subtracts reported fuel from the caller-owned fuel table (one owner).
local function consumeFuel(ps, rep)
    local out = Tables.deepCopy(ps)
    for _, id in ipairs(Tables.sortedKeys(rep.fuelUsed)) do
        out[id].amount = math.max(0, out[id].amount - rep.fuelUsed[id].amount)
    end
    return out
end

-- Random network with every feature: two renewables, a CHP generator,
-- two batteries, prioritized, uncontrolled, all-or-nothing and heat loads.
local function scenario(rng)
    local modes = { "auto", "auto", "auto", "on", "off" }
    local condB2 = rng:range(0.5, 1)
    local policy = { startBelow = rng:range(0.15, 0.4), stopAbove = rng:range(0.6, 0.98), minRunHours = rng:range(0, 3) }
    local net = star({
        Gen.producer({ id = "PV", def = "solar_array", exposure = rng:range(0.5, 1) }),
        Gen.producer({ id = "WT", def = "wind_turbine_small" }),
        Gen.producer({ id = "GEN", def = "generator_gas_chp", mode = rng:pick(modes), policy = policy }),
        Battery.new({ id = "B1", def = "battery_bank", e = rng:range(0, 3.9) }),
        Battery.new({ id = "B2", def = "car_battery_heavy", cond = condB2, e = rng:range(0, 0.65 * condB2) }),
        Dispatch.consumer({ id = "L1", priority = 1 }),
        Dispatch.consumer({ id = "L2", priority = 2 }),
        Dispatch.consumer({ id = "L3", priority = 2 }),
        Dispatch.consumer({ id = "V", uncontrolled = true }),
        Dispatch.consumer({ id = "H1", heat = true, priority = 1 }),
        Dispatch.consumer({ id = "H2", heat = true, priority = 2 }),
    })
    local ps = {
        PV = { kw = rng:range(0, 1.5) },
        WT = { kw = rng:range(0, 1.0) },
        GEN = { fuel = rng:pick({ "propane", "biogas" }), amount = rng:range(0.2, 6), powerFactor = rng:range(0.6, 1) },
    }
    local l2 = rng:range(0, 2)
    local demand = {
        L1 = { kw = rng:range(0, 1.5) },
        L2 = { kw = l2, minKW = l2 },
        L3 = { kw = rng:range(0, 1.2), minKW = rng:range(0, 0.3) },
        V = { kw = rng:range(0, 0.6) },
        H1 = { kw = rng:range(0, 5) },
        H2 = { kw = rng:range(0, 5) },
    }
    if demand.L3.minKW > demand.L3.kw then demand.L3.minKW = demand.L3.kw end
    return net, ps, demand
end

------------------------------------------------------------------------------
-- Content and definitions
------------------------------------------------------------------------------

T.case("energy: content validates and maps the vanilla car batteries", function()
    T.eq(#R.validate(), 0, table.concat(R.validate(), " | "))
    T.eq(Battery.def("car_battery_standard").item, "Base.CarBattery1")
    T.eq(Battery.def("car_battery_heavy").item, "Base.CarBattery2")
    T.eq(Battery.def("car_battery_sport").item, "Base.CarBattery3")
    T.eq(Dispatch.loadDef("battery_charger").item, "Base.CarBatteryCharger")
    T.ok(Battery.def("battery_bank") ~= nil and Gen.def("battery_bank") == nil, "roles are separate")
    for _, id in ipairs({ "car_battery_standard", "car_battery_heavy", "car_battery_sport", "battery_bank" }) do
        local d = Battery.def(id)
        T.ok(d.etaCharge * d.etaDischarge < 1, id .. " round trip loses")
    end
    local bad = Battery.problems({ capacityKWh = 1, maxChargeKW = 1, maxDischargeKW = 1, etaCharge = 1, etaDischarge = 1,
        selfDischargePerHour = 0, reconnectFraction = 0 })
    local text = table.concat(bad, "\n")
    T.ok(string.find(text, "round trip must lose energy", 1, true), "lossless round trip rejected")
    T.ok(string.find(text, "reconnectFraction", 1, true), "zero reconnect rejected")
    local leaky = table.concat(Battery.problems({ capacityKWh = 100, maxChargeKW = 0.01, maxDischargeKW = 1, etaCharge = 0.9,
        etaDischarge = 0.9, selfDischargePerHour = 0.005, reconnectFraction = 0.1 }), "\n")
    T.ok(string.find(leaky, "could never become full", 1, true), "charging must outrun self-discharge")
    local windBad = table.concat(Gen.problems({ energy = "wind", ratedKW = 1, cutInMS = 12, ratedMS = 11, cutOutMS = 25 }), "\n")
    T.ok(string.find(windBad, "cutInMS", 1, true), "wind curve order")
    local fueledBad = table.concat(Gen.problems({ energy = "fueled", ratedKW = 1, efficiency = 0.9, consumer = "nope" }), "\n")
    T.ok(string.find(fueledBad, "efficiency", 1, true) and string.find(fueledBad, "unknown consumer profile", 1, true), fueledBad)
end)

------------------------------------------------------------------------------
-- Battery
------------------------------------------------------------------------------

T.case("energy: battery round trip always loses usable energy", function()
    for _, id in ipairs({ "car_battery_standard", "car_battery_heavy", "car_battery_sport", "battery_bank" }) do
        local d = Battery.def(id)
        local b = Battery.new({ id = "X", def = id, e = 0 })
        local c = Battery.run(b, 50, 0, 100)
        T.ok(c.ok, tostring(c.reason))
        close(c.battery.e, d.capacityKWh, id .. " charged to capacity")
        T.ok(c.rejectedKWh > 0, "offer above the charge limit is rejected")
        local dis = Battery.run(c.battery, 0, 50, 100)
        T.ok(dis.ok, tostring(dis.reason))
        T.near(dis.battery.e, 0, 1e-12, id .. " discharged to empty")
        T.ok(dis.dischargedKWh < c.chargedKWh * d.etaCharge * d.etaDischarge + 1e-12, id .. " loses at least the efficiency product")
        close(c.chargedKWh, (c.battery.e - b.e) + c.chargeLossKWh + c.selfDischargeKWh, id .. " charge balance")
        close(-dis.dischargedKWh, (dis.battery.e - c.battery.e) + dis.dischargeLossKWh + dis.selfDischargeKWh, id .. " discharge balance")
    end
    -- Property over random definitions and random partial cycles.
    local rng = TLG.Rng.new(TEST_SEED)
    for k = 1, 25 do
        local id = "test_battery_" .. k
        local ec, ed = rng:range(0.5, 1), rng:range(0.5, 1)
        if ec * ed >= 1 then ed = 0.99 end
        R.define("machine", { id = id, energy = "battery", capacityKWh = rng:range(0.1, 20), maxChargeKW = rng:range(0.05, 5),
            maxDischargeKW = rng:range(0.05, 5), etaCharge = ec, etaDischarge = ed,
            selfDischargePerHour = rng:range(0, 1e-3), reconnectFraction = rng:range(0.01, 0.5) })
    end
    local ok, err = pcall(function()
        for k = 1, 25 do
            local b = Battery.new({ id = "P", def = "test_battery_" .. k, e = 0 })
            local c = Battery.run(b, rng:range(0.01, 6), 0, rng:range(0.1, 10))
            local dis = Battery.run(c.battery, 0, 1e6, 1e4)
            T.ok(c.chargedKWh <= 0 or dis.dischargedKWh < c.chargedKWh, "random round trip " .. k .. " loses energy")
            T.ok(dis.battery.e >= 0 and dis.battery.e <= 1e-9, "empty after full discharge")
        end
    end)
    for k = 1, 25 do R.entries.machine["test_battery_" .. k] = nil end
    T.ok(ok, tostring(err))
end)

T.case("energy: battery state of charge stays within capacity and the disconnect has hysteresis", function()
    local rng = TLG.Rng.new(TEST_SEED + 1)
    local d = Battery.def("car_battery_standard")
    local b = Battery.new({ id = "B", def = "car_battery_standard", e = 0.2, cond = 0.8 })
    local cap = d.capacityKWh * 0.8
    for _ = 1, 200 do
        local r
        if rng:next() < 0.5 then r = Battery.run(b, rng:range(0, 1), 0, rng:range(0, 3)) else r = Battery.run(b, 0, rng:range(0, 2), rng:range(0, 3)) end
        T.ok(r.ok, tostring(r.reason))
        b = r.battery
        T.ok(b.e >= 0 and b.e <= cap, "e within [0, capacity]: " .. tostring(b.e))
    end
    -- Run empty: discharge is refused until reconnectFraction is reached.
    b = Battery.run(b, 0, 10, 50).battery
    T.eq(b.lvd, true, "disconnected when empty")
    local small = Battery.run(b, 0.02, 0, 1).battery
    T.ok(small.e > 0 and small.e < d.reconnectFraction * cap and small.lvd, "still disconnected below reconnect")
    local refused = Battery.run(small, 0, 0.5, 1)
    T.near(refused.dischargedKWh, 0, 0, "no discharge while disconnected")
    local back = Battery.run(small, 0.16, 0, 2)
    T.ok(not back.battery.lvd, "reconnected above the threshold")
    T.ok(Battery.run(back.battery, 0, 0.5, 0.1).dischargedKWh > 0, "discharges after reconnect")
    -- Condition loss never leaves e above the new capacity.
    local worn = Battery.withCondition(Battery.new({ id = "W", def = "battery_bank", e = 3.9 }), 0.5)
    close(worn.battery.e, 1.95, "clamped to worn capacity")
    close(worn.lostKWh, 1.95, "lost energy reported")
end)

T.case("energy: battery self-discharge is linear, stops at empty and splits exactly", function()
    local d = Battery.def("battery_bank")
    local b = Battery.new({ id = "B", def = "battery_bank", e = 1.0 })
    local idle = Battery.run(b, 0, 0, 100)
    close(idle.battery.e, 1.0 - d.selfDischargePerHour * d.capacityKWh * 100, "linear self-discharge")
    local long = Battery.run(b, 0, 0, 1e5)
    T.eq(long.battery.e, 0, "never below zero")
    close(long.selfDischargeKWh, 1.0, "self-discharge cannot exceed stored energy")
    local rng = TLG.Rng.new(TEST_SEED + 2)
    for trial = 1, 10 do
        local start = Battery.new({ id = "B", def = "battery_bank", e = rng:range(0, 3.9) })
        local pIn, pOut = 0, 0
        if trial % 2 == 0 then pIn = rng:range(0, 2) else pOut = rng:range(0, 3) end
        local hours = rng:range(1, 20)
        local whole = Battery.run(start, pIn, pOut, hours)
        local cur, t = start, 0
        local sums = { chargedKWh = 0, dischargedKWh = 0, selfDischargeKWh = 0 }
        while t < hours do
            local dt = math.min(hours - t, rng:range(0.01, 5))
            local r = Battery.run(cur, pIn, pOut, dt)
            for k in pairs(sums) do sums[k] = sums[k] + r[k] end
            cur, t = r.battery, t + dt
        end
        close(whole.battery.e, cur.e, "split e " .. trial)
        T.eq(whole.battery.lvd, cur.lvd, "split lvd " .. trial)
        for k in pairs(sums) do close(whole[k], sums[k], "split " .. k .. " " .. trial) end
    end
end)

------------------------------------------------------------------------------
-- Generation models
------------------------------------------------------------------------------

T.case("energy: solar follows time of day, season, cloud, exposure and condition", function()
    local def = Gen.def("solar_array")
    local function kw(doy, hour, cloud, node) return Gen.availableKW(def, node or {}, { dayOfYear = doy, hourOfDay = hour, cloud = cloud or 0 }) end
    T.eq(kw(190, 2), 0, "night")
    T.ok(kw(190, 13) > kw(190, 9) and kw(190, 9) > kw(190, 6.5), "rises towards solar noon")
    local function daily(doy)
        local s = 0
        for h = 0, 23 do s = s + kw(doy, h + 0.5) end
        return s
    end
    T.ok(daily(190) > daily(355) * 1.3, "summer day yields clearly more than winter: " .. daily(190) .. " vs " .. daily(355))
    T.ok(Gen.dayLength(172) > 14 and Gen.dayLength(355) < 10, "day length by season")
    close(kw(190, 13, 1) / kw(190, 13, 0), 0.25, "full overcast keeps diffuse 25%")
    T.ok(kw(190, 13, 0.5) < kw(190, 13, 0) and kw(190, 13, 0.5) > kw(190, 13, 1), "partial cloud in between")
    close(kw(190, 13, 0, { exposure = 0.5 }), kw(190, 13) * 0.5, "exposure scales")
    close(kw(190, 13, 0, { cond = 0.25 }), kw(190, 13) * 0.25, "condition scales")
    local rng = TLG.Rng.new(TEST_SEED + 3)
    for _ = 1, 300 do
        local v = kw(rng:int(1, 365), rng:range(0, 24), rng:next(), { exposure = rng:next(), cond = rng:next() })
        T.ok(v >= 0 and v <= def.ratedKW, "bounded by rating")
    end
    local nkw, why = Gen.availableKW(def, {}, { dayOfYear = 190, hourOfDay = 0 / 0 })
    T.ok(nkw == nil and why == "invalid_time", "NaN hour rejected")
    nkw, why = Gen.availableKW(def, {}, { dayOfYear = 190, hourOfDay = 12, cloud = 1.5 })
    T.ok(nkw == nil and why == "invalid_weather", "cloud above 1 rejected")
end)

T.case("energy: wind output is bounded and weather-derived", function()
    local def = Gen.def("wind_turbine_small")
    local function kw(v, node) return Gen.availableKW(def, node or {}, { windMS = v }) end
    T.eq(kw(2.9), 0, "below cut-in")
    T.eq(kw(25), 0, "furled at cut-out")
    T.eq(kw(11), def.ratedKW, "rated at rated speed")
    T.eq(kw(18), def.ratedKW, "flat between rated and cut-out")
    T.ok(kw(5) < kw(7) and kw(7) < kw(9), "rises with wind speed")
    close(kw(11, { exposure = 0.5 }), kw(5.5), "exposure scales wind speed")
    local rng = TLG.Rng.new(TEST_SEED + 4)
    for _ = 1, 300 do
        local v = kw(rng:range(0, 60), { cond = rng:next(), exposure = rng:next() })
        T.ok(v >= 0 and v <= def.ratedKW, "bounded")
    end
    local nkw, why = Gen.availableKW(def, {}, { windMS = -1 })
    T.ok(nkw == nil and why == "invalid_weather", "negative wind rejected")
end)

T.case("energy: hydro delivers the authored flow", function()
    local def = Gen.def("hydro_wheel")
    local base = Gen.availableKW(def, {}, {})
    close(base, 9.81 * def.flowM3s * def.headM * def.efficiency, "hydraulic power")
    T.eq(Gen.availableKW(def, {}, { dayOfYear = 10, hourOfDay = 3, cloud = 1 }), base, "independent of time and weather")
    close(Gen.availableKW(def, { headM = 0.75 }), base / 2, "site head override")
    T.eq(Gen.availableKW(def, { flowM3s = 10 }), def.ratedKW, "capped at rating")
    R.define("machine", { id = "test_hydro_seasonal", energy = "hydro", ratedKW = 2, flowM3s = 0.1, headM = 1, efficiency = 0.5,
        monthly = { 1.5, 1.5, 1.5, 1, 1, 0.5, 0.5, 0.5, 0.5, 1, 1, 1.5 } })
    local seasonal = Gen.def("test_hydro_seasonal")
    local jan, jul = Gen.availableKW(seasonal, {}, { month = 1 }), Gen.availableKW(seasonal, {}, { month = 7 })
    local problems = Gen.problems(seasonal)
    R.entries.machine.test_hydro_seasonal = nil
    T.eq(#problems, 0)
    close(jan / jul, 3, "authored monthly flow")
end)

T.case("energy: fueled generation shares one fuel budget between electricity, heat and losses", function()
    for _, c in ipairs({ { "generator_flex_5kw", "gasoline" }, { "generator_diesel_6kw", "diesel" }, { "generator_gas_chp", "propane" },
        { "generator_gas_chp", "biogas" } }) do
        local def, mj = Gen.def(c[1]), R.get("fuel", c[2]).energyMJ
        local rated = Gen.budget(def, def.ratedKW, 2, mj)
        T.ok(rated.ok, tostring(rated.reason))
        close(rated.electricKWh, rated.fuelUnits * mj * def.efficiency / 3.6, c[1] .. " units x energyMJ x efficiency")
        close(rated.fuelKWh, rated.electricKWh + rated.heatKWh + rated.lossKWh, c[1] .. " electric + heat + loss = fuel")
        close(rated.heatKWh, (def.heatRecovery or 0) * (rated.fuelKWh - rated.electricKWh), c[1] .. " heat from waste only")
        local half = Gen.budget(def, def.ratedKW / 2, 2, mj)
        T.ok(half.electricKWh / half.fuelKWh < def.efficiency, c[1] .. " part load is less efficient")
        local idle = Gen.budget(def, 0, 1, mj)
        T.ok(idle.fuelKWh > 0 and idle.electricKWh == 0, c[1] .. " idle burn")
    end
    T.eq(Gen.budget(Gen.def("generator_gas_chp"), 5, 1, 93).reason, "invalid_power", "above rating")
end)

------------------------------------------------------------------------------
-- Dispatch
------------------------------------------------------------------------------

T.case("energy: allocation follows priority with stable id tie-break; uncontrolled load first", function()
    local net = star({
        Gen.producer({ id = "PV1", def = "solar_array" }),
        Gen.producer({ id = "PV2", def = "solar_array" }),
        Dispatch.consumer({ id = "V", uncontrolled = true }),
        Dispatch.consumer({ id = "C", priority = 2 }),
        Dispatch.consumer({ id = "B", priority = 2 }),
        Dispatch.consumer({ id = "A", priority = 1 }),
    })
    local r = run(net, 1, { PV1 = { kw = 1.5 }, PV2 = { kw = 1.5 } },
        { V = { kw = 0.5 }, A = { kw = 1.5 }, B = { kw = 1.5, minKW = 1.5 }, C = { kw = 0.8 } })
    local c = r.report.consumers
    close(c.V.servedKWh, 0.5, "uncontrolled served first")
    close(c.A.servedKWh, 1.5, "priority 1")
    T.eq(c.B.servedKWh, 0, "all-or-nothing load that does not fit gets nothing")
    close(c.B.unmetKWh, 1.5, "its demand is recorded as unmet")
    close(c.C.servedKWh, 0.8, "next flexible load takes the rest")
    close(r.report.totals.curtailedKWh, 0.2, "surplus curtailed")
    conserved(r.report, "priority")
    -- Equal priority: the lower id wins; node order does not matter.
    for _, order in ipairs({ { "D", "E" }, { "E", "D" } }) do
        local n2 = star({ Gen.producer({ id = "PV", def = "solar_array" }),
            Dispatch.consumer({ id = order[1], priority = 3 }), Dispatch.consumer({ id = order[2], priority = 3 }) })
        local r2 = run(n2, 1, { PV = { kw = 1.5 } }, { D = { kw = 1 }, E = { kw = 1 } })
        close(r2.report.consumers.D.servedKWh, 1, "tie-break by id")
        close(r2.report.consumers.E.servedKWh, 0.5, "remainder to the higher id")
    end
    local a = Dispatch.allocate(5, { { id = "x", kw = 3, priority = 2 }, { id = "z", kw = 3, priority = 1 }, { id = "y", kw = 2, priority = 1 } })
    T.ok(a.ok)
    T.eq(a.allocation.y, 2); T.eq(a.allocation.z, 3); T.eq(a.allocation.x, 0)
    close(a.total, 5, "never more than available")
end)

T.case("energy: a battery empties mid-interval and the lowest priority loses supply first", function()
    local d = Battery.def("battery_bank")
    local net = star({
        Gen.producer({ id = "PV", def = "solar_array" }),
        Battery.new({ id = "B1", def = "battery_bank", e = 1.0 }),
        Dispatch.consumer({ id = "A", priority = 1 }),
        Dispatch.consumer({ id = "B", priority = 2 }),
    })
    local r = run(net, 2, { PV = { kw = 1.0 } }, { A = { kw = 1 }, B = { kw = 1 } })
    local tEmpty = 1.0 / (1 / d.etaDischarge + d.selfDischargePerHour * d.capacityKWh)
    close(r.report.consumers.A.servedKWh, 2, "priority 1 always served")
    close(r.report.consumers.B.servedKWh, tEmpty, "priority 2 served until the battery is empty")
    local empty = nil
    for _, e in ipairs(r.report.events) do
        if e.kind == "battery_empty" then empty = e end
    end
    T.ok(empty ~= nil, "battery_empty event")
    close(empty.t, tEmpty, "event at the exact time")
    T.eq(r.network.batteries.B1.lvd, true)
    conserved(r.report, "empty")
end)

T.case("energy: storage respects charge and discharge limits with losses", function()
    local d = Battery.def("battery_bank")
    local net = star({ Gen.producer({ id = "PV", def = "solar_array" }), Battery.new({ id = "B1", def = "battery_bank", e = 0 }) })
    local r = run(net, 1, { PV = { kw = 1.5 } }, {})
    close(r.report.batteries.B1.chargedKWh, d.maxChargeKW, "charge limit")
    close(r.report.totals.curtailedKWh, 1.5 - d.maxChargeKW, "rest curtailed")
    close(r.network.batteries.B1.e, d.maxChargeKW * d.etaCharge - d.selfDischargePerHour * d.capacityKWh, "charge efficiency")
    T.eq(r.network.batteries.B1.lvd, false, "reconnected while charging")
    conserved(r.report, "charge limit")
    local s = Battery.def("car_battery_standard")
    local net2 = star({ Battery.new({ id = "C1", def = "car_battery_standard", e = s.capacityKWh }), Dispatch.consumer({ id = "L" }) })
    local r2 = run(net2, 0.1, {}, { L = { kw = 1.0 } })
    close(r2.report.consumers.L.servedKWh, s.maxDischargeKW * 0.1, "discharge limit")
    close(r2.report.consumers.L.unmetKWh, (1.0 - s.maxDischargeKW) * 0.1, "unmet recorded")
    close(r2.network.batteries.C1.e, s.capacityKWh - (s.maxDischargeKW / s.etaDischarge + s.selfDischargePerHour * s.capacityKWh) * 0.1,
        "discharge efficiency")
    conserved(r2.report, "discharge limit")
end)

T.case("energy: recovered heat is allocated at most once across several consumers", function()
    local def = Gen.def("generator_gas_chp")
    local function chp(heatDemand)
        local net = star({
            Gen.producer({ id = "GEN", def = "generator_gas_chp", mode = "on" }),
            Dispatch.consumer({ id = "L1", priority = 1 }),
            Dispatch.consumer({ id = "H1", heat = true, priority = 1 }),
            Dispatch.consumer({ id = "H2", heat = true, priority = 2 }),
            Dispatch.consumer({ id = "H3", heat = true, priority = 2, def = "heat_loop" }),
        })
        return run(net, 1, { GEN = { fuel = "propane", amount = 50 } }, heatDemand)
    end
    local fuelKW = def.ratedKW / def.efficiency
    local avail = def.heatRecovery * (fuelKW - def.ratedKW)
    local r = chp({ L1 = { kw = 4 }, H1 = { kw = 6 }, H2 = { kw = 6 }, H3 = { kw = 6 } })
    local c = r.report.consumers
    close(c.H1.servedKWh, 6, "first heat consumer")
    close(c.H2.servedKWh, avail - 6, "second gets only the remainder")
    T.eq(c.H3.servedKWh, 0, "nothing left for the third")
    close(r.report.totals.heatKWh, avail, "total heat equals available recovered heat")
    close(r.report.generators.GEN.heatKWh, avail, "generator recovered heat")
    T.near(r.report.totals.heatUnusedKWh, 0, 1e-12)
    close(r.report.fuelUsed.GEN.amount, fuelKW * 3.6 / 93.0, "fuel for rated output")
    conserved(r.report, "chp full")
    local low = chp({ L1 = { kw = 4 }, H1 = { kw = 2 }, H2 = { kw = 1 } })
    close(low.report.totals.heatKWh, 3, "small demand fully served")
    close(low.report.totals.heatUnusedKWh, avail - 3, "unused heat is waste")
    conserved(low.report, "chp partial")
    local none = chp({ H1 = { kw = 5 } })
    T.eq(none.report.consumers.H1.servedKWh > 0, true, "idle CHP still offers recovered heat")
    T.le(none.report.consumers.H1.servedKWh, none.report.generators.GEN.heatKWh + 1e-12, "bounded by recovered heat")
end)

T.case("energy: fuel use is reported once for the consumption owner and exhaustion stops the generator", function()
    local def = Gen.def("generator_flex_5kw")
    local net = star({ Gen.producer({ id = "GEN", def = "generator_flex_5kw", mode = "on" }), Dispatch.consumer({ id = "L" }) })
    local ps = { GEN = { fuel = "gasoline", amount = 1.0 } }
    local r = run(net, 5, ps, { L = { kw = 2 } })
    local fkw = Gen.fuelKW(def, 2)
    local tOut = (1.0 * 32 / 3.6) / fkw
    close(r.report.fuelUsed.GEN.amount, 1.0, "all fuel burned, never more")
    T.le(r.report.fuelUsed.GEN.amount, 1.0, "bounded by the fuel offered")
    T.eq(r.report.fuelUsed.GEN.owner, "tlg")
    T.eq(r.report.fuelUsed.GEN.fuel, "gasoline")
    close(r.report.consumers.L.servedKWh, 2 * tOut, "served until the tank ran dry")
    T.eq(r.network.producers.GEN.running, false)
    T.eq(r.network.producers.GEN.stopReason, "no_fuel")
    T.eq(r.network.producers.GEN.amount, nil, "the network never stores fuel")
    T.eq(r.network.producers.GEN.fuel, nil, "the network never stores fuel")
    T.eq(ps.GEN.amount, 1.0, "caller's fuel record untouched")
    local stop = r.report.events[#r.report.events]
    T.ok(stop.kind == "generator_stop" and stop.reason == "no_fuel", "stop event")
    close(stop.t, tOut, "stops at exhaustion time")
    -- A second call with the subtracted fuel cannot run again.
    local again = run(r.network, 6, consumeFuel(ps, r.report), { L = { kw = 2 } })
    T.eq(again.report.totals.generatedKWh, 0)
    -- Native consumption owner is reported as such (informational only).
    R.define("machine", { id = "test_native_gen", energy = "fueled", consumer = "generator_si_stock", owner = "native",
        ratedKW = 3, efficiency = 0.2 })
    local ok, err = pcall(function()
        local n2 = star({ Gen.producer({ id = "VG", def = "test_native_gen", mode = "on" }), Dispatch.consumer({ id = "L" }) })
        local r2 = run(n2, 1, { VG = { fuel = "gasoline", amount = 5 } }, { L = { kw = 1 } })
        T.eq(r2.report.fuelUsed.VG.owner, "native")
    end)
    R.entries.machine.test_native_gen = nil
    T.ok(ok, tostring(err))
end)

T.case("energy: auto-start generator uses hysteresis and a minimum run time", function()
    local d = Battery.def("battery_bank")
    local leak = d.selfDischargePerHour * d.capacityKWh
    local function cycle(policy, hours)
        local net = star({
            Gen.producer({ id = "GEN", def = "generator_diesel_6kw", mode = "auto", policy = policy }),
            Battery.new({ id = "B1", def = "battery_bank", e = 2.0 }),
            Dispatch.consumer({ id = "L", priority = 1 }),
        })
        local r = run(net, hours, { GEN = { fuel = "diesel", amount = 500 } }, { L = { kw = 1 } })
        local runs, offs, last, lastKind = {}, {}, nil, nil
        for _, e in ipairs(r.report.events) do
            if e.id == "GEN" then
                T.ok(e.kind ~= lastKind, "starts and stops alternate")
                if e.kind == "generator_start" then
                    T.eq(e.reason, "reserve_low")
                    if last then offs[#offs + 1] = e.t - last end
                else
                    T.eq(e.reason, "reserve_restored")
                    runs[#runs + 1] = e.t - last
                end
                last, lastKind = e.t, e.kind
            end
        end
        conserved(r.report, "hysteresis")
        return r, runs, offs
    end
    local r, runs, offs = cycle({ startBelow = 0.3, stopAbove = 0.9, minRunHours = 2 }, 100)
    local chargeTime = 0.6 * d.capacityKWh / (d.maxChargeKW * d.etaCharge - leak)
    local drainTime = 0.6 * d.capacityKWh / (1 / d.etaDischarge + leak)
    T.ok(#runs >= 15 and #runs <= 25, "bounded number of cycles: " .. #runs)
    for i, h in ipairs(runs) do close(h, chargeTime, "run " .. i .. " ends at stopAbove", 1e-7) end
    for i, h in ipairs(offs) do close(h, drainTime, "pause " .. i .. " ends at startBelow", 1e-7) end
    local soc = r.network.batteries.B1.e / d.capacityKWh
    T.ok(soc >= 0.3 - 1e-9 and soc <= 0.9 + 1e-9, "state of charge stays in the band")
    -- Minimum run time dominates a narrow band: every run lasts exactly 4 h.
    local _, runs2 = cycle({ startBelow = 0.3, stopAbove = 0.5, minRunHours = 4 }, 60)
    T.ok(#runs2 >= 3, "several runs")
    for i, h in ipairs(runs2) do close(h, 4, "run " .. i .. " honours the minimum run time", 1e-7) end
end)

T.case("energy: auto-start without storage follows unmet demand and stages generators", function()
    local net = star({
        Gen.producer({ id = "G1", def = "generator_flex_5kw", mode = "auto" }),
        Gen.producer({ id = "G2", def = "generator_flex_5kw", mode = "auto" }),
        Gen.producer({ id = "PV", def = "solar_array" }),
        Dispatch.consumer({ id = "L", priority = 1 }),
    })
    local ps = { G1 = { fuel = "gasoline", amount = 20 }, G2 = { fuel = "ethanol", amount = 20 }, PV = { kw = 1 } }
    local r = run(net, 3, ps, { L = { kw = 4 } })
    T.eq(r.network.producers.G1.running, true, "first generator covers the deficit")
    T.eq(r.network.producers.G2.running, false, "second is not needed")
    T.eq(r.report.events[1].reason, "deficit")
    T.near(r.report.totals.unmetKWh, 0, 1e-9)
    local quiet = run(r.network, 6, consumeFuel(ps, r.report), { L = { kw = 0.5 } })
    T.eq(quiet.network.producers.G1.running, false, "stops once no longer needed after its minimum run")
    T.eq(quiet.network.producers.G1.stopReason, "reserve_restored")
    T.ok(r.report.fuelUsed.G2 == nil, "an idle generator burns nothing")
    conserved(r.report, "staging")
end)

------------------------------------------------------------------------------
-- Exactness and conservation
------------------------------------------------------------------------------

T.case("energy: one long dispatch equals randomly split dispatches", function()
    local rng = TLG.Rng.new(TEST_SEED + 5)
    for trial = 1, 16 do
        local net, ps, demand = scenario(rng)
        local horizonH = rng:range(2, 96)
        local whole = run(net, horizonH, ps, demand)
        local cur, fuel, rep, t = net, ps, nil, 0
        local pieces = 0
        while t < horizonH do
            local nt = math.min(horizonH, t + rng:range(0.001, horizonH / 3))
            local r = run(cur, nt, fuel, demand)
            fuel = consumeFuel(fuel, r.report)
            if rep == nil then rep = r.report else rep = Dispatch.merge(rep, r.report) end
            cur, t, pieces = r.network, nt, pieces + 1
        end
        sameNetwork(whole.network, cur, "trial " .. trial)
        sameReport(whole.report, rep, "trial " .. trial)
        conserved(whole.report, "trial " .. trial)
    end
end)

T.case("energy: piecewise-constant input sequences are split-invariant", function()
    local rng = TLG.Rng.new(TEST_SEED + 6)
    for trial = 1, 6 do
        local net = scenario(rng)
        local segments = {}
        local t = 0
        for i = 1, 6 do
            local _, ps, demand = scenario(rng)
            t = t + rng:range(0.5, 20)
            segments[i] = { t1 = t, ps = ps, demand = demand }
        end
        -- Fuel is owned by the caller: each segment offers its own refill.
        local coarse, fine = net, net
        local repC, repF = nil, nil
        for _, seg in ipairs(segments) do
            local rc = run(coarse, seg.t1, seg.ps, seg.demand)
            if repC == nil then repC = rc.report else repC = Dispatch.merge(repC, rc.report) end
            coarse = rc.network
            local fuel, tt = seg.ps, fine.t
            while tt < seg.t1 do
                local nt = math.min(seg.t1, tt + rng:range(0.01, 6))
                local rf = run(fine, nt, fuel, seg.demand)
                fuel = consumeFuel(fuel, rf.report)
                if repF == nil then repF = rf.report else repF = Dispatch.merge(repF, rf.report) end
                fine, tt = rf.network, nt
            end
        end
        sameNetwork(coarse, fine, "sequence " .. trial)
        sameReport(repC, repF, "sequence " .. trial)
        conserved(repC, "sequence " .. trial)
    end
end)

T.case("energy: grid-stepped advance with weather-driven solar and wind is split-invariant", function()
    local rng = TLG.Rng.new(TEST_SEED + 7)
    local function weather(step)
        return { cloud = 0.5 + 0.5 * math.sin(step.day * 1.7 + step.hourOfDay / 5), windMS = 7 + 6 * math.sin(step.mid / 7) }
    end
    local function demand(step)
        local evening = step.hourOfDay >= 18 and step.hourOfDay < 23
        return { L1 = { kw = evening and 1.2 or 0.4 }, H1 = { kw = 2 }, V = { kw = 0.3 } }
    end
    for trial = 1, 4 do
        local net = star({
            Gen.producer({ id = "PV", def = "solar_array", exposure = 0.9 }),
            Gen.producer({ id = "WT", def = "wind_turbine_small" }),
            Gen.producer({ id = "GEN", def = "generator_gas_chp", mode = "auto",
                policy = { startBelow = 0.2, stopAbove = 0.8, minRunHours = 1.5 } }),
            Battery.new({ id = "B1", def = "battery_bank", e = rng:range(0.5, 3.9) }),
            Dispatch.consumer({ id = "L1", priority = 1 }),
            Dispatch.consumer({ id = "V", uncontrolled = true }),
            Dispatch.consumer({ id = "H1", heat = true }),
        }, nil, rng:range(0, 30))
        local toT = net.t + rng:range(24, 120)
        local ctx = { weather = weather, demand = demand, fuel = { GEN = { fuel = "propane", amount = rng:range(1, 10) } } }
        local whole = ES.advance(net, toT, ctx)
        T.ok(whole.ok, tostring(whole.reason))
        local cur, fuel, rep = net, ctx.fuel, nil
        while cur.t < toT do
            local nt = math.min(toT, cur.t + rng:range(0.05, 30))
            local r = ES.advance(cur, nt, { weather = weather, demand = demand, fuel = fuel })
            T.ok(r.ok, tostring(r.reason))
            if rep == nil then rep = r.report else rep = Dispatch.merge(rep, r.report) end
            cur, fuel = r.network, r.fuel
        end
        sameNetwork(whole.network, cur, "advance " .. trial)
        sameReport(whole.report, rep, "advance " .. trial)
        close(whole.fuel.GEN.amount, fuel.GEN.amount, "remaining fuel " .. trial)
        conserved(whole.report, "advance " .. trial)
        T.ok(whole.report.totals.renewableKWh > 0, "renewables produced")
    end
end)

T.case("energy: energy is conserved across random networks", function()
    local rng = TLG.Rng.new(TEST_SEED + 8)
    for trial = 1, 40 do
        local net, ps, demand = scenario(rng)
        local r = run(net, rng:range(0.1, 200), ps, demand)
        conserved(r.report, "random " .. trial)
        local t = r.report.totals
        T.ok(t.heatKWh <= t.recoveredHeatKWh + 1e-9, "heat delivered never exceeds heat recovered")
        T.ok(t.curtailedKWh >= -1e-9 and t.lossesKWh >= -1e-9 and t.unmetKWh >= -1e-9, "non-negative categories")
        for _, id in ipairs(Tables.sortedKeys(r.network.batteries)) do
            local b = r.network.batteries[id]
            local cap = Battery.capacity(b)
            T.ok(b.e >= 0 and b.e <= cap, "battery " .. id .. " within capacity")
        end
        if r.report.fuelUsed.GEN then T.le(r.report.fuelUsed.GEN.amount, ps.GEN.amount + 1e-12, "fuel bounded") end
    end
end)

------------------------------------------------------------------------------
-- Topology
------------------------------------------------------------------------------

T.case("energy: loops and duplicate edges never count a source twice", function()
    local nodes = {
        Dispatch.junction("J1"), Dispatch.junction("J2"), Dispatch.junction("J3"),
        Gen.producer({ id = "PV1", def = "solar_array" }), Gen.producer({ id = "PV2", def = "solar_array" }),
        Battery.new({ id = "B1", def = "battery_bank", e = 3.9 }),
        Dispatch.consumer({ id = "L1" }),
        Gen.producer({ id = "PV1", def = "solar_array" }),   -- identical duplicate node: deduped
    }
    local edges = {
        { "J1", "J2" }, { "J2", "J3" }, { "J3", "J1" },           -- loop
        { "PV1", "J1" }, { "PV1", "J2" }, { "J1", "PV1" },        -- two paths and a duplicate
        { "PV2", "J3" }, { "J2", "J2" }, { a = "B1", b = "J3" }, { "L1", "J1" },
    }
    local g = Dispatch.graph(nodes, edges)
    T.ok(g.ok, tostring(g.reason))
    local comp = Dispatch.component(g.graph, "L1")
    T.eq(table.concat(comp, ","), "B1,J1,J2,J3,L1,PV1,PV2")
    local net = Dispatch.network(g.graph, { "L1", "PV1", "PV1", "J2", "J1", "J3", "PV2", "B1" }, 0).network
    T.eq(Tables.count(net.producers), 2, "each producer once")
    local r = run(net, 1, { PV1 = { kw = 1 }, PV2 = { kw = 0.5 } }, { L1 = { kw = 0.2 } })
    close(r.report.totals.renewableKWh, 1.5, "available energy counted once")
    conserved(r.report, "loop")
    T.eq(Dispatch.graph({ Gen.producer({ id = "X", def = "solar_array" }), Gen.producer({ id = "X", def = "solar_panel" }) }, {}).reason,
        "duplicate_node")
    T.eq(Dispatch.graph({ Dispatch.junction("A") }, { { "A", "Z" } }).reason, "unknown_node")
end)

T.case("energy: only affected components are rebuilt after a topology change", function()
    local g = Dispatch.graph({
        Dispatch.junction("J1"), Gen.producer({ id = "PV1", def = "solar_panel" }), Dispatch.consumer({ id = "L1" }),
        Dispatch.junction("J2"), Gen.producer({ id = "PV2", def = "solar_panel" }), Dispatch.consumer({ id = "L2" }),
        Dispatch.consumer({ id = "L3" }),
    }, { { "J1", "PV1" }, { "J1", "L1" }, { "J2", "PV2" }, { "J2", "L2" } }).graph
    local before = Tables.deepCopy(g)
    T.eq(#Dispatch.components(g), 3)
    local c = Dispatch.connect(g, "J1", "L3")
    T.eq(#c.affected, 1)
    T.eq(table.concat(c.affected[1], ","), "J1,L1,L3,PV1", "merged component only")
    local d = Dispatch.disconnect(c.graph, "J1", "PV1")
    T.eq(#d.affected, 2)
    T.eq(table.concat(d.affected[1], ","), "J1,L1,L3")
    T.eq(table.concat(d.affected[2], ","), "PV1")
    local rm = Dispatch.removeNode(g, "J2")
    T.eq(#rm.affected, 2, "former neighbours of the removed junction")
    T.eq(table.concat(rm.affected[1], ","), "L2")
    T.eq(table.concat(rm.affected[2], ","), "PV2")
    local add = Dispatch.addNode(g, Dispatch.junction("J9"))
    T.eq(table.concat(add.affected[1], ","), "J9")
    T.ok(Tables.deepEqual(g, before, 0), "the original graph is unchanged")
    T.eq(table.concat(Dispatch.component(g, "J1"), ","), "J1,L1,PV1")
    -- Device state survives a rebuild through Dispatch.store.
    local net = Dispatch.network(c.graph, c.affected[1], 0).network
    local stored = Dispatch.store(c.graph, run(net, 2, { PV1 = { kw = 0.1 } }, { L1 = { kw = 0.05 } }).network)
    T.ok(Tables.deepEqual(stored.adj, c.graph.adj, 0), "store keeps the topology")
end)

------------------------------------------------------------------------------
-- Malformed input and purity
------------------------------------------------------------------------------

T.case("energy: malformed input is rejected with a reason", function()
    local net = star({
        Gen.producer({ id = "PV", def = "solar_array" }),
        Gen.producer({ id = "GEN", def = "generator_gas_chp", mode = "on" }),
        Battery.new({ id = "B1", def = "battery_bank", e = 1 }),
        Dispatch.consumer({ id = "L" }),
        Dispatch.consumer({ id = "C", def = "battery_charger" }),
    })
    local nan, inf = 0 / 0, math.huge
    local function reason(ps, demand, interval)
        return ES.dispatch(net, interval or { t0 = 0, t1 = 1 }, ps or {}, demand or {}).reason
    end
    T.eq(reason({ PV = { kw = -1 } }), "invalid_power")
    T.eq(reason({ PV = { kw = nan } }), "invalid_power")
    T.eq(reason({ PV = { kw = inf } }), "invalid_power")
    T.eq(reason({ PV = { kw = 2 } }), "over_rating")
    T.eq(reason({ PV = 5 }), "invalid_producer_state")
    T.eq(reason({ NOPE = { kw = 1 } }), "unknown_producer")
    T.eq(reason({ [7] = { kw = 1 } }), "unknown_producer")
    T.eq(reason(nil, { NOPE = { kw = 1 } }), "unknown_consumer")
    T.eq(reason(nil, { L = { kw = -0.5 } }), "invalid_demand")
    T.eq(reason(nil, { L = { kw = nan } }), "invalid_demand")
    T.eq(reason(nil, { L = { kw = 1, minKW = 2 } }), "invalid_demand")
    T.eq(reason(nil, { C = { kw = 5 } }), "over_rating")
    T.eq(reason({ GEN = { fuel = "plutonium", amount = 1 } }), "unknown_fuel")
    T.eq(reason({ GEN = { fuel = "water", amount = 1 } }), "unknown_fuel")
    T.eq(reason({ GEN = { fuel = "diesel", amount = 1 } }), "incompatible_fuel")
    T.eq(reason({ GEN = { fuel = "propane", amount = -1 } }), "invalid_fuel_amount")
    T.eq(reason({ GEN = { fuel = "propane", amount = nan } }), "invalid_fuel_amount")
    T.eq(reason({ GEN = { fuel = "propane", amount = 1, powerFactor = 1.5 } }), "invalid_power_factor")
    T.eq(reason({ GEN = { fuel = "propane", amount = 1, energyMJ = 0 } }), "invalid_energy")
    T.eq(reason(nil, nil, { t0 = 0, t1 = -1 }), "clock_regression")
    T.eq(reason(nil, nil, { t0 = 5, t1 = 6 }), "time_mismatch")
    T.eq(reason(nil, nil, { t0 = 0, t1 = nan }), "invalid_interval")
    T.eq(ES.dispatch(net, { t0 = 0, t1 = 1 }, "x", {}).reason, "invalid_producer_state")
    local broken = Tables.deepCopy(net)
    broken.batteries.B1.e = 10
    T.eq(ES.dispatch(broken, { t0 = 0, t1 = 1 }, {}, {}).reason, "invalid_battery")
    broken = Tables.deepCopy(net)
    broken.batteries.B1.def = "nope"
    T.eq(ES.dispatch(broken, { t0 = 0, t1 = 1 }, {}, {}).reason, "unknown_battery_def")
    broken = Tables.deepCopy(net)
    broken.producers.GEN.policy = { startBelow = 0.8, stopAbove = 0.5 }
    T.eq(ES.dispatch(broken, { t0 = 0, t1 = 1 }, {}, {}).reason, "invalid_policy")
    broken = Tables.deepCopy(net)
    broken.producers.GEN.mode = "sometimes"
    T.eq(ES.dispatch(broken, { t0 = 0, t1 = 1 }, {}, {}).reason, "invalid_mode")
    broken = Tables.deepCopy(net)
    broken.producers.PV.cond = nan
    T.eq(ES.dispatch(broken, { t0 = 0, t1 = 1 }, {}, {}).reason, "invalid_producer")
    T.eq(Battery.run(Battery.new({ id = "B", def = "battery_bank" }), nan, 0, 1).reason, "invalid_power")
    T.eq(Battery.run(Battery.new({ id = "B", def = "battery_bank" }), 1, 1, 1).reason, "charge_and_discharge")
    T.eq(Battery.run(Battery.new({ id = "B", def = "nope" }), 1, 0, 1).reason, "unknown_battery_def")
    T.eq(Dispatch.allocate(-1, {}).reason, "invalid_power")
    T.eq(Dispatch.allocate(1, { { id = "a", kw = nan } }).reason, "invalid_demand")
    T.eq(Dispatch.graph({ { id = "x", kind = "reactor" } }, {}).reason, "invalid_node")
    T.eq(Dispatch.network({ nodes = {} }, { "ghost" }, 0).reason, "unknown_node")
    T.eq(ES.advance(net, -1, {}).reason, "clock_regression")
    T.eq(ES.advance(net, 1, { stepHours = 0 }).reason, "invalid_step")
    T.eq(ES.advance(net, 1, { fuel = { NOPE = { fuel = "propane", amount = 1 } } }).reason, "unknown_producer")
    T.eq(ES.advance(net, 1, { weather = { cloud = nan } }).reason, "invalid_weather")
end)

T.case("energy: inputs are never mutated", function()
    local rng = TLG.Rng.new(TEST_SEED + 9)
    local net, ps, demand = scenario(rng)
    local a, b, c = Tables.deepCopy(net), Tables.deepCopy(ps), Tables.deepCopy(demand)
    local r = run(net, 30, ps, demand)
    T.ok(Tables.deepEqual(net, a, 0) and Tables.deepEqual(ps, b, 0) and Tables.deepEqual(demand, c, 0), "dispatch inputs unchanged")
    T.ok(r.network ~= net and r.network.batteries ~= net.batteries, "a new network is returned")
    local merged = Dispatch.merge(r.report, run(r.network, 40, ps, demand).report)
    T.ok(merged.consumers.L1 ~= r.report.consumers.L1, "merge builds new records")
    local bat = Battery.new({ id = "B", def = "battery_bank", e = 2 })
    local before = Tables.deepCopy(bat)
    Battery.run(bat, 1, 0, 3)
    Battery.withCondition(bat, 0.5)
    T.ok(Tables.deepEqual(bat, before, 0), "battery record unchanged")
    local ctx = { fuel = { GEN = { fuel = "propane", amount = 3 } }, weather = { cloud = 0.2, windMS = 6 } }
    local ctxCopy = Tables.deepCopy(ctx)
    T.ok(ES.advance(net, 12, ctx).ok)
    T.ok(Tables.deepEqual(ctx, ctxCopy, 0), "advance context unchanged")
end)
