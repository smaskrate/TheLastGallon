-- Electricity and heat networks (spec §12): explicit topology, dispatch and
-- grid-stepped catch-up. Contract name: EnergyService.dispatch.
--
-- EnergyService.dispatch(network, interval, producerState, demand)
--   network        record of one connected component (Dispatch.network)
--   interval       { t0 = network.t, t1 } world hours
--   producerState  { [id] = { kw = available } }                  solar/wind/hydro
--                  { [id] = { fuel = fuelId, amount = units,       fueled
--                             energyMJ = optional blend value per unit,
--                             powerFactor = optional 0..1 derating } }
--                  (a missing entry means 0 kW / no fuel)
--   demand         { [consumerId] = { kw = requested, minKW = optional } }
-- Returns { ok = true, network = advanced copy, report } or
-- { ok = false, reason = code }. Inputs are never modified.
--
-- All inputs are constant over the interval; the caller splits time where
-- they change (Dispatch.advance does so on a fixed hourly grid). Inside the
-- interval the dispatch is event-driven: battery full/empty/reconnect, fuel
-- exhaustion, reserve thresholds and minimum run time end a sub-step exactly,
-- and every flow is constant within a sub-step. One call over [t0,t2]
-- therefore equals calls over [t0,t1] and [t1,t2] (the caller subtracting the
-- reported fuel in between) up to floating-point rounding; tests check 1e-9
-- relative. Tolerances: Battery.eps (1e-12 kWh per kWh of capacity),
-- SOC_TOL 1e-10, TIME_TOL 1e-9 h, POWER_TOL 1e-9 kW.
-- dispatch is meant for one piecewise-constant interval: MAX_STEPS bounds the
-- sub-steps of a single call (did_not_converge beyond it). Long catch-up goes
-- through Dispatch.advance, which dispatches one grid cell (1 h) per call.
-- A zero-length dispatch (t1 == t0) still settles the state (it may start or
-- stop a generator and report the events); a zero-length advance returns an
-- unchanged copy.
--
-- Each sub-step follows spec §12:
--  1. availability: renewables (must-take), running generators (ratedKW x
--     powerFactor), battery discharge (limit, zero when empty/disconnected)
--  2. demand: electric consumers; heat consumers separately
--  3. allocation: uncontrolled loads first (D-011: vanilla appliances have no
--     priority), then priority ascending (1 before 2), ties by consumer id;
--     minKW = kw makes a load all-or-nothing, minKW < kw allows partial supply
--  4. power limits: battery charge/discharge limits, generator ratings
--  5. merit order: renewables, then running generators (shared in proportion
--     to their available rating), then batteries in id order; surplus charges
--     batteries in id order (renewables first, then running generators) and
--     the remaining renewable surplus is curtailed
--  6. unmet demand, curtailment, battery and conversion losses recorded
--  7. stored energy, fuel and run time advanced
-- Generators: mode "on" runs while fuelled, "off" never, "auto" (default)
-- follows its policy { startBelow, stopAbove, minRunHours } (node, network or
-- DEFAULT_POLICY): it starts when the network state of charge is <= startBelow
-- or when starting it reduces unmet demand; it stops only after minRunHours,
-- with SOC >= stopAbove (networks with storage) and when stopping would not
-- increase unmet demand. startBelow < stopAbove is enforced (hysteresis).
-- A battery that runs empty stays disconnected until reconnectFraction, so
-- all-or-nothing loads cannot chatter at an empty battery.
-- Heat: running fueled producers with heatRecovery offer recovered heat to
-- heat consumers by priority, never more than is available in total; the rest
-- is waste. Generators are electricity-led (heat demand never starts them).
--
-- Fuel ownership: the network never stores fuel. report.fuelUsed[producerId]
-- = { fuel, amount, owner } is applied once by the consumption owner (the TLG
-- supply when owner = "tlg"; the native burn when owner = "native", in which
-- case the figure is informational and must not be subtracted again).
--
-- Accounting identity (report.totals):
--   energyInKWh = deliveredKWh + storedDeltaKWh + lossesKWh + curtailedKWh
--   energyIn  = renewable energy available + fuel energy burned
--   delivered = electricity + heat served to consumers
--   losses    = battery charge/discharge losses + self-discharge
--             + generator conversion losses + recovered heat nobody used
require "TLG/Registry/Registry"
require "TLG/Util/Num"
require "TLG/Util/Tables"
require "TLG/Domain/Energy/Battery"
require "TLG/Domain/Energy/Generation"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Energy = TLG.Domain.Energy or {}
TLG.Domain.Energy.Dispatch = TLG.Domain.Energy.Dispatch or {}
local Dispatch = TLG.Domain.Energy.Dispatch
local Battery, Gen = TLG.Domain.Energy.Battery, TLG.Domain.Energy.Generation
local Registry, Num, Tables = TLG.Registry, TLG.Num, TLG.Tables

