require "support/fixtures"
require "TLG/Persistence/Migrations"
local M, Supply = TLG.Persistence.Migrations, TLG.Domain.Supply

local function fixture(name)
    return loadstring(__TLG_SOURCES["fixtures/" .. name], name)()
end

T.case("migrations: v0 fixture upgrades deterministically and never rejuvenates", function()
    local raw = fixture("supply_v0")
    local a, status = M.upgrade("supply", raw)
    T.eq(status, "upgraded")
    T.eq(a.v, 1)
    T.near(a.q.gasoline, 14.5, 1e-12); T.near(a.q.water, 0.02, 1e-12)
    T.near(a.deg.gasoline, 1.5, 1e-12, "3000 h of recorded age kept as degradation")
    T.eq(a.comp, nil); T.eq(a.age, nil)
    local b = M.upgrade("supply", fixture("supply_v0"))
    T.ok(TLG.Tables.deepEqual(a, b, 0), "same input, same output")
    T.eq(raw.v, nil, "input not mutated")
end)

T.case("migrations: upgrading a current record is a no-op (repeatable)", function()
    local cur = M.upgrade("supply", fixture("supply_v0"))
    local again, status = M.upgrade("supply", cur)
    T.eq(status, "current")
    T.ok(TLG.Tables.deepEqual(again, cur, 0))
end)

T.case("migrations: future schemas are preserved and reported read-only", function()
    local future = { v = 99, id = "S1-1", q = { gasoline = 3 }, newField = { x = 1 } }
    local rec, status = M.upgrade("supply", future)
    T.eq(status, "future")
    T.ok(rec == future, "returned untouched")
    local side, why = M.sidecar("supply", future)
    T.eq(side, nil); T.eq(why, "future_schema")
end)

T.case("migrations: malformed versions are rejected", function()
    T.eq(select(2, M.upgrade("supply", { v = -1 })), "invalid")
    T.eq(select(2, M.upgrade("supply", { v = 0.5 })), "invalid")
    T.eq(select(2, M.upgrade("supply", "nope")), "invalid")
    T.eq(select(2, M.upgrade("unknown_kind", { v = 1 })), "invalid")
end)

T.case("migrations: an upgraded record is a valid supply after normalisation", function()
    local rec = M.upgrade("supply", fixture("supply_v0"))
    local s = F.supply({ storage = rec.storage, cap = 20, q = rec.q, deg = rec.deg, t = rec.t, cond = rec.cond })
    T.eq(#Supply.check(s), 0, table.concat(Supply.check(s), ","))
end)

T.case("catch-up: a two-year unloaded interval is bounded work and equals stepped advancement", function()
    local env = F.env()
    local s = F.supply({ storage = "drum_steel", cap = 200, q = { gasoline = 150, diesel = 30, water = 0.1 },
        deg = { gasoline = 0.2, diesel = 0.1 } })
    local segs = env:segments(0, 24 * 730, "sheltered")
    T.le(#segs, 732, "one segment per day")
    local whole = TLG.Domain.Aging.advance(s, 24 * 730, env)
    local stepped = s
    for d = 1, 730 do stepped = TLG.Domain.Aging.advance(stepped, d * 24, env) end
    F.assertSupplyClose(whole, stepped, 1e-9, "catch-up")
end)

T.case("migrations: process and project records have no pre-release format (v0 is invalid)", function()
    -- Machines and conversion projects were introduced at schema 1; a record
    -- without a version is not a known format and must be left alone.
    T.eq(select(2, M.upgrade("process", { state = "Ready" })), "invalid")
    T.eq(select(2, M.upgrade("project", { state = "InProgress" })), "invalid")
    T.eq(select(2, M.upgrade("project", { v = 2, state = "InProgress" })), "future")
end)