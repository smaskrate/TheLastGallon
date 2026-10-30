require "support/fixtures"
require "TLG/Domain/Automation"
local A = TLG.Domain.Automation

local rule = {
    id = "keep-transport-ethanol", recipe = "ethanol_ferment", machineId = "F1",
    reserve = { target = 40, low = 20 },
    inputs = { sugar_eq = { perBatch = 20, protect = 40 }, water = { perBatch = 100, protect = 0 } },
    yieldPerBatch = 10, minBatchFraction = 0.5,
}

T.case("automation: refills the reserve while preserving the protected food stock", function()
    local p = A.plan(rule, { reserve = 5, stocks = { sugar_eq = 70, water = 500 }, machine = { state = "Ready" } })
    T.eq(p.action, "start")
    T.near(p.batch.sugar_eq, 20, 1e-12, "one batch, not more")
    local tight = A.plan(rule, { reserve = 5, stocks = { sugar_eq = 52, water = 500 }, machine = { state = "Ready" } })
    T.eq(tight.action, "start")
    T.near(tight.batch.sugar_eq, 12, 1e-12, "only the unprotected 12 kg")
    local blocked = A.plan(rule, { reserve = 5, stocks = { sugar_eq = 45, water = 500 }, machine = { state = "Ready" } })
    T.eq(blocked.action, "wait"); T.eq(blocked.reason, "protected_sugar_eq")
    T.eq(blocked.notify[1], "low_sugar_eq")
end)

T.case("automation: no action when the reserve is fine or the machine is busy", function()
    T.eq(A.plan(rule, { reserve = 25, stocks = { sugar_eq = 100, water = 500 }, machine = { state = "Ready" } }).reason, "reserve_ok")
    T.eq(A.plan(rule, { reserve = 0, stocks = { sugar_eq = 100, water = 500 }, machine = { state = "Processing" } }).reason, "busy")
    local paused = A.plan(rule, { reserve = 0, stocks = {}, machine = { state = "Paused", pause = "no_heat" } })
    T.eq(paused.action, "wait"); T.eq(paused.reason, "no_heat", "concrete pause reason surfaces")
end)

T.case("automation: full output waits instead of re-emitting", function()
    local p = A.plan(rule, { reserve = 0, stocks = {}, machine = { state = "OutputReady" }, outputRoom = 0 })
    T.eq(p.action, "wait"); T.eq(p.reason, "output_full"); T.eq(p.notify[1], "output_full")
    T.eq(A.plan(rule, { reserve = 0, stocks = {}, machine = { state = "OutputReady" }, outputRoom = 10 }).action, "collect")
end)

T.case("automation: queue is bounded and idempotent across retries", function()
    local q = A.newQueue()
    for i = 1, A.MAX_QUEUE do
        local r = A.enqueue(q, { id = "b" .. i, recipe = "ethanol_ferment" })
        T.ok(r.ok); q = r.queue
    end
    T.eq(A.enqueue(q, { id = "b99" }).reason, "queue_full")
    T.ok(A.enqueue(q, { id = "b3" }).duplicate, "retry after reconnect does not enqueue twice")
    local head
    head, q = A.pop(q)
    T.eq(head.id, "b1"); T.eq(#q.entries, A.MAX_QUEUE - 1)
    T.ok(A.enqueue(q, { id = "b1" }).duplicate, "a consumed id stays consumed")
    T.eq(A.enqueue(q, { recipe = "x" }).reason, "malformed")
end)

T.case("automation: generator auto-start uses hysteresis and a minimum run time", function()
    local policy = { startBelow = 0.3, stopAbove = 0.9, minRunHours = 2 }
    T.eq(A.generatorDecision(policy, { running = false }, 0.5, 0), "keep")
    T.eq(A.generatorDecision(policy, { running = false }, 0.25, 0), "start")
    T.eq(A.generatorDecision(policy, { running = true, startedAt = 10 }, 0.95, 11), "keep", "min run time")
    T.eq(A.generatorDecision(policy, { running = true, startedAt = 10 }, 0.95, 12.5), "stop")
    T.eq(A.generatorDecision(policy, { running = true, startedAt = 10 }, 0.6, 20), "keep", "no oscillation inside the band")
end)