Dispatch.SCHEMA = (TLG.SCHEMA and TLG.SCHEMA.network) or 1
Dispatch.MAX_STEPS = 100000
Dispatch.MAX_GRID_STEPS = 50000
Dispatch.DEFAULT_PRIORITY = 100
Dispatch.DEFAULT_POLICY = { startBelow = 0.25, stopAbove = 0.90, minRunHours = 1 }
Dispatch.DEFAULT_ORIGIN = { dayOfYear = 190, hourOfDay = 9 }
Dispatch.NODE_KINDS = { producer = true, battery = true, consumer = true, junction = true }
Dispatch.MODES = { auto = true, on = true, off = true }
Dispatch.SOC_TOL = 1e-10
Dispatch.TIME_TOL = 1e-9
Dispatch.POWER_TOL = 1e-9
local SOC_TOL, TIME_TOL, POWER_TOL = Dispatch.SOC_TOL, Dispatch.TIME_TOL, Dispatch.POWER_TOL

local function fail(reason) return { ok = false, reason = reason } end
local function positive(v) return Num.isFinite(v) and v > 0 end
local function nonneg(v) return Num.isFinite(v) and v >= 0 end
local function unit(v) return Num.isFinite(v) and v >= 0 and v <= 1 end

------------------------------------------------------------------------------
-- Load definitions (MachineDefinition with energy = "load")
------------------------------------------------------------------------------

Registry.addValidator("machine", function(def, problem)
    if def.energy ~= "load" then return end
    if not positive(def.maxKW) then problem("load needs positive maxKW") end
    if def.heat ~= nil and type(def.heat) ~= "boolean" then problem("load heat flag must be boolean") end
end)

function Dispatch.loadDef(id)
    local def = Registry.get("machine", id)
    if def ~= nil and def.energy == "load" then return def end
    return nil
end

-- Node helpers. Consumers: priority (lower is served first), heat = true for
-- heat consumers, uncontrolled = true for aggregate vanilla load (D-011).
function Dispatch.consumer(o)
    return { kind = "consumer", id = o.id, def = o.def, priority = o.priority, heat = o.heat, uncontrolled = o.uncontrolled }
end

function Dispatch.junction(id)
    return { kind = "junction", id = id }
end

------------------------------------------------------------------------------
-- Topology
--   graph = { nodes = { [id] = node }, adj = { [id] = { [neighbour] = true } } }
-- Edges are undirected; duplicates and self-loops collapse in the adjacency
-- sets. Change operations return a new graph (copy-on-write) plus the list of
-- affected components, so callers rebuild only those networks.
------------------------------------------------------------------------------

local function validNode(n)
    return type(n) == "table" and type(n.id) == "string" and n.id ~= "" and Dispatch.NODE_KINDS[n.kind] == true
end

local function edgeEnds(e)
    if type(e) ~= "table" then return nil, nil end
    if e[1] ~= nil then return e[1], e[2] end
    return e.a, e.b
end

function Dispatch.graph(nodes, edges)
    if type(nodes) ~= "table" or (edges ~= nil and type(edges) ~= "table") then return fail("invalid_topology") end
    local g = { nodes = {}, adj = {} }
    for _, n in ipairs(nodes) do
        if not validNode(n) then return fail("invalid_node") end
        local old = g.nodes[n.id]
        if old == nil then
            g.nodes[n.id] = Tables.deepCopy(n)
            g.adj[n.id] = {}
        elseif not Tables.deepEqual(old, n, 0) then
            return fail("duplicate_node")
        end
    end
    for _, e in ipairs(edges or {}) do
        local a, b = edgeEnds(e)
        if a == nil or b == nil or g.nodes[a] == nil or g.nodes[b] == nil then return fail("unknown_node") end
        if a ~= b then
            g.adj[a][b] = true
            g.adj[b][a] = true
        end
    end
    return { ok = true, graph = g }
end

