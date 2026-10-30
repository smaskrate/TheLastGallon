-- Battery storage for electricity networks (spec §12; §6 rule 13 "battery
-- round trips lose usable energy").
--
-- Record (persistent; also usable directly as a topology node):
--   { v, kind = "battery", id, def, e, cond, lvd }
--   e     usable stored energy in kWh, always within [0, capacity]
--   cond  condition 0..1; usable capacity = def.capacityKWh * cond
--   lvd   low-voltage disconnect latch: set when the battery runs empty,
--         cleared when e reaches reconnectFraction * capacity
--
-- Definition (MachineDefinition with energy = "battery", TLG/Content/Energy):
--   capacityKWh                    usable capacity at full condition
--   maxChargeKW, maxDischargeKW    grid-side power limits
--   etaCharge, etaDischarge        separate efficiencies, product < 1
--   selfDischargePerHour           fraction of capacity lost per hour
--   reconnectFraction              lvd hysteresis, in (0, 1)
--
-- All flows are grid-side kW. With constant flows the stored energy is linear
-- in time:
--   de/dt = etaCharge * pIn - pOut / etaDischarge - leak
--   leak  = selfDischargePerHour * capacity  (only while e > 0)
-- so every regime change (full, empty, reconnect) has a closed-form time and
-- one long run equals many short ones up to floating-point rounding.
-- Boundary regimes:
--   full   accepts only the float power that offsets self-discharge
--   empty  no discharge until reconnect (lvd); self-discharge never takes e
--          below zero (it consumes at most the incoming charge)
require "TLG/Registry/Registry"
require "TLG/Util/Num"
require "TLG/Util/Tables"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Energy = TLG.Domain.Energy or {}
TLG.Domain.Energy.Battery = TLG.Domain.Energy.Battery or {}
local Battery = TLG.Domain.Energy.Battery
local Registry, Num, Tables = TLG.Registry, TLG.Num, TLG.Tables

Battery.SCHEMA = 1
Battery.MAX_STEPS = 100000

local function fail(reason) return { ok = false, reason = reason } end
local function positive(v) return Num.isFinite(v) and v > 0 end
local function nonneg(v) return Num.isFinite(v) and v >= 0 end
local function unit(v) return Num.isFinite(v) and v >= 0 and v <= 1 end

-- Energy tolerance (kWh) of the full/empty regimes. It only absorbs rounding
-- at an event; it is far below any quantity a player can observe.
function Battery.eps(cap)
    return 1e-12 * math.max(1, cap)
end

-- Definition problems (used by the registry validator and by tests).
function Battery.problems(def)
    local out = {}
    local function bad(msg) out[#out + 1] = msg end
    if not positive(def.capacityKWh) then bad("battery needs positive capacityKWh") end
    if not positive(def.maxChargeKW) then bad("battery needs positive maxChargeKW") end
    if not positive(def.maxDischargeKW) then bad("battery needs positive maxDischargeKW") end
    local ec, ed = def.etaCharge, def.etaDischarge
    if not (positive(ec) and ec <= 1) then bad("etaCharge must be in (0,1]") end
    if not (positive(ed) and ed <= 1) then bad("etaDischarge must be in (0,1]") end
    if positive(ec) and positive(ed) and ec * ed >= 1 then
        bad("round trip must lose energy (etaCharge * etaDischarge < 1)")
    end
    if not (nonneg(def.selfDischargePerHour) and def.selfDischargePerHour < 0.01) then
        bad("selfDischargePerHour must be in [0, 0.01)")
    elseif positive(def.maxChargeKW) and positive(ec) and positive(def.capacityKWh) and
        def.maxChargeKW * ec <= def.selfDischargePerHour * def.capacityKWh then
        bad("charging cannot outrun self-discharge (battery could never become full)")
    end
    if not (positive(def.reconnectFraction) and def.reconnectFraction < 1) then
        bad("reconnectFraction must be in (0,1)")
    end
    return out
end

Registry.addValidator("machine", function(def, problem)
    if def.energy ~= "battery" then return end
    for _, msg in ipairs(Battery.problems(def)) do problem(msg) end
end)

function Battery.def(id)
    local def = Registry.get("machine", id)
    if def ~= nil and def.energy == "battery" then return def end
    return nil
end

function Battery.new(o)
    local e = o.e or 0
    return {
        v = Battery.SCHEMA, kind = "battery", id = o.id, def = o.def, e = e,
        cond = o.cond == nil and 1 or o.cond, lvd = (o.lvd == true) or e <= 0,
    }
end

function Battery.capacity(b, def)
    def = def or Battery.def(b.def)
    return def.capacityKWh * (b.cond == nil and 1 or b.cond)
end

function Battery.soc(b, def)
    local cap = Battery.capacity(b, def)
    if cap <= 0 then return 0 end
    return b.e / cap
end

-- Validates a battery record. Returns def, capacity or nil, reason.
function Battery.check(b)
    if type(b) ~= "table" or type(b.id) ~= "string" then return nil, "invalid_battery" end
    local def = Battery.def(b.def)
    if def == nil then return nil, "unknown_battery_def" end
    local cond = b.cond == nil and 1 or b.cond
    if not unit(cond) then return nil, "invalid_battery" end
    local cap = def.capacityKWh * cond
    local eps = Battery.eps(cap)
    if not Num.isFinite(b.e) or b.e < -eps or b.e > cap + eps then return nil, "invalid_battery" end
    return def, cap
end

-- Working view used by the integrators (never persisted, owned by the caller).
function Battery.view(b, def, cap)
    local e = Num.clamp(b.e, 0, cap)
    local eps = Battery.eps(cap)
    return {
        id = b.id, def = def, cap = cap, e = e, eps = eps,
        lvd = (b.lvd == true) or e <= eps,
        full = cap > 0 and e >= cap - eps,
        leak = def.selfDischargePerHour * cap,
        rc = def.reconnectFraction * cap,
        etaC = def.etaCharge, etaD = def.etaDischarge,
        maxC = def.maxChargeKW, maxD = def.maxDischargeKW,
    }
end

-- Grid-side charge acceptance (kW). A full battery takes only float power.
function Battery.acceptKW(w)
    if w.cap <= 0 then return 0 end
    if w.e >= w.cap - w.eps then return math.min(w.maxC, w.leak / w.etaC) end
    return w.maxC
end

-- Grid-side discharge capability (kW).
function Battery.supplyKW(w)
    if w.cap <= 0 or w.lvd or w.e <= w.eps then return 0 end
    return w.maxD
end

-- Stored-side rate (kWh per hour) and the self-discharge actually incurred
-- (kW) for constant grid-side flows.
function Battery.rate(w, pIn, pOut)
    local gain = w.etaC * pIn
    local draw = pOut / w.etaD
    if w.e <= w.eps and draw <= 0 then
        local leak = math.min(w.leak, gain)
        return gain - leak, leak
    end
    return gain - draw - w.leak, w.leak
end

-- Hours until the next regime change at stored-side rate r (math.huge: none).
-- Always strictly positive, so integrators make progress.
function Battery.horizon(w, r)
    local best = math.huge
    if r > 0 then
        if w.e < w.cap - w.eps then best = (w.cap - w.e) / r end
        if w.lvd and w.e < w.rc - w.eps then best = math.min(best, (w.rc - w.e) / r) end
    elseif r < 0 and w.e > w.eps then
        best = w.e / -r
    end
    return best
end

function Battery.advance(w, r, dt)
    w.e = Num.clamp(w.e + r * dt, 0, w.cap)
end

-- Latches regime flags after an advance; returns the list of event kinds.
function Battery.settle(w)
    local events = {}
    local full = w.cap > 0 and w.e >= w.cap - w.eps
    if full and not w.full then events[#events + 1] = "battery_full" end
    w.full = full
    if w.e <= w.eps then
        if not w.lvd then
            w.lvd = true
            events[#events + 1] = "battery_empty"
        end
    elseif w.lvd and w.e >= w.rc - w.eps then
        w.lvd = false
        events[#events + 1] = "battery_reconnect"
    end
    return events
end

-- Adds one constant-flow step to an accounting table (kWh).
function Battery.account(acc, w, pIn, pOut, leak, dt)
    acc.chargedKWh = acc.chargedKWh + pIn * dt
    acc.dischargedKWh = acc.dischargedKWh + pOut * dt
    acc.chargeLossKWh = acc.chargeLossKWh + (1 - w.etaC) * pIn * dt
    acc.dischargeLossKWh = acc.dischargeLossKWh + pOut * (1 / w.etaD - 1) * dt
    acc.selfDischargeKWh = acc.selfDischargeKWh + leak * dt
end

function Battery.newAccount()
    return { chargedKWh = 0, dischargedKWh = 0, chargeLossKWh = 0, dischargeLossKWh = 0, selfDischargeKWh = 0 }
end

-- Battery.run(b, pIn, pOut, hours): a stand-alone battery (charger, vehicle)
-- offered a constant grid-side charge pIn or asked for a constant discharge
-- pOut (kW) for `hours`, saturating at the power limits and at full/empty.
-- Returns { ok, battery, chargedKWh, dischargedKWh, chargeLossKWh,
-- dischargeLossKWh, selfDischargeKWh, rejectedKWh, unmetKWh, events } with
--   chargedKWh - dischargedKWh = (e1 - e0) + chargeLoss + dischargeLoss + selfDischarge
function Battery.run(b, pIn, pOut, hours)
    local def, cap = Battery.check(b)
    if def == nil then return fail(cap) end
    pIn, pOut = pIn or 0, pOut or 0
    if not nonneg(pIn) or not nonneg(pOut) then return fail("invalid_power") end
    if pIn > 0 and pOut > 0 then return fail("charge_and_discharge") end
    if not nonneg(hours) then return fail("invalid_interval") end
    local w = Battery.view(b, def, cap)
    local acc = Battery.newAccount()
    acc.rejectedKWh, acc.unmetKWh = 0, 0
    local events = {}
    local t, guard = 0, 0
    while t < hours do
        guard = guard + 1
        if guard > Battery.MAX_STEPS then return fail("did_not_converge") end
        local inNow = math.min(pIn, Battery.acceptKW(w))
        local outNow = math.min(pOut, Battery.supplyKW(w))
        local r, leak = Battery.rate(w, inNow, outNow)
        local remaining = hours - t
        local dt = Battery.horizon(w, r)
        local last = dt >= remaining
        if last then dt = remaining end
        Battery.account(acc, w, inNow, outNow, leak, dt)
        acc.rejectedKWh = acc.rejectedKWh + (pIn - inNow) * dt
        acc.unmetKWh = acc.unmetKWh + (pOut - outNow) * dt
        Battery.advance(w, r, dt)
        if last then t = hours else t = t + dt end
        for _, kind in ipairs(Battery.settle(w)) do
            events[#events + 1] = { t = t, kind = kind, id = b.id }
        end
    end
    local out = Tables.deepCopy(b)
    out.e, out.lvd = w.e, w.lvd
    acc.ok, acc.battery, acc.events = true, out, events
    return acc
end

-- Condition change (wear, repair). Energy above the new capacity is lost and
-- reported; it never reappears when the condition is restored.
function Battery.withCondition(b, cond)
    local def, cap = Battery.check(b)
    if def == nil then return fail(cap) end
    if not unit(cond) then return fail("invalid_condition") end
    local out = Tables.deepCopy(b)
    local newCap = def.capacityKWh * cond
    local lost = math.max(0, math.min(b.e, cap) - newCap)
    out.cond = cond
    out.e = Num.clamp(b.e, 0, newCap)
    if out.e <= Battery.eps(newCap) then out.lvd = true end
    return { ok = true, battery = out, lostKWh = lost }
end

return Battery
