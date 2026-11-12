-- Gas handling (spec §5, §10; decision D-014): gases are not liquids.
--
-- Canonical unit is the normal cubic metre (Nm3); propane is displayed in kg
-- at PROPANE_KG_PER_NM3. This module provides
--   * the vanilla propane tank mapping. Base.PropaneTank is a drainable with
--     5000 uses and no FluidContainer (RT-DS). TLG maps one full tank to
--     4.48 Nm3 = 9.0 kg (a 20 lb cylinder), the capacity of the
--     propane_cylinder storage profile; one use = 0.000896 Nm3 (1.8 g).
--     Nm3 -> uses rounds down so a conversion never manufactures gas; the
--     remainder is returned for the caller to keep or record as a loss.
--   * gas transfers between gas supplies (reusing TLG.Domain.Mixing, which
--     also checks time, capacity and phase). Refused here before Mixing runs:
--       not_gas / phase_mismatch  liquid <-> gas or liquid <-> liquid moves
--       not_storable              stream-only gases (woodgas) never go into a
--                                 storage vessel; they exist only inside the
--                                 producer's bounded buffer
--       vessel_incompatible       a vessel only takes the gases it is built
--                                 for (propane cylinders hold propane only)
--       vessel_unsafe             a damaged vessel (cond below its minimum)
--                                 cannot be filled; it can still be emptied
--     Vessel condition never touches the fuel: propane has no aging
--     parameters, so it never degrades, whatever its container.
--   * collectInto: moves a finished Process gas output into a bounded holder
--   * Gas.Gasifier: continuous solid-feed gas producer (below)
require "TLG/Domain/Fuel/Mixing"
require "TLG/Domain/Production/Process"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Gas = TLG.Domain.Gas or {}
local Gas = TLG.Domain.Gas
local Supply, Mixing, Process = TLG.Domain.Supply, TLG.Domain.Mixing, TLG.Domain.Process
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

Gas.PROPANE_KG_PER_NM3 = 2.01
Gas.TANK_USES = 5000
Gas.TANK_NM3 = 4.48
Gas.NM3_PER_USE = Gas.TANK_NM3 / Gas.TANK_USES
-- Rounding tolerance (in uses) for float error in uses -> Nm3 -> uses.
Gas.USE_TOLERANCE = 1e-9
-- Vessels below this condition refuse filling unless their rule says otherwise.
Gas.MIN_FILL_COND = 0.5

-- Gases that only exist as an operating stream (never stored or bottled).
Gas.STREAM_ONLY = Gas.STREAM_ONLY or {}
Gas.STREAM_ONLY.woodgas = true

-- Vessel rules by storage profile id. `accepts` = nil accepts any storable
-- gas. Content modules add rules for the profiles they define.
Gas.VESSELS = Gas.VESSELS or {}
Gas.VESSELS.propane_cylinder = { accepts = { propane = true }, minFillCond = 0.5 }
Gas.VESSELS.gas_holder = { accepts = { biogas = true }, minFillCond = 0.3 }
Gas.DEFAULT_VESSEL = { minFillCond = Gas.MIN_FILL_COND }

local function fail(reason) return { ok = false, reason = reason } end

