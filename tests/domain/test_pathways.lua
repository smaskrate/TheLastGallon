-- M6-M8 pathways: biodiesel, wood gas, biogas, propane and the route audit.
require "support/fixtures"
require "TLG/Domain/Routes"
local R, Gas, Supply, Mixing, Aging = TLG.Registry, TLG.Domain.Gas, TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Aging
local Process, Tables, Climate, Routes = TLG.Domain.Process, TLG.Tables, TLG.Domain.Climate, TLG.Domain.Routes
local Consumers, Gasifier = TLG.Domain.Consumers, TLG.Domain.Gas.Gasifier
local Biogas, Propane = TLG.Content.Biogas, TLG.Content.Propane

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function rho(id)
    local f = R.need("fuel", id)
    if f.phase == "solid" then return 1 end
    return f.density
end

local function massOf(t)
    local s = 0
    for _, id in ipairs(Tables.sortedKeys(t or {})) do s = s + t[id] * rho(id) end
    return s
end

local function sum(t)
    local s = 0
    for _, k in ipairs(Tables.sortedKeys(t or {})) do s = s + t[k] end
    return s
end

-- inputs + props.external = outputs + byproducts + props.losses (kg), with
-- densities taken from the registry independently of the converter.
local function assertBalance(inputs, res, label)
    local props = res.props or {}
    local lhs = massOf(inputs) + sum(props.external)
    local rhs = massOf(res.outputs) + massOf(res.byproducts) + sum(props.losses)
    T.near(lhs, rhs, 1e-9 * math.max(1, lhs), label .. ": inputs + external = outputs + byproducts + losses")
    for _, k in ipairs(Tables.sortedKeys(props.external or {})) do
        T.ok(props.external[k] >= -1e-12, label .. ": external " .. k .. " is an inflow")
    end
    for _, k in ipairs(Tables.sortedKeys(props.losses or {})) do
        T.ok(props.losses[k] >= -1e-12, label .. ": loss " .. k .. " is not negative")
    end
    for _, id in ipairs(Tables.sortedKeys(res.outputs or {})) do T.ok(res.outputs[id] >= 0, label .. ": output " .. id) end
    for _, id in ipairs(Tables.sortedKeys(res.byproducts or {})) do
        T.ok(res.byproducts[id] >= 0, label .. ": byproduct " .. id)
    end
end

-- Constant daily temperature (outdoor) for every day of the run.
local function climate(tempC)
    local log = {}
    for d = -10, 1200 do log[d] = { t = tempC, rh = 0.7 } end
    return Climate.new({ dayOfYear = 190, hourOfDay = 9 }, log)
end

local function runToEnd(proc, env, step, limit)
    local t = proc.t
    local stop = t + (limit or 24 * 60)
    while (proc.state == "Processing" or proc.state == "Paused") and t < stop do
        t = math.min(stop, t + (step or 6))
        proc = Process.advance(proc, t, env)
    end
    return proc
end

-- Loads, fuels, starts and finishes one batch; checks its material balance.
local function batch(machine, recipe, inputs, o)
    o = o or {}
    local t0 = o.t or 0
    local l = Process.load(Process.new({ id = machine .. "_1", machine = machine, t = t0 }), recipe, inputs, o.skill or 0)
    T.ok(l.ok, recipe .. " load: " .. tostring(l.reason))
    local p = l.proc
    if o.firebox then p = Process.addFirebox(p, o.firebox).proc end
    p = Process.start(p, t0).proc
    p = runToEnd(p, o.env or F.env(), o.step or 6, o.limit)
    T.eq(p.state, "OutputReady", recipe .. " finished")
    assertBalance(inputs, { outputs = p.outputs, byproducts = p.byproducts, props = p.outProps }, recipe)
    return p
end

local function collectAll(p)
    local c = Process.collect(p, 1e9)
    T.ok(c.ok, "collect: " .. tostring(c.reason))
    T.eq(c.proc.state, "Ready")
    return c
end

local function digester(machine, inputs, o)
    o = o or {}
    local recipe = (machine == "biogas_digester_heated") and "biogas_digest_heated" or "biogas_digest"
    local l = Process.load(Process.new({ id = "D1", machine = machine, t = o.t or 0 }), recipe, inputs, 0)
    T.ok(l.ok, "digester load: " .. tostring(l.reason))
    local p = l.proc
    if o.firebox then p = Process.addFirebox(p, o.firebox).proc end
    return Process.start(p, o.t or 0).proc
end

local function lit(machine, load, o)
    o = o or {}
    local st = Gasifier.new({ id = "G1", machine = machine, t = o.t or 0 })
    if o.filter then st.filter = o.filter end
    local l = Gasifier.load(st, load, o.t or 0)
    T.ok(l.ok, "gasifier load: " .. tostring(l.reason))
    local s = Gasifier.start(l.st, o.t or 0)
    T.ok(s.ok, "gasifier start: " .. tostring(s.reason))
    return s.st
end

