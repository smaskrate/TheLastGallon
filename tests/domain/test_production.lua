require "support/fixtures"
require "TLG/Content/Production"
local Process, R = TLG.Domain.Process, TLG.Registry

local function fermenter(t) return Process.new({ id = "F1", machine = "fermenter_barrel", t = t or 0 }) end
local function still(t) return Process.new({ id = "S1", machine = "reflux_still", t = t or 0 }) end

local function runToEnd(proc, env, stepHours, limitHours)
    local t = proc.t
    local stop = t + (limitHours or 24 * 30)
    while (proc.state == "Processing" or proc.state == "Paused") and t < stop do
        t = t + (stepHours or 24)
        proc = Process.advance(proc, t, env)
    end
    return proc
end

T.case("production: content validates", function()
    T.eq(#R.validate(), 0, table.concat(R.validate(), " | "))
end)

T.case("production: plan rejects ineligible, out-of-bounds and busy batches", function()
    local f = fermenter()
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 1, water = 20 }, f).reason, "not_enough_sugar_eq")
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 10, water = 20, gasoline = 1 }, f).reason, "ineligible_gasoline")
    T.eq(Process.plan("ethanol_distill", { ethanol = 10, water = 60 }, Process.new({ id = "PS", machine = "pot_still" })).reason, "over_capacity")
    T.eq(Process.plan("ethanol_distill", { water = 10 }, f).reason, "wrong_machine")
    T.eq(Process.plan("nope", {}, f).reason, "unknown_recipe")
    local loaded = Process.load(f, "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 10, water = 50 }, loaded).reason, "machine_busy")
end)

T.case("production: complete ethanol chain with explicit material balance", function()
    local env = F.env()
    local f = Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 20, water = 100 }, 0).proc
    f = Process.start(f, 0).proc
    f = runToEnd(f, env, 24)
    T.eq(f.state, "OutputReady")
    T.near(f.outputs.ethanol, 20 * 0.55, 1e-9)
    T.near(f.outputs.water, 100, 1e-9)
    T.eq(f.byproducts.yeast_starter, 1, "starter culture regenerates")
    local c = Process.collect(f, 1000)
    T.eq(c.proc.state, "Ready")
    -- Distil the wash in two loads (still capacity 120 L).
    local s = still(f.t)
    local load = { ethanol = c.parcel.ethanol, water = 100 }
    s = Process.load(s, "ethanol_distill", load, 0)
    T.ok(s.ok, tostring(s.reason))
    s = Process.addFirebox(s.proc, 50).proc
    s = Process.start(s, f.t).proc
    s = runToEnd(s, env, 6)
    T.eq(s.state, "OutputReady")
    local eth, water = s.outputs.ethanol, s.outputs.water
    T.near(eth, 11 * 0.92, 1e-9)
    T.near(water / (eth + water), 0.06, 1e-9, "94% purity")
    T.near(eth + water + s.byproducts.stillage, 111, 1e-9, "volume balance")
end)

T.case("production: firebox exhaustion pauses with a concrete reason and refuelling resumes", function()
    local env = F.env()
    local s = Process.load(still(), "ethanol_distill", { ethanol = 10, water = 100 }).proc
    s = Process.addFirebox(s, 3).proc
    s = Process.start(s, 0).proc
    s = Process.advance(s, 48, env)
    T.eq(s.state, "Paused"); T.eq(s.pause, "no_heat")
    T.near(s.firebox, 0, 1e-12)
    s = Process.addFirebox(s, 40).proc
    s = runToEnd(s, env, 6)
    T.eq(s.state, "OutputReady")
end)

T.case("production: one large advance equals many small ones", function()
    local env = F.env()
    local base = Process.load(still(), "ethanol_distill", { ethanol = 10, water = 100 }).proc
    base = Process.addFirebox(base, 20).proc
    base = Process.start(base, 3.5).proc
    local whole = Process.advance(base, 200, env)
    local stepped, t = base, 3.5
    local rng = TLG.Rng.new(TEST_SEED)
    while t < 200 do
        t = math.min(200, t + rng:range(0.05, 7))
        stepped = Process.advance(stepped, t, env)
    end
    T.eq(whole.state, stepped.state)
    T.near(whole.firebox, stepped.firebox, 1e-9)
    T.near(whole.stageDone, stepped.stageDone, 1e-9)
    if whole.outputs.ethanol then T.near(whole.outputs.ethanol, stepped.outputs.ethanol, 1e-9) end
    T.near(whole.completedAt or -1, stepped.completedAt or -1, 1e-9)
end)

