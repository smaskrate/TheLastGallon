-- Persistent workshop conversions (spec §11): ConversionDefinition validation
-- and ConversionService, the persistent project state machine.
--
-- A project is plain data stored with the device (vehicle Engine part modData,
-- generator object modData, generator item modData while carried). The domain
-- never calls game APIs; adapters pass snapshots and authoritative world time:
--
--   actor  { id, skills = { Mechanics = 4 }, recipes = { ["Basic Mechanics"] = true },
--            inventory = { ["Base.Wrench"] = 1 } }          counts by item full type
--   device { key            stable key that never depends on position (moving is allowed)
--            kind           "vehicle" | "generator"
--            chassis        vehicle script full name or generator item full type
--            engineId       identity of the installed engine (stamped by the adapter)
--            engineProfile  ConsumerProfile currently in effect (canBegin only)
--            tankAmount     fuel the caller observed in the device tank (litres)
--            destroyed      true when the device is gone
--            available      false while it cannot be worked on (carried, running, towed)
--            project        project record already stored on the device (canBegin only) }
--   req    { now          authoritative world hours (never client-reported)
--            expectedRev  optional revision the requester saw; a mismatch is "stale"
--            leave        work only: release the worker after crediting }
--
-- States and transitions (anything else is rejected):
--   Planned      draft from Project.new; reserves nothing    -> InProgress (begin)
--   InProgress   stage inspect -> prepare (drain/isolate) -> install -> configure
--                -> test -> commission
--                -> Commissioned (work completes the commission stage)
--                -> Cancelled    (cancel: "abandoned" | destroy: "destroyed" |
--                                 reconcile: "engine_replaced")
--   Commissioned -> Removed (remove) | Cancelled (destroy, "destroyed")
--                -> Reverted | Invalidated (reconcile: engine replaced, per rules)
--   Cancelled, Removed, Reverted and Invalidated are terminal.
--
-- Benefits (target ConsumerProfile, fuel storage changes, cargo/weight impact,
-- visuals) exist only while Commissioned and only for the same device key and
-- engine identity, so an engine replacement can never leave a ghost benefit.
--
-- Work: join assigns a worker (at most maxWorkers; joining again re-anchors).
-- A work report credits the worker's time since their previous report (at most
-- the worker timeout, after which the assignment ends) to the current stage
-- and spills into later stages while they are not blocked. A blocked report
-- credits nothing further, records the concrete reason in project.blocked and
-- releases the worker, so idle time is never credited and nobody is counted
-- twice. Modules are consumed once into per-stage counters (deliver), possibly
-- ahead of their stage. Salvage returns floor(sum(delivered * fraction)) per
-- item; the rest is recorded as lost, so delivered == returned + lost.
--
-- Results: { ok = true, project = <new record>, ... } or { ok = false,
-- reason = code, missing = sorted list, rev = current revision }. Inputs are
-- never mutated. Every committed change increments rev exactly once; a request
-- that changes nothing returns the same record with unchanged = true.
--
-- Reason codes: malformed_request, invalid_time, malformed_project,
-- malformed_actor, malformed_device, stale, time_regression, unknown_conversion,
-- invalid_conversion, not_planned, not_started, not_in_progress, not_commissioned,
-- already_commissioned, project_closed, project_active, already_converted,
-- device_destroyed, device_unavailable, wrong_device_kind, unsupported_chassis,
-- wrong_engine_profile, wrong_device, engine_replaced, missing_skill,
-- missing_recipe, missing_tool, missing_module, tank_unknown, tank_not_empty,
-- not_assigned, project_full, nothing_needed.
require "TLG/Registry/Registry"
require "TLG/Util/Tables"
require "TLG/Util/Num"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Conversions = TLG.Domain.Conversions or {}
TLG.Domain.Conversions.Project = TLG.Domain.Conversions.Project or {}
local Project = TLG.Domain.Conversions.Project
TLG.Domain.ConversionService = Project
local Registry, Tables, Num = TLG.Registry, TLG.Tables, TLG.Num

Project.SCHEMA = (TLG.SCHEMA and TLG.SCHEMA.project) or 1
Project.STAGES = { "inspect", "prepare", "install", "configure", "test", "commission" }
Project.STAGE_INDEX = {}
for i, id in ipairs(Project.STAGES) do Project.STAGE_INDEX[id] = i end
Project.STATES = { Planned = true, InProgress = true, Commissioned = true, Cancelled = true, Removed = true,
    Reverted = true, Invalidated = true }
Project.TERMINAL = { Cancelled = true, Removed = true, Reverted = true, Invalidated = true }
Project.DEVICE_KINDS = { vehicle = true, generator = true }
Project.ENGINE_RULES = { revert = true, invalidate = true }
-- Perk names verified in the 42.21 scripts (media/scripts/generated):
-- Mechanics vehicles/template_gastank.txt:45, Electricity
-- recipes/recipes_electrical.txt:106, MetalWelding recipes/recipes_metalWelding.txt:46.
Project.SKILLS = { Mechanics = true, Electricity = true, MetalWelding = true }
-- Stages that need an empty tank when fuelStorageChanges.drainRequired is set.
Project.DRAIN_STAGES = { prepare = true, install = true }
-- Litres a drained tank may still report (unsiphonable residue, float noise).
Project.DRAIN_TOLERANCE = 0.05
-- Default longest gap between two work reports of a live worker; a later
-- report credits at most this much and ends the assignment (crash/disconnect
-- without leave). A caller that reports often passes a tighter
-- req.workerTimeoutHours: the in-game adapter reports every 15 minutes while
-- the worker stays at the device and passes 1 h, so time away is not credited
-- (ConversionDevices.WORKER_TIMEOUT_HOURS).
Project.WORKER_TIMEOUT_HOURS = 12
Project.DEFAULT_MAX_WORKERS = 2
Project.MAX_WORKERS = 8
local EPS = 1e-9

------------------------------------------------------------------------------
-- ConversionDefinition validation
------------------------------------------------------------------------------
local function isItemId(s)
    return type(s) == "string" and #s <= 128 and string.find(s, "^[%w_]+%.[%w_]+$") ~= nil
end
Project.isItemId = isItemId

local function isList(t)
    return type(t) == "table" and Tables.count(t) == #t
end

local function isWhole(x, lo, hi)
    return Num.isFinite(x) and math.floor(x) == x and x >= lo and (hi == nil or x <= hi)
end

local function checkItemList(list, label, problem)
    if not isList(list) then
        problem(label .. " must be a list of item ids")
        return
    end
    local seen = {}
    for i = 1, #list do
        local id = list[i]
        if not isItemId(id) then
            problem(label .. " has invalid item id " .. tostring(id))
        elseif seen[id] then
            problem(label .. " lists " .. id .. " twice")
        else
            seen[id] = true
        end
    end
end

local function stageTable(t, label, problem)
    if type(t) ~= "table" then
        problem(label .. " must be a table keyed by stage id")
        return false
    end
    for k in pairs(t) do
        if Project.STAGE_INDEX[k] == nil then problem(label .. " uses unknown stage " .. tostring(k)) end
    end
    return true
end

local function acceptedPhases(profile)
    local phases = {}
    if type(profile.accepts) == "table" then
        for fuelId in pairs(profile.accepts) do
            local f = Registry.get("fuel", fuelId)
            if f then phases[f.phase] = true end
        end
    end
    return phases
end

local function checkKnowledge(k, problem)
    if type(k) ~= "table" then
        problem("requiredKnowledge must be a table")
        return
    end
    if k.skills ~= nil and type(k.skills) ~= "table" then
        problem("requiredKnowledge.skills must be a table")
    elseif k.skills ~= nil then
        for name, level in pairs(k.skills) do
            if not Project.SKILLS[name] then problem("unknown skill " .. tostring(name)) end
            if not isWhole(level, 0, 10) then
                problem("skill level for " .. tostring(name) .. " must be an integer 0..10")
            end
        end
    end
    if k.recipes ~= nil and not isList(k.recipes) then
        problem("requiredKnowledge.recipes must be a list")
    elseif k.recipes ~= nil then
        for i = 1, #k.recipes do
            if type(k.recipes[i]) ~= "string" or k.recipes[i] == "" then
                problem("requiredKnowledge.recipes has an empty entry")
            end
        end
    end
end

local function checkStages(stages, problem)
    if not isList(stages) or #stages ~= #Project.STAGES then
        problem("workStages must list the six stages " .. table.concat(Project.STAGES, ","))
        return
    end
    for i = 1, #stages do
        local st = stages[i]
        if type(st) ~= "table" or st.id ~= Project.STAGES[i] then
            problem("workStages[" .. tostring(i) .. "] must be " .. Project.STAGES[i])
        elseif not (Num.isFinite(st.hours) and st.hours > 0) then
            problem("stage " .. Project.STAGES[i] .. " needs positive hours")
        end
    end
end

local function checkToolsAndModules(def, problem)
    local toolSet = {}
    if stageTable(def.requiredTools, "requiredTools", problem) then
        for stage, list in pairs(def.requiredTools) do
            checkItemList(list, "requiredTools." .. tostring(stage), problem)
            if isList(list) then
                for i = 1, #list do
                    if type(list[i]) == "string" then toolSet[list[i]] = true end
                end
            end
        end
    end
    if not stageTable(def.requiredModules, "requiredModules", problem) then return end
    local installModules = 0
    for stage, items in pairs(def.requiredModules) do
        local label = "requiredModules." .. tostring(stage)
        if type(items) ~= "table" then
            problem(label .. " must map item ids to counts")
        else
            for item, n in pairs(items) do
                if not isItemId(item) then problem(label .. " has invalid item id " .. tostring(item)) end
                if not isWhole(n, 1) then
                    problem(label .. " count for " .. tostring(item) .. " must be a positive integer")
                elseif stage == "install" then
                    installModules = installModules + n
                end
                if toolSet[item] then problem(tostring(item) .. " is both a tool and a module") end
            end
        end
    end
    if installModules == 0 then problem("install stage must consume at least one module") end
end

local function checkFuelStorage(fs, target, problem)
    if type(fs) ~= "table" then
        problem("fuelStorageChanges must be a table")
        return
    end
    if type(fs.drainRequired) ~= "boolean" then problem("fuelStorageChanges.drainRequired must be boolean") end
    if fs.tank ~= "keep" and fs.tank ~= "disable" then problem("fuelStorageChanges.tank must be keep or disable") end
    if fs.tank == "keep" then
        local sp = type(fs.tankProfile) == "string" and Registry.get("storage", fs.tankProfile) or nil
        if sp == nil then
            problem("unknown tankProfile " .. tostring(fs.tankProfile))
        elseif sp.phase ~= "liquid" then
            problem("tankProfile " .. sp.id .. " must hold liquid")
        end
    end
    local gasStorages = 0
    if fs.external ~= nil then
        if type(fs.external) ~= "table" or not isList(fs.external.storages) or #fs.external.storages == 0 then
            problem("fuelStorageChanges.external needs a list of storages")
        else
            for i = 1, #fs.external.storages do
                local sid = fs.external.storages[i]
                local sp = type(sid) == "string" and Registry.get("storage", sid) or nil
                if sp == nil then
                    problem("unknown external storage " .. tostring(sid))
                elseif sp.phase ~= "gas" then
                    problem("external storage " .. sid .. " must hold gas")
                else
                    gasStorages = gasStorages + 1
                end
            end
        end
    end
    if target ~= nil then
        local phases = acceptedPhases(target)
        if phases.liquid and fs.tank ~= "keep" then problem("target burns liquid fuel but the tank is disabled") end
        if phases.gas and gasStorages == 0 then problem("target burns gas but no external gas storage is declared") end
    end
end

local function checkRules(r, problem)
    if type(r) ~= "table" then
        problem("reversalAndSalvageRules must be a table")
        return
    end
    local fractions = { "removeReturn", "cancelReturn", "destroyedReturn", "invalidatedReturn" }
    for i = 1, #fractions do
        local v = r[fractions[i]]
        if not (Num.isFinite(v) and v >= 0 and v <= 1) then
            problem("reversalAndSalvageRules." .. fractions[i] .. " must be a fraction in [0,1]")
        end
    end
    if type(r.onEngineReplaced) ~= "string" or not Project.ENGINE_RULES[r.onEngineReplaced] then
        problem("reversalAndSalvageRules.onEngineReplaced must be revert or invalidate")
    end
    if not (Num.isFinite(r.removeHours) and r.removeHours > 0) then
        problem("reversalAndSalvageRules.removeHours must be positive")
    end
    checkItemList(r.tools or {}, "reversalAndSalvageRules.tools", problem)
end

function Project.validateDefinition(def, problem)
    if type(def.deviceKind) ~= "string" or not Project.DEVICE_KINDS[def.deviceKind] then
        problem("deviceKind must be vehicle or generator")
    end
    if not isList(def.supportedChassis) or #def.supportedChassis == 0 then
        problem("supportedChassis needs at least one chassis id")
    else
        checkItemList(def.supportedChassis, "supportedChassis", problem)
    end
    if def.chassisClass ~= nil and (type(def.chassisClass) ~= "string" or def.chassisClass == "") then
        problem("chassisClass must be a non-empty string")
    end
    local original = type(def.originalEngineProfile) == "string" and Registry.get("consumer", def.originalEngineProfile) or nil
    if original == nil then problem("unknown originalEngineProfile " .. tostring(def.originalEngineProfile)) end
    local target = type(def.targetConsumerProfile) == "string" and Registry.get("consumer", def.targetConsumerProfile) or nil
    if target == nil then problem("unknown targetConsumerProfile " .. tostring(def.targetConsumerProfile)) end
    if original ~= nil and original == target then problem("targetConsumerProfile equals originalEngineProfile") end
    checkKnowledge(def.requiredKnowledge, problem)
    checkStages(def.workStages, problem)
    checkToolsAndModules(def, problem)
    local c = def.cargoAndWeightImpact
    if type(c) ~= "table" then
        problem("cargoAndWeightImpact must be a table")
    else
        if not (Num.isFinite(c.massKg) and c.massKg >= 0) then problem("cargoAndWeightImpact.massKg must be >= 0") end
        if c.cargoLitres ~= nil and not (Num.isFinite(c.cargoLitres) and c.cargoLitres <= 0) then
            problem("cargoAndWeightImpact.cargoLitres must be <= 0")
        end
        if c.powerFactor ~= nil and not (Num.isFinite(c.powerFactor) and c.powerFactor > 0 and c.powerFactor <= 1) then
            problem("cargoAndWeightImpact.powerFactor must be in (0,1]")
        end
    end
    checkFuelStorage(def.fuelStorageChanges, target, problem)
    local v = def.visualConfiguration
    if type(v) ~= "table" or type(v.labelKey) ~= "string" or v.labelKey == "" then
        problem("visualConfiguration needs a labelKey")
    end
    checkRules(def.reversalAndSalvageRules, problem)
    if def.maxWorkers ~= nil and not isWhole(def.maxWorkers, 1, Project.MAX_WORKERS) then
        problem("maxWorkers must be an integer 1.." .. tostring(Project.MAX_WORKERS))
    end
end

if not Project.validatorInstalled then
    Project.validatorInstalled = true
    Registry.addValidator("conversion", function(def, problem) Project.validateDefinition(def, problem) end)
end

------------------------------------------------------------------------------
-- Snapshots and helpers
------------------------------------------------------------------------------
local function fail(reason, extra)
    local r = { ok = false, reason = reason }
    if extra then
        for k, v in pairs(extra) do r[k] = v end
    end
    return r
end

local function validProject(p)
    if type(p) ~= "table" or p.v ~= Project.SCHEMA or type(p.state) ~= "string" or not Project.STATES[p.state] then
        return false
    end
    if not Num.isFinite(p.rev) or not Num.isFinite(p.t) then return false end
    if p.state == "Planned" then return true end
    return type(p.snap) == "table" and type(p.hours) == "table" and type(p.delivered) == "table"
        and type(p.workers) == "table" and type(p.credit) == "table" and type(p.deviceKey) == "string"
end

local function validActor(actor)
    if type(actor) ~= "table" or type(actor.id) ~= "string" or #actor.id == 0 or #actor.id > 64 then return false end
    if actor.skills ~= nil and type(actor.skills) ~= "table" then return false end
    if actor.recipes ~= nil and type(actor.recipes) ~= "table" then return false end
    if actor.inventory ~= nil and type(actor.inventory) ~= "table" then return false end
    for k, n in pairs(actor.inventory or {}) do
        if type(k) ~= "string" or not Num.isFinite(n) or n < 0 then return false end
    end
    for k, n in pairs(actor.skills or {}) do
        if type(k) ~= "string" or not Num.isFinite(n) then return false end
    end
    return true
end

local function validDevice(device)
    return type(device) == "table" and type(device.key) == "string" and #device.key > 0 and #device.key <= 128
        and type(device.chassis) == "string" and type(device.kind) == "string"
        and type(device.engineId) == "string" and #device.engineId > 0
        and (device.tankAmount == nil or type(device.tankAmount) == "number")
end

local function checkRequest(project, req)
    if type(req) ~= "table" then return fail("malformed_request") end
    if not Num.isFinite(req.now) or req.now < 0 then return fail("invalid_time") end
    if req.expectedRev ~= nil and not Num.isFinite(req.expectedRev) then return fail("malformed_request") end
    if req.workerTimeoutHours ~= nil and not (Num.isFinite(req.workerTimeoutHours) and req.workerTimeoutHours > 0) then
        return fail("malformed_request")
    end
    if not validProject(project) then return fail("malformed_project") end
    if req.expectedRev ~= nil and req.expectedRev ~= project.rev then
        return fail("stale", { rev = project.rev, state = project.state })
    end
    if req.now < project.t - EPS then return fail("time_regression", { rev = project.rev }) end
    return nil
end

local function closedReason(p)
    if p.state == "Planned" then return "not_started" end
    if Project.TERMINAL[p.state] then return "project_closed" end
    if p.state == "Commissioned" then return "already_commissioned" end
    return "not_in_progress"
end

local function deviceProblem(p, device)
    if not validDevice(device) then return "malformed_device" end
    if device.key ~= p.deviceKey or device.chassis ~= p.chassis or device.kind ~= p.deviceKind then
        return "wrong_device"
    end
    if device.destroyed then return "device_destroyed" end
    if device.engineId ~= p.engineId then return "engine_replaced" end
    return nil
end

local function recipeSet(actor)
    local set = {}
    for k, v in pairs(actor.recipes or {}) do
        if type(k) == "string" and v then set[k] = true end
        if type(v) == "string" then set[v] = true end
    end
    return set
end

-- Returns reason, sorted missing list (nil when the actor qualifies).
local function knowledgeMissing(k, actor)
    local missing = {}
    local skills = (type(k) == "table" and k.skills) or {}
    for _, name in ipairs(Tables.sortedKeys(skills)) do
        local have = (actor.skills and actor.skills[name]) or 0
        if have < skills[name] then missing[#missing + 1] = name .. ":" .. tostring(skills[name]) end
    end
    if #missing > 0 then return "missing_skill", missing end
    local known = recipeSet(actor)
    local recipes = (type(k) == "table" and k.recipes) or {}
    for i = 1, #recipes do
        if not known[recipes[i]] then missing[#missing + 1] = recipes[i] end
    end
    if #missing > 0 then return "missing_recipe", Tables.sort(missing) end
    return nil
end

local function toolsMissing(tools, actor)
    local missing = {}
    local inv = actor.inventory or {}
    for i = 1, #(tools or {}) do
        if (inv[tools[i]] or 0) < 1 then missing[#missing + 1] = tools[i] end
    end
    return Tables.sort(missing)
end

local function stageHours(p, stage)
    return p.snap.workStages[Project.STAGE_INDEX[stage]].hours
end

local function maxWorkers(p)
    return p.snap.maxWorkers or Project.DEFAULT_MAX_WORKERS
end

local function workerTimeout(req)
    return req.workerTimeoutHours or Project.WORKER_TIMEOUT_HOURS
end

-- Modules still owed to a stage: { item = count }.
local function outstandingFor(p, stage)
    local need = {}
    local required = (p.snap.requiredModules and p.snap.requiredModules[stage]) or {}
    local got = p.delivered[stage] or {}
    for _, item in ipairs(Tables.sortedKeys(required)) do
        local left = required[item] - (got[item] or 0)
        if left > 0 then need[item] = left end
    end
    return need
end

-- Why `actor` cannot work on `stage` of `p` right now (nil when it can).
local function stageBlock(p, stage, actor, device)
    if device.available == false then
        return { reason = "device_unavailable", stage = stage, missing = {} }
    end
    local tools = toolsMissing(p.snap.requiredTools and p.snap.requiredTools[stage], actor)
    if #tools > 0 then return { reason = "missing_tool", stage = stage, missing = tools } end
    local need = outstandingFor(p, stage)
    if not Tables.isEmpty(need) then
        return { reason = "missing_module", stage = stage, missing = Tables.sortedKeys(need), need = need }
    end
    local fs = p.snap.fuelStorageChanges
    if fs and fs.drainRequired and Project.DRAIN_STAGES[stage] then
        local amount = device.tankAmount
        if not Num.isFinite(amount) then return { reason = "tank_unknown", stage = stage, missing = {} } end
        if amount > Project.DRAIN_TOLERANCE then
            return { reason = "tank_not_empty", stage = stage, missing = {}, amount = amount }
        end
    end
    return nil
end

local function blockFailure(block, rev)
    return fail(block.reason, { missing = block.missing, need = block.need, amount = block.amount,
        stage = block.stage, rev = rev })
end

local function commit(out, now)
    out.rev = out.rev + 1
    out.t = now
end

local function completeStage(out, t, device)
    local idx = Project.STAGE_INDEX[out.stage]
    if idx < #Project.STAGES then
        out.stage = Project.STAGES[idx + 1]
        return
    end
    out.state, out.stage = "Commissioned", nil
    out.commissionedAt = t
    out.engineId = device.engineId
    out.workers = {}
    out.blocked = nil
end

local function stageStarted(p, stage, i)
    if p.state ~= "InProgress" then return true end
    return i < Project.STAGE_INDEX[p.stage] or (p.hours[stage] or 0) > 0
end

-- fractionFor(stage, index) -> share of that stage's delivered modules that
-- comes back. Returns returned, lost (both { item = count }).
local function salvage(p, fractionFor)
    local exact, total = {}, {}
    for i, stage in ipairs(Project.STAGES) do
        local got = p.delivered[stage] or {}
        local frac = fractionFor(stage, i)
        for _, item in ipairs(Tables.sortedKeys(got)) do
            exact[item] = (exact[item] or 0) + got[item] * frac
            total[item] = (total[item] or 0) + got[item]
        end
    end
    local returned, lost = {}, {}
    for _, item in ipairs(Tables.sortedKeys(total)) do
        local back = math.min(total[item], math.floor(exact[item] + 1e-9))
        if back > 0 then returned[item] = back end
        if total[item] - back > 0 then lost[item] = total[item] - back end
    end
    return returned, lost
end

local function finish(out, state, reason, now, returned, lost)
    out.state, out.endReason, out.endedAt = state, reason, now
    out.stage = nil
    out.workers = {}
    out.blocked = nil
    out.salvage = { returned = returned, lost = lost }
end

-- Immutable parameter snapshot: balance updates never reinterpret a project.
function Project.snapshot(conversionId)
    local def = Registry.need("conversion", conversionId)
    local snap = Tables.deepCopy(def)
    snap.kind = nil
    snap.supportedChassis = nil
    return snap, Registry.fingerprint("conversion", conversionId)
end

------------------------------------------------------------------------------
-- ConversionService
------------------------------------------------------------------------------
function Project.new(o)
    o = o or {}
    return { v = Project.SCHEMA, id = o.id, rev = 0, conversion = o.conversion, state = "Planned", t = o.t or 0 }
end

-- Checks whether `actor` may start converting `device` with the draft `project`.
function Project.canBegin(project, actor, device)
    if not validProject(project) then return fail("malformed_project") end
    if project.state ~= "Planned" then return fail("not_planned", { state = project.state }) end
    local def = type(project.conversion) == "string" and Registry.get("conversion", project.conversion) or nil
    if def == nil then return fail("unknown_conversion") end
    -- Boot only logs content problems, so never snapshot a broken definition.
    local problems = {}
    Project.validateDefinition(def, function(msg) problems[#problems + 1] = msg end)
    if #problems > 0 then return fail("invalid_conversion", { problems = Tables.sort(problems) }) end
    if not validActor(actor) then return fail("malformed_actor") end
    if not validDevice(device) or type(device.engineProfile) ~= "string" then return fail("malformed_device") end
    if device.destroyed then return fail("device_destroyed") end
    if device.available == false then return fail("device_unavailable") end
    if device.kind ~= def.deviceKind then return fail("wrong_device_kind") end
    if not Tables.contains(def.supportedChassis, device.chassis) then return fail("unsupported_chassis") end
    local existing = device.project
    if type(existing) == "table" then
        -- Drafts and closed projects reserve nothing; one live project per device.
        if existing.state == "InProgress" then return fail("project_active", { conversion = existing.conversion }) end
        if existing.state == "Commissioned" then
            return fail("already_converted", { conversion = existing.conversion })
        end
    end
    if device.engineProfile ~= def.originalEngineProfile then
        return fail("wrong_engine_profile", { expected = def.originalEngineProfile })
    end
    local why, missing = knowledgeMissing(def.requiredKnowledge, actor)
    if why then return fail(why, { missing = missing }) end
    local tools = toolsMissing(def.requiredTools and def.requiredTools.inspect, actor)
    if #tools > 0 then return fail("missing_tool", { missing = tools }) end
    return { ok = true }
end

-- Planned -> InProgress: reserves the device by key and snapshots the definition.
function Project.begin(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    local can = Project.canBegin(project, actor, device)
    if not can.ok then
        can.rev = project.rev
        return can
    end
    local out = Tables.deepCopy(project)
    out.snap, out.fp = Project.snapshot(project.conversion)
    out.state, out.stage = "InProgress", "inspect"
    out.deviceKey, out.chassis, out.deviceKind = device.key, device.chassis, device.kind
    out.engineId, out.originalProfile = device.engineId, device.engineProfile
    out.hours, out.delivered, out.workers, out.credit = {}, {}, {}, {}
    for _, stage in ipairs(Project.STAGES) do
        out.hours[stage] = 0
        out.delivered[stage] = {}
    end
    out.startedAt, out.startedBy = req.now, actor.id
    commit(out, req.now)
    return { ok = true, project = out }
end

-- Assigns a worker. Re-joining re-anchors the worker (the unreported gap is
-- forfeited); expired assignments of other workers are evicted.
function Project.join(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    local dp = deviceProblem(project, device)
    if dp then return fail(dp, { rev = project.rev }) end
    local why, missing = knowledgeMissing(project.snap.requiredKnowledge, actor)
    if why then return fail(why, { missing = missing, rev = project.rev }) end
    local block = stageBlock(project, project.stage, actor, device)
    if block then return blockFailure(block, project.rev) end
    local now = req.now
    local out = Tables.deepCopy(project)
    local evicted = {}
    for _, id in ipairs(Tables.sortedKeys(out.workers)) do
        if id ~= actor.id and now - out.workers[id].t > workerTimeout(req) then
            out.workers[id] = nil
            evicted[#evicted + 1] = id
        end
    end
    local mine = out.workers[actor.id]
    if mine then
        if math.abs(mine.t - now) <= EPS and #evicted == 0 then
            return { ok = true, project = project, rejoined = true, unchanged = true, evicted = evicted }
        end
        mine.t = now
    else
        local max = maxWorkers(out)
        if Tables.count(out.workers) >= max then
            return fail("project_full", { max = max, rev = project.rev })
        end
        out.workers[actor.id] = { t = now, since = now }
    end
    out.blocked = nil
    commit(out, now)
    return { ok = true, project = out, rejoined = mine ~= nil, evicted = evicted }
end

-- Credits the worker's authoritative time since their previous report.
function Project.work(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    local dp = deviceProblem(project, device)
    if dp then return fail(dp, { rev = project.rev }) end
    local w = project.workers[actor.id]
    if w == nil then return fail("not_assigned", { rev = project.rev }) end
    local now = req.now
    local elapsed = math.max(0, now - w.t)
    if elapsed <= EPS and not req.leave then
        return { ok = true, project = project, credited = 0, unused = 0, unchanged = true, released = false,
            expired = false, commissioned = false, events = {} }
    end
    local out = Tables.deepCopy(project)
    local span, expired = elapsed, false
    if span > workerTimeout(req) then
        span, expired = workerTimeout(req), true
    end
    local cursor, credited, block, events = w.t, 0, nil, {}
    local guard = 0
    while span > EPS and out.state == "InProgress" and guard < 64 do
        guard = guard + 1
        local stage = out.stage
        block = stageBlock(out, stage, actor, device)
        if block then break end
        local need = stageHours(out, stage) - out.hours[stage]
        local use = math.min(span, need)
        out.hours[stage] = out.hours[stage] + use
        credited, span, cursor = credited + use, span - use, cursor + use
        if need - use <= EPS then
            out.hours[stage] = stageHours(out, stage)
            events[#events + 1] = { kind = "stage_done", stage = stage, t = cursor }
            completeStage(out, cursor, device)
            if out.state == "Commissioned" then events[#events + 1] = { kind = "commissioned", t = cursor } end
        end
    end
    out.credit[actor.id] = (out.credit[actor.id] or 0) + credited
    local released = true
    if out.state == "InProgress" then
        if block or expired or req.leave then
            out.workers[actor.id] = nil
        else
            out.workers[actor.id].t = now
            released = false
        end
        if block then
            out.blocked = { reason = block.reason, stage = block.stage, missing = block.missing, need = block.need,
                amount = block.amount, actor = actor.id, t = now }
        elseif credited > EPS then
            out.blocked = nil
        end
    end
    commit(out, now)
    return { ok = true, project = out, credited = credited, unused = math.max(0, elapsed - credited),
        blocked = block, released = released, expired = expired, commissioned = out.state == "Commissioned",
        events = events }
end

-- Releases a worker without crediting (use work{leave = true} to credit first).
function Project.leave(project, actor, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    if project.workers[actor.id] == nil then return fail("not_assigned", { rev = project.rev }) end
    local out = Tables.deepCopy(project)
    out.workers[actor.id] = nil
    commit(out, req.now)
    return { ok = true, project = out }
end

-- Takes outstanding modules (current and later stages, in stage order) from
-- the actor's inventory. The caller removes `consumed` in the same commit.
function Project.deliver(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    local dp = deviceProblem(project, device)
    if dp then return fail(dp, { rev = project.rev }) end
    local out = Tables.deepCopy(project)
    local inv = Tables.copy(actor.inventory or {})
    local consumed, outstanding, any = {}, {}, false
    for i = Project.STAGE_INDEX[out.stage], #Project.STAGES do
        local stage = Project.STAGES[i]
        local need = outstandingFor(out, stage)
        for _, item in ipairs(Tables.sortedKeys(need)) do
            local have = math.floor(inv[item] or 0)
            local take = math.min(have, need[item])
            if take > 0 then
                out.delivered[stage][item] = (out.delivered[stage][item] or 0) + take
                consumed[item] = (consumed[item] or 0) + take
                inv[item] = have - take
                any = true
            end
            if need[item] - take > 0 then outstanding[item] = (outstanding[item] or 0) + need[item] - take end
        end
    end
    if not any then
        if Tables.isEmpty(outstanding) then return fail("nothing_needed", { rev = project.rev }) end
        return fail("missing_module", { missing = Tables.sortedKeys(outstanding), need = outstanding, rev = project.rev })
    end
    if out.blocked and out.blocked.reason == "missing_module" and Tables.isEmpty(outstandingFor(out, out.blocked.stage)) then
        out.blocked = nil
    end
    commit(out, req.now)
    return { ok = true, project = out, consumed = consumed, outstanding = outstanding }
end

local function removalMissing(p, actor)
    local why, missing = knowledgeMissing(p.snap.requiredKnowledge, actor)
    if why then return why, missing end
    local tools = toolsMissing(p.snap.reversalAndSalvageRules.tools, actor)
    if #tools > 0 then return "missing_tool", tools end
    return nil
end

-- Abandons an unfinished project. Modules of stages that never started come
-- back in full; started stages return cancelReturn.
function Project.cancel(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    local dp = deviceProblem(project, device)
    if dp then return fail(dp, { rev = project.rev }) end
    local why, missing = removalMissing(project, actor)
    if why then return fail(why, { missing = missing, rev = project.rev }) end
    local out = Tables.deepCopy(project)
    local frac = out.snap.reversalAndSalvageRules.cancelReturn
    local returned, lost = salvage(out, function(stage, i)
        if stageStarted(out, stage, i) then return frac end
        return 1
    end)
    finish(out, "Cancelled", "abandoned", req.now, returned, lost)
    commit(out, req.now)
    return { ok = true, project = out, returned = returned, lost = lost }
end

-- Commissioned -> Removed: the device returns to its original profile.
function Project.remove(project, actor, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "Commissioned" then
        local reason = project.state == "InProgress" and "not_commissioned" or closedReason(project)
        return fail(reason, { rev = project.rev, state = project.state })
    end
    if not validActor(actor) then return fail("malformed_actor", { rev = project.rev }) end
    local dp = deviceProblem(project, device)
    if dp then return fail(dp, { rev = project.rev }) end
    local why, missing = removalMissing(project, actor)
    if why then return fail(why, { missing = missing, rev = project.rev }) end
    local out = Tables.deepCopy(project)
    local frac = out.snap.reversalAndSalvageRules.removeReturn
    local returned, lost = salvage(out, function() return frac end)
    finish(out, "Removed", "removed", req.now, returned, lost)
    commit(out, req.now)
    return { ok = true, project = out, returned = returned, lost = lost }
end

-- The device was destroyed: the project is cancelled; destroyedReturn applies
-- to everything it held (installed or not).
function Project.destroy(project, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" and project.state ~= "Commissioned" then
        return fail(closedReason(project), { rev = project.rev, state = project.state })
    end
    local out = Tables.deepCopy(project)
    local frac = out.snap.reversalAndSalvageRules.destroyedReturn
    local returned, lost = salvage(out, function() return frac end)
    finish(out, "Cancelled", "destroyed", req.now, returned, lost)
    commit(out, req.now)
    return { ok = true, project = out, returned = returned, lost = lost }
end

-- Applies what the adapter observed on the device: destruction or an engine
-- replacement (rules: revert returns removeReturn/cancelReturn, invalidate
-- returns invalidatedReturn; modules of unstarted stages always come back).
-- Nothing observed -> unchanged (same revision).
function Project.reconcile(project, device, req)
    local bad = checkRequest(project, req)
    if bad then return bad end
    if project.state ~= "InProgress" and project.state ~= "Commissioned" then
        return { ok = true, project = project, unchanged = true }
    end
    if not validDevice(device) then return fail("malformed_device", { rev = project.rev }) end
    if device.key ~= project.deviceKey or device.chassis ~= project.chassis or device.kind ~= project.deviceKind then
        return fail("wrong_device", { rev = project.rev })
    end
    if device.destroyed then
        local r = Project.destroy(project, { now = req.now })
        r.change = "destroyed"
        return r
    end
    if device.engineId == project.engineId then return { ok = true, project = project, unchanged = true } end
    local out = Tables.deepCopy(project)
    local rules = out.snap.reversalAndSalvageRules
    local revert = rules.onEngineReplaced == "revert"
    local returned, lost, state
    if out.state == "InProgress" then
        local frac = revert and rules.cancelReturn or rules.invalidatedReturn
        returned, lost = salvage(out, function(stage, i)
            if stageStarted(out, stage, i) then return frac end
            return 1
        end)
        state = "Cancelled"
    elseif revert then
        returned, lost = salvage(out, function() return rules.removeReturn end)
        state = "Reverted"
    else
        returned, lost = salvage(out, function() return rules.invalidatedReturn end)
        state = "Invalidated"
    end
    finish(out, state, "engine_replaced", req.now, returned, lost)
    commit(out, req.now)
    return { ok = true, project = out, returned = returned, lost = lost, change = "engine_replaced" }
end

-- What the adapter applies to the device; nil unless the project is
-- Commissioned and the snapshot still describes the same device and engine.
function Project.benefits(project, device)
    if not validProject(project) or project.state ~= "Commissioned" then return nil end
    if not validDevice(device) or device.destroyed then return nil end
    if device.key ~= project.deviceKey or device.chassis ~= project.chassis or device.engineId ~= project.engineId then
        return nil
    end
    local s = project.snap
    return {
        conversion = project.conversion,
        consumerProfile = s.targetConsumerProfile,
        fuelStorage = Tables.deepCopy(s.fuelStorageChanges),
        cargo = Tables.deepCopy(s.cargoAndWeightImpact),
        visual = Tables.deepCopy(s.visualConfiguration),
    }
end

-- ConsumerProfile in effect: the target only while benefits apply.
function Project.effectiveProfile(project, device)
    local b = Project.benefits(project, device)
    if b then return b.consumerProfile end
    if type(project) == "table" and type(project.originalProfile) == "string" then return project.originalProfile end
    if type(device) == "table" then return device.engineProfile end
    return nil
end

-- Read-only view for UI: progress and the concrete reason the given actor
-- cannot work right now (falls back to the last recorded block).
function Project.status(project, actor, device)
    if not validProject(project) then return { state = "invalid" } end
    local s = { state = project.state, rev = project.rev, conversion = project.conversion, stage = project.stage,
        endReason = project.endReason }
    if project.state == "InProgress" then
        local total, done = 0, 0
        for _, st in ipairs(project.snap.workStages) do
            total = total + st.hours
            done = done + (project.hours[st.id] or 0)
        end
        s.stageIndex = Project.STAGE_INDEX[project.stage]
        s.stageHours = stageHours(project, project.stage)
        s.stageDone = project.hours[project.stage] or 0
        s.totalHours, s.doneHours = total, done
        s.workers, s.maxWorkers = Tables.count(project.workers), maxWorkers(project)
        s.outstanding = outstandingFor(project, project.stage)
        s.blocked = project.blocked
        if validActor(actor) and device ~= nil then
            local dp = deviceProblem(project, device)
            if dp then
                s.blocked = { reason = dp, stage = project.stage, missing = {} }
            else
                local why, missing = knowledgeMissing(project.snap.requiredKnowledge, actor)
                if why then
                    s.blocked = { reason = why, stage = project.stage, missing = missing }
                else
                    s.blocked = stageBlock(project, project.stage, actor, device)
                end
            end
        end
    end
    s.benefits = Project.benefits(project, device) ~= nil
    return s
end

-- Invariant violations (empty list when consistent).
function Project.check(p)
    if not validProject(p) then return { "malformed project" } end
    local bad = {}
    local function need(cond, msg)
        if not cond then bad[#bad + 1] = msg end
    end
    need(p.rev >= 0 and math.floor(p.rev) == p.rev, "rev must be a non-negative integer")
    if p.state == "Planned" then return bad end
    local idx = Project.STAGE_INDEX[p.stage or ""]
    if p.state == "InProgress" then
        need(idx ~= nil, "in-progress project needs a stage")
    else
        need(p.stage == nil, "only in-progress projects have a stage")
    end
    local hoursSum = 0
    for i, stage in ipairs(Project.STAGES) do
        local h = p.hours[stage] or 0
        local full = stageHours(p, stage)
        hoursSum = hoursSum + h
        need(h >= -EPS and h <= full + EPS, "hours out of range in " .. stage)
        if p.state == "InProgress" and idx ~= nil then
            if i < idx then
                need(math.abs(h - full) <= 1e-6, "completed stage " .. stage .. " lacks hours")
            elseif i > idx then
                need(h <= EPS, "future stage " .. stage .. " has hours")
            else
                need(h < full, "current stage " .. stage .. " is complete but not advanced")
            end
        elseif p.state == "Commissioned" then
            need(math.abs(h - full) <= 1e-6, "commissioned project lacks hours in " .. stage)
        end
        local required = p.snap.requiredModules[stage] or {}
        for _, item in ipairs(Tables.sortedKeys(p.delivered[stage] or {})) do
            local n = p.delivered[stage][item]
            need(n >= 0 and n <= (required[item] or 0), "delivered " .. item .. " exceeds requirement in " .. stage)
        end
    end
    local creditSum = 0
    for _, id in ipairs(Tables.sortedKeys(p.credit)) do creditSum = creditSum + p.credit[id] end
    need(math.abs(creditSum - hoursSum) <= 1e-6, "credited hours do not match stage hours")
    local nWorkers = Tables.count(p.workers)
    need(nWorkers <= maxWorkers(p), "too many workers")
    need(p.state == "InProgress" or nWorkers == 0, "workers on a project that is not in progress")
    if p.state == "Commissioned" then need(Num.isFinite(p.commissionedAt), "commissionedAt missing") end
    if Project.TERMINAL[p.state] then
        local s = p.salvage
        need(type(s) == "table" and type(s.returned) == "table" and type(s.lost) == "table", "salvage record missing")
        if type(s) == "table" and type(s.returned) == "table" and type(s.lost) == "table" then
            local total = {}
            for _, stage in ipairs(Project.STAGES) do
                for _, item in ipairs(Tables.sortedKeys(p.delivered[stage] or {})) do
                    total[item] = (total[item] or 0) + p.delivered[stage][item]
                end
            end
            for _, item in ipairs(Tables.sortedKeys(total)) do
                need((s.returned[item] or 0) + (s.lost[item] or 0) == total[item], "salvage does not balance for " .. item)
            end
            for _, item in ipairs(Tables.sortedKeys(s.returned)) do
                need(total[item] ~= nil, "returned " .. item .. " that was never delivered")
            end
        end
    end
    return bad
end

-- Published conversion matrix: one row per (chassis, conversion), sorted.
function Project.matrix()
    local rows = {}
    for _, def in ipairs(Registry.all("conversion")) do
        local list = type(def.supportedChassis) == "table" and def.supportedChassis or {}
        for _, chassis in ipairs(list) do
            rows[#rows + 1] = { chassis = chassis, conversion = def.id, deviceKind = def.deviceKind,
                class = def.chassisClass, from = def.originalEngineProfile, to = def.targetConsumerProfile }
        end
    end
    return Tables.sort(rows, function(a, b)
        if a.chassis ~= b.chassis then return a.chassis < b.chassis end
        return a.conversion < b.conversion
    end)
end

return Project
