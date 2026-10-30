require "support/fixtures"
require "TLG/Authority/Transactions"
local Tx, Ledger, Reservations = TLG.Authority.Transactions, TLG.Authority.Ledger, TLG.Authority.Reservations
local Supply = TLG.Domain.Supply

local function world()
    local W = { records = {}, access = {}, failWrite = {}, writes = 0 }
    W.ctx = { now = 100, env = F.env(), ledger = Ledger.new(8), reservations = Reservations.new() }
    W.ctx.resolve = function(ref)
        if type(ref.id) ~= "string" or W.records[ref.id] == nil then return nil, "missing" end
        local ep = { key = ref.id, consumer = ref.consumer }
        function ep:canAccess() if W.access[ref.id] == false then return false, "too_far" end return true end
        function ep:read() return W.records[ref.id] end
        function ep:write(r)
            if W.failWrite[ref.id] then return false, "refused" end
            W.records[ref.id] = r
            W.writes = W.writes + 1
            return true
        end
        return ep
    end
    function W.add(id, o)
        o.id = id
        o.storage = o.storage or "jerrycan_steel"
        o.t = o.t or 100
        W.records[id] = F.supply(o)
        return W.records[id]
    end
    return W
end

local function req(id, src, dst, amount, extra)
    local r = { requestId = id, source = { id = src }, destination = { id = dst }, amount = amount }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

T.case("authority: transfer commits, bumps revisions and returns authoritative totals", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 }, deg = { gasoline = 1 } })
    W.add("B", { q = {} })
    local r = Tx.transfer(W.ctx, "p1", req("r1", "A", "B", 4))
    T.ok(r.ok, tostring(r.reason))
    T.near(r.moved, 4, 1e-12)
    T.eq(r.source.rev, 1); T.eq(r.destination.rev, 1)
    T.near(Supply.total(W.records.A), 6, 1e-12)
    T.near(W.records.B.deg.gasoline, 1, 1e-6)
end)

T.case("authority: duplicate request ids never repeat the operation", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 } }); W.add("B", { q = {} })
    local first = Tx.transfer(W.ctx, "p1", req("r1", "A", "B", 3))
    local again = Tx.transfer(W.ctx, "p1", req("r1", "A", "B", 3))
    T.ok(again.ok and again.duplicate, "duplicate flagged")
    T.near(Supply.total(W.records.B), 3, 1e-12, "moved once")
    T.eq(again.destination.rev, first.destination.rev)
    -- Same id from another actor is a different request.
    T.ok(Tx.transfer(W.ctx, "p2", req("r1", "A", "B", 3)).duplicate == nil)
end)

T.case("authority: stale revisions are rejected without mutation", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 } }); W.add("B", { q = {} })
    Tx.transfer(W.ctx, "p1", req("r1", "A", "B", 1))
    local r = Tx.transfer(W.ctx, "p2", req("r2", "A", "B", 5, { expectedSourceRevision = 0 }))
    T.eq(r.reason, "stale")
    T.eq(r.source.rev, 1, "reply carries current revision for UI refresh")
    T.near(Supply.total(W.records.A), 9, 1e-12)
end)

T.case("authority: malformed, unknown and inaccessible requests are rejected", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 } }); W.add("B", { q = {} })
    T.eq(Tx.transfer(W.ctx, "p", { source = { id = "A" }, destination = { id = "B" }, amount = 1 }).reason, "malformed_request_id")
    T.eq(Tx.transfer(W.ctx, "p", req("x1", "A", "B", 0 / 0)).reason, "invalid_amount")
    T.eq(Tx.transfer(W.ctx, "p", req("x2", "A", "B", -2)).reason, "invalid_amount")
    T.eq(Tx.transfer(W.ctx, "p", req("x3", "A", "B", 1e9)).reason, "invalid_amount")
    T.eq(Tx.transfer(W.ctx, "p", req("x4", "NOPE", "B", 1)).reason, "unknown_source")
    T.eq(Tx.transfer(W.ctx, "p", { requestId = "x5", source = "A", destination = { id = "B" }, amount = 1 }).reason, "malformed_source")
    W.access.B = false
    T.eq(Tx.transfer(W.ctx, "p", req("x6", "A", "B", 1)).reason, "no_access_destination")
    T.eq(W.writes, 0, "nothing committed")
end)

T.case("authority: spoofed quantities are bounded by the real source", function()
    local W = world()
    W.add("A", { q = { gasoline = 2.5 } }); W.add("B", { q = {} })
    local r = Tx.transfer(W.ctx, "p", req("s1", "A", "B", 99999))
    T.near(r.moved, 2.5, 1e-12)
end)

T.case("authority: simultaneous withdrawals cannot overdraw", function()
    local W = world()
    W.add("SRC", { q = { gasoline = 10 }, storage = "drum_steel", cap = 200 })
    W.add("C1", { q = {} }); W.add("C2", { q = {} })
    local a = Tx.transfer(W.ctx, "p1", req("a", "SRC", "C1", 8))
    local b = Tx.transfer(W.ctx, "p2", req("b", "SRC", "C2", 8))
    T.near(a.moved + b.moved, 10, 1e-12)
    T.near(Supply.total(W.records.SRC), 0, 1e-12)
    T.eq(Tx.transfer(W.ctx, "p3", req("c", "SRC", "C2", 1)).reason, "source_empty")
end)

T.case("authority: reservations protect long actions from other players", function()
    local W = world()
    W.add("SRC", { q = { gasoline = 10 }, storage = "drum_steel", cap = 200 })
    W.add("C1", { q = {} })
    W.ctx.reservations:create("SRC", "p1", 6, W.ctx.now, 2)
    local other = Tx.transfer(W.ctx, "p2", req("o", "SRC", "C1", 8))
    T.near(other.moved, 4, 1e-12, "only unreserved quantity")
    local owner = Tx.transfer(W.ctx, "p1", req("w", "SRC", "C1", 6))
    T.near(owner.moved, 6, 1e-12, "owner can use its reservation")
    W.ctx.reservations:expire(W.ctx.now + 5)
    T.eq(W.ctx.reservations:reserved("SRC"), 0, "expired")
end)

T.case("authority: incompatible pours need an explicit experimental request", function()
    local W = world()
    W.add("ETH", { q = { ethanol = 10 }, deg = { ethanol = 0 } })
    W.add("TANK", { q = { gasoline = 5 }, storage = "vehicle_tank", cap = 50 })
    local r = Tx.transfer(W.ctx, "p", { requestId = "e1", source = { id = "ETH" },
        destination = { id = "TANK", consumer = "engine_si_stock" }, amount = 10 })
    T.eq(r.reason, "incompatible")
    T.ok(r.evaluation and not r.evaluation.compatible)
    T.near(Supply.total(W.records.TANK), 5, 1e-12)
    local r2 = Tx.transfer(W.ctx, "p", { requestId = "e2", source = { id = "ETH" },
        destination = { id = "TANK", consumer = "engine_si_stock" }, amount = 10, experimental = true })
    T.ok(r2.ok and r2.experimental)
end)

T.case("authority: participants are advanced to the common authoritative time", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 }, t = 0, deg = { gasoline = 0 } })
    W.add("B", { q = {}, t = 50 })
    W.ctx.now = 24 * 30
    local r = Tx.transfer(W.ctx, "p", req("t1", "A", "B", 5))
    T.ok(r.ok)
    T.eq(W.records.A.t, 24 * 30); T.eq(W.records.B.t, 24 * 30)
    T.ok(W.records.B.deg.gasoline > 0, "aged before moving")
end)

T.case("authority: a refused destination write rolls the source back", function()
    local W = world()
    W.add("A", { q = { gasoline = 10 } }); W.add("B", { q = {} })
    W.failWrite.B = true
    local r = Tx.transfer(W.ctx, "p", req("f1", "A", "B", 4))
    T.eq(r.reason, "commit_failed_destination")
    T.near(Supply.total(W.records.A), 10, 1e-12, "restored")
    T.eq(W.ctx.ledger:lookup("p", "f1"), nil, "failed request not remembered")
end)

T.case("authority: ledger is bounded", function()
    local L = Ledger.new(3)
    for i = 1, 5 do L:record("p", "r" .. i, { i = i }) end
    T.eq(L:lookup("p", "r1"), nil); T.eq(L:lookup("p", "r5").i, 5)
end)

T.case("authority: reconciliation never creates fresh fuel from unknown changes", function()
    local rec = F.supply({ id = "V", storage = "vehicle_tank", cap = 50, q = { gasoline = 30, ethanol = 3 },
        deg = { gasoline = 0.4, ethanol = 0.1 } })
    local down, info = Tx.reconcile(rec, { total = 22 }, { deg = 2.5 })
    T.near(info.removed, 11, 1e-9)
    T.near(Supply.fraction(down, "ethanol"), 3 / 33, 1e-9, "proportional draw keeps composition")
    local up, info2 = Tx.reconcile(rec, { total = 43 }, { deg = 2.5 }, "gasoline")
    T.near(info2.added, 10, 1e-9)
    T.near(up.deg.gasoline, (30 * 0.4 + 10 * 2.5) / 40, 1e-9, "unknown inflow at pessimistic baseline")
    local items = Tx.reconcile(rec, { comp = { gasoline = 20, ethanol = 5 } }, { deg = 3 })
    T.near(items.q.gasoline, 20, 1e-9); T.near(items.q.ethanol, 5, 1e-9)
    T.near(items.deg.ethanol, (3 * 0.1 + 2 * 3) / 5, 1e-9)
end)