local function sumValues(t)
    local values = {}
    for _, k in ipairs(Tables.sortedKeys(t or {})) do values[#values + 1] = t[k] end
    return Num.sum(values)
end
Gas.sumValues = sumValues

------------------------------------------------------------------------------
-- Units and the vanilla propane tank
------------------------------------------------------------------------------

-- Density of a gas fuel in kg/Nm3.
function Gas.density(fuelId)
    local f = Registry.need("fuel", fuelId)
    if f.phase ~= "gas" then error("not a gas: " .. tostring(fuelId)) end
    return f.density
end

function Gas.toKg(fuelId, nm3) return nm3 * Gas.density(fuelId) end
function Gas.fromKg(fuelId, kg) return kg / Gas.density(fuelId) end

-- Drainable uses -> Nm3. Returns nil for malformed input; uses above the
-- tank maximum are clamped (a drainable cannot hold more).
function Gas.usesToNm3(uses)
    if not Num.isFinite(uses) or uses < 0 then return nil end
    return math.min(uses, Gas.TANK_USES) * Gas.TANK_NM3 / Gas.TANK_USES
end

-- Nm3 -> whole uses (rounded down), plus the remainder in Nm3 that did not
-- fit into a whole use or into the tank. Returns nil for malformed input.
function Gas.nm3ToUses(nm3)
    if not Num.isFinite(nm3) or nm3 < 0 then return nil end
    local capped = math.min(nm3, Gas.TANK_NM3)
    local uses = math.floor(capped * Gas.TANK_USES / Gas.TANK_NM3 + Gas.USE_TOLERANCE)
    if uses > Gas.TANK_USES then uses = Gas.TANK_USES end
    if uses < 0 then uses = 0 end
    local rem = nm3 - Gas.usesToNm3(uses)
    if rem < 0 then rem = 0 end
    return uses, rem
end

-- Gas supply for a vanilla propane tank with `uses` left.
function Gas.cylinderFromUses(uses, o)
    o = o or {}
    local nm3 = Gas.usesToNm3(uses)
    if nm3 == nil then return nil end
    return Supply.new({ id = o.id, storage = o.storage or "propane_cylinder", q = { propane = nm3 },
        cond = o.cond, t = o.t, cap = o.cap })
end

-- Whole uses a gas supply can show on the vanilla drainable.
function Gas.usesFromSupply(s)
    return Gas.nm3ToUses(s.q.propane or 0)
end

-- Nominal energy of a component table (MJ).
function Gas.energyMJ(components)
    local values = {}
    for _, id in ipairs(Tables.sortedKeys(components or {})) do
        local f = Registry.need("fuel", id)
        values[#values + 1] = components[id] * (f.energyMJ or 0)
    end
    return Num.sum(values)
end

------------------------------------------------------------------------------
-- Vessels and transfers
------------------------------------------------------------------------------

function Gas.vesselRule(storageId)
    return Gas.VESSELS[storageId] or Gas.DEFAULT_VESSEL
end

-- Can `dst` receive the components (id -> quantity)? Returns ok, reason.
function Gas.canReceive(dst, components)
    if dst.phase ~= "gas" then return false, "phase_mismatch" end
    local rule = Gas.vesselRule(dst.storage)
    for _, id in ipairs(Tables.sortedKeys(components or {})) do
        local f = Registry.get("fuel", id)
        if f == nil then return false, "unknown_component" end
        if f.phase ~= "gas" then return false, "phase_mismatch" end
        if Gas.STREAM_ONLY[id] then return false, "not_storable" end
        if rule.accepts ~= nil and not rule.accepts[id] then return false, "vessel_incompatible" end
    end
    if not Num.isFinite(dst.cond) or dst.cond < (rule.minFillCond or Gas.MIN_FILL_COND) then
        return false, "vessel_unsafe"
    end
    return true
end

-- Pure preview of moving up to `amount` Nm3 between two gas supplies.
-- Same result shape as Mixing.previewTransfer.
function Gas.previewTransfer(src, dst, amount, opts)
    if src.phase ~= "gas" and dst.phase ~= "gas" then return fail("not_gas") end
    if src.phase ~= dst.phase then return fail("phase_mismatch") end
    local ok, why = Gas.canReceive(dst, src.q)
    if not ok then return fail(why) end
    return Mixing.previewTransfer(src, dst, amount, opts)
end

-- A consumer draws up to `nm3` from a gas supply (proportional removal).
function Gas.draw(s, nm3)
    if s.phase ~= "gas" then return fail("not_gas") end
    if not Num.isFinite(nm3) or nm3 < 0 then return fail("invalid_amount") end
    local out, parcel = Mixing.removeProportional(s, nm3)
    return { ok = true, supply = out, parcel = parcel, drawn = sumValues(parcel), energyMJ = Gas.energyMJ(parcel) }
end

-- Moves a finished Process gas output into a gas supply, bounded by the
-- supply's free room. The rest stays in the machine (OutputReady, pause
-- "output_full") and is never emitted twice. A refusal leaves both the
-- process and the holder untouched. Participants share the holder's time.
function Gas.collectInto(proc, holder)
    if proc.state ~= "OutputReady" then return fail("nothing_ready") end
    local ok, why = Gas.canReceive(holder, proc.outputs)
    if not ok then return fail(why) end
    local room = Supply.free(holder)
    if room <= Num.DUST then return fail("destination_full") end
    local c = Process.collect(proc, room)
    if not c.ok then return c end
    local amount = sumValues(c.parcel)
    local src = Supply.new({ storage = holder.storage, cap = amount + 1, q = c.parcel, t = holder.t })
    local tr = Mixing.previewTransfer(src, holder, amount)
    if not tr.ok then return fail(tr.reason) end
    return { ok = true, proc = c.proc, holder = tr.dst, moved = tr.moved, parcel = c.parcel,
        byproducts = c.byproducts, props = c.props }
end

------------------------------------------------------------------------------
-- Gas.Gasifier: continuous solid-feed gas producer (spec §10, wood gas)
------------------------------------------------------------------------------
-- Stationary and vehicle gasifiers are machine definitions flagged
-- `gasifier = true` (Registry.define overwrites a definition's `kind` field
-- with the registry kind, so `kind` cannot mark them) sharing this runtime
-- and one recipe/converter (TLG/Content/WoodGas). State
-- is plain data (modData):
--   v, id, rev, machine, recipe   schema, ids
--   state   Ready (cold) | Processing (lit) | Paused | Faulted | Decommissioned
--   pause   buffer_full | filter_full | hopper_empty | paused_by_player |
--           needs_repair (Faulted)
--   mode    warming | running | throttled (while Processing; display only)
--   hopper  { feed id = kg, water = kg }: one homogeneous mix, consumed in
--           proportion, so bulk loads of any size are one action
--   warm    hours of warm-up done (gas is usable once warm >= warmupHours)
--   idle    hours since combustion stopped (the fire goes out at holdHours)
--   buffer  Nm3 of woodgas between gasifier and engine (<= bufferNm3)
--   filter  filter load in kg-equivalents (pause filter_full at filterKg)
--   held    byproducts waiting for service { wood_tar, wood_ash, water }
--   cond    condition; eff = 1 - 0.3 (1 - cond) as in Process; each filter
--           cycle costs wearPerFilterCycle (Faulted at 0)
--   snap    recipe snapshot taken when lit (balance updates never
--           reinterpret a running gasifier)
--   t       last simulated world hour
--   totals  cumulative fed (kg) and produced/delivered/flared/vented (Nm3)
--
-- advance(st, toT, demand): `demand` is the engine draw in Nm3/h, constant
-- for the call (callers split calls where the draw changes). The interval is
-- simulated event by event (warm-up done, buffer full/empty, hopper empty,
-- filter full, fire out) with linear dynamics in between, so one large
-- advance equals many small ones. Regimes while lit:
--   warming    feed burns at warmupFeedFrac of the full rate; gas is flared
--   running    full rate; the buffer fills at (production - draw)
--   throttled  buffer full and draw below production: production follows
--              the draw (an engine pulls the gas it uses)
-- A full buffer with no draw pauses production (buffer_full) and resumes as
-- soon as something draws. While paused nothing burns; after holdHours the
-- fire goes out: state Ready, warm-up lost, buffer vented (woodgas is not
-- stored). Draw the buffer cannot meet is reported as info.shortfall.
-- Gas ledger: buffer_end = buffer_0 + produced - delivered - vented
-- (flared gas never enters the buffer). Mass ledger per converter call:
-- fed + external.air = (produced + flared) x density + byproducts + losses.
Gas.Gasifier = Gas.Gasifier or {}
local Gasifier = Gas.Gasifier
Gasifier.SCHEMA = 1
Gasifier.RECIPE = "woodgas_gasify"
Gasifier.EPS = 1e-12
-- Buffer tolerance (Nm3) for the full/empty regime decisions.
Gasifier.BUFFER_EPS = 1e-9
Gasifier.MAX_STEPS = 1000

Registry.addValidator("machine", function(def, problem)
    if def.gasifier ~= true then return end
    local function positive(k)
        if not (Num.isFinite(def[k]) and def[k] > 0) then problem("gasifier needs positive " .. k) end
    end
    positive("capacity"); positive("feedKgPerHour"); positive("warmupHours"); positive("holdHours")
    positive("bufferNm3"); positive("filterKg")
    if not (Num.isFinite(def.warmupFeedFrac) and def.warmupFeedFrac > 0 and def.warmupFeedFrac <= 1) then
        problem("gasifier needs warmupFeedFrac in (0,1]")
    end
    local w = def.wearPerFilterCycle
    if w ~= nil and not (Num.isFinite(w) and w >= 0 and w <= 1) then problem("invalid wearPerFilterCycle") end
end)

local function hopperMass(h) return sumValues(h) end

local function moistureOf(h)
    local total = hopperMass(h)
    if total <= 0 then return 0 end
    return (h.water or 0) / total
end

local function addTo(dst, src)
    for _, id in ipairs(Tables.sortedKeys(src or {})) do dst[id] = (dst[id] or 0) + src[id] end
end

local function event(info, t, kind, reason)
    info.events[#info.events + 1] = { t = t, kind = kind, reason = reason }
end

local function effOf(st) return 1 - 0.3 * (1 - st.cond) end

-- Recipe definition in force: the snapshot while lit, the registry otherwise.
local function recipeOf(st)
    if st.snap ~= nil then return st.snap.params end
    return Registry.need("recipe", st.recipe)
end

local function convert(st, m, feed)
    local rec = recipeOf(st)
    return Process.converters[rec.converter](feed, rec.params or {}, m, effOf(st), 0, nil)
end

-- Gas (Nm3) and filter load (kg-eq) per kg of the current hopper mix.
local function unitRates(st, m)
    local mass = hopperMass(st.hopper)
    local unit = {}
    for _, id in ipairs(Tables.sortedKeys(st.hopper)) do unit[id] = st.hopper[id] / mass end
    local r = convert(st, m, unit)
    return r.outputs.woodgas or 0, (r.props and r.props.filterLoad) or 0
end

-- Removes `kg` from the hopper in proportion (everything when `all`).
local function take(st, kg, all)
    local mass = hopperMass(st.hopper)
    local feed = {}
    if all or kg >= mass then
        for _, id in ipairs(Tables.sortedKeys(st.hopper)) do feed[id] = st.hopper[id] end
        st.hopper = {}
        return feed
    end
    local f = kg / mass
    for _, id in ipairs(Tables.sortedKeys(st.hopper)) do
        local q = st.hopper[id] * f
        feed[id] = q
        st.hopper[id] = st.hopper[id] - q
        if st.hopper[id] <= 0 then st.hopper[id] = nil end
    end
    return feed
end

-- Burns a slice of the hopper through the shared converter; returns the gas.
local function burn(st, m, info, kg, all)
    local feed = take(st, kg, all)
    local res = convert(st, m, feed)
    addTo(info.fed, feed)
    st.totals.fed = st.totals.fed + sumValues(feed)
    addTo(st.held, res.byproducts)
    addTo(info.byproducts, res.byproducts)
    addTo(info.losses, res.props.losses)
    addTo(info.external, res.props.external)
    st.filter = st.filter + (res.props.filterLoad or 0)
    return res.outputs.woodgas or 0
end

local function pause(st, info, why)
    st.state, st.pause, st.mode, st.idle = "Paused", why, nil, 0
    event(info, st.t, "paused", why)
end

-- Fire out (or fault): warm-up lost, buffer vented, snapshot released.
local function extinguish(st, info, state, why)
    local prev = st.pause
    info.vented = info.vented + st.buffer
    st.totals.vented = st.totals.vented + st.buffer
    st.buffer = 0
    st.state, st.pause, st.mode = state, why, nil
    st.warm, st.idle, st.snap = 0, 0, nil
    event(info, st.t, state == "Faulted" and "faulted" or "went_out", why or prev)
end

-- The filter is full: snap it, charge one filter cycle of wear, then pause
-- (or fault when the condition is gone). Every detection path comes here, so
-- the wear is charged exactly once per cycle.
local function filterFull(st, m, info)
    st.filter = m.filterKg
    st.cond = math.max(0, st.cond - (m.wearPerFilterCycle or 0))
    if st.cond <= 0 then
        extinguish(st, info, "Faulted", "needs_repair")
    else
        pause(st, info, "filter_full")
    end
end

-- One step while lit. Event times are compared inclusively in a fixed order
-- (hopper, filter, warm-up, buffer); a tied event that loses is picked up at
-- the start of the next step at the same instant.
local function stepLit(st, m, info, span, D)
    local mass = hopperMass(st.hopper)
    if mass <= Num.DUST then return pause(st, info, "hopper_empty") end
    if st.filter >= m.filterKg - 1e-9 then return filterFull(st, m, info) end
    local g, lf = unitRates(st, m)
    local cap, B = m.bufferNm3, st.buffer
    local warming = st.warm < m.warmupHours - Gasifier.EPS
    local r, inflow
    if warming then
        r, inflow, st.mode = m.feedKgPerHour * m.warmupFeedFrac, 0, "warming"
    else
        local P = m.feedKgPerHour * g
        if B >= cap - Gasifier.BUFFER_EPS and D < P then
            if D <= 0 then return pause(st, info, "buffer_full") end
            r, inflow, st.mode = D / g, D, "throttled"
        else
            r, inflow, st.mode = m.feedKgPerHour, P, "running"
        end
    end
    local dt, ev = span, nil
    local dtH = mass / r
    if dtH <= dt then dt, ev = dtH, "hopper_empty" end
    if lf > 0 then
        local dtF = (m.filterKg - st.filter) / (r * lf)
        if dtF <= dt then dt, ev = dtF, "filter_full" end
    end
    if warming then
        local dtW = m.warmupHours - st.warm
        if dtW <= dt then dt, ev = dtW, "warmed_up" end
    end
    if st.mode ~= "throttled" then
        if inflow > D and B < cap - Gasifier.BUFFER_EPS then
            local dtB = (cap - B) / (inflow - D)
            if dtB <= dt then dt, ev = dtB, "buffer_full" end
        elseif inflow < D and B > Gasifier.BUFFER_EPS then
            local dtB = B / (D - inflow)
            if dtB <= dt then dt, ev = dtB, "buffer_empty" end
        end
    end

    local gas = burn(st, m, info, r * dt, ev == "hopper_empty")
    local inGas = gas
    if warming then
        inGas = 0
        info.flared = info.flared + gas
        st.totals.flared = st.totals.flared + gas
        st.warm = st.warm + dt
    else
        info.produced = info.produced + gas
        st.totals.produced = st.totals.produced + gas
    end
    local want = D * dt
    if st.mode ~= "throttled" and st.buffer <= Gasifier.BUFFER_EPS and inGas < want then
        -- Starving: everything produced goes straight to the engine.
        info.delivered = info.delivered + inGas
        st.totals.delivered = st.totals.delivered + inGas
        info.shortfall = info.shortfall + (want - inGas)
    else
        st.buffer = st.buffer + inGas - want
        if st.buffer < 0 then st.buffer = 0 end
        info.delivered = info.delivered + want
        st.totals.delivered = st.totals.delivered + want
    end
    st.t = st.t + dt

    if ev == "warmed_up" then
        st.warm = m.warmupHours
        event(info, st.t, "warmed_up")
    elseif ev == "buffer_full" then
        st.buffer = cap
        event(info, st.t, "buffer_full")
    elseif ev == "buffer_empty" then
        st.buffer = 0
        event(info, st.t, "buffer_empty")
    elseif ev == "hopper_empty" then
        pause(st, info, "hopper_empty")
    elseif ev == "filter_full" then
        filterFull(st, m, info)
    end
end

local function stepPaused(st, m, info, span, D)
    local dt, ev = span, nil
    local hold = math.max(0, m.holdHours - st.idle)
    if hold <= dt then dt, ev = hold, "went_out" end
    if D > 0 and st.buffer > Gasifier.BUFFER_EPS then
        local dtB = st.buffer / D
        if dtB <= dt then dt, ev = dtB, "buffer_empty" end
    end
    local want = D * dt
    local got = math.min(st.buffer, want)
    if ev == "buffer_empty" then got = st.buffer end
    st.buffer = st.buffer - got
    info.delivered = info.delivered + got
    st.totals.delivered = st.totals.delivered + got
    if want > got then info.shortfall = info.shortfall + (want - got) end
    st.idle = st.idle + dt
    st.t = st.t + dt
    if ev == "buffer_empty" then
        st.buffer = 0
        event(info, st.t, "buffer_empty")
    elseif ev == "went_out" then
        st.idle = m.holdHours
        extinguish(st, info, "Ready", nil)
    end
end

function Gasifier.new(o)
    local m = Registry.need("machine", o.machine)
    if m.gasifier ~= true then error("not a gasifier machine: " .. tostring(o.machine)) end
    return {
        v = Gasifier.SCHEMA, id = o.id, rev = 0, machine = m.id, recipe = o.recipe or Gasifier.RECIPE,
        state = "Ready", pause = nil, mode = nil, hopper = {}, warm = 0, idle = 0, buffer = 0, filter = 0,
        held = {}, cond = o.cond or 1, t = o.t or 0, snap = nil,
        totals = { fed = 0, produced = 0, delivered = 0, flared = 0, vented = 0 },
    }
end

-- Validates a bulk hopper load without changing anything. Eligibility and
-- per-load bounds come from the shared planner (Process.plan on a Ready
-- shim, so top-ups work while lit); room and moisture are checked here.
function Gasifier.planLoad(st, load)
    if type(load) ~= "table" then return fail("invalid_load") end
    local total = 0
    for _, id in ipairs(Tables.sortedKeys(load)) do
        local q = load[id]
        if type(id) ~= "string" or not Num.isFinite(q) or q < 0 then return fail("invalid_amount") end
        total = total + q
    end
    if total <= Num.DUST then return fail("empty_load") end
    if st.state == "Decommissioned" then return fail("decommissioned") end
    local p = Process.plan(st.recipe, load, { machine = st.machine, state = "Ready", cond = st.cond })
    if not p.ok then return p end
    local m = Registry.need("machine", st.machine)
    local room = m.capacity - hopperMass(st.hopper)
    if total > room + 1e-9 then return fail("hopper_full") end
    local mix = Tables.copy(st.hopper)
    addTo(mix, load)
    if moistureOf(mix) > recipeOf(st).params.wetMax + 1e-12 then return fail("feed_too_wet") end
    return { ok = true, accepted = total, room = room, expected = p.expected }
end

-- Bulk loading: the whole load goes into the hopper in one action, in any
-- state but Decommissioned. The caller advances a lit gasifier to `now`
-- first. A hot gasifier paused on hopper_empty resumes.
function Gasifier.load(st, load, now)
    if now ~= nil and math.abs(now - st.t) > 1e-6 then
        if st.state ~= "Ready" or now < st.t then return fail("time_mismatch") end
    end
    local p = Gasifier.planLoad(st, load)
    if not p.ok then return p end
    local out = Tables.deepCopy(st)
    if now ~= nil and now > out.t then out.t = now end
    for _, id in ipairs(Tables.sortedKeys(load)) do
        if load[id] > 0 then out.hopper[id] = (out.hopper[id] or 0) + load[id] end
    end
    if out.state == "Paused" and out.pause == "hopper_empty" then
        out.state, out.pause, out.idle = "Processing", nil, 0
    end
    return { ok = true, st = out, accepted = p.accepted, expected = p.expected }
end

-- Lights a cold gasifier (warm-up from zero) or resumes one the player
-- stopped while it is still hot.
function Gasifier.start(st, now)
    if st.state == "Paused" and st.pause == "paused_by_player" then
        if now ~= nil and math.abs(now - st.t) > 1e-6 then return fail("time_mismatch") end
        local out = Tables.deepCopy(st)
        out.state, out.pause, out.idle = "Processing", nil, 0
        return { ok = true, st = out }
    end
    if st.state == "Faulted" then return fail("needs_repair") end
    if st.state ~= "Ready" then return fail("busy") end
    now = now or st.t
    if now < st.t - 1e-6 then return fail("time_regression") end
    if st.cond <= 0 then return fail("needs_repair") end
    local m = Registry.need("machine", st.machine)
    if hopperMass(st.hopper) <= Num.DUST then return fail("hopper_empty") end
    if st.filter >= m.filterKg - 1e-9 then return fail("filter_full") end
    local snap = Process.snapshot(st.recipe)
    if moistureOf(st.hopper) > snap.params.params.wetMax + 1e-12 then return fail("feed_too_wet") end
    local out = Tables.deepCopy(st)
    out.t = math.max(now, st.t)
    out.state, out.pause, out.mode = "Processing", nil, "warming"
    out.warm, out.idle, out.buffer = 0, 0, 0
    out.snap = snap
    return { ok = true, st = out }
end

-- Closes the air intake: production stops; the fire goes out after holdHours.
function Gasifier.stop(st)
    if st.state ~= "Processing" then return fail("not_processing") end
    local out = Tables.deepCopy(st)
    out.state, out.pause, out.mode, out.idle = "Paused", "paused_by_player", nil, 0
    return { ok = true, st = out }
end

-- Service (gasifier not burning): empties filter, ash pit and condensate trap
-- in one action and returns their contents. A gasifier paused on
-- filter_full that is still hot resumes.
function Gasifier.service(st, now)
    if st.state ~= "Ready" and st.state ~= "Paused" and st.state ~= "Faulted" then return fail("busy") end
    if now ~= nil and math.abs(now - st.t) > 1e-6 then
        if st.state == "Paused" or now < st.t then return fail("time_mismatch") end
    end
    local out = Tables.deepCopy(st)
    if now ~= nil and now > out.t then out.t = now end
    local returned = out.held
    out.held, out.filter = {}, 0
    if out.state == "Paused" and out.pause == "filter_full" then
        out.state, out.pause, out.idle = "Processing", nil, 0
    end
    return { ok = true, st = out, returned = returned }
end

function Gasifier.repair(st, amount)
    if st.state == "Processing" or st.state == "Decommissioned" then return fail("busy") end
    if not Num.isFinite(amount) or amount <= 0 then return fail("invalid_amount") end
    local out = Tables.deepCopy(st)
    out.cond = Num.clamp(out.cond + amount, 0, 1)
    if out.state == "Faulted" and out.cond > 0 then out.state, out.pause = "Ready", nil end
    return { ok = true, st = out }
end

-- Empties the hopper of a cold gasifier and returns its contents.
function Gasifier.unload(st)
    if st.state ~= "Ready" and st.state ~= "Faulted" then return fail("busy") end
    local out = Tables.deepCopy(st)
    local returned = out.hopper
    out.hopper = {}
    return { ok = true, st = out, returned = returned }
end

-- Puts the fire out now (D-040, a generator's gasifier): warm-up lost, the
-- buffer let out, the hopper kept. `why` names the reason in the event list
-- (the player's "put_out" unless given). Returns the gas let out.
function Gasifier.putOut(st, now, why)
    if st.state ~= "Processing" and st.state ~= "Paused" then return fail("not_lit") end
    if now ~= nil and math.abs(now - st.t) > 1e-6 then return fail("time_mismatch") end
    local out = Tables.deepCopy(st)
    local info = { events = {}, vented = 0 }
    extinguish(out, info, "Ready", why or "put_out")
    return { ok = true, st = out, vented = info.vented }
end

-- An engine that takes its gas in lumps (D-040: a generator's hourly
-- refill) draws up to `nm3` from the buffer of a gasifier brought to `now`.
-- It gets what the buffer holds, in any state that has a buffer (a paused
-- gasifier keeps the gas it made until it goes out, as stepPaused serves
-- it). One paused on buffer_full resumes, its buffer no longer full; one
-- paused for another reason stays paused. Returns the state and the Nm3
-- taken.
function Gasifier.draw(st, nm3, now)
    if not Num.isFinite(nm3) or nm3 < 0 then return fail("invalid_amount") end
    if now ~= nil and math.abs(now - st.t) > 1e-6 then return fail("time_mismatch") end
    local taken = math.min(nm3, st.buffer)
    if taken <= 0 then return { ok = true, st = st, taken = 0 } end
    local out = Tables.deepCopy(st)
    out.buffer = st.buffer - taken
    if out.buffer <= Gasifier.EPS then out.buffer = 0 end
    out.totals.delivered = out.totals.delivered + taken
    if out.state == "Paused" and out.pause == "buffer_full" then
        out.state, out.pause, out.idle = "Processing", nil, 0
    end
    return { ok = true, st = out, taken = taken }
end

function Gasifier.decommission(st)
    if st.state ~= "Ready" and st.state ~= "Faulted" then return fail("busy") end
    if hopperMass(st.hopper) > Num.DUST or not Tables.isEmpty(st.held) then return fail("not_empty") end
    local out = Tables.deepCopy(st)
    out.state = "Decommissioned"
    return { ok = true, st = out }
end

-- Gas output at full rate (Nm3/h) with the current hopper mix.
function Gasifier.ratedOutput(st)
    if hopperMass(st.hopper) <= Num.DUST then return 0 end
    local m = Registry.need("machine", st.machine)
    local g = unitRates(st, m)
    return m.feedKgPerHour * g
end

function Gasifier.status(st)
    local m = Registry.need("machine", st.machine)
    -- A paused gasifier is still hot: it goes out after holdLeft hours.
    local holdLeft = st.state == "Paused" and math.max(0, m.holdHours - st.idle) or nil
    return {
        state = st.state, reason = st.pause, mode = st.mode,
        hopperKg = hopperMass(st.hopper), moisture = moistureOf(st.hopper),
        warm = math.min(1, st.warm / m.warmupHours), buffer = st.buffer, bufferCap = m.bufferNm3,
        filter = st.filter / m.filterKg, holdLeft = holdLeft, held = Tables.copy(st.held), cond = st.cond,
    }
end

-- Advances to world hour `toT` with a constant engine draw (Nm3/h).
-- Returns a new state and { events, produced, delivered, shortfall, flared,
-- vented, fed, byproducts, losses, external }; `st` is not modified.
function Gasifier.advance(st, toT, demand)
    local out = Tables.deepCopy(st)
    local info = { events = {}, produced = 0, delivered = 0, shortfall = 0, flared = 0, vented = 0,
        fed = {}, byproducts = {}, losses = {}, external = {} }
    if not Num.isFinite(toT) then error("gasifier advance: invalid target time") end
    local D = demand or 0
    if not Num.isFinite(D) or D < 0 then error("gasifier advance: invalid demand") end
    if toT <= out.t then return out, info end
    local m = Registry.need("machine", out.machine)
    local steps = 0
    while out.t < toT - Gasifier.EPS do
        steps = steps + 1
        if steps > Gasifier.MAX_STEPS then error("gasifier advance did not converge") end
        local span = toT - out.t
        if out.state == "Paused" and out.pause == "buffer_full" and D > 0 then
            out.state, out.pause, out.idle = "Processing", nil, 0
            event(info, out.t, "resumed", "draw")
        end
        if out.state == "Processing" then
            stepLit(out, m, info, span, D)
        elseif out.state == "Paused" then
            stepPaused(out, m, info, span, D)
        else
            info.shortfall = info.shortfall + D * span
            out.t = toT
        end
    end
    out.t = toT
    return out, info
end

return Gas