-- Sorted ids of the connected component containing `id` (iterative BFS; a
-- visited set makes loops and duplicate edges harmless). nil if unknown.
function Dispatch.component(g, id)
    if type(g) ~= "table" or type(g.nodes) ~= "table" or g.nodes[id] == nil then return nil end
    local seen, queue, head = { [id] = true }, { id }, 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        for nb in pairs(g.adj[cur] or {}) do
            if not seen[nb] then
                seen[nb] = true
                queue[#queue + 1] = nb
            end
        end
    end
    return Tables.sortedKeys(seen)
end

function Dispatch.components(g)
    local out, seen = {}, {}
    for _, id in ipairs(Tables.sortedKeys(g.nodes)) do
        if not seen[id] then
            local comp = Dispatch.component(g, id)
            for _, m in ipairs(comp) do seen[m] = true end
            out[#out + 1] = comp
        end
    end
    return out
end

local function cloneGraph(g, touched)
    local out = { nodes = Tables.copy(g.nodes), adj = Tables.copy(g.adj) }
    for _, id in ipairs(touched) do
        if out.adj[id] ~= nil then out.adj[id] = Tables.copy(out.adj[id]) end
    end
    return out
end

local function distinctComponents(g, ids)
    local out, seen = {}, {}
    for _, id in ipairs(ids) do
        if g.nodes[id] ~= nil and not seen[id] then
            local comp = Dispatch.component(g, id)
            for _, m in ipairs(comp) do seen[m] = true end
            out[#out + 1] = comp
        end
    end
    return out
end

function Dispatch.connect(g, a, b)
    if g.nodes[a] == nil or g.nodes[b] == nil then return fail("unknown_node") end
    local out = cloneGraph(g, { a, b })
    if a ~= b then
        out.adj[a][b] = true
        out.adj[b][a] = true
    end
    return { ok = true, graph = out, affected = distinctComponents(out, { a }) }
end

function Dispatch.disconnect(g, a, b)
    if g.nodes[a] == nil or g.nodes[b] == nil then return fail("unknown_node") end
    local out = cloneGraph(g, { a, b })
    out.adj[a][b] = nil
    out.adj[b][a] = nil
    return { ok = true, graph = out, affected = distinctComponents(out, { a, b }) }
end

function Dispatch.addNode(g, node)
    if not validNode(node) then return fail("invalid_node") end
    if g.nodes[node.id] ~= nil then return fail("duplicate_node") end
    local out = cloneGraph(g, {})
    out.nodes[node.id] = Tables.deepCopy(node)
    out.adj[node.id] = {}
    return { ok = true, graph = out, affected = { { node.id } } }
end

-- Removing a node affects the components of its former neighbours (the
-- node's own network disappears).
function Dispatch.removeNode(g, id)
    if g.nodes[id] == nil then return fail("unknown_node") end
    local neighbours = Tables.sortedKeys(g.adj[id])
    local out = cloneGraph(g, neighbours)
    out.nodes[id] = nil
    out.adj[id] = nil
    for _, nb in ipairs(neighbours) do out.adj[nb][id] = nil end
    return { ok = true, graph = out, affected = distinctComponents(out, neighbours) }
end

------------------------------------------------------------------------------
-- Model preparation (validation of network, producer state and demand)
------------------------------------------------------------------------------

local function checkPolicy(p)
    if type(p) ~= "table" then return nil end
    local h = p.minRunHours == nil and 0 or p.minRunHours
    if not (unit(p.startBelow) and unit(p.stopAbove) and p.startBelow < p.stopAbove and nonneg(h)) then return nil end
    return { startBelow = p.startBelow, stopAbove = p.stopAbove, minRunHours = h }
end

local function prepareGenerator(net, id, p, def, cond, st)
    local mode = p.mode == nil and "auto" or p.mode
    if not Dispatch.MODES[mode] then return nil, "invalid_mode" end
    local policy = checkPolicy(p.policy or net.policy or Dispatch.DEFAULT_POLICY)
    if policy == nil then return nil, "invalid_policy" end
    local runFor = p.runFor == nil and 0 or p.runFor
    if not nonneg(runFor) then return nil, "invalid_producer" end
    local idle, slope = Gen.curve(def)
    local g = {
        id = id, def = def, cond = cond, mode = mode, policy = policy, running = p.running == true,
        runFor = runFor, stopReason = p.stopReason, owner = def.owner or "tlg", idle = idle, slope = slope,
        hr = def.heatRecovery or 0, cap = 0, fuelKWh = 0, amount = 0, p = 0, f = 0, h = 0,
    }
    if st ~= nil then
        local f = Registry.get("fuel", st.fuel)
        if f == nil or f.role ~= "fuel" then return nil, "unknown_fuel" end
        if def.consumer ~= nil then
            local profile = Registry.get("consumer", def.consumer)
            if profile == nil or profile.accepts[st.fuel] == nil then return nil, "incompatible_fuel" end
        end
        if not nonneg(st.amount) then return nil, "invalid_fuel_amount" end
        local mj = st.energyMJ == nil and f.energyMJ or st.energyMJ
        if not positive(mj) then return nil, "invalid_energy" end
        local pf = st.powerFactor == nil and 1 or st.powerFactor
        if not unit(pf) then return nil, "invalid_power_factor" end
        g.fuel, g.amount, g.energyMJ = st.fuel, st.amount, mj
        g.fuelKWh = Gen.fuelEnergyKWh(st.amount, mj)
        g.cap = def.ratedKW * pf
    end
    g.fuelEps = 1e-12 * math.max(1, g.fuelKWh)
    return g
end

local function checkIds(map, known, unknownReason, badReason)
    for _, id in ipairs(Tables.sortedKeys(map)) do
        if type(id) ~= "string" or known[id] == nil then return unknownReason end
        if type(map[id]) ~= "table" then return badReason end
    end
    return nil
end

local function consumerLess(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.id < b.id
end

local function prepare(net, ps, demand)
    if type(net) ~= "table" or type(net.producers) ~= "table" or type(net.batteries) ~= "table" or
        type(net.consumers) ~= "table" or not Num.isFinite(net.t) then
        return nil, "invalid_network"
    end
    if type(ps) ~= "table" then return nil, "invalid_producer_state" end
    if type(demand) ~= "table" then return nil, "invalid_demand" end
    local why = checkIds(ps, net.producers, "unknown_producer", "invalid_producer_state") or
        checkIds(demand, net.consumers, "unknown_consumer", "invalid_demand")
    if why ~= nil then return nil, why end
    local m = { ren = {}, gens = {}, bats = {}, loads = {}, heats = {}, R = 0, capTotal = 0, H = 0, heatUsed = 0 }
    for _, id in ipairs(Tables.sortedKeys(net.producers)) do
        local p = net.producers[id]
        if type(p) ~= "table" or p.id ~= id then return nil, "invalid_producer" end
        local def = Gen.def(p.def)
        if def == nil then return nil, "unknown_producer_def" end
        local cond = p.cond == nil and 1 or p.cond
        if not unit(cond) then return nil, "invalid_producer" end
        local st = ps[id]
        if def.energy == "fueled" then
            local g, gwhy = prepareGenerator(net, id, p, def, cond, st)
            if g == nil then return nil, gwhy end
            m.gens[#m.gens + 1] = g
        else
            local kw = 0
            if st ~= nil then
                kw = st.kw
                if not nonneg(kw) then return nil, "invalid_power" end
                if kw > def.ratedKW * (1 + 1e-9) then return nil, "over_rating" end
            end
            m.ren[#m.ren + 1] = { id = id, kw = kw, used = 0 }
            m.R = m.R + kw
        end
    end
    for _, id in ipairs(Tables.sortedKeys(net.batteries)) do
        local b = net.batteries[id]
        if type(b) ~= "table" or b.id ~= id then return nil, "invalid_battery" end
        local def, cap = Battery.check(b)
        if def == nil then return nil, cap end
        local w = Battery.view(b, def, cap)
        w.e0, w.pIn, w.pOut, w.r, w.leakNow, w.acc, w.dcap = w.e, 0, 0, 0, 0, 0, 0
        m.bats[#m.bats + 1] = w
        m.capTotal = m.capTotal + cap
    end
    for _, id in ipairs(Tables.sortedKeys(net.consumers)) do
        local c = net.consumers[id]
        if type(c) ~= "table" or c.id ~= id then return nil, "invalid_consumer" end
        local def = nil
        if c.def ~= nil then
            def = Dispatch.loadDef(c.def)
            if def == nil then return nil, "unknown_consumer_def" end
        end
        local priority = c.priority == nil and Dispatch.DEFAULT_PRIORITY or c.priority
        if not nonneg(priority) then return nil, "invalid_consumer" end
        local kw, minKW = 0, 0
        local d = demand[id]
        if d ~= nil then
            kw = d.kw
            if not nonneg(kw) then return nil, "invalid_demand" end
            minKW = d.minKW == nil and 0 or d.minKW
            if not nonneg(minKW) or minKW > kw then return nil, "invalid_demand" end
            if def ~= nil and kw > def.maxKW * (1 + 1e-9) then return nil, "over_rating" end
        end
        local entry = { id = id, kw = kw, min = minKW, priority = priority, rank = c.uncontrolled == true and 0 or 1, x = 0 }
        if c.heat == true or (def ~= nil and def.heat == true) then
            m.heats[#m.heats + 1] = entry
        else
            m.loads[#m.loads + 1] = entry
        end
    end
    Tables.sort(m.loads, consumerLess)
    Tables.sort(m.heats, consumerLess)
    return m
end

------------------------------------------------------------------------------
-- Networks
------------------------------------------------------------------------------

-- Network record of one connected component (ids from Dispatch.component).
-- Each member appears once however many paths lead to it, so a loop or a
-- duplicate edge can never count a source twice.
function Dispatch.network(g, ids, t, policy)
    if type(g) ~= "table" or type(g.nodes) ~= "table" then return fail("invalid_topology") end
    if type(ids) ~= "table" or ids[1] == nil then return fail("empty_component") end
    if not Num.isFinite(t) then return fail("invalid_interval") end
    local set = {}
    for _, id in ipairs(ids) do
        if g.nodes[id] == nil then return fail("unknown_node") end
        set[id] = true
    end
    local members = Tables.sortedKeys(set)
    local net = {
        v = Dispatch.SCHEMA, id = "net:" .. members[1], t = t, members = members,
        producers = {}, batteries = {}, consumers = {},
    }
    for _, id in ipairs(members) do
        local n = g.nodes[id]
        if n.kind == "producer" then
            net.producers[id] = Tables.deepCopy(n)
        elseif n.kind == "battery" then
            net.batteries[id] = Tables.deepCopy(n)
        elseif n.kind == "consumer" then
            net.consumers[id] = Tables.deepCopy(n)
        end
    end
    if policy ~= nil then net.policy = Tables.deepCopy(policy) end
    local m, why = prepare(net, {}, {})
    if m == nil then return fail(why) end
    return { ok = true, network = net }
end

-- New graph whose member nodes carry the network's current device state.
function Dispatch.store(g, net)
    local out = { nodes = Tables.copy(g.nodes), adj = Tables.copy(g.adj) }
    for _, map in ipairs({ net.producers, net.batteries, net.consumers }) do
        for _, id in ipairs(Tables.sortedKeys(map)) do
            if out.nodes[id] ~= nil then out.nodes[id] = Tables.deepCopy(map[id]) end
        end
    end
    return out
end

------------------------------------------------------------------------------
-- Allocation
------------------------------------------------------------------------------

-- Greedy allocation in list order: a request gets its full kW when it fits,
-- otherwise what is left if that is at least its minKW, otherwise nothing.
-- Never allocates more than `avail` in total. write = true stores .x.
local function allocate(avail, list, write)
    local rem, served, unmet = math.max(0, avail), 0, 0
    for _, c in ipairs(list) do
        local x = 0
        if c.kw > 0 and rem > 0 then
            if rem >= c.kw - 1e-12 * math.max(1, c.kw) then
                x = math.min(c.kw, rem)
            elseif c.min < c.kw and rem >= c.min then
                x = rem
            end
        end
        if write then c.x = x end
        rem = rem - x
        served = served + x
        unmet = unmet + (c.kw - x)
    end
    return served, unmet
end

-- Public allocation of a shared budget (electricity or recovered heat):
-- requests = { { id, kw, minKW = optional, priority = optional } }.
-- Returns { ok, allocation = { [id] = kW }, total, unmet }.
function Dispatch.allocate(availableKW, requests)
    if not nonneg(availableKW) then return fail("invalid_power") end
    if type(requests) ~= "table" then return fail("invalid_demand") end
    local list, seen = {}, {}
    for _, r in ipairs(requests) do
        if type(r) ~= "table" or type(r.id) ~= "string" or seen[r.id] then return fail("invalid_demand") end
        seen[r.id] = true
        local minKW = r.minKW == nil and 0 or r.minKW
        local priority = r.priority == nil and Dispatch.DEFAULT_PRIORITY or r.priority
        if not nonneg(r.kw) or not nonneg(minKW) or minKW > r.kw or not nonneg(priority) then return fail("invalid_demand") end
        list[#list + 1] = { id = r.id, kw = r.kw, min = minKW, priority = priority, rank = 1, x = 0 }
    end
    Tables.sort(list, consumerLess)
    local total, unmet = allocate(availableKW, list, true)
    local out = {}
    for _, c in ipairs(list) do out[c.id] = c.x end
    return { ok = true, allocation = out, total = total, unmet = unmet }
end

------------------------------------------------------------------------------
-- Dispatch internals
------------------------------------------------------------------------------

local function canRun(g)
    return g.mode ~= "off" and g.cond > 0 and g.cap > 0 and g.fuelKWh > g.fuelEps
end

local function batterySupply(m)
    local s = 0
    for _, w in ipairs(m.bats) do s = s + Battery.supplyKW(w) end
    return s
end

-- Unmet electric demand (kW) with the running generators, optionally without
-- `except` or with `extra`.
local function unmetWith(m, except, extra)
    local cap = 0
    for _, g in ipairs(m.gens) do
        if (g.running and g ~= except) or g == extra then cap = cap + g.cap end
    end
    local _, unmet = allocate(m.R + cap + batterySupply(m), m.loads, false)
    return unmet
end

local function socOf(m)
    if m.capTotal <= 0 then return nil end
    local e = 0
    for _, w in ipairs(m.bats) do e = e + w.e end
    return e / m.capTotal
end

local function startReason(m, g, soc)
    if g.mode == "on" then return "manual" end
    if soc ~= nil and soc <= g.policy.startBelow + SOC_TOL then return "reserve_low" end
    local base = unmetWith(m, nil, nil)
    if base > POWER_TOL and unmetWith(m, nil, g) < base - POWER_TOL then return "deficit" end
    return nil
end

local function stopReason(m, g, soc)
    if g.mode == "off" then return "switched_off" end
    if g.cond <= 0 then return "broken" end
    if g.fuelKWh <= g.fuelEps then return "no_fuel" end
    if g.cap <= 0 then return "fuel_unsuitable" end
    if g.mode ~= "auto" then return nil end
    if g.runFor < g.policy.minRunHours - TIME_TOL then return nil end
    if soc ~= nil and soc < g.policy.stopAbove - SOC_TOL then return nil end
    if unmetWith(m, g, nil) > unmetWith(m, nil, nil) + POWER_TOL then return nil end
    return "reserve_restored"
end

-- Applies every state transition due at time t (idempotent).
local function settle(m, t, events)
    for _, w in ipairs(m.bats) do
        for _, kind in ipairs(Battery.settle(w)) do
            events[#events + 1] = { t = t, kind = kind, id = w.id }
        end
    end
    local soc = socOf(m)
    for _, g in ipairs(m.gens) do
        if g.running then
            local why = stopReason(m, g, soc)
            if why ~= nil then
                g.running, g.stopReason = false, why
                events[#events + 1] = { t = t, kind = "generator_stop", id = g.id, reason = why }
            end
        elseif canRun(g) then
            local why = startReason(m, g, soc)
            if why ~= nil then
                g.running, g.runFor, g.stopReason = true, 0, nil
                events[#events + 1] = { t = t, kind = "generator_start", id = g.id, reason = why }
            end
        end
    end
end

-- Constant flows for the current state (steps 1-6 for one sub-step).
local function flows(m)
    local G = 0
    for _, g in ipairs(m.gens) do
        if g.running then G = G + g.cap end
    end
    local D, A = 0, 0
    for _, w in ipairs(m.bats) do
        w.dcap, w.acc = Battery.supplyKW(w), Battery.acceptKW(w)
        D, A = D + w.dcap, A + w.acc
    end
    local served = allocate(m.R + G + D, m.loads, true)
    local uR = math.min(m.R, served)
    local uG = math.min(G, served - uR)
    local uD = Num.clamp(served - uR - uG, 0, D)
    local cR = math.min(A, m.R - uR)
    local cG = math.max(0, math.min(A - cR, G - uG))
    local remC, remD = cR + cG, uD
    for _, w in ipairs(m.bats) do
        w.pIn = math.min(w.acc, remC)
        w.pOut = math.min(w.dcap, remD)
        remC, remD = remC - w.pIn, remD - w.pOut
        w.r, w.leakNow = Battery.rate(w, w.pIn, w.pOut)
    end
    local out = uG + cG
    local H = 0
    for _, g in ipairs(m.gens) do
        if g.running then
            g.p = out * g.cap / G
            g.f = g.idle + g.slope * g.p
            g.h = g.hr * (g.f - g.p)
        else
            g.p, g.f, g.h = 0, 0, 0
        end
        H = H + g.h
    end
    local usedR = uR + cR
    for _, r in ipairs(m.ren) do
        if m.R > 0 then r.used = r.kw * usedR / m.R else r.used = 0 end
    end
    m.H = H
    m.heatUsed = allocate(H, m.heats, true)
end

-- Hours until the next event (or `remaining`).
local function horizon(m, remaining)
    local dt = remaining
    local soc, ds = socOf(m), 0
    for _, w in ipairs(m.bats) do
        dt = math.min(dt, Battery.horizon(w, w.r))
        ds = ds + w.r
    end
    if soc ~= nil then ds = ds / m.capTotal end
    for _, g in ipairs(m.gens) do
        if g.running then
            if g.f > 0 then dt = math.min(dt, g.fuelKWh / g.f) end
            if g.mode == "auto" then
                if g.runFor < g.policy.minRunHours - TIME_TOL then dt = math.min(dt, g.policy.minRunHours - g.runFor) end
                if soc ~= nil and ds > 0 and soc < g.policy.stopAbove - SOC_TOL then
                    dt = math.min(dt, (g.policy.stopAbove - soc) / ds)
                end
            end
        elseif g.mode == "auto" and canRun(g) and soc ~= nil and ds < 0 and soc > g.policy.startBelow + SOC_TOL then
            dt = math.min(dt, (soc - g.policy.startBelow) / -ds)
        end
    end
    return math.max(0, dt)
end

local function newAccumulator(m)
    local acc = { ren = {}, gen = {}, con = {}, bat = {} }
    for _, r in ipairs(m.ren) do acc.ren[r.id] = { availableKWh = 0, usedKWh = 0, curtailedKWh = 0 } end
    for _, g in ipairs(m.gens) do
        acc.gen[g.id] = { electricKWh = 0, fuelKWh = 0, heatKWh = 0, heatUsedKWh = 0, heatUnusedKWh = 0, lossKWh = 0, runHours = 0 }
    end
    for _, c in ipairs(m.loads) do acc.con[c.id] = { demandKWh = 0, servedKWh = 0, unmetKWh = 0, heat = false } end
    for _, c in ipairs(m.heats) do acc.con[c.id] = { demandKWh = 0, servedKWh = 0, unmetKWh = 0, heat = true } end
    for _, w in ipairs(m.bats) do acc.bat[w.id] = Battery.newAccount() end
    return acc
end

local function accumulate(m, acc, dt)
    if dt <= 0 then return end
    for _, r in ipairs(m.ren) do
        local a = acc.ren[r.id]
        a.availableKWh = a.availableKWh + r.kw * dt
        a.usedKWh = a.usedKWh + r.used * dt
        a.curtailedKWh = a.curtailedKWh + (r.kw - r.used) * dt
    end
    local share = 0
    if m.H > 0 then share = m.heatUsed / m.H end
    for _, g in ipairs(m.gens) do
        if g.running then
            local a = acc.gen[g.id]
            a.electricKWh = a.electricKWh + g.p * dt
            a.fuelKWh = a.fuelKWh + g.f * dt
            a.heatKWh = a.heatKWh + g.h * dt
            a.heatUsedKWh = a.heatUsedKWh + g.h * share * dt
            a.heatUnusedKWh = a.heatUnusedKWh + g.h * (1 - share) * dt
            a.lossKWh = a.lossKWh + (g.f - g.p - g.h) * dt
            a.runHours = a.runHours + dt
        end
    end
    for _, list in ipairs({ m.loads, m.heats }) do
        for _, c in ipairs(list) do
            local a = acc.con[c.id]
            a.demandKWh = a.demandKWh + c.kw * dt
            a.servedKWh = a.servedKWh + c.x * dt
            a.unmetKWh = a.unmetKWh + (c.kw - c.x) * dt
        end
    end
    for _, w in ipairs(m.bats) do Battery.account(acc.bat[w.id], w, w.pIn, w.pOut, w.leakNow, dt) end
end

local function advanceState(m, dt)
    for _, w in ipairs(m.bats) do Battery.advance(w, w.r, dt) end
    for _, g in ipairs(m.gens) do
        if g.running then
            g.fuelKWh = math.max(0, g.fuelKWh - g.f * dt)
            g.runFor = g.runFor + dt
        end
    end
end

------------------------------------------------------------------------------
-- Reports
------------------------------------------------------------------------------

-- Network totals from the per-id records of a report (also used after merge).
function Dispatch.totals(r)
    local function sum(map, field, wantHeat)
        local values = {}
        for _, id in ipairs(Tables.sortedKeys(map)) do
            local rec = map[id]
            if wantHeat == nil or (rec.heat == true) == wantHeat then values[#values + 1] = rec[field] end
        end
        return Num.sum(values)
    end
    local t = {}
    t.renewableKWh = sum(r.producers, "availableKWh")
    t.curtailedKWh = sum(r.producers, "curtailedKWh")
    t.fuelKWh = sum(r.generators, "fuelKWh")
    t.generatedKWh = sum(r.generators, "electricKWh")
    t.recoveredHeatKWh = sum(r.generators, "heatKWh")
    t.heatUnusedKWh = sum(r.generators, "heatUnusedKWh")
    t.generatorLossKWh = sum(r.generators, "lossKWh")
    t.electricDemandKWh = sum(r.consumers, "demandKWh", false)
    t.electricKWh = sum(r.consumers, "servedKWh", false)
    t.unmetKWh = sum(r.consumers, "unmetKWh", false)
    t.heatDemandKWh = sum(r.consumers, "demandKWh", true)
    t.heatKWh = sum(r.consumers, "servedKWh", true)
    t.unmetHeatKWh = sum(r.consumers, "unmetKWh", true)
    t.chargedKWh = sum(r.batteries, "chargedKWh")
    t.dischargedKWh = sum(r.batteries, "dischargedKWh")
    t.selfDischargeKWh = sum(r.batteries, "selfDischargeKWh")
    t.batteryLossKWh = sum(r.batteries, "chargeLossKWh") + sum(r.batteries, "dischargeLossKWh")
    local deltas = {}
    for _, id in ipairs(Tables.sortedKeys(r.batteries)) do
        deltas[#deltas + 1] = r.batteries[id].e1 - r.batteries[id].e0
    end
    t.storedDeltaKWh = Num.sum(deltas)
    t.energyInKWh = t.renewableKWh + t.fuelKWh
    t.deliveredKWh = t.electricKWh + t.heatKWh
    t.lossesKWh = Num.sum({ t.batteryLossKWh, t.selfDischargeKWh, t.generatorLossKWh, t.heatUnusedKWh })
    return t
end

local function buildReport(m, acc, events, t0, t1)
    local r = {
        t0 = t0, t1 = t1, hours = t1 - t0, producers = {}, generators = {}, consumers = {},
        batteries = {}, fuelUsed = {}, events = events,
    }
    for _, x in ipairs(m.ren) do r.producers[x.id] = acc.ren[x.id] end
    for _, g in ipairs(m.gens) do
        local a = acc.gen[g.id]
        a.fuel, a.owner, a.running, a.stopReason, a.fuelUnits = g.fuel, g.owner, g.running, g.stopReason, 0
        if g.energyMJ ~= nil and a.fuelKWh > 0 then
            a.fuelUnits = math.min(g.amount, Gen.units(a.fuelKWh, g.energyMJ))
            r.fuelUsed[g.id] = { fuel = g.fuel, amount = a.fuelUnits, owner = g.owner }
        end
        r.generators[g.id] = a
    end
    for _, id in ipairs(Tables.sortedKeys(acc.con)) do r.consumers[id] = acc.con[id] end
    for _, w in ipairs(m.bats) do
        local a = acc.bat[w.id]
        a.e0, a.e1, a.lvd = w.e0, w.e, w.lvd
        r.batteries[w.id] = a
    end
    r.totals = Dispatch.totals(r)
    return r
end

-- Fields that take the later interval's value when reports are merged.
local LAST = { e1 = true, lvd = true, running = true, stopReason = true, fuel = true, owner = true, heat = true }

local function mergeMap(a, b)
    local out = {}
    for _, id in ipairs(Tables.sortedKeys(a)) do out[id] = Tables.copy(a[id]) end
    for _, id in ipairs(Tables.sortedKeys(b)) do
        local src, dst = b[id], out[id]
        if dst == nil then
            out[id] = Tables.copy(src)
        else
            for _, k in ipairs(Tables.sortedKeys(src)) do
                local v = src[k]
                if k ~= "e0" and not LAST[k] and type(v) == "number" and type(dst[k]) == "number" then
                    dst[k] = dst[k] + v
                elseif k ~= "e0" then
                    dst[k] = v
                end
            end
            for k in pairs(LAST) do dst[k] = src[k] end
        end
    end
    return out
end

-- Report of [a.t0, b.t1] from consecutive reports a and b.
function Dispatch.merge(a, b)
    local r = { t0 = a.t0, t1 = b.t1, hours = a.hours + b.hours }
    r.producers = mergeMap(a.producers, b.producers)
    r.generators = mergeMap(a.generators, b.generators)
    r.consumers = mergeMap(a.consumers, b.consumers)
    r.batteries = mergeMap(a.batteries, b.batteries)
    r.fuelUsed = mergeMap(a.fuelUsed, b.fuelUsed)
    r.events = {}
    for _, e in ipairs(a.events) do r.events[#r.events + 1] = e end
    for _, e in ipairs(b.events) do r.events[#r.events + 1] = e end
    r.totals = Dispatch.totals(r)
    return r
end

------------------------------------------------------------------------------
-- EnergyService.dispatch
------------------------------------------------------------------------------

local function finish(network, m, t1)
    local out = Tables.deepCopy(network)
    out.t = t1
    for _, w in ipairs(m.bats) do
        local b = out.batteries[w.id]
        b.e, b.lvd = w.e, w.lvd
    end
    for _, g in ipairs(m.gens) do
        local p = out.producers[g.id]
        p.running, p.runFor, p.stopReason = g.running, g.runFor, g.stopReason
    end
    return out
end

function Dispatch.dispatch(network, interval, producerState, demand)
    if type(network) ~= "table" or not Num.isFinite(network.t) then return fail("invalid_network") end
    if type(interval) ~= "table" or not Num.isFinite(interval.t0) or not Num.isFinite(interval.t1) then
        return fail("invalid_interval")
    end
    local t0, t1 = interval.t0, interval.t1
    if math.abs(t0 - network.t) > TIME_TOL * math.max(1, math.abs(t0)) then return fail("time_mismatch") end
    if t1 < t0 then return fail("clock_regression") end
    local m, why = prepare(network, producerState or {}, demand or {})
    if m == nil then return fail(why) end
    local acc = newAccumulator(m)
    local events = {}
    local t = t0
    settle(m, t, events)
    local guard = 0
    while t < t1 do
        guard = guard + 1
        if guard > Dispatch.MAX_STEPS then return fail("did_not_converge") end
        flows(m)
        local remaining = t1 - t
        local dt = horizon(m, remaining)
        local last = dt >= remaining
        if last then dt = remaining end
        accumulate(m, acc, dt)
        advanceState(m, dt)
        if last then t = t1 else t = t + dt end
        settle(m, t, events)
    end
    return { ok = true, network = finish(network, m, t1), report = buildReport(m, acc, events, t0, t1) }
end

------------------------------------------------------------------------------
-- Grid-stepped catch-up (unloaded simulation)
------------------------------------------------------------------------------

local function emptyReport(t0, t1)
    local r = { t0 = t0, t1 = t1, hours = t1 - t0, producers = {}, generators = {}, consumers = {}, batteries = {},
        fuelUsed = {}, events = {} }
    r.totals = Dispatch.totals(r)
    return r
end

-- Dispatch.advance(network, toT, ctx) dispatches cell by cell on a fixed grid
-- (Generation.steps), computing renewable availability per cell with the
-- generation models, so time-varying inputs stay split-invariant.
--   ctx.origin      { dayOfYear, hourOfDay } at world hour 0
--   ctx.stepHours   grid cell length (default 1)
--   ctx.weather     table or function(step) -> { cloud, snow, windMS }
--   ctx.demand      table or function(step) -> demand
--   ctx.fuel        { [generatorId] = { fuel, amount, energyMJ, powerFactor } }
--   ctx.latitude, ctx.solarNoon   optional site overrides
-- Returns { ok, network, report, fuel = remaining fuel per generator }. The
-- caller (consumption owner) applies report.fuelUsed once.
function Dispatch.advance(network, toT, ctx)
    ctx = ctx or {}
    if type(network) ~= "table" or not Num.isFinite(network.t) or type(network.producers) ~= "table" then
        return fail("invalid_network")
    end
    if not Num.isFinite(toT) then return fail("invalid_interval") end
    if toT < network.t then return fail("clock_regression") end
    local stepHours = ctx.stepHours == nil and 1 or ctx.stepHours
    if not positive(stepHours) then return fail("invalid_step") end
    local origin = ctx.origin or Dispatch.DEFAULT_ORIGIN
    if Gen.stepCount(network.t, toT, stepHours) > Dispatch.MAX_GRID_STEPS then return fail("too_many_steps") end
    if ctx.fuel ~= nil and type(ctx.fuel) ~= "table" then return fail("invalid_producer_state") end
    local fuel = Tables.deepCopy(ctx.fuel or {})
    local net, total = network, nil
    for _, st in ipairs(Gen.steps(network.t, toT, origin, stepHours)) do
        local weather = ctx.weather
        if type(weather) == "function" then weather = weather(st) end
        weather = weather or {}
        local ps = {}
        for _, id in ipairs(Tables.sortedKeys(net.producers)) do
            local p = net.producers[id]
            local def = Gen.def(p.def)
            if def == nil then return fail("unknown_producer_def") end
            if def.energy == "fueled" then
                if fuel[id] ~= nil then ps[id] = fuel[id] end
            else
                local kw, why = Gen.availableKW(def, p, {
                    dayOfYear = st.dayOfYear, hourOfDay = st.hourOfDay, month = st.month, cloud = weather.cloud,
                    snow = weather.snow, windMS = weather.windMS, latitude = ctx.latitude, solarNoon = ctx.solarNoon,
                })
                if kw == nil then return fail(why) end
                ps[id] = { kw = kw }
            end
        end
        for _, id in ipairs(Tables.sortedKeys(fuel)) do
            if net.producers[id] == nil then return fail("unknown_producer") end
        end
        local dem = ctx.demand
        if type(dem) == "function" then dem = dem(st) end
        local r = Dispatch.dispatch(net, { t0 = st.t0, t1 = st.t1 }, ps, dem or {})
        if not r.ok then return r end
        net = r.network
        if total == nil then total = r.report else total = Dispatch.merge(total, r.report) end
        for _, id in ipairs(Tables.sortedKeys(r.report.fuelUsed)) do
            local f = Tables.copy(fuel[id])
            f.amount = math.max(0, f.amount - r.report.fuelUsed[id].amount)
            fuel[id] = f
        end
    end
    if total == nil then
        net = Tables.deepCopy(network)
        total = emptyReport(network.t, toT)
    end
    return { ok = true, network = net, report = total, fuel = fuel }
end

------------------------------------------------------------------------------
-- Contract alias (spec §4 "EnergyService.dispatch")
------------------------------------------------------------------------------

TLG.EnergyService = TLG.EnergyService or {}
local EnergyService = TLG.EnergyService
EnergyService.dispatch = Dispatch.dispatch
EnergyService.advance = Dispatch.advance
EnergyService.graph = Dispatch.graph
EnergyService.component = Dispatch.component
EnergyService.network = Dispatch.network
EnergyService.allocate = Dispatch.allocate

return Dispatch
