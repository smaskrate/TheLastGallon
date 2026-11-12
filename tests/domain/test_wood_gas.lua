require "support/fixtures"
require "TLG/Domain/GasFeed"
require "TLG/Domain/Consumers"
local F, Gas, Tables, Consumers, R = TLG.Domain.GasFeed, TLG.Domain.Gas, TLG.Tables, TLG.Domain.Consumers, TLG.Registry
local Gasifier = Gas.Gasifier

-- Nm3 of wood gas per litre of petrol: 32 MJ / 5 MJ (Content/Fuels.lua).
local NM3_PER_L = 32 / 5

local function lit(load, t)
    local st = Gasifier.new({ id = "W1", machine = "gasifier_stationary", t = t or 0 })
    local l = Gasifier.load(st, load, t or 0)
    T.ok(l.ok, "load: " .. tostring(l.reason))
    local s = Gasifier.start(l.st, t or 0)
    T.ok(s.ok, "start: " .. tostring(s.reason))
    return s.st
end

local function sum(t)
    local n = 0
    for _, v in pairs(t or {}) do n = n + v end
    return n
end

T.case("wood gas: a feed adds the gas energy for energy, never past the cap", function()
    T.near(F.nm3For("woodgas", 1), NM3_PER_L, 1e-12)
    local rec = F.new({ id = "GS-W1", t = 0 })
    local r = F.feed(rec, 0, 0.0161, "woodgas", 5, 2)
    T.near(r.taken, 0.0161 * NM3_PER_L, 1e-12, "as much as the room holds")
    T.near(r.fuel, 0.0161, 1e-12)
    T.near(r.rec.buf.woodgas, r.taken, 1e-12)
    T.eq(r.rec.fuel, r.fuel)
    T.eq(r.rec.t, 2)
    local short = F.feed(rec, 0, 0.0161, "woodgas", 0.05, 2)
    T.near(short.taken, 0.05, 1e-12, "no more than is given")
    T.near(short.fuel, 0.05 / NM3_PER_L, 1e-12)
    T.near(F.litresOf(short.rec.buf), short.fuel, 1e-12)
    T.eq(F.feed(r.rec, r.fuel, 0.0161, "woodgas", 1, 3).taken, 0, "no room")
    T.ok(rawequal(F.feed(r.rec, r.fuel, 0.0161, "woodgas", 1, 3).rec, r.rec), "the record is returned untouched")
    T.eq(F.feed(rec, 0, 1, "woodgas", 0, 3).taken, 0, "nothing given")
end)

T.case("wood gas: the litres a step leaves above the margin still read as gas", function()
    T.ok(F.MARGIN > F.TOLERANCE, "the margin is above the tolerance litres are compared with")
    local step = 0.015
    local r = F.feed(F.new({ id = "GS-W2" }), 0, step + F.MARGIN, "woodgas", 10, 0)
    T.ok(F.holdsGas(r.rec, r.fuel))
    T.ok(F.holdsGas(r.rec, r.fuel - step), "after the hour's step")
    local e = Consumers.evaluate("generator_gas", F.supply(r.rec, r.fuel - step), {})
    T.ok(e.compatible, table.concat(e.reasons, ","))
    -- The wood-gas derate lowers an engine's power only: a generator's
    -- start (the gate rolls against startFactor) and its wear are as on
    -- propane (D-040).
    T.eq(e.grade, "good")
    T.eq(e.startFactor, 1)
    T.eq(e.wearFactor, 1)
    T.near(e.powerFactor, 0.6, 1e-12)
    -- With the fuel setting at 0 the step is 0 and the cap is the margin
    -- alone, which a refill still fills.
    local zero = F.feed(F.new({ id = "GS-W3" }), 0, F.MARGIN, "woodgas", 10, 0)
    T.near(zero.fuel, F.MARGIN, 1e-12)
    T.ok(F.holdsGas(zero.rec, zero.fuel))
end)

