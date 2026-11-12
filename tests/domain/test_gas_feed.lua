require "support/fixtures"
require "TLG/Domain/GasFeed"
require "TLG/Domain/Consumers"
local F, Gas, Tables, Consumers = TLG.Domain.GasFeed, TLG.Domain.Gas, TLG.Tables, TLG.Domain.Consumers

-- Litres of petrol per Nm3 of propane: 93 MJ / 32 MJ (Content/Fuels.lua).
local L_PER_NM3 = 93 / 32

local function connected(uses)
    local r = F.connect(F.new({ id = "GS-1", t = 0 }), uses, 0)
    assert(r.ok, tostring(r.reason))
    return r.rec
end

T.case("gas feed: energy for energy, a full tank is about 13 litres", function()
    T.near(F.litresOf({ propane = Gas.TANK_NM3 }), 4.48 * L_PER_NM3, 1e-9)
    T.near(F.litresOf({ propane = Gas.TANK_NM3 }), 13.02, 0.01)
    T.near(F.propaneLitres(1), L_PER_NM3, 1e-12)
    T.eq(F.litresOf({}), 0)
end)

T.case("gas feed: a refill tops the buffer up with whole uses from the tank", function()
    local r = F.refill(connected(5000), 0, 10, 1)
    T.ok(r.ok)
    -- 10 L is 3.44086 Nm3, 3840.25 uses: 3840 whole uses go in.
    T.eq(r.moved, 3840)
    T.eq(r.rec.tank.uses, 5000 - 3840)
    T.near(r.rec.buf.propane, 3840 * Gas.NM3_PER_USE, 1e-12)
    T.near(r.fuel, 3840 * Gas.NM3_PER_USE * L_PER_NM3, 1e-9)
    T.ok(r.fuel <= 10 and 10 - r.fuel < Gas.NM3_PER_USE * L_PER_NM3, "less than one use below the cap")
    T.eq(r.rec.fuel, r.fuel)
    T.eq(r.rec.t, 1)
end)

T.case("gas feed: no refill without room, a tank or a use's worth of room", function()
    local full = F.refill(connected(5000), 0, 10, 0).rec
    local again = F.refill(full, full.fuel, 10, 2)
    T.eq(again.moved, 0)
    T.ok(rawequal(again.rec, full), "the record is returned untouched")
    T.eq(F.refill(F.new({ id = "GS-2" }), 0, 10, 0).moved, 0, "no tank")
    local small = F.refill(full, 10 - Gas.NM3_PER_USE * L_PER_NM3 * 0.5, 10, 0)
    T.eq(small.moved, 0, "half a use of room")
    local last = F.refill(connected(3), 0, 10, 0)
    T.eq(last.moved, 3, "the tank's last uses")
    T.eq(last.rec.tank.uses, 0)
    T.eq(F.refill(last.rec, 0, 10, 0).moved, 0, "an empty tank gives nothing")
end)

T.case("gas feed: the game burns the mix in proportion", function()
    local rec = { v = 1, id = "GS-3", buf = { propane = 2, woodgas = 1 }, fuel = 6, t = 0 }
    local cur = F.current(rec, 3)
    T.near(cur.propane, 1, 1e-12)
    T.near(cur.woodgas, 0.5, 1e-12)
    T.ok(Tables.isEmpty(F.current(rec, 0)), "burned out")
    -- A rise the mod did not make is not gas.
    T.near(F.current(rec, 9).propane, 2, 1e-12)
end)

T.case("gas feed: connect refuses a second tank and an empty one, and changes nothing then", function()
    local rec = connected(10)
    local before = Tables.deepCopy(rec)
    T.eq(F.connect(rec, 500, 1).reason, "tank_connected")
    T.eq(F.connect(F.new({ id = "GS-4" }), 0, 1).reason, "tank_empty")
    T.eq(F.connect(F.new({ id = "GS-4" }), 0 / 0, 1).reason, "tank_empty")
    T.ok(Tables.deepEqual(rec, before), "a refused connect leaves the record as it was")
    T.eq(F.connect(F.new({ id = "GS-5" }), 6000, 1).rec.tank.uses, Gas.TANK_USES, "no more than a full tank")
    T.eq(F.disconnect(F.new({ id = "GS-6" }), 0, 1).reason, "no_tank")
end)

T.case("gas feed: a tank taken back at once is as full as it went in, less at most a use", function()
    local r = F.refill(connected(5000), 0, 10, 0)
    local d = F.disconnect(r.rec, r.fuel, 1)
    T.ok(d.ok)
    T.ok(d.uses == 5000 or d.uses == 4999, "uses back: " .. tostring(d.uses))
    T.eq(d.rec.tank, nil)
    T.ok(d.fuel >= 0 and d.fuel < Gas.NM3_PER_USE * L_PER_NM3, "less than a use stays in the buffer")
    T.near(F.litresOf(d.rec.buf), d.fuel, 1e-9)
    -- The tank never goes past full: what does not fit stays in the buffer.
    local nearlyFull = F.connect(F.new({ id = "GS-7" }), 4990, 0).rec
    nearlyFull.buf, nearlyFull.fuel = { propane = 100 * Gas.NM3_PER_USE }, F.propaneLitres(100 * Gas.NM3_PER_USE)
    local d2 = F.disconnect(nearlyFull, nearlyFull.fuel, 0)
    T.eq(d2.uses, Gas.TANK_USES)
    T.near(d2.rec.buf.propane, 90 * Gas.NM3_PER_USE, 1e-12)
end)

T.case("gas feed: no propane is made or lost over connect, steps, refills and removal", function()
    local start = 5000
    local rec = connected(start)
    local fuel, cap, burnedNm3 = 0, 10, 0
    local r = F.refill(rec, fuel, cap, 0)
    rec, fuel = r.rec, r.fuel
    -- Twenty hourly steps of different sizes, each followed by a refill.
    for i = 1, 20 do
        local step = 0.002 + 0.0137 * (i % 7)
        burnedNm3 = burnedNm3 + step / L_PER_NM3
        fuel = fuel - step
        r = F.refill(rec, fuel, cap, i)
        rec, fuel = r.rec, r.fuel
        T.near(F.litresOf(F.current(rec, fuel)), fuel, 1e-9, "the buffer's gas is its litres at hour " .. i)
    end
    local d = F.disconnect(rec, fuel, 21)
    local left = (d.rec.buf.propane or 0) + d.uses * Gas.NM3_PER_USE + burnedNm3
    T.near(left, start * Gas.NM3_PER_USE, 1e-9, "tank + buffer + burned = what was connected")
end)

T.case("gas feed: holding gas, venting, and the buffer read as propane", function()
    local r = F.refill(connected(100), 0, 10, 0)
    T.ok(F.holdsGas(r.rec, r.fuel))
    T.ok(not F.holdsGas(r.rec, 0), "burned out")
    T.ok(not F.holdsGas(F.new({ id = "GS-8" }), 3), "no gas given: liquid")
    T.ok(not F.holdsGas(nil, 3))
    local v = F.vent(r.rec, 5)
    T.ok(Tables.isEmpty(v.buf))
    T.eq(v.fuel, 0)
    T.eq(v.tank.uses, r.rec.tank.uses, "venting leaves the tank to whoever removes it")
    local e = Consumers.evaluate("generator_gas", F.supply(r.rec, r.fuel), {})
    T.ok(e.compatible, table.concat(e.reasons, ","))
    T.eq(e.grade, "good")
    T.eq(e.wearFactor, 1)
    T.eq(Consumers.evaluate("generator_gas", F.supply(F.new({ id = "GS-9" }), 0), {}).grade, "empty")
end)