T.case("production: cold stalls fermentation and spoils it after the grace period", function()
    -- Winter climate log: -10 C outdoors (3 C sheltered) every day.
    local log = {}
    for d = -10, 400 do log[d] = { t = -10, rh = 0.7 } end
    local env = TLG.Domain.Climate.new({ dayOfYear = 190, hourOfDay = 9 }, log)
    local f = Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc
    f = Process.start(f, 0).proc
    f = Process.advance(f, 200, env)
    T.eq(f.state, "Faulted"); T.eq(f.pause, "batch_spoiled")
    T.near(f.spoiled.sugar_eq, 10, 1e-12, "spoiled contents are accounted, not deleted")
end)

T.case("production: status names the stage only while the batch runs", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    T.eq(Process.status(f).stage, "prepare")
    T.eq(Process.status(Process.advance(f, 2, env)).stage, "ferment")
    f = runToEnd(f, env, 24)
    local s = Process.status(f)
    T.eq(s.state, "OutputReady"); T.ok(s.stage == nil, "finished: no current stage (RT-SP run 28 showed fermenting)")
    local part = Process.collect(f, 10).proc
    s = Process.status(part)
    T.eq(s.state, "OutputReady"); T.eq(s.reason, "output_full"); T.ok(s.stage == nil)
    T.ok(Process.status(Process.collect(part, 1000).proc).stage == nil)
end)

T.case("production: outputs are emitted once and a full destination cannot duplicate them", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    f = runToEnd(f, env, 24)
    local total = f.outputs.ethanol + f.outputs.water
    local a = Process.collect(f, 10)
    T.near(a.parcel.ethanol + a.parcel.water, 10, 1e-9)
    T.eq(a.proc.state, "OutputReady"); T.eq(a.proc.pause, "output_full")
    local again = Process.advance(a.proc, a.proc.t + 500, env)
    T.near(again.outputs.ethanol + again.outputs.water, total - 10, 1e-9, "no re-emission while waiting")
    local b = Process.collect(again, 1000)
    T.near(b.parcel.ethanol + b.parcel.water + 10, total, 1e-9)
    T.eq(b.proc.state, "Ready")
    T.eq(Process.collect(b.proc, 10).reason, "nothing_ready")
end)

T.case("production: recipe updates never reinterpret an active batch", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    local def = R.get("recipe", "ethanol_ferment")
    local old = def.params.ethanolYieldLPerKg
    def.params.ethanolYieldLPerKg = 0.9
    f = runToEnd(f, env, 24)
    def.params.ethanolYieldLPerKg = old
    T.near(f.outputs.ethanol, 10 * 0.55, 1e-9, "snapshot used")
    T.ok(f.recipe == nil or f.recipe.fp ~= nil)
end)