T.case("wood gas: a mixed buffer burns in proportion and feeds on top", function()
    local rec = { v = 1, id = "GS-W4", buf = { propane = 0.0005 }, fuel = 0.0005 * 93 / 32, t = 0 }
    local r = F.feed(rec, rec.fuel, rec.fuel + 0.01, "woodgas", 1, 1)
    T.near(r.rec.buf.propane, 0.0005, 1e-12, "the propane left stays")
    T.near(r.rec.buf.woodgas, 0.01 * NM3_PER_L, 1e-12)
    T.near(F.litresOf(r.rec.buf), r.fuel, 1e-12)
end)

T.case("wood gas: a draw takes from the gasifier's buffer and resumes one paused full", function()
    local m = R.need("machine", "gasifier_stationary")
    local st = Gasifier.advance(lit({ firewood = 100 }), 2, 0)
    T.eq(st.state, "Paused")
    T.eq(st.pause, "buffer_full", "warmed, its buffer full, nothing drawing")
    T.near(st.buffer, m.bufferNm3, 1e-9)
    local d = Gasifier.draw(st, 0.096, 2)
    T.ok(d.ok)
    T.near(d.taken, 0.096, 1e-12)
    T.near(d.st.buffer, m.bufferNm3 - 0.096, 1e-9)
    T.eq(d.st.state, "Processing", "its buffer is no longer full")
    T.eq(d.st.idle, 0)
    T.near(d.st.totals.delivered, st.totals.delivered + 0.096, 1e-12)
    T.eq(st.state, "Paused", "the state given is not changed")
    -- It makes the gas again at its full rate, then waits.
    local back = Gasifier.advance(d.st, 2.1, 0)
    T.eq(back.pause, "buffer_full")
    T.near(back.buffer, m.bufferNm3, 1e-9)
    T.near(back.totals.fed - st.totals.fed, 0.096 / 2.2, 1e-9, "the wood the drawn gas cost")
    local all = Gasifier.draw(st, 50, 2)
    T.near(all.taken, m.bufferNm3, 1e-9, "no more than the buffer holds")
    T.eq(all.st.buffer, 0)
    T.eq(Gasifier.draw(st, 1, 2.5).reason, "time_mismatch")
    T.eq(Gasifier.draw(st, -1, 2).reason, "invalid_amount")
    T.eq(Gasifier.draw(st, 0 / 0, 2).reason, "invalid_amount")
end)

T.case("wood gas: no draw while warming; a hot gasifier paused for another reason keeps its gas", function()
    local warming = lit({ firewood = 100 })
    local d = Gasifier.draw(warming, 1, 0)
    T.eq(d.taken, 0)
    T.ok(rawequal(d.st, warming))
    -- 2 kg burn in the warm-up; the last 0.5 kg make 1.1 Nm3, less than
    -- the buffer holds.
    local dry = Gasifier.advance(lit({ firewood = 2.5 }), 0.6, 0)
    T.eq(dry.state, "Paused")
    T.eq(dry.pause, "hopper_empty")
    T.ok(dry.buffer > 0, "the gas made before the hopper ran out")
    local got = Gasifier.draw(dry, 0.1, 0.6)
    T.near(got.taken, math.min(0.1, dry.buffer), 1e-12)
    T.eq(got.st.pause, "hopper_empty", "still waiting for wood")
end)

T.case("wood gas: Put out puts the fire out at once and keeps the hopper", function()
    local st = Gasifier.advance(lit({ firewood = 100 }), 2, 0)
    local p = Gasifier.putOut(st, 2)
    T.ok(p.ok)
    T.eq(p.st.state, "Ready")
    T.eq(p.st.buffer, 0)
    T.eq(p.st.warm, 0)
    T.eq(p.st.snap, nil)
    T.near(p.vented, st.buffer, 1e-12)
    T.near(p.st.totals.vented, st.totals.vented + st.buffer, 1e-12)
    T.near(Gasifier.status(p.st).hopperKg, Gasifier.status(st).hopperKg, 1e-12, "the wood stays in the hopper")
    T.eq(Gasifier.putOut(p.st, 2).reason, "not_lit")
    T.eq(Gasifier.putOut(st, 3).reason, "time_mismatch")
    T.ok(Gasifier.putOut(lit({ firewood = 10 }), 0).ok, "while warming too")
    T.ok(Gasifier.start(p.st, 2).ok, "lit again, from cold")
    T.eq(Gasifier.start(p.st, 2).st.mode, "warming")
end)

