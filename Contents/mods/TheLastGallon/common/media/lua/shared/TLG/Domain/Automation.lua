-- Automation (spec §13): bounded batch queues and reserve-keeping rules.
--
-- A rule watches a reserve (e.g. transport ethanol), a machine and the stocks
-- it may draw on. Planning is a pure function of the observed state: it
-- returns at most one action per machine per evaluation, never reserves more
-- than one batch, and never touches protected quantities (e.g. keep 40 kg of
-- food). Queue entries carry ids so a retry after reconnect cannot enqueue or
-- consume twice. Paused machines always report a concrete reason.
require "TLG/Util/Tables"
require "TLG/Util/Num"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Automation = TLG.Domain.Automation or {}
local A = TLG.Domain.Automation
local Tables, Num = TLG.Tables, TLG.Num

A.MAX_QUEUE = 8

-- Queue -------------------------------------------------------------------
function A.newQueue()
    return { entries = {}, seen = {} }
end

-- Adds a batch request; duplicates (same id) and overflow are rejected.
function A.enqueue(queue, entry)
    if type(entry) ~= "table" or type(entry.id) ~= "string" then return { ok = false, reason = "malformed" } end
    if queue.seen[entry.id] then return { ok = true, duplicate = true } end
    if #queue.entries >= A.MAX_QUEUE then return { ok = false, reason = "queue_full" } end
    local q = Tables.deepCopy(queue)
    q.entries[#q.entries + 1] = Tables.deepCopy(entry)
    q.seen[entry.id] = true
    return { ok = true, queue = q }
end

-- Removes and returns the head entry (when the machine accepted it).
function A.pop(queue)
    if #queue.entries == 0 then return nil, queue end
    local q = Tables.deepCopy(queue)
    local head = table.remove(q.entries, 1)
    return head, q
end

-- Rules -------------------------------------------------------------------
-- rule = {
--   id, recipe, machineId,
--   reserve = { target = litres, low = litres }     -- refill below `low` up to `target`
--   inputs  = { stockId = { perBatch = qty, protect = qty } }
--   yieldPerBatch = litres of reserve product per batch (planning estimate)
--   minBatchFraction = 0..1 (smallest batch worth starting, default 0.5)
-- }
-- observed = {
--   reserve = litres now, stocks = { stockId = qty }, machine = { state, pause },
--   outputRoom = litres that can receive output
-- }
-- Returns { action = "start" | "collect" | "wait" | "none", batch = { stock = qty },
--           reason = code, notify = { codes } }.
function A.plan(rule, observed)
    local out = { action = "none", notify = {} }
    local m = observed.machine or {}
    if m.state == "OutputReady" then
        if (observed.outputRoom or 0) <= 0 then
            out.action, out.reason = "wait", "output_full"
            out.notify[#out.notify + 1] = "output_full"
        else
            out.action = "collect"
        end
        return out
    end
    if m.state == "Paused" then
        out.action, out.reason = "wait", m.pause or "paused"
        return out
    end
    if m.state ~= "Ready" then
        out.action, out.reason = "wait", "busy"
        return out
    end
    local reserve = observed.reserve or 0
    if reserve >= rule.reserve.low then
        out.reason = "reserve_ok"
        return out
    end
    local wanted = rule.reserve.target - reserve
    local fraction = math.min(1, wanted / math.max(1e-9, rule.yieldPerBatch))
    -- Limit by every input's usable (unprotected) stock.
    for _, id in ipairs(Tables.sortedKeys(rule.inputs)) do
        local inp = rule.inputs[id]
        local usable = math.max(0, (observed.stocks[id] or 0) - (inp.protect or 0))
        if usable < inp.perBatch * (rule.minBatchFraction or 0.5) then
            out.action, out.reason = "wait", "protected_" .. id
            out.notify[#out.notify + 1] = "low_" .. id
            return out
        end
        fraction = math.min(fraction, usable / inp.perBatch)
    end
    if fraction < (rule.minBatchFraction or 0.5) then
        fraction = rule.minBatchFraction or 0.5
    end
    out.action = "start"
    out.batch = {}
    for _, id in ipairs(Tables.sortedKeys(rule.inputs)) do
        out.batch[id] = rule.inputs[id].perBatch * Num.clamp(fraction, 0, 1)
    end
    out.reason = "refill_reserve"
    return out
end

-- Generator auto-start with hysteresis and minimum run time.
-- policy = { startBelow, stopAbove, minRunHours }  (state of charge 0..1)
-- state  = { running, startedAt }
function A.generatorDecision(policy, state, soc, now)
    if state.running then
        local ranLongEnough = (now - (state.startedAt or now)) >= (policy.minRunHours or 0)
        if soc >= policy.stopAbove and ranLongEnough then return "stop" end
        return "keep"
    end
    if soc <= policy.startBelow then return "start" end
    return "keep"
end

return A