local function addInfo(acc, info)
    for _, k in ipairs({ "produced", "delivered", "shortfall", "flared", "vented" }) do
        acc[k] = (acc[k] or 0) + info[k]
    end
    for _, k in ipairs({ "fed", "byproducts", "losses", "external" }) do
        acc[k] = acc[k] or {}
        for _, id in ipairs(Tables.sortedKeys(info[k])) do acc[k][id] = (acc[k][id] or 0) + info[k][id] end
    end
    acc.events = acc.events or {}
    for _, e in ipairs(info.events) do acc.events[#acc.events + 1] = e end
    return acc
end

local function hasEvent(events, kind, reason)
    for _, e in ipairs(events) do
        if e.kind == kind and (reason == nil or e.reason == reason) then return true end
    end
    return false
end

local function near(a, b) return math.abs(a - b) <= 1e-7 * math.max(1, math.abs(a), math.abs(b)) end

local function assertSameMap(a, b, label)
    local keys = {}
    for k in pairs(a or {}) do keys[k] = true end
    for k in pairs(b or {}) do keys[k] = true end
    for _, k in ipairs(Tables.sortedKeys(keys)) do
        local x, y = (a or {})[k] or 0, (b or {})[k] or 0
        T.ok(near(x, y), label .. "." .. k .. " " .. tostring(x) .. " vs " .. tostring(y))
    end
end

------------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------------

T.case("pathways: content validates", function()
    local problems = R.validate()
    T.eq(#problems, 0, table.concat(problems, " | "))
    for _, rid in ipairs({ "press_oilseed", "methanol_wood_distill", "ash_burn", "lye_leach", "biodiesel_react",
        "biodiesel_wash", "woodgas_gasify", "biogas_digest", "biogas_digest_heated" }) do
        local def = R.need("recipe", rid)
        for _, mid in ipairs(def.machines) do
            local m = R.need("machine", mid)
            T.ok(m.capacity ~= nil, mid .. " declares a capacity")
            for _, st in ipairs(def.stages) do
                if st.hoursFrom then T.ok(m[st.hoursFrom] ~= nil, mid .. " defines " .. st.hoursFrom) end
                if st.heatKW then T.ok(m.firebox ~= nil, mid .. " has a firebox for " .. st.id) end
            end
        end
    end
end)

------------------------------------------------------------------------------
-- Biodiesel
------------------------------------------------------------------------------

T.case("pathways: biodiesel chain from seed, wood and ash with explicit material balance", function()
    local oil = collectAll(batch("oil_press", "press_oilseed", { oilseed = 40 }))
    T.near(oil.parcel.plant_oil, 40 * 0.30 / 0.92, 1e-9, "pressed oil")
    T.near(oil.byproducts.press_cake, 40 - 12 - 0.4, 1e-9, "press cake")

    local meth = collectAll(batch("wood_retort", "methanol_wood_distill", { firewood = 100 }, { firebox = 30 }))
    T.near(meth.parcel.methanol, 4 / 0.79, 1e-9, "methanol from wood, not a finite-only input")
    T.near(meth.byproducts.charcoal, 28, 1e-9)
    T.near(meth.byproducts.wood_tar, 7, 1e-9)

    local ash = collectAll(batch("ash_pit", "ash_burn", { firewood = 100 }))
    T.near(ash.parcel.wood_ash, 1.5, 1e-9)
    local lye = collectAll(batch("lye_leacher", "lye_leach", { wood_ash = ash.parcel.wood_ash, water = 4 }, { firebox = 10 }))
    T.near(lye.parcel.lye, 1.5 * 0.15, 1e-9, "lye from wood ash")
    T.near(lye.byproducts.spent_ash, 1.5 - 0.225, 1e-9)

    local oilL = oil.parcel.plant_oil
    local load = { plant_oil = oilL, methanol = 2.0, lye = oilL * 0.0125 }
    T.le(load.methanol, meth.parcel.methanol, "methanol comes from the retort")
    T.le(load.lye, lye.parcel.lye, "lye comes from the leacher")
    local reactor = batch("biodiesel_reactor", "biodiesel_react", load, { firebox = 5 })
    local crude = collectAll(reactor)
    T.near(crude.parcel.biodiesel, oilL * 0.985, 1e-9, "conversion")
    T.ok(crude.byproducts.glycerin > 0, "glycerin settles out")
    T.eq(crude.props.quality.grade, "crude")
    local crudeFuel = Supply.new({ storage = "drum_steel", q = crude.parcel, deg = crude.props.deg, t = reactor.t })
    local ev = Consumers.evaluate("engine_ci_bio", crudeFuel)
    T.ok(not ev.compatible and Tables.contains(ev.reasons, "incompatible_fuel"), "unwashed crude is refused")
    T.ok(Tables.contains(ev.reasons, "sediment"), "and carries soap")

    local wash = Tables.copy(crude.parcel)
    wash.water = (wash.water or 0) + 0.3 * crude.parcel.biodiesel + 0.2
    local washer = batch("biodiesel_wash_tank", "biodiesel_wash", wash, { firebox = 5 })
    local fuel = collectAll(washer)
    T.eq(fuel.props.quality.grade, "good", "nominal batch")
    T.near(fuel.parcel.biodiesel, 40 * 0.30 / 0.92 * 0.985, 1e-9, "whole-chain yield")
    local drum = Supply.new({ storage = "drum_steel", q = fuel.parcel, deg = fuel.props.deg, t = washer.t })
    F.noViolations(drum, "biodiesel drum")
    local bio = Consumers.evaluate("engine_ci_bio", drum)
    T.ok(bio.compatible, "washed biodiesel runs a diesel engine")
    T.eq(bio.grade, "good")
    T.eq(#bio.reasons, 0, table.concat(bio.reasons, ","))
    local stock = Consumers.evaluate("engine_ci_stock", drum)
    T.ok(stock.compatible and Tables.contains(stock.reasons, "marginal_biodiesel"), "stock diesel: marginal")
end)

T.case("pathways: biodiesel batch quality follows methanol, water, washing, wear and season", function()
    local react, wash = R.need("recipe", "biodiesel_react"), R.need("recipe", "biodiesel_wash")
    local reactor, tank = R.need("machine", "biodiesel_reactor"), R.need("machine", "biodiesel_wash_tank")
    local conv, washConv = Process.converters.transesterify, Process.converters.wash_biodiesel
    local function washed(crude, waterL)
        local w = Tables.copy(crude)
        w.water = (w.water or 0) + waterL
        local r = washConv(w, wash.params, tank, 1, 0)
        assertBalance(w, r, "wash")
        return r, Consumers.evaluate("engine_ci_bio", Supply.new({ storage = "drum_steel", q = r.outputs, deg = r.props.deg }))
    end
    local nominalIn = { plant_oil = 40, methanol = 6, lye = 0.5 }
    local nominal = conv(nominalIn, react.params, reactor, 1, 0)
    assertBalance(nominalIn, nominal, "nominal react")
    local okWash, okEval = washed(nominal.outputs, 12)
    T.eq(okWash.props.quality.grade, "good")
    T.ok(okEval.compatible and #okEval.reasons == 0, table.concat(okEval.reasons, ","))
    -- Short methanol: half the oil stays unreacted; washing cannot fix it.
    local shortIn = { plant_oil = 40, methanol = 3, lye = 0.5 }
    local short = conv(shortIn, react.params, reactor, 1, 0)
    assertBalance(shortIn, short, "short methanol")
    T.ok(short.outputs.plant_oil > 15, "unreacted oil")
    local shortWash, shortEval = washed(short.outputs, 12)
    T.ok(not shortEval.compatible and Tables.contains(shortEval.reasons, "incompatible_fuel"))
    T.eq(shortWash.props.quality.grade, "poor")
    -- Too little wash water leaves soap (sediment) and methanol in the fuel.
    local dirtyWash, dirtyEval = washed(nominal.outputs, 2)
    T.ok(Tables.contains(dirtyEval.reasons, "sediment"), table.concat(dirtyEval.reasons, ","))
    T.eq(dirtyWash.props.quality.grade, "poor")
    T.ok(dirtyWash.props.quality.washed < 0.2)
    -- Wet oil makes soap and costs yield.
    local wetIn = { plant_oil = 40, methanol = 6, lye = 0.5, water = 2 }
    local wet = conv(wetIn, react.params, reactor, 1, 0)
    assertBalance(wetIn, wet, "wet react")
    T.ok(wet.outputs.sediment > 3 * nominal.outputs.sediment, "water makes soap")
    T.ok(wet.outputs.biodiesel < nominal.outputs.biodiesel, "and costs yield")
    -- A worn reactor converts less; skill converts more; aborted batches return everything.
    T.ok(conv(nominalIn, react.params, reactor, 0.85, 0).outputs.biodiesel < nominal.outputs.biodiesel)
    T.ok(conv(nominalIn, react.params, reactor, 1, 10).outputs.biodiesel > nominal.outputs.biodiesel)
    local half = conv(nominalIn, react.params, reactor, 1, 0, 0.5)
    T.near(massOf(half.outputs) + sum(half.props.losses), massOf(nominalIn), 1e-9, "partial batch returned in full")
    -- Settling is seasonal: slow in a cold workshop, stalled in a freezing one.
    local function started()
        local p = Process.load(Process.new({ id = "R", machine = "biodiesel_reactor" }), "biodiesel_react", nominalIn, 0).proc
        return Process.start(Process.addFirebox(p, 5).proc, 0).proc
    end
    T.near(runToEnd(started(), F.env(), 1).completedAt, 10.5, 1e-9, "summer: 0.5 + 2 + 8 h")
    T.near(runToEnd(started(), climate(-5), 1).completedAt, 18.5, 1e-9, "cold workshop settles at half rate")
    local frozen = Process.advance(started(), 48, climate(-20))
    T.eq(frozen.state, "Paused"); T.eq(frozen.pause, "too_cold")
    T.eq(Process.status(frozen).stage, "settle")
end)

------------------------------------------------------------------------------
-- Wood gas
------------------------------------------------------------------------------

T.case("pathways: stationary and vehicle gasifiers share one converter; wet wood costs gas and fouls the filter", function()
    local rec = R.need("recipe", "woodgas_gasify")
    T.ok(Tables.contains(rec.machines, "gasifier_stationary") and Tables.contains(rec.machines, "gasifier_vehicle"))
    T.eq(rec.stream, true)
    local a = Process.plan("woodgas_gasify", { firewood = 10 }, { machine = "gasifier_stationary", state = "Ready", cond = 1 })
    local b = Process.plan("woodgas_gasify", { firewood = 10 }, { machine = "gasifier_vehicle", state = "Ready", cond = 1 })
    T.near(a.expected.outputs.woodgas, 22, 1e-9, "2.2 Nm3 per kg of seasoned firewood")
    T.near(b.expected.outputs.woodgas, a.expected.outputs.woodgas, 1e-12, "same converter")
    T.eq(R.need("fuel", "woodgas").phase, "gas", "a gas stream, not a liquid")
    local conv, m = Process.converters.gasify, R.need("machine", "gasifier_stationary")
    local dryIn, wetIn, charIn = { firewood = 40 }, { firewood = 40, water = 10 }, { charcoal = 40 }
    local dry, wet, char = conv(dryIn, rec.params, m, 1, 0), conv(wetIn, rec.params, m, 1, 0), conv(charIn, rec.params, m, 1, 0)
    assertBalance(dryIn, dry, "dry gasify"); assertBalance(wetIn, wet, "wet gasify"); assertBalance(charIn, char, "charcoal")
    T.ok(dry.props.external.air > 0, "producer gas draws air")
    T.ok(wet.outputs.woodgas < 0.7 * dry.outputs.woodgas, "wet wood penalty")
    T.ok(wet.props.filterLoad > 1.5 * dry.props.filterLoad, "wet wood fouls the filter")
    T.near(wet.byproducts.water, 10, 1e-12, "moisture leaves as condensate")
    T.ok(char.outputs.woodgas > dry.outputs.woodgas and char.props.filterLoad < dry.props.filterLoad, "charcoal is cleaner")
    local half = conv(wetIn, rec.params, m, 1, 0, 0.5)
    assertBalance(wetIn, half, "aborted gasify")
    -- Woodgas can never be bottled, not even from a batch-mode output.
    local fake = { state = "OutputReady", outputs = { woodgas = 5 } }
    T.eq(Gas.collectInto(fake, F.supply({ id = "H", storage = "gas_holder", t = 0 })).reason, "not_storable")
    -- The vehicle variant carries its conversion costs as data.
    local v = R.need("machine", "gasifier_vehicle")
    T.ok(v.vehicle.installedMassKg > 0 and v.vehicle.powerFactor < 1 and v.capacity < m.capacity)
end)

T.case("pathways: gasifier warms up, streams into a bounded buffer and balances gas and mass", function()
    local m = R.need("machine", "gasifier_stationary")
    local st = lit("gasifier_stationary", { firewood = 100 }, { t = 2 })
    T.eq(Gasifier.status(st).mode, "warming")
    local out, info = Gasifier.advance(st, 2.5, 12)
    T.eq(out.state, "Processing"); T.near(out.warm, 0.5, 1e-12)
    T.near(info.flared, 2 * 2.2, 1e-9, "warm-up burns feed and flares its gas")
    T.near(info.delivered, 0, 1e-12); T.near(info.shortfall, 6, 1e-9, "the engine waits for warm-up")
    T.ok(hasEvent(info.events, "warmed_up"))
    out, info = Gasifier.advance(out, 4, 12)
    T.near(out.buffer, m.bufferNm3, 1e-9, "buffer fills to its bound")
    T.eq(out.mode, "throttled", "then production follows the draw")
    T.near(info.delivered, 12 * 1.5, 1e-9); T.near(info.shortfall, 0, 1e-9)
    -- With no draw a full buffer pauses production; nothing burns while paused.
    local idle = Gasifier.advance(out, 5, 0)
    T.eq(idle.state, "Paused"); T.eq(idle.pause, "buffer_full")
    T.near(idle.totals.fed, out.totals.fed, 1e-12)
    local resumed = Gasifier.advance(idle, 5.5, 12)
    T.eq(resumed.state, "Processing", "a draw resumes a hot gasifier")
    local cold, coldInfo = Gasifier.advance(idle, 9, 0)
    T.eq(cold.state, "Ready", "fire out after the hold time")
    T.near(coldInfo.vented, m.bufferNm3, 1e-9, "woodgas is not stored: the buffer is vented")
    T.eq(Gasifier.start(cold, 9).ok, true, "relight")
    -- Full run with a steady draw: every kg and Nm3 accounted for.
    local acc = {}
    local run
    run, info = Gasifier.advance(st, 30, 12)
    addInfo(acc, info)
    T.eq(run.state, "Ready", "hopper empty, buffer drained, fire out")
    T.near(sum(acc.fed), 100, 1e-9)
    T.near(run.buffer, st.buffer + acc.produced - acc.delivered - acc.vented, 1e-9, "gas ledger")
    T.near(acc.produced + acc.flared, 100 * 2.2, 1e-9)
    local gasKg = (acc.produced + acc.flared) * rho("woodgas")
    T.near(sum(acc.fed) + sum(acc.external), gasKg + massOf(acc.byproducts) + sum(acc.losses), 1e-9, "mass ledger")
    T.near(run.held.wood_tar, 1.2, 1e-9); T.near(run.held.wood_ash, 1.0, 1e-9)
    T.near(run.filter, 100, 1e-9, "filter load in kg of dry firewood")
    T.near(acc.delivered, acc.produced, 1e-9, "everything produced reached the engine")
end)

T.case("pathways: gasifier filter loading pauses for service and service resumes it", function()
    local m = R.need("machine", "gasifier_stationary")
    local st = lit("gasifier_stationary", { firewood = 60 }, { filter = m.filterKg - 20 })
    local out, info = Gasifier.advance(st, 5, 10)
    T.eq(out.state, "Paused"); T.eq(out.pause, "filter_full")
    T.ok(hasEvent(info.events, "paused", "filter_full"))
    T.near(out.filter, m.filterKg, 1e-12)
    T.near(out.totals.fed, 20, 1e-9, "full after 20 kg of dry firewood")
    T.near(out.cond, 1 - m.wearPerFilterCycle, 1e-12, "each filter cycle wears the gasifier")
    T.eq(Gasifier.start(out, out.t).reason, "busy")
    T.eq(Gasifier.service(lit("gasifier_stationary", { firewood = 5 }), 0).reason, "busy", "no service while burning")
    local sv = Gasifier.service(out, out.t)
    T.ok(sv.ok); T.eq(sv.st.state, "Processing", "still hot: resumes")
    T.near(sv.st.filter, 0, 1e-12)
    T.near(sv.returned.wood_tar, 20 * 0.012, 1e-9); T.near(sv.returned.wood_ash, 20 * 0.010, 1e-9)
    T.ok(Tables.isEmpty(sv.st.held))
    local after = Gasifier.advance(sv.st, sv.st.t + 1, 10)
    T.eq(after.state, "Processing"); T.ok(after.totals.fed > out.totals.fed)
    -- Left unserviced it goes out, and a cold gasifier with a full filter will not light.
    local cold = Gasifier.advance(out, out.t + 4, 0)
    T.eq(cold.state, "Ready")
    T.eq(Gasifier.start(cold, cold.t).reason, "filter_full")
    local fixed = Gasifier.service(cold, cold.t + 1).st
    T.ok(Gasifier.start(fixed, fixed.t).ok)
    -- The last filter cycle of a worn gasifier faults it until repaired.
    local worn = lit("gasifier_stationary", { firewood = 30 }, { filter = m.filterKg - 5 })
    worn.cond = m.wearPerFilterCycle
    local faulted, finfo = Gasifier.advance(worn, 5, 10)
    T.eq(faulted.state, "Faulted"); T.eq(faulted.pause, "needs_repair")
    T.ok(hasEvent(finfo.events, "faulted"))
    T.near(faulted.buffer, 0, 1e-12, "buffer vented on fault")
    T.eq(Gasifier.start(faulted, faulted.t).reason, "needs_repair")
    local repaired = Gasifier.repair(faulted, 1).st
    T.eq(repaired.state, "Ready")
    T.eq(Gasifier.start(repaired, repaired.t).reason, "filter_full")
    T.ok(Gasifier.start(Gasifier.service(repaired, repaired.t).st, repaired.t).ok)
end)

T.case("pathways: gasifier hopper takes bulk loads and refuses malformed or wet ones", function()
    local st = Gasifier.new({ id = "G", machine = "gasifier_stationary" })
    local big = Gasifier.load(st, { firewood = 90, charcoal = 30 })
    T.ok(big.ok, tostring(big.reason))
    T.near(Gasifier.status(big.st).hopperKg, 120, 1e-12, "one action fills the hopper")
    T.near(big.expected.outputs.woodgas, 90 * 2.2 + 30 * 4.2, 1e-9, "load preview")
    T.eq(Gasifier.load(big.st, { firewood = 1 }).reason, "hopper_full")
    T.eq(Gasifier.load(st, {}).reason, "empty_load")
    T.eq(Gasifier.load(st, { firewood = -5 }).reason, "invalid_amount")
    T.eq(Gasifier.load(st, { firewood = 0 / 0 }).reason, "invalid_amount")
    T.eq(Gasifier.load(st, { gasoline = 5 }).reason, "ineligible_gasoline")
    T.eq(Gasifier.load(st, { firewood = 50, water = 30 }).reason, "feed_too_wet")
    local van = Gasifier.new({ id = "V", machine = "gasifier_vehicle" })
    T.eq(Gasifier.load(van, { firewood = 61 }).reason, "over_capacity")
    T.eq(Gasifier.start(van, 0).reason, "hopper_empty")
    T.raises(function() Gasifier.advance(big.st, 0 / 0, 1) end, "invalid target time")
    T.raises(function() Gasifier.advance(big.st, 10, -1) end, "invalid demand")
    T.raises(function() Gasifier.advance(big.st, 10, 1 / 0) end, "invalid demand")
    T.raises(function() Gasifier.new({ id = "N", machine = "oil_press" }) end, "not a gasifier")
    -- Top-up while lit (no machine_busy), at the gasifier's current time.
    local running = Gasifier.advance(lit("gasifier_vehicle", { firewood = 30 }), 1, 20)
    T.eq(running.state, "Processing")
    T.eq(Gasifier.load(running, { firewood = 10 }, 0.5).reason, "time_mismatch")
    local top = Gasifier.load(running, { firewood = 10 }, 1)
    T.ok(top.ok, tostring(top.reason))
    T.near(Gasifier.status(top.st).hopperKg, Gasifier.status(running).hopperKg + 10, 1e-12)
    -- Out of fuel: a refill resumes a hot gasifier without a new warm-up.
    local dry = Gasifier.advance(lit("gasifier_vehicle", { firewood = 5 }), 1, 20)
    T.eq(dry.state, "Paused"); T.eq(dry.pause, "hopper_empty")
    local refill = Gasifier.load(dry, { firewood = 20 }, dry.t)
    T.eq(refill.st.state, "Processing"); T.near(refill.st.warm, R.need("machine", "gasifier_vehicle").warmupHours, 1e-12)
end)

T.case("pathways: gasifier one large advance equals many small randomized advances", function()
    local function fresh()
        return lit("gasifier_stationary", { firewood = 100, water = 15 }, { t = 5, filter = 300 })
    end
    -- Engine draw schedule: running, stopped briefly (within the hold), running.
    local schedule = { { to = 12, d = 9 }, { to = 13.5, d = 0 }, { to = 60, d = 9 } }
    local whole, wacc = fresh(), {}
    for _, seg in ipairs(schedule) do
        local info
        whole, info = Gasifier.advance(whole, seg.to, seg.d)
        addInfo(wacc, info)
    end
    local stepped, sacc, t = fresh(), {}, 5
    local rng = TLG.Rng.new(TEST_SEED)
    for _, seg in ipairs(schedule) do
        while t < seg.to do
            t = math.min(seg.to, t + rng:range(0.01, 2.5))
            local info
            stepped, info = Gasifier.advance(stepped, t, seg.d)
            addInfo(sacc, info)
        end
    end
    for _, kind in ipairs({ "warmed_up", "buffer_full", "resumed", "buffer_empty", "went_out" }) do
        T.ok(hasEvent(wacc.events, kind), "scenario covers " .. kind)
    end
    T.ok(hasEvent(wacc.events, "paused", "buffer_full") and hasEvent(wacc.events, "paused", "filter_full"))
    T.eq(stepped.state, whole.state); T.eq(stepped.pause, whole.pause)
    for _, k in ipairs({ "buffer", "filter", "warm", "idle", "cond", "t" }) do
        T.ok(near(stepped[k], whole[k]), k .. " " .. tostring(stepped[k]) .. " vs " .. tostring(whole[k]))
    end
    assertSameMap(stepped.hopper, whole.hopper, "hopper")
    assertSameMap(stepped.held, whole.held, "held")
    assertSameMap(stepped.totals, whole.totals, "totals")
    for _, k in ipairs({ "produced", "delivered", "shortfall", "flared", "vented" }) do
        T.ok(near(sacc[k], wacc[k]), k .. " " .. tostring(sacc[k]) .. " vs " .. tostring(wacc[k]))
    end
    assertSameMap(sacc.fed, wacc.fed, "fed")
    assertSameMap(sacc.losses, wacc.losses, "losses")
    T.near(whole.buffer, wacc.produced - wacc.delivered - wacc.vented, 1e-9, "gas ledger")
end)

------------------------------------------------------------------------------
-- Biogas
------------------------------------------------------------------------------

T.case("pathways: biogas digester fills a bounded gas holder with explicit material balance", function()
    local inputs = { manure = 600, food_waste = 300 }
    local early = Process.advance(digester("biogas_digester", inputs), 40, F.env())
    T.eq(Process.status(early).stage, "inoculate", "startup delay")
    T.ok(Tables.isEmpty(early.outputs), "no gas while the culture establishes")
    local p = runToEnd(digester("biogas_digester", inputs), F.env(), 24, 24 * 30)
    T.eq(p.state, "OutputReady")
    T.near(p.completedAt, 409, 1e-9, "1 h loading + 48 h inoculation + 360 h digestion")
    T.near(p.outputs.biogas, 600 * 0.05 + 300 * 0.15, 1e-9)
    T.near(p.byproducts.digestate, 900 - 75 * 1.15, 1e-9)
    assertBalance(inputs, { outputs = p.outputs, byproducts = p.byproducts, props = p.outProps }, "digest")
    -- A 20 Nm3 holder bounds each collection; the rest waits in the digester.
    local holder = F.supply({ id = "GH", storage = "gas_holder", t = p.t })
    local c = Gas.collectInto(p, holder)
    T.ok(c.ok, tostring(c.reason))
    T.near(c.moved, 20, 1e-9); T.eq(c.proc.state, "OutputReady"); T.eq(c.proc.pause, "output_full")
    T.eq(Gas.collectInto(c.proc, c.holder).reason, "destination_full")
    local proc, moved, drawn, digestate, guard = c.proc, c.moved, 0, nil, 0
    holder = c.holder
    local again = Process.advance(proc, proc.t + 500, F.env())
    T.near(again.outputs.biogas, 55, 1e-9, "never emitted twice while waiting")
    while proc.state == "OutputReady" do
        guard = guard + 1
        T.ok(guard < 20, "collection converges")
        local d = Gas.draw(holder, 15)
        drawn, holder = drawn + d.drawn, d.supply
        local cc = Gas.collectInto(proc, holder)
        T.ok(cc.ok, tostring(cc.reason))
        proc, holder, moved = cc.proc, cc.holder, moved + cc.moved
        if cc.byproducts then digestate = cc.byproducts.digestate end
    end
    T.near(moved, 75, 1e-9, "every Nm3 collected exactly once")
    T.near(Supply.total(holder) + drawn, 75, 1e-9)
    T.near(digestate, 813.75, 1e-9, "digestate handed out with the last gas")
    F.noViolations(holder, "gas holder")
    local later, info = Aging.advance(holder, holder.t + 24 * 10, F.env())
    T.ok(info.leaked > 0, "the holder leaks slowly")
    T.near(Supply.total(later) + info.leaked, Supply.total(holder), 1e-9, "leak is explicit")
    T.ok(Consumers.evaluate("generator_gas", later).compatible, "stationary gas generator")
    T.near(Gas.energyMJ(later.q), Supply.total(later) * 21.5, 1e-9)
end)

T.case("pathways: digester temperature: nominal when warm, slow when cool, stalled when cold, heated in winter", function()
    local inputs = { manure = 300 }
    local warm = runToEnd(digester("biogas_digester", inputs), climate(35), 24, 24 * 40)
    T.eq(warm.state, "OutputReady"); T.near(warm.completedAt, 409, 1e-9, "mesophilic optimum")
    local cool = runToEnd(digester("biogas_digester", inputs), climate(15), 24, 24 * 80)
    T.eq(cool.state, "OutputReady"); T.near(cool.completedAt, 1 + 408 / 0.35, 1e-6, "slow below 20 C")
    T.near(cool.outputs.biogas, warm.outputs.biogas, 1e-12, "cold slows digestion, it does not change the yield")
    local hot = runToEnd(digester("biogas_digester", inputs), climate(45), 24, 24 * 80)
    T.near(hot.completedAt, 1 + 408 / 0.35, 1e-6, "slow above the mesophilic band")
    local cold = Process.advance(digester("biogas_digester", inputs), 24 * 60, climate(5))
    T.eq(cold.state, "Paused"); T.eq(cold.pause, "too_cold", "stalls below 10 C")
    T.eq(Process.status(cold).stage, "inoculate"); T.near(cold.stageDone, 0, 1e-12)
    local thawed = runToEnd(cold, climate(30), 24, 24 * 40)
    T.eq(thawed.state, "OutputReady", "a stalled batch resumes when warm (no spoilage)")
    local heated = runToEnd(digester("biogas_digester_heated", inputs, { firebox = 60 }), climate(-5), 24, 24 * 40)
    T.eq(heated.state, "OutputReady"); T.near(heated.completedAt, 349, 1e-9, "held at the optimum by its heater")
    local unfuelled = Process.advance(digester("biogas_digester_heated", inputs), 100, climate(-5))
    T.eq(unfuelled.state, "Paused"); T.eq(unfuelled.pause, "no_heat")
end)

T.case("pathways: digester one large advance equals many small randomized advances", function()
    -- Mid-March start: stalled (below 10 C), then slow, then done in spring.
    local env = Climate.new({ dayOfYear = 75, hourOfDay = 9 })
    local base = digester("biogas_digester", { manure = 500, food_waste = 200, water = 100 }, { t = 3.25 })
    local stop = 24 * 75
    local mid = Process.advance(base, 24 * 5, env)
    T.eq(mid.state, "Paused"); T.eq(mid.pause, "too_cold")
    local whole = Process.advance(base, stop, env)
    local stepped, t = base, 3.25
    local rng = TLG.Rng.new(TEST_SEED + 7)
    while t < stop do
        t = math.min(stop, t + rng:range(0.5, 40))
        stepped = Process.advance(stepped, t, env)
    end
    T.eq(whole.state, "OutputReady", "finished inside the window")
    T.eq(stepped.state, whole.state)
    T.near(stepped.completedAt, whole.completedAt, 1e-6)
    T.ok(whole.completedAt > 24 * 5 + 408, "the stall and the slow band both cost time")
    T.near(stepped.outputs.biogas, whole.outputs.biogas, 1e-9)
    T.near(stepped.byproducts.digestate, whole.byproducts.digestate, 1e-9)
end)

T.case("pathways: digestate is never feedstock and digester output per day is capped", function()
    T.eq(R.need("fuel", "digestate").role, "product")
    for _, def in ipairs(R.all("recipe")) do
        T.ok(def.inputs == nil or def.inputs.digestate == nil, def.id .. " must not accept digestate")
    end
    local d = Process.new({ id = "D", machine = "biogas_digester" })
    T.eq(Process.plan("biogas_digest", { manure = 100, digestate = 50 }, d).reason, "ineligible_digestate")
    T.eq(Process.plan("biogas_digest", { food_waste = 300 }, d).reason, "not_enough_manure")
    local cap = Biogas.capNm3PerDay()
    T.ok(cap > 0 and cap <= Biogas.MAX_NM3_PER_DIGESTER_DAY, "cap " .. tostring(cap))
    local conv, def, m = Process.converters.digest, R.need("recipe", "biogas_digest"), R.need("machine", "biogas_digester")
    local balanced = conv({ manure = 300, food_waste = 300 }, def.params, m, 1, 0)
    local sourIn = { manure = 20, food_waste = 300 }
    local sour = conv(sourIn, def.params, m, 1, 0)
    assertBalance(sourIn, sour, "sour digest")
    T.ok(sour.props.sour < 1, "food-waste-only batches sour")
    T.ok(sour.outputs.biogas < 0.6 * balanced.outputs.biogas, "and cannot exploit the high food-waste yield")
    local half = conv({ manure = 300, water = 50 }, def.params, m, 1, 0, 0.25)
    assertBalance({ manure = 300, water = 50 }, half, "aborted digest")
end)

------------------------------------------------------------------------------
-- Propane
------------------------------------------------------------------------------

T.case("pathways: propane tank mapping round-trips and never manufactures gas", function()
    T.near(Gas.usesToNm3(5000), 4.48, 1e-12, "full tank")
    T.near(Propane.kg(Gas.usesToNm3(5000)), 9.0, 0.01, "displayed as 9.0 kg")
    T.near(Gas.PROPANE_KG_PER_NM3, R.need("fuel", "propane").density, 1e-12, "display density matches content")
    T.near(R.need("storage", "propane_cylinder").capacity, Gas.TANK_NM3, 1e-12, "one tank fills one cylinder")
    for u = 0, 5000 do
        local back, rem = Gas.nm3ToUses(Gas.usesToNm3(u))
        if back ~= u then T.fail("uses " .. u .. " came back as " .. tostring(back)) end
        if rem > 1e-12 then T.fail("remainder for " .. u .. " = " .. tostring(rem)) end
    end
    local rng = TLG.Rng.new(TEST_SEED)
    for _ = 1, 500 do
        local x = rng:range(0, 4.48)
        local u, rem = Gas.nm3ToUses(x)
        T.le(Gas.usesToNm3(u), x + 1e-15, "rounds down")
        T.near(Gas.usesToNm3(u) + rem, x, 1e-12, "remainder accounts for the rest")
        T.le(rem, Gas.NM3_PER_USE + 1e-15, "remainder below one use")
    end
    local u, rem = Gas.nm3ToUses(5.0)
    T.eq(u, 5000, "clamped to a full tank")
    T.near(rem, 0.52, 1e-12, "overflow returned as remainder")
    T.eq(Gas.usesToNm3(-1), nil); T.eq(Gas.nm3ToUses(0 / 0), nil); T.eq(Gas.usesToNm3(1 / 0), nil)
    T.eq(Propane.supplyFromItem("Base.Unknown", 10), nil)
end)

T.case("pathways: propane transfers stay gas-only, vessels are separate from fuel, propane never ages", function()
    local env = F.env()
    local a = Propane.supplyFromItem("Base.PropaneTank", 5000, { id = "A", t = 0 })
    local b = Propane.supplyFromItem("Base.PropaneTank", 1000, { id = "B", t = 0 })
    local tr = Gas.previewTransfer(a, b, 10)
    T.ok(tr.ok, tostring(tr.reason))
    T.near(tr.moved, Supply.free(b), 1e-12, "bounded by free room")
    T.near(Supply.total(tr.src) + Supply.total(tr.dst), Supply.total(a) + Supply.total(b), 1e-12, "conserved")
    -- Liquid <-> gas is refused both ways, also by the generic mixer.
    local can = F.supply({ id = "C", storage = "jerrycan_steel", q = { gasoline = 10 }, t = 0 })
    T.eq(Gas.previewTransfer(can, b, 1).reason, "phase_mismatch")
    T.eq(Gas.previewTransfer(a, can, 1).reason, "phase_mismatch")
    T.eq(Gas.previewTransfer(can, F.supply({ id = "D", storage = "jerrycan_steel", t = 0 }), 1).reason, "not_gas")
    T.eq(Mixing.previewTransfer(a, can, 1).reason, "phase_mismatch")
    T.eq(Gas.draw(can, 1).reason, "not_gas")
    -- Vessels only take what they are built for; woodgas is never stored.
    local holder = F.supply({ id = "H", storage = "gas_holder", q = { biogas = 5 }, t = 0 })
    T.eq(Gas.previewTransfer(holder, b, 1).reason, "vessel_incompatible")
    local wood = F.supply({ id = "W", storage = "gas_holder", cap = 5, q = { woodgas = 1 }, t = 0 })
    T.eq(Gas.previewTransfer(wood, holder, 1).reason, "not_storable")
    T.eq(Gas.previewTransfer(a, Propane.supplyFromItem("Base.PropaneTank", 0, { id = "Z", t = 1 }), 1).reason,
        "time_mismatch", "Mixing still checks time")
    -- Propane does not age; vessel condition is separate from the fuel.
    local old = Aging.advance(a, 24 * 365 * 3, env)
    T.near(old.q.propane, 4.48, 1e-12, "no loss over three years")
    T.ok(old.deg.propane == nil, "propane carries no degradation index")
    local dented = Propane.supplyFromItem("Base.PropaneTank", 2000, { id = "E", cond = 0.2, t = 0 })
    T.near(Aging.advance(dented, 24 * 365, env).q.propane, dented.q.propane, 1e-12, "a damaged cylinder keeps its fuel")
    T.eq(Gas.previewTransfer(a, dented, 1).reason, "vessel_unsafe", "but cannot be refilled")
    T.ok(Gas.previewTransfer(dented, b, 1).ok, "it can still be emptied")
    -- Bulk tank to cylinder refill; the cylinder shows full uses again.
    local bulk = Propane.bulkTank(0.5, { id = "BULK", t = 0 })
    local fill = Gas.previewTransfer(bulk, Propane.supplyFromItem("Base.PropaneTank", 0, { id = "F", t = 0 }), 100)
    T.near(fill.moved, 4.48, 1e-12)
    T.eq(Gas.usesFromSupply(fill.dst), 5000)
    T.near(Supply.total(fill.src), 190 - 4.48, 1e-9)
    T.ok(Consumers.evaluate("generator_gas", fill.dst).compatible, "converted gas generator")
end)

------------------------------------------------------------------------------
-- Process.plan on the pathway recipes
------------------------------------------------------------------------------

T.case("pathways: Process.plan rejects malformed and impossible pathway batches", function()
    local press = Process.new({ id = "P", machine = "oil_press" })
    local reactor = Process.new({ id = "R", machine = "biodiesel_reactor" })
    T.eq(Process.plan("press_oilseed", { oilseed = -4 }, press).reason, "invalid_oilseed")
    T.eq(Process.plan("press_oilseed", { oilseed = 1 }, press).reason, "not_enough_oilseed")
    T.eq(Process.plan("press_oilseed", { oilseed = 41 }, press).reason, "too_much_oilseed")
    T.eq(Process.plan("press_oilseed", { oilseed = 10, gasoline = 1 }, press).reason, "ineligible_gasoline")
    T.eq(Process.plan("biodiesel_react", { plant_oil = 20, methanol = 3, lye = 0.25 }, press).reason, "wrong_machine")
    T.eq(Process.plan("biodiesel_react", { plant_oil = 100, methanol = 25, lye = 2, water = 5 }, reactor).reason,
        "over_capacity")
    T.eq(Process.plan("biodiesel_react", { plant_oil = 20, lye = 0.25 }, reactor).reason, "not_enough_methanol")
    T.eq(Process.plan("biodiesel_react", { plant_oil = 20, methanol = 3, lye = 0.25, water = 6 }, reactor).reason,
        "too_much_water")
    T.eq(Process.plan("biodiesel_wash", { methanol = 1, water = 10 }, Process.new({ id = "W", machine = "biodiesel_wash_tank" })).reason,
        "not_enough_biodiesel")
    T.eq(Process.plan("methanol_wood_distill", { firewood = 5 }, Process.new({ id = "X", machine = "wood_retort" })).reason,
        "not_enough_firewood")
    T.eq(Process.plan("lye_leach", { wood_ash = 5 }, Process.new({ id = "L", machine = "lye_leacher" })).reason,
        "not_enough_water")
    T.eq(Process.plan("biogas_digest", { manure = 600, food_waste = 300, water = 100 },
        Process.new({ id = "D", machine = "biogas_digester" })).reason, "over_capacity")
    T.eq(Process.plan("biogas_digest", { manure = 100 }, Process.new({ id = "H", machine = "biogas_digester_heated" })).reason,
        "wrong_machine")
    T.eq(Process.plan("nope", { oilseed = 10 }, press).reason, "unknown_recipe")
    local loaded = Process.load(press, "press_oilseed", { oilseed = 10 }).proc
    T.eq(Process.plan("press_oilseed", { oilseed = 10 }, loaded).reason, "machine_busy")
    T.eq(Process.plan("press_oilseed", { oilseed = 10 }, Process.new({ id = "B", machine = "oil_press", cond = 0 })).reason,
        "needs_repair")
    for _, rid in ipairs({ "press_oilseed", "methanol_wood_distill", "ash_burn", "lye_leach", "biodiesel_react",
        "biodiesel_wash", "biogas_digest", "biogas_digest_heated" }) do
        local def = R.need("recipe", rid)
        T.ok(not Process.plan(rid, {}, Process.new({ id = "E", machine = def.machines[1] })).ok, rid .. " refuses an empty batch")
    end
    -- Gasifier loads: every feed is an optional alternative, so the gasifier refuses empty loads itself.
    T.eq(Gasifier.planLoad(Gasifier.new({ id = "G", machine = "gasifier_stationary" }), {}).reason, "empty_load")
    T.eq(Gasifier.planLoad(Gasifier.new({ id = "G", machine = "gasifier_stationary", cond = 0 }), { firewood = 5 }).reason,
        "needs_repair")
end)

------------------------------------------------------------------------------
-- Route audit
------------------------------------------------------------------------------

T.case("pathways: every route publishes its bootstrap audit and the audit passes", function()
    local problems = Routes.audit()
    T.eq(#problems, 0, table.concat(problems, " | "))
    for _, id in ipairs({ "ethanol", "biodiesel", "woodgas", "biogas", "propane", "generator_battery" }) do
        local r = Routes.get(id)
        T.ok(r ~= nil, "route " .. id)
        for _, f in ipairs(Routes.REQUIRED_FIELDS) do T.ok(r[f] ~= nil, id .. "." .. f) end
    end
    for _, id in ipairs({ "ethanol", "biodiesel", "woodgas", "biogas" }) do T.eq(Routes.get(id).classification, "renewable", id) end
    T.eq(Routes.get("propane").classification, "transitional")
    T.eq(Routes.get("generator_battery").classification, "transitional")
    T.eq(Routes.chargingClass("biogas"), "renewable", "a battery inherits its charging route")
    T.eq(Routes.chargingClass("generator_battery"), "transitional")
    local early = false
    for _, r in ipairs(Routes.list) do
        if r.early and r.classification == "renewable" and not r.startup.electricity
            and (r.startup.heat == "firewood" or r.startup.heat == "none") then
            early = true
        end
    end
    T.ok(early, "an early renewable route starts with manual work and independent heat")
end)

T.case("pathways: route audit fails a renewable label on a consumed input without a renewable source", function()
    local fake = Tables.deepCopy(Routes.get("propane"))
    fake.id, fake.classification = "fake_propane", "renewable"
    local text = table.concat(Routes.auditRoute(fake), "\n")
    T.ok(string.find(text, "consumes propane with no renewable source", 1, true), text)
    -- A chain that quietly adds a scavenged reagent cannot hide it ...
    local eth = Tables.deepCopy(Routes.get("ethanol"))
    eth.id = "fake_ethanol"
    eth.recipes[#eth.recipes + 1] = "ethanol_dry"
    text = table.concat(Routes.auditRoute(eth), "\n")
    T.ok(string.find(text, "undeclared input quicklime_kg", 1, true), text)
    -- ... and once declared it breaks the renewable label.
    eth.consumes[#eth.consumes + 1] = "quicklime_kg"
    text = table.concat(Routes.auditRoute(eth), "\n")
    T.ok(string.find(text, "consumes quicklime_kg with no renewable source", 1, true), text)
    -- Honest labels in the other direction too, and no route may need its own product to start.
    local wood = Tables.deepCopy(Routes.get("woodgas"))
    wood.id, wood.classification, wood.startup = "fake_woodgas", "transitional", { heat = "woodgas" }
    text = table.concat(Routes.auditRoute(wood), "\n")
    T.ok(string.find(text, "transitional route has no finite input", 1, true), text)
    T.ok(string.find(text, "startup heat needs its own product woodgas", 1, true), text)
    T.eq(#Routes.audit(), 0, "the shipped list was not modified")
end)