-- A generator's hours on wood gas as the adapter runs them: in each hour's
-- first minute the refill draws the room up to that hour's step and the
-- margin from the gasifier, brought to that moment with no other draw; the
-- game burns the step at the hour's end.
local function hours(st, rec, fuel, steps, t0)
    local short, stopped = 0, false
    for i, step in ipairs(steps) do
        local cap = step + F.MARGIN
        st = Gasifier.advance(st, t0 + i - 1 + 1 / 60, 0)
        local d = Gasifier.draw(st, F.nm3For("woodgas", cap - fuel), st.t)
        st = d.st
        local f = F.feed(rec, fuel, cap, "woodgas", d.taken, st.t)
        rec, fuel = f.rec, f.fuel
        if fuel < cap - 1e-9 then short = short + 1 end
        fuel = fuel - step
        if fuel <= 0 then fuel, stopped = 0, true end
    end
    return st, rec, fuel, short, stopped
end

T.case("wood gas: hourly draws keep the gasifier lit and the generator fed, and every Nm3 is accounted for", function()
    local st0 = Gasifier.advance(lit({ firewood = 100 }), 1, 0)
    local steps = {}
    for i = 1, 48 do steps[i] = (i % 5 == 0) and 0.035 or 0.015 end
    local st, r, fuel, short, stopped = hours(st0, F.new({ id = "GS-W5" }), 0, steps, 1)
    T.eq(short, 0, "every hour's refill found its gas")
    T.ok(not stopped, "no step emptied the generator")
    T.near(fuel, F.MARGIN, 1e-12, "the margin is left after the last step")
    T.ok(st.state == "Processing" or st.pause == "buffer_full", "still lit: " .. tostring(st.state) .. "/" .. tostring(st.pause))
    local burned = 0
    for _, s in ipairs(steps) do burned = burned + s end
    T.near(st.totals.delivered, F.nm3For("woodgas", burned + F.MARGIN), 1e-9,
        "what the gasifier gave is what burned and the margin left")
    T.near(F.litresOf(F.current(r, fuel)), fuel, 1e-12)
    -- Gas ledger: fed wood x yield = flared + delivered + its own buffer + vented.
    T.near(st.totals.fed * 2.2, st.totals.flared + st.totals.delivered + st.buffer + st.totals.vented, 1e-9)
    -- Nobody draws: it goes out its hold after the last draw, and the gas
    -- in its buffer is let out.
    local cold = Gasifier.advance(st, st.t + 3.01, 0)
    T.eq(cold.state, "Ready")
    T.eq(cold.buffer, 0)
    T.ok(Gasifier.advance(st, st.t + 2.9, 0).state ~= "Ready", "not before its hold")
end)

T.case("wood gas: lumps and a steady draw cost the same wood for the same gas", function()
    local m = R.need("machine", "gasifier_stationary")
    local start = Gasifier.advance(lit({ firewood = 100 }), 1, 0)
    -- Steady: the domain's throttled regime at 0.096 Nm3/h for 40 hours.
    local steady = Gasifier.advance(start, 41, 0.096)
    -- Lumps: 0.096 Nm3 drawn once an hour for 40 hours.
    local lumps = start
    for i = 1, 40 do
        lumps = Gasifier.advance(lumps, 1 + i, 0)
        lumps = Gasifier.draw(lumps, 0.096, lumps.t).st
    end
    lumps = Gasifier.advance(lumps, 41.5, 0)
    T.near(steady.totals.delivered, 40 * 0.096, 1e-9)
    T.near(lumps.totals.delivered, 40 * 0.096, 1e-9)
    T.near(lumps.buffer, m.bufferNm3, 1e-9)
    T.near(steady.buffer, m.bufferNm3, 1e-9)
    T.near(steady.totals.fed, lumps.totals.fed, 1e-9, "the same wood")
    T.near(lumps.totals.fed - start.totals.fed, 40 * 0.096 / 2.2, 1e-9)
end)