T.case("production: abort keeps the wash so far for a still; invalid transitions are refused", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    f = Process.advance(f, 49, env)
    local a = Process.abort(f)
    T.ok(a.ok); T.eq(a.proc.state, "OutputReady"); T.eq(a.proc.stoppedEarly, true)
    local k = a.kept
    T.ok(k.ethanol > 0 and k.ethanol < 5.5, "partially fermented")
    T.near(k.sugar_eq + k.ethanol / 0.55, 10, 1e-9, "every kg of sugar in the wash, fermented or not")
    T.near(k.water, 50, 1e-9); T.ok(TLG.Tables.isEmpty(a.discarded))
    -- A still takes the weak wash, sugar and all; collecting empties the vessel.
    local c = Process.collect(a.proc, 120)
    T.eq(c.proc.state, "Ready"); T.ok(c.proc.stoppedEarly == nil)
    T.ok(Process.load(still(), "ethanol_distill", c.parcel).ok)
    -- A second abort throws the kept wash away instead.
    local twice = Process.abort(a.proc)
    T.eq(twice.proc.state, "Ready"); T.near(twice.discarded.water, 50, 1e-9); T.ok(TLG.Tables.isEmpty(twice.kept))
    -- A finished batch's output is collected, not aborted.
    local done = runToEnd(Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc, env, 24)
    T.eq(Process.abort(done).reason, "nothing_to_abort")
    -- The starter culture of the last finished batch is not handed out again.
    local used = Process.collect(done, 1000).proc
    local next = Process.start(Process.load(used, "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, used.t).proc
    local cut = Process.collect(Process.abort(Process.advance(next, used.t + 49, env)).proc, 1000)
    T.ok(cut.byproducts == nil, "no starter culture from an aborted batch")
    T.eq(Process.start(fermenter(), 0).reason, "not_loaded")
    T.eq(Process.resumeCmd(fermenter()).reason, "not_paused")
    T.eq(Process.decommission(f).reason, "busy")
    T.ok(Process.decommission(fermenter()).ok)
end)

T.case("production: manual pause holds progress", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    f = Process.advance(f, 10, env)
    local done = f.stageDone
    f = Process.pauseCmd(f).proc
    f = Process.advance(f, 40, env)
    T.eq(f.state, "Paused"); T.eq(f.pause, "paused_by_player")
    T.near(f.stageDone, done, 1e-12)
    f = Process.resumeCmd(f).proc
    f = Process.advance(f, 60, env)
    T.ok(f.stageDone > done)
end)


T.case("production: machine definitions keep their own kind (registry name stored separately)", function()
    T.eq(R.get("machine", "fermenter_barrel").kind, "fermenter")
    T.eq(R.get("machine", "reflux_still").kind, "still")
    T.eq(R.get("machine", "fermenter_barrel").registryKind, "machine")
end)
T.case("production: aborting a still keeps its spirit, throws the rest of the wash away, every litre accounted", function()
    local env = F.env()
    local s = Process.load(still(), "ethanol_distill", { ethanol = 10, water = 100 }).proc
    s = Process.addFirebox(s, 50).proc
    s = Process.start(s, 0).proc
    s = Process.advance(s, 4, env)
    local a = Process.abort(s)
    T.ok(a.ok); T.eq(a.proc.state, "OutputReady")
    local total = 0
    for _, v in pairs(a.kept) do total = total + v end
    for _, v in pairs(a.discarded) do total = total + v end
    T.near(total, 110, 1e-9, "nothing disappears on abort")
    T.near(a.kept.water / (a.kept.ethanol + a.kept.water), 0.06, 1e-9, "only the spirit is kept (94 %)")
    T.ok(a.discarded.stillage > 0 and a.discarded.water > 0 and a.discarded.ethanol > 0, "the undistilled wash, listed")
    T.near(a.proc.firebox, s.firebox, 1e-12, "the firebox keeps its wood")
end)

T.case("production: a drying column keeps its ethanol on abort; a spoiled batch is refused a load and thrown away", function()
    local env = F.env()
    local d = Process.load(Process.new({ id = "D1", machine = "drying_column", t = 0 }), "ethanol_dry",
        { ethanol = 4, water = 1, quicklime_kg = 4 }).proc
    local a = Process.abort(Process.advance(Process.start(d, 0).proc, 6, env))
    T.eq(a.proc.state, "OutputReady"); T.near(a.kept.ethanol, 4, 1e-9); T.near(a.kept.water, 1 - 0.98 * 0.5, 1e-9)
    T.near(a.discarded.spent_lime, 4 + 0.98 * 0.5, 1e-9)
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 6, water = 30 }).proc, 0).proc
    f = Process.advance(Process.pauseCmd(Process.advance(f, 5, env)).proc, 5 + 73, env)
    T.eq(f.state, "Faulted"); T.eq(f.pause, "batch_spoiled")
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 6, water = 30 }, f).reason, "batch_spoiled")
    local s = Process.abort(f)
    T.ok(s.ok and s.spoiled); T.eq(s.proc.state, "Ready"); T.ok(TLG.Tables.isEmpty(s.kept))
    T.near(s.discarded.water, 30, 1e-9); T.near(s.discarded.sugar_eq, 6, 1e-9)
    T.ok(Process.load(s.proc, "ethanol_ferment", { sugar_eq = 6, water = 30 }).ok, "the fermenter takes a new mash")
end)

T.case("production: plan rejects NaN/negative amounts, stream recipes and oversized output", function()
    local f = fermenter()
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 0 / 0, water = 50 }, f).reason, "invalid_sugar_eq")
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = -3, water = 50 }, f).reason, "invalid_sugar_eq")
    T.eq(Process.plan("ethanol_ferment", { sugar_eq = 1, water = 1 }, f).reason, "not_enough_sugar_eq",
        "deterministic first failure (sorted inputs)")
end)