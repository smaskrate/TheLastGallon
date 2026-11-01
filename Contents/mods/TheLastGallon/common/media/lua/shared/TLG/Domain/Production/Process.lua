-- Shared production framework (spec §9): ProductionService.plan / advance.
--
-- States and transitions (anything else is rejected):
--   Ready          -> InputsReserved (load)            -> Maintenance (service)
--   InputsReserved -> Processing (start)               -> Ready (unload)
--   Processing     -> Paused (resource missing/pause)  -> OutputReady (last stage done)
--                  -> Faulted (condition exhausted)
--   Paused         -> Processing (resources back/resume) -> Ready (abort, partial result)
--   OutputReady    -> Ready (outputs fully collected)
--   Faulted        -> Maintenance (repair)             Maintenance -> Ready (service done)
--   any idle state -> Decommissioned (removal; only when empty)
--
-- Active processes keep an immutable parameter snapshot of their recipe
-- (with fingerprint), so balance updates never reinterpret half-processed
-- inputs. Advancement is event-based over climate segments: stage completions,
-- firebox exhaustion and spoilage happen at exact times, so one large advance
-- equals many small ones; outputs are produced exactly once into a bounded
-- buffer and are only removed by explicit collection.
require "TLG/Registry/Registry"
require "TLG/Util/Tables"
require "TLG/Util/Num"
require "TLG/Domain/Climate"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Process = TLG.Domain.Process or {}
local Process = TLG.Domain.Process
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

Process.SCHEMA = 1
Process.STATES = {
    Ready = true, InputsReserved = true, Processing = true, Paused = true,
    OutputReady = true, Faulted = true, Maintenance = true, Decommissioned = true,
}
-- Converters turn reserved inputs into outputs. They are versioned with the
-- recipe; a converter change must bump RecipeDefinition.version.
Process.converters = Process.converters or {}

Registry.addValidator("machine", function(def, problem)
    -- Production machines carry a kind (fermenter, still, ...); energy devices
    -- registered as machines carry energy instead (TLG/Content/Energy.lua).
    if type(def.kind) ~= "string" and type(def.energy) ~= "string" then problem("machine needs kind or energy role") end
    if def.capacity ~= nil and not (Num.isFinite(def.capacity) and def.capacity > 0) then problem("invalid capacity") end
    if def.outputCapacity ~= nil and not (Num.isFinite(def.outputCapacity) and def.outputCapacity > 0) then
        problem("invalid outputCapacity")
    end
    if def.firebox and not (def.firebox.capacityKg > 0 and def.firebox.kwhPerKg > 0 and def.firebox.efficiency > 0) then
        problem("invalid firebox")
    end
    if def.wearPerBatch ~= nil and (def.wearPerBatch < 0 or def.wearPerBatch > 1) then problem("invalid wearPerBatch") end
end)

Registry.addValidator("recipe", function(def, problem)
    if type(def.version) ~= "number" then problem("recipe needs numeric version") end
    local machineOk = false
    for _, mid in ipairs(def.machines or {}) do
        if Registry.get("machine", mid) == nil then problem("unknown machine " .. tostring(mid)) else machineOk = true end
    end
    if not machineOk then problem("recipe has no valid machine") end
    if Process.converters[def.converter] == nil then problem("unknown converter " .. tostring(def.converter)) end
    if type(def.stages) ~= "table" or #def.stages == 0 then problem("recipe needs stages") end
    for i, st in ipairs(def.stages or {}) do
        if not (Num.isFinite(st.hours) and st.hours > 0) and not st.hoursFrom then
            problem("stage " .. i .. " needs positive hours")
        end
    end
    for id, b in pairs(def.inputs or {}) do
        if Registry.get("fuel", id) == nil then problem("unknown input " .. tostring(id)) end
        if b.min ~= nil and b.max ~= nil and b.min > b.max then problem("impossible bounds for " .. id) end
        if b.min ~= nil and b.min < 0 then problem("negative min for " .. id) end
    end
    for k, v in pairs(def.params or {}) do
        if type(v) == "number" and k:find("[Yy]ield") and v < 0 then problem("negative yield " .. k) end
    end
end)

function Process.new(o)
    local m = Registry.need("machine", o.machine)
    return {
        v = Process.SCHEMA, id = o.id, rev = 0, machine = m.id, state = "Ready",
        recipe = nil, stage = 0, stageDone = 0, inputs = {}, outputs = {}, outProps = {},
        firebox = 0, pause = nil, pausedFor = 0, cond = o.cond or 1, batches = 0,
        t = o.t or 0, skill = 0,
    }
end

local function fail(reason) return { ok = false, reason = reason } end

local function sumTable(t)
    local s = 0
    for _, k in ipairs(Tables.sortedKeys(t)) do s = s + t[k] end
    return s
end

-- Immutable snapshot of the recipe parameters used for one batch.
function Process.snapshot(recipeId)
    local def = Registry.need("recipe", recipeId)
    local snap = Tables.deepCopy(def)
    snap.registryKind = nil
    return { id = def.id, version = def.version, fp = Registry.fingerprint("recipe", def.id), params = snap }
end

-- ProductionService.plan(recipeId, inputs, machineState): validates a batch
-- without changing anything. Returns { ok, reason, inputs, expected }.
function Process.plan(recipeId, inputs, proc)
    local def = Registry.get("recipe", recipeId)
    if def == nil then return fail("unknown_recipe") end
    local m = Registry.need("machine", proc.machine)
    if not Tables.contains(def.machines, m.id) then return fail("wrong_machine") end
    if proc.state ~= "Ready" then return fail("machine_busy") end
    if proc.cond <= 0 then return fail("needs_repair") end
    -- Deterministic order so the first reported problem never depends on pairs().
    for _, id in ipairs(Tables.sortedKeys(inputs)) do
        if def.inputs[id] == nil then return fail("ineligible_" .. id) end
        if not Num.isFinite(inputs[id]) or inputs[id] < 0 then return fail("invalid_" .. id) end
    end
    for _, id in ipairs(Tables.sortedKeys(def.inputs)) do
        local b = def.inputs[id]
        local q = inputs[id] or 0
        if b.min and q < b.min - 1e-9 then return fail("not_enough_" .. id) end
        if b.max and q > b.max + 1e-9 then return fail("too_much_" .. id) end
    end
    if m.capacity and sumTable(inputs) > m.capacity + 1e-9 then return fail("over_capacity") end
    local expected = Process.converters[def.converter](inputs, def.params or {}, m, 1)
    -- Finished output must fit the machine's output buffer (validated field).
    if m.outputCapacity and sumTable(expected.outputs or {}) > m.outputCapacity + 1e-9 then
        return fail("output_capacity")
    end
    return { ok = true, inputs = Tables.copy(inputs), expected = expected }
end

-- Ready -> InputsReserved. Inputs become owned by the machine.
function Process.load(proc, recipeId, inputs, skill)
    -- Continuous (stream) recipes are validated with plan() but run by their own
    -- runtime (e.g. TLG.Domain.Gas.Gasifier), never loaded as a batch.
    local def = Registry.get("recipe", recipeId)
    if def and def.stream then return fail("stream_recipe") end
    local p = Process.plan(recipeId, inputs, proc)
    if not p.ok then return p end
    local out = Tables.deepCopy(proc)
    out.state = "InputsReserved"
    out.recipe = Process.snapshot(recipeId)
    out.inputs = Tables.copy(inputs)
    out.stage, out.stageDone, out.pause, out.pausedFor = 0, 0, nil, 0
    out.skill = Num.clamp(skill or 0, 0, 10)
    return { ok = true, proc = out, expected = p.expected }
end

-- InputsReserved -> Ready, returning the inputs.
function Process.unload(proc)
    if proc.state ~= "InputsReserved" then return fail("not_loaded") end
    local out = Tables.deepCopy(proc)
    local returned = out.inputs
    out.inputs, out.recipe, out.state = {}, nil, "Ready"
    return { ok = true, proc = out, returned = returned }
end

function Process.addFirebox(proc, kg)
    local m = Registry.need("machine", proc.machine)
    if not m.firebox then return fail("no_firebox") end
    if kg <= 0 then return fail("invalid_amount") end
    local out = Tables.deepCopy(proc)
    local room = m.firebox.capacityKg - out.firebox
    local used = math.min(room, kg)
    if used <= 0 then return fail("firebox_full") end
    out.firebox = out.firebox + used
    return { ok = true, proc = out, used = used }
end

function Process.start(proc, now)
    if proc.state ~= "InputsReserved" then return fail("not_loaded") end
    if math.abs(now - proc.t) > 1e-6 and now < proc.t then return fail("time_regression") end
    local out = Tables.deepCopy(proc)
    out.state, out.stage, out.stageDone, out.t = "Processing", 1, 0, now
    out.startedAt = now
    return { ok = true, proc = out }
end

function Process.pauseCmd(proc)
    if proc.state ~= "Processing" then return fail("not_processing") end
    local out = Tables.deepCopy(proc)
    out.state, out.pause = "Paused", "paused_by_player"
    out.manualPause = true
    return { ok = true, proc = out }
end

function Process.resumeCmd(proc)
    if proc.state ~= "Paused" then return fail("not_paused") end
    local out = Tables.deepCopy(proc)
    out.manualPause = nil
    out.state, out.pause = "Processing", nil
    return { ok = true, proc = out }
