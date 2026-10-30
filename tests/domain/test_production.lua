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

T.case("production: abort returns the partial result; invalid transitions are refused", function()
    local env = F.env()
    local f = Process.start(Process.load(fermenter(), "ethanol_ferment", { sugar_eq = 10, water = 50 }).proc, 0).proc
    f = Process.advance(f, 49, env)
    local a = Process.abort(f)
    T.ok(a.ok); T.eq(a.proc.state, "Ready")
    T.ok(a.returned.ethanol > 0 and a.returned.ethanol < 5.5, "partially fermented")
    T.ok(a.returned.sugar_eq > 0, "unfermented sugar returned")
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

