-- Authoritative mutations (spec §14). Runs on the server, or locally in
-- single-player. Clients only send requests; nothing here trusts a
-- client-reported quality, amount, elapsed time or completion.
--
-- Endpoints are supplied by adapters through ctx.resolve(ref, ctx):
--   endpoint.key              stable key (reservations)
--   endpoint:canAccess(actor) -> ok, reason   (proximity, ownership)
--   endpoint:read()           -> committed supply record (reconciled with native)
--   endpoint:write(record, change) -> ok, reason   (commit; may move native quantity)
--   endpoint.consumer         optional ConsumerProfile id fed by this endpoint
--
-- Procedure for a transfer request:
--   1 validate request, actor, references and access
--   2 advance both participants to the common authoritative time
--   3 check expected revisions          4 check compatibility
--   5 bound the quantity (source, reservations, room, request)
--   6 compute deltas (same function as UI previews)
--   7 commit both                         8 increment revisions
--   9 return and remember the authoritative result (idempotent retries)
require "TLG/Domain/Fuel/Aging"
require "TLG/Domain/Fuel/Mixing"
require "TLG/Domain/Consumers"
require "TLG/Authority/Ledger"
require "TLG/Authority/Reservations"

TLG.Authority = TLG.Authority or {}
TLG.Authority.Transactions = TLG.Authority.Transactions or {}
local Tx = TLG.Authority.Transactions
local D = TLG.Domain
local Supply, Mixing, Aging, Num = D.Supply, D.Mixing, D.Aging, TLG.Num

Tx.MAX_REQUEST_AMOUNT = 100000

local function reject(reason, extra)
    local r = { ok = false, reason = reason }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

local function summary(rec)
    return { id = rec.id, rev = rec.rev, total = Supply.total(rec), t = rec.t }
end

-- Shared request validation; returns nil when valid, else a rejection.
function Tx.validateRequest(req, fields)
    if type(req) ~= "table" then return reject("malformed") end
    if type(req.requestId) ~= "string" or #req.requestId == 0 or #req.requestId > 64 then
        return reject("malformed_request_id")
    end
    for _, f in ipairs(fields or {}) do
        if type(req[f]) ~= "table" then return reject("malformed_" .. f) end
    end
    if req.amount ~= nil then
        if not Num.isFinite(req.amount) or req.amount <= 0 or req.amount > Tx.MAX_REQUEST_AMOUNT then
            return reject("invalid_amount")
        end
    end
    return nil
end

local function open(ctx, ref, actor, which)
    local ep, why = ctx.resolve(ref, ctx)
    if ep == nil then return nil, reject("unknown_" .. which, { detail = why }) end
    -- Access is checked against the live player object when the transport
    -- supplies one; the ledger and reservations use the stable actor key.
    local ok, reason = ep:canAccess(ctx.player or actor)
    if not ok then return nil, reject("no_access_" .. which, { detail = reason }) end
    return ep
end

-- Advances a committed record to `now`; returns the advanced record.
function Tx.advance(ctx, rec)
    local out = Aging.advance(rec, ctx.now, ctx.env)
    return out
end