end

-- Stage duration in hours for this batch.
local function stageHours(proc, st)
    local h = st.hours
    if st.hoursFrom then
        local m = Registry.need("machine", proc.machine)
        local amount = sumTable(proc.inputs)
        h = math.max(st.minHours or 0.5, amount / (m[st.hoursFrom] or 1))
    end
    -- Skill shortens labour-bound stages (up to 25% at skill 10).
    if st.labor then h = h * (1 - 0.025 * (proc.skill or 0)) end
    return h
end

-- Progress rate in a segment and the pause reason when the rate is zero.
local function stageRate(proc, st, seg, m)
    if st.heatKW and st.heatKW > 0 then
        if not m.firebox or proc.firebox <= 1e-9 then return 0, "no_heat" end
    end
    if st.tempMin and seg.tempC < st.tempMin then return 0, "too_cold" end
    if st.tempMax and seg.tempC > st.tempMax then return 0, "too_hot" end
    if st.slowBelow and seg.tempC < st.slowBelow then return st.slowRate or 0.4, nil end
    if st.slowAbove and seg.tempC > st.slowAbove then return st.slowRate or 0.4, nil end
    return 1, nil
end

local function completeBatch(out, m)
    local params = out.recipe.params
    local conv = Process.converters[params.converter]
    local eff = 1 - 0.3 * (1 - out.cond)
    local produced = conv(out.inputs, params.params or {}, m, eff, out.skill)
    out.outputs = produced.outputs
    out.outProps = produced.props or {}
    out.byproducts = produced.byproducts
    out.inputs = {}
    out.state = "OutputReady"
    out.pause = nil
    out.batches = out.batches + 1
    out.cond = math.max(0, out.cond - (m.wearPerBatch or 0))
    out.completedAt = out.t
end

-- Where the machine stands, for the climate model (D-021): nil until an
-- adapter records proc.site = { room, z }; proc.temps = { [hour] = tempC }
-- are readings taken there and proc.fires = { [hour] = note or false } the
-- notes of the fire warming it (D-022, Climate.siteDayMean). Without a site
-- the definition's thermal exposure applies.
function Process.site(proc)
    if proc.site == nil then return nil end
    return { room = proc.site.room == true, z = proc.site.z or 0, temps = proc.temps, fires = proc.fires,
        from = proc.startedAt }
end

-- ProductionService.advance(process, resources, interval).
-- env: Climate instance (segments by the machine's site or thermal exposure).
function Process.advance(proc, toT, env)
    local out = Tables.deepCopy(proc)
    local info = { events = {}, heatKWh = 0, fireboxBurned = 0 }
    if toT <= out.t then return out, info end
    if out.state ~= "Processing" and out.state ~= "Paused" then
        out.t = toT
        return out, info
    end
    local m = Registry.need("machine", out.machine)
    local segs = env:segments(out.t, toT, m.thermal or "sheltered", Process.site(out))
    local guard = 0
    for _, seg in ipairs(segs) do
        local t = seg.t0
        while t < seg.t1 - 1e-12 and (out.state == "Processing" or out.state == "Paused") do
            guard = guard + 1
            if guard > 10000 then error("process advance did not converge") end
            local params = out.recipe.params
            local st = params.stages[out.stage]
            local rate, why = stageRate(out, st, seg, m)
            if out.manualPause then rate, why = 0, "paused_by_player" end
            local span = seg.t1 - t
            local burnPerHour = 0
            if rate > 0 and st.heatKW and st.heatKW > 0 then
                burnPerHour = st.heatKW / (m.firebox.kwhPerKg * m.firebox.efficiency)
            end
            if rate <= 0 then
                -- Paused for the rest of the segment (spoilage clock runs).
                if out.state ~= "Paused" then
                    out.state, out.pause = "Paused", why
                    info.events[#info.events + 1] = { t = t, kind = "paused", reason = why }
                end
                out.pause = why
                local limit = st.maxPauseHours
                if limit and out.pausedFor + span >= limit then
                    local dt = limit - out.pausedFor
                    out.pausedFor = limit
                    t = t + dt
                    out.t = t
                    out.state, out.pause = "Faulted", "batch_spoiled"
                    out.spoiled = out.inputs
                    out.inputs = {}
                    info.events[#info.events + 1] = { t = t, kind = "spoiled" }
                    break
                end
                out.pausedFor = out.pausedFor + span
                t = seg.t1
            else
                if out.state == "Paused" then
                    out.state, out.pause = "Processing", nil
                    info.events[#info.events + 1] = { t = t, kind = "resumed" }
                end
                local need = (stageHours(out, st) - out.stageDone) / rate
                local untilEmpty = math.huge
                if burnPerHour > 0 then untilEmpty = out.firebox / burnPerHour end
                local dt = math.min(span, need, untilEmpty)
                out.stageDone = out.stageDone + dt * rate
                if burnPerHour > 0 then
                    local burned = math.min(out.firebox, dt * burnPerHour)
                    out.firebox = out.firebox - burned
                    info.fireboxBurned = info.fireboxBurned + burned
                    info.heatKWh = info.heatKWh + dt * st.heatKW
                end
                t = t + dt
                out.t = t
                if dt >= need - 1e-12 then
                    info.events[#info.events + 1] = { t = t, kind = "stage_done", stage = st.id }
                    if out.stage >= #params.stages then
                        completeBatch(out, m)
                        info.events[#info.events + 1] = { t = t, kind = "completed" }
                    else
                        out.stage, out.stageDone = out.stage + 1, 0
                    end
                elseif dt >= untilEmpty - 1e-12 then
                    out.firebox = 0
                end
            end
        end
        if out.state ~= "Processing" and out.state ~= "Paused" then break end
    end
    out.t = toT
    return out, info
end

-- Collect up to `room` units of outputs (OutputReady -> Ready when empty).
-- Returns the collected parcel; never emits more than was produced.
function Process.collect(proc, room)
    if proc.state ~= "OutputReady" then return fail("nothing_ready") end
    local out = Tables.deepCopy(proc)
    local total = sumTable(out.outputs)
    local take = math.min(room, total)
    if take <= 0 then return fail("output_full") end
    local parcel = {}
    local frac = take / total
    for _, id in ipairs(Tables.sortedKeys(out.outputs)) do
        local q = (take >= total - 1e-12) and out.outputs[id] or out.outputs[id] * frac
        parcel[id] = q
        out.outputs[id] = out.outputs[id] - q
        if out.outputs[id] <= Num.DUST then out.outputs[id] = nil end
    end
    if Tables.isEmpty(out.outputs) then
        out.state, out.recipe, out.outProps = "Ready", nil, {}
    else
        out.pause = "output_full"
    end
    return { ok = true, proc = out, parcel = parcel, props = proc.outProps, byproducts = (Tables.isEmpty(out.outputs) and proc.byproducts) or nil }
end

-- Abort a paused/processing batch: the partial result is returned explicitly.
function Process.abort(proc)
    if proc.state ~= "Processing" and proc.state ~= "Paused" and proc.state ~= "InputsReserved" then
        return fail("nothing_to_abort")
    end
    local out = Tables.deepCopy(proc)
    local partial, partialBy = {}, nil
    if out.state ~= "InputsReserved" then
        local params = out.recipe.params
        local m = Registry.need("machine", out.machine)
        local done = 0
        local total = 0
        for i, st in ipairs(params.stages) do
            local h = stageHours(out, st)
            total = total + h
            if i < out.stage then done = done + h elseif i == out.stage then done = done + out.stageDone end
        end
        local frac = total > 0 and done / total or 0
        local conv = Process.converters[params.converter]
        local res = conv(out.inputs, params.params or {}, m, 1, out.skill, frac)
        partial, partialBy = res.outputs, res.byproducts
    else
        partial = out.inputs
    end
    out.inputs, out.recipe, out.state, out.pause, out.manualPause = {}, nil, "Ready", nil, nil
    out.stage, out.stageDone, out.pausedFor = 0, 0, 0
    -- Both outputs and byproducts are returned so an abort never loses material.
    return { ok = true, proc = out, returned = partial, byproducts = partialBy }
end

function Process.repair(proc, amount)
    if proc.state ~= "Faulted" and proc.state ~= "Ready" and proc.state ~= "Maintenance" then
        return fail("busy")
    end
    local out = Tables.deepCopy(proc)
    out.cond = Num.clamp(out.cond + amount, 0, 1)
    out.state = (out.cond >= 1 - 1e-9 or proc.state == "Ready") and "Ready" or "Maintenance"
    out.spoiled = nil
    if out.state == "Ready" then out.pause = nil end
    return { ok = true, proc = out }
end

function Process.decommission(proc)
    if proc.state ~= "Ready" and proc.state ~= "Maintenance" and proc.state ~= "Faulted" then
        return fail("busy")
    end
    if not Tables.isEmpty(proc.inputs) or not Tables.isEmpty(proc.outputs) then return fail("not_empty") end
    local out = Tables.deepCopy(proc)
    out.state = "Decommissioned"
    return { ok = true, proc = out, firebox = out.firebox }
end

-- Human-facing status: state plus concrete pause reason (spec §13).
function Process.status(proc)
    return { state = proc.state, reason = proc.pause, stage = proc.recipe and proc.recipe.params.stages[proc.stage] and
        proc.recipe.params.stages[proc.stage].id or nil }
end

return Process