function Tx.transfer(ctx, actor, req)
    local bad = Tx.validateRequest(req, { "source", "destination" })
    if bad then return bad end
    if req.amount == nil then return reject("invalid_amount") end
    local seen = ctx.ledger:lookup(actor, req.requestId)
    if seen then
        local copy = TLG.Tables.deepCopy(seen)
        copy.duplicate = true
        return copy
    end
    local srcEp, e1 = open(ctx, req.source, actor, "source")
    if not srcEp then return e1 end
    local dstEp, e2 = open(ctx, req.destination, actor, "destination")
    if not dstEp then return e2 end
    if srcEp.key == dstEp.key then return reject("same_supply") end

    local src = Tx.advance(ctx, srcEp:read())
    local dst = Tx.advance(ctx, dstEp:read())
    if req.expectedSourceRevision ~= nil and req.expectedSourceRevision ~= src.rev then
        return reject("stale", { source = summary(src), destination = summary(dst) })
    end
    if req.expectedDestinationRevision ~= nil and req.expectedDestinationRevision ~= dst.rev then
        return reject("stale", { source = summary(src), destination = summary(dst) })
    end

    local reservedByOthers = ctx.reservations:reserved(srcEp.key, actor)
    local available = math.max(0, Supply.total(src) - reservedByOthers)
    local amount = math.min(req.amount, available)
    if amount <= Num.DUST then
        return reject(reservedByOthers > 0 and "reserved_by_other" or "source_empty")
    end

    local preview = Mixing.previewTransfer(src, dst, amount)
    if not preview.ok then return reject(preview.reason) end
    if preview.moved <= 0 then return reject(preview.reason or "nothing_moved") end

    local evaluation
    if dstEp.consumer then
        evaluation = D.Consumers.evaluate(dstEp.consumer, preview.dst, { ambientC = ctx.ambientC })
        if not evaluation.compatible and not req.experimental then
            return reject("incompatible", { evaluation = evaluation })
        end
    end

    local newSrc, newDst = preview.src, preview.dst
    newSrc.rev = src.rev + 1
    newDst.rev = dst.rev + 1
    local ok, why = srcEp:write(newSrc, { kind = "transfer_out", amount = preview.moved, parcel = preview.parcel })
    if not ok then return reject("commit_failed_source", { detail = why }) end
    ok, why = dstEp:write(newDst, { kind = "transfer_in", amount = preview.moved, parcel = preview.parcel })
    if not ok then
        -- Restore the source so nothing is lost if the destination refused.
        srcEp:write(src, { kind = "rollback" })
        return reject("commit_failed_destination", { detail = why })
    end
    local response = {
        ok = true,
        requestId = req.requestId,
        moved = preview.moved,
        source = summary(newSrc),
        destination = summary(newDst),
        evaluation = evaluation,
        experimental = req.experimental and true or nil,
    }
    ctx.ledger:record(actor, req.requestId, response)
    return response
end

-- Reconciles a record with a native observation the adapter made
-- (D-006). observed = { total = number, comp = optional { id = qty } }.
-- baseline = { deg = number, mic = number } for unknown inflow.
-- Changes are measured against `rec` as written, never against an advanced
-- record (aging moves fuel to water, which native fluids never show), and
-- decreases leave from it. at = { now = hour, env = Climate } (optional):
-- the record is advanced to `at.now` before the inflow mixes in, so fuel
-- found then carries the baseline of that moment and is not aged again over
-- the time it went unseen (RT-SP run 54). Without `at` it mixes in at rec.t.
function Tx.reconcile(rec, observed, baseline, primary, at)
    local out = Supply.copy(rec)
    local info = { removed = 0, added = 0 }
    local inflow = {}
    if observed.comp then
        for _, id in ipairs(TLG.Tables.sortedKeys(observed.comp)) do
            local want = observed.comp[id]
            local have = out.q[id] or 0
            if want > have + 1e-6 then inflow[#inflow + 1] = { id = id, n = want - have } end
        end
        for _, id in ipairs(TLG.Tables.sortedKeys(out.q)) do
            local want = observed.comp[id] or 0
            if out.q[id] > want + 1e-6 then
                info.removed = info.removed + (out.q[id] - want)
                out.q[id] = want
            end
        end
        Supply.normalize(out)
    else
        local have = Supply.total(out)
        if observed.total < have - 1e-6 then
            out = Mixing.removeProportional(out, have - observed.total)
            info.removed = have - observed.total
        elseif observed.total > have + 1e-6 then
            inflow[1] = { id = primary or Supply.primary(out) or "gasoline", n = observed.total - have }
        end
    end
    if at and #inflow > 0 then out = Aging.advance(out, at.now, at.env) end
    for _, p in ipairs(inflow) do
        out = Mixing.addUntracked(out, p.id, p.n, baseline)
        info.added = info.added + p.n
    end
    return out, info
end

return Tx
