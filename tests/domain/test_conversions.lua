require "support/fixtures"
require "TLG/Content/Conversions"
local P, R, Tables, Num = TLG.Domain.ConversionService, TLG.Registry, TLG.Tables, TLG.Num

------------------------------------------------------------------------------
-- Fixtures: plain snapshots like the adapters would build them.
------------------------------------------------------------------------------
local TOOLS = { "Base.Screwdriver", "Base.Wrench", "Base.Pliers", "Base.PipeWrench" }

local function actor(id, items, o)
    o = o or {}
    local inv = {}
    if not o.noTools then
        for _, t in ipairs(TOOLS) do inv[t] = 1 end
    end
    for _, k in ipairs(Tables.sortedKeys(items or {})) do inv[k] = items[k] end
    return {
        id = id,
        skills = o.skills or { Mechanics = 10, Electricity = 10, MetalWelding = 10 },
        recipes = o.recipes or { ["Generator"] = true, ["Basic Mechanics"] = true, ["Intermediate Mechanics"] = true },
        inventory = inv,
    }
end

local function gen(o)
    local d = { key = "gen:G-1", kind = "generator", chassis = "Base.Generator", engineId = "G-1",
        engineProfile = "generator_si_stock", tankAmount = 0, position = { x = 10, y = 20, z = 0 } }
    for k, v in pairs(o or {}) do d[k] = v end
    return d
end

local function car(o)
    local d = { key = "veh:42:Base.CarNormal", kind = "vehicle", chassis = "Base.CarNormal", engineId = "E-1",
        engineProfile = "engine_si_stock", tankAmount = 0 }
    for k, v in pairs(o or {}) do d[k] = v end
    return d
end

-- All modules a conversion consumes over its stages.
local function modulesOf(conv)
    local def = R.get("conversion", conv)
    local all = {}
    for _, stage in ipairs(P.STAGES) do
        local m = def.requiredModules[stage] or {}
        for _, item in ipairs(Tables.sortedKeys(m)) do all[item] = (all[item] or 0) + m[item] end
    end
    return all
end

local function must(r, label)
    if not (r and r.ok) then
        error("ASSERT: " .. tostring(label or "operation") .. " failed: " .. tostring(r and r.reason), 2)
    end
    return r.project
end

-- The adapter removes consumed items from the inventory in the same commit.
local function take(a, consumed)
    for _, item in ipairs(Tables.sortedKeys(consumed or {})) do
        a.inventory[item] = (a.inventory[item] or 0) - consumed[item]
    end
end

local function start(conv, dev, a, now)
    local draft = P.new({ id = "C-" .. conv, conversion = conv, t = now or 0 })
    return must(P.begin(draft, a, dev, { now = now or 0 }), "begin")
end

-- Begun, all modules delivered, one worker assigned.
local function prepared(conv, dev, now)
    local a = actor("p1", modulesOf(conv))
    local p = start(conv, dev, a, now)
    local r = P.deliver(p, a, dev, { now = now or 0 })
    p = must(r, "deliver")
    take(a, r.consumed)
    p = must(P.join(p, a, dev, { now = now or 0 }), "join")
    return p, a
end

local function sumDelivered(p)
    local n = 0
    for _, stage in ipairs(P.STAGES) do
        for _, item in ipairs(Tables.sortedKeys(p.delivered[stage])) do n = n + p.delivered[stage][item] end
    end
    return n
end

local function noProblems(p, label)
    local bad = P.check(p)
    T.eq(#bad, 0, (label or "invariants") .. ": " .. table.concat(bad, ", "))
end

------------------------------------------------------------------------------
-- Definitions
------------------------------------------------------------------------------
T.case("conversion: shipped definitions validate and use the verified chassis ids", function()
    local problems = R.validate()
    T.eq(#problems, 0, table.concat(problems, " | "))
    local flex = R.get("conversion", "flex_generator")
    T.eq(table.concat(flex.supportedChassis, ","), "Base.Generator,Base.Generator_Yellow,Base.Generator_Blue,Base.Generator_Old")
    T.eq(flex.targetConsumerProfile, "generator_si_flex")
    local gas = R.get("conversion", "gas_generator")
    T.eq(gas.targetConsumerProfile, "generator_gas")
    T.eq(table.concat(gas.supportedChassis, ","), table.concat(flex.supportedChassis, ","))
    local vehicles = { flex_car_normal = "Base.CarNormal", flex_small_car = "Base.SmallCar",
        flex_pickup_truck = "Base.PickUpTruck", flex_step_van = "Base.StepVan" }
    for _, id in ipairs(Tables.sortedKeys(vehicles)) do
        local def = R.get("conversion", id)
        T.ok(def ~= nil, "defined: " .. id)
        T.eq(def.deviceKind, "vehicle")
        T.eq(#def.supportedChassis, 1)
        T.eq(def.supportedChassis[1], vehicles[id])
        T.eq(def.targetConsumerProfile, "engine_si_flex")
    end
    local rows = P.matrix()
    T.eq(#rows, 12, "4 generators x 2 routes + 4 vehicles")
    T.eq(rows[1].chassis, "Base.CarNormal")
    T.eq(rows[2].chassis .. "/" .. rows[2].conversion, "Base.Generator/flex_generator")
    T.eq(rows[3].chassis .. "/" .. rows[3].conversion, "Base.Generator/gas_generator")
end)

T.case("conversion: validator reports malformed definitions", function()
    local ok, err = pcall(function()
        R.define("conversion", { id = "test_conv_bad", deviceKind = "boat",
            supportedChassis = { "CarNormal", "Base.Car Normal" },
            originalEngineProfile = "nope", targetConsumerProfile = "engine_si_flex",
            requiredKnowledge = { skills = { Cooking = 3, Mechanics = 11 }, recipes = { "" } },
            requiredTools = { weld = { "Base.Wrench" }, install = { "Wrench", "Base.Pliers", "Base.Pliers" } },
            requiredModules = { install = { ["Base.SheetMetal"] = 0, ["Base.Pliers"] = 1 } },
            workStages = { { id = "install", hours = -1 } },
            cargoAndWeightImpact = { massKg = -5, cargoLitres = 10, powerFactor = 2 },
            fuelStorageChanges = { drainRequired = "yes", tank = "maybe" },
            visualConfiguration = 5,
            reversalAndSalvageRules = { removeReturn = 1.5, cancelReturn = 0.5, destroyedReturn = 0,
                invalidatedReturn = 0, onEngineReplaced = "ignore", removeHours = 0, tools = { "Wrench" } },
            maxWorkers = 0 })
        R.define("conversion", { id = "test_conv_bad_gas", deviceKind = "generator",
            supportedChassis = { "Base.Generator" },
            originalEngineProfile = "generator_gas", targetConsumerProfile = "generator_gas",
            requiredKnowledge = {},
            requiredTools = {},
            requiredModules = { install = { ["Base.RubberHose"] = 1 } },
            workStages = { { id = "inspect", hours = 1 }, { id = "prepare", hours = 1 }, { id = "install", hours = 1 },
                { id = "configure", hours = 1 }, { id = "commission", hours = 1 }, { id = "test", hours = 1 } },
            cargoAndWeightImpact = { massKg = 1 },
            fuelStorageChanges = { drainRequired = true, tank = "keep", tankProfile = "nope_tank",
                external = { storages = { "jerrycan_steel", "nope_gas" } } },
            visualConfiguration = { labelKey = "x" },
            reversalAndSalvageRules = { removeReturn = 0.5, cancelReturn = 0.5, destroyedReturn = 0,
                invalidatedReturn = 0, onEngineReplaced = "revert", removeHours = 1 } })
        R.define("conversion", { id = "test_conv_garbage", supportedChassis = "Base.CarNormal", workStages = "x",
            requiredTools = 3, requiredModules = { install = 5 }, requiredKnowledge = { skills = "x", recipes = "y" },
            fuelStorageChanges = { drainRequired = true, tank = "disable" }, targetConsumerProfile = "generator_si_flex" })
    end)
    local okValidate, text = pcall(function() return table.concat(R.validate(), "\n") end)
    local okBegin, begun = pcall(function()
        return P.canBegin(P.new({ conversion = "test_conv_bad_gas" }), actor("p1"), gen({ engineProfile = "generator_gas" }))
    end)
    local okMatrix, rows = pcall(P.matrix)
    R.entries.conversion.test_conv_bad = nil
    R.entries.conversion.test_conv_bad_gas = nil
    R.entries.conversion.test_conv_garbage = nil
    T.ok(ok, tostring(err))
    T.ok(okValidate, "validator never throws on malformed data: " .. tostring(text))
    T.ok(okBegin, tostring(begun))
    T.eq(begun.reason, "invalid_conversion", "a broken definition can never be begun")
    T.ok(#begun.problems > 0)
    T.ok(okMatrix, "matrix tolerates malformed entries: " .. tostring(rows))
    local expected = {
        "test_conv_bad: deviceKind must be vehicle or generator",
        "test_conv_bad: supportedChassis has invalid item id CarNormal",
        "test_conv_bad: supportedChassis has invalid item id Base.Car Normal",
        "test_conv_bad: unknown originalEngineProfile nope",
        "test_conv_bad: unknown skill Cooking",
        "test_conv_bad: skill level for Mechanics must be an integer 0..10",
        "test_conv_bad: requiredKnowledge.recipes has an empty entry",
        "test_conv_bad: requiredTools uses unknown stage weld",
        "test_conv_bad: requiredTools.install has invalid item id Wrench",
        "test_conv_bad: requiredTools.install lists Base.Pliers twice",
        "test_conv_bad: requiredModules.install count for Base.SheetMetal must be a positive integer",
        "test_conv_bad: Base.Pliers is both a tool and a module",
        "test_conv_bad: workStages must list the six stages",
        "test_conv_bad: cargoAndWeightImpact.massKg must be >= 0",
        "test_conv_bad: cargoAndWeightImpact.cargoLitres must be <= 0",
        "test_conv_bad: cargoAndWeightImpact.powerFactor must be in (0,1]",
        "test_conv_bad: fuelStorageChanges.drainRequired must be boolean",
        "test_conv_bad: fuelStorageChanges.tank must be keep or disable",
        "test_conv_bad: visualConfiguration needs a labelKey",
        "test_conv_bad: reversalAndSalvageRules.removeReturn must be a fraction in [0,1]",
        "test_conv_bad: reversalAndSalvageRules.onEngineReplaced must be revert or invalidate",
        "test_conv_bad: reversalAndSalvageRules.removeHours must be positive",
        "test_conv_bad: reversalAndSalvageRules.tools has invalid item id Wrench",
        "test_conv_bad: maxWorkers must be an integer 1..8",
        "test_conv_bad_gas: targetConsumerProfile equals originalEngineProfile",
        "test_conv_bad_gas: workStages[5] must be test",
        "test_conv_bad_gas: workStages[6] must be commission",
        "test_conv_bad_gas: unknown tankProfile nope_tank",
        "test_conv_bad_gas: external storage jerrycan_steel must hold gas",
        "test_conv_bad_gas: unknown external storage nope_gas",
        "test_conv_bad_gas: target burns gas but no external gas storage is declared",
        "test_conv_garbage: deviceKind must be vehicle or generator",
        "test_conv_garbage: supportedChassis needs at least one chassis id",
        "test_conv_garbage: requiredKnowledge.skills must be a table",
        "test_conv_garbage: requiredKnowledge.recipes must be a list",
        "test_conv_garbage: requiredTools must be a table keyed by stage id",
        "test_conv_garbage: requiredModules.install must map item ids to counts",
        "test_conv_garbage: install stage must consume at least one module",
        "test_conv_garbage: target burns liquid fuel but the tank is disabled",
        "test_conv_garbage: cargoAndWeightImpact must be a table",
        "test_conv_garbage: reversalAndSalvageRules must be a table",
    }
    for _, frag in ipairs(expected) do
        T.ok(string.find(text, frag, 1, true) ~= nil, "missing problem: " .. frag)
    end
    T.eq(#R.validate(), 0, "clean after removing the test entries")
end)

------------------------------------------------------------------------------
-- canBegin and request validation
------------------------------------------------------------------------------
T.case("conversion: canBegin checks device, chassis, profile, knowledge, tools and existing projects", function()
    local a = actor("p1")
    local draft = P.new({ conversion = "flex_generator" })
    for _, chassis in ipairs({ "Base.Generator", "Base.Generator_Old", "Base.Generator_Yellow", "Base.Generator_Blue" }) do
        local r = P.canBegin(draft, a, gen({ chassis = chassis }))
        T.ok(r.ok, chassis .. ": " .. tostring(r.reason))
    end
    T.eq(P.canBegin(P.new({ conversion = "nope" }), a, gen()).reason, "unknown_conversion")
    T.eq(P.canBegin(draft, a, car()).reason, "wrong_device_kind")
    T.eq(P.canBegin(draft, a, gen({ chassis = "Base.CarNormal" })).reason, "unsupported_chassis")
    T.eq(P.canBegin(P.new({ conversion = "flex_car_normal" }), a, car({ chassis = "Base.SportsCar" })).reason,
        "unsupported_chassis")
    T.eq(P.canBegin(draft, a, gen({ engineProfile = "generator_si_flex" })).reason, "wrong_engine_profile")
    T.eq(P.canBegin(draft, a, gen({ destroyed = true })).reason, "device_destroyed")
    T.eq(P.canBegin(draft, a, gen({ available = false })).reason, "device_unavailable")
    T.eq(P.canBegin(draft, a, gen({ engineProfile = 5 })).reason, "malformed_device")
    local r = P.canBegin(draft, actor("novice", nil, { skills = { Mechanics = 1 } }), gen())
    T.eq(r.reason, "missing_skill")
    T.eq(table.concat(r.missing, ","), "Electricity:2,Mechanics:2")
    r = P.canBegin(draft, actor("unread", nil, { recipes = {} }), gen())
    T.eq(r.reason, "missing_recipe")
    T.eq(r.missing[1], "Generator")
    T.ok(P.canBegin(draft, actor("list", nil, { recipes = { "Generator" } }), gen()).ok, "recipes as a list")
    r = P.canBegin(draft, actor("bare", nil, { noTools = true }), gen())
    T.eq(r.reason, "missing_tool")
    T.eq(r.missing[1], "Base.Screwdriver")
    local active = start("flex_generator", gen(), a, 0)
    T.eq(P.canBegin(draft, a, gen({ project = active })).reason, "project_active")
    T.eq(P.canBegin(P.new({ conversion = "gas_generator" }), a, gen({ project = active })).reason, "project_active")
    T.eq(P.canBegin(active, a, gen()).reason, "not_planned")
    local done = { v = active.v, state = "Commissioned", conversion = "flex_generator" }
    T.eq(P.canBegin(P.new({ conversion = "gas_generator" }), a, gen({ project = done })).reason, "already_converted")
    local closed = { v = active.v, state = "Removed", conversion = "flex_generator" }
    T.ok(P.canBegin(draft, a, gen({ project = closed })).ok, "a closed project does not block a new one")
    T.ok(P.canBegin(draft, a, gen({ project = P.new({ conversion = "gas_generator" }) })).ok, "drafts reserve nothing")
end)

T.case("conversion: malformed requests and invalid transitions are rejected without mutation", function()
    local a = actor("p1")
    local dev = gen()
    local draft = P.new({ conversion = "flex_generator", t = 5 })
    T.eq(P.begin(draft, a, dev, nil).reason, "malformed_request")
    T.eq(P.begin(draft, a, dev, { now = 0 / 0 }).reason, "invalid_time")
    T.eq(P.begin(draft, a, dev, { now = 1 / 0 }).reason, "invalid_time")
    T.eq(P.begin(draft, a, dev, { now = -1 }).reason, "invalid_time")
    T.eq(P.begin(draft, a, dev, { now = 4 }).reason, "time_regression")
    T.eq(P.begin(draft, { id = "" }, dev, { now = 5 }).reason, "malformed_actor")
    T.eq(P.begin(draft, { id = "x", inventory = { ["Base.Wrench"] = -1 } }, dev, { now = 5 }).reason, "malformed_actor")
    T.eq(P.begin(draft, a, { key = 5 }, { now = 5 }).reason, "malformed_device")
    T.eq(P.begin(draft, a, gen({ engineId = "" }), { now = 5 }).reason, "malformed_device")
    T.eq(P.begin("draft", a, dev, { now = 5 }).reason, "malformed_project")
    T.eq(P.join(draft, a, dev, { now = 5 }).reason, "not_started")
    T.eq(P.destroy(draft, { now = 5 }).reason, "not_started")
    local p = start("flex_generator", dev, a, 5)
    local before = Tables.deepCopy(p)
    T.eq(P.join(p, a, dev, { now = 6, expectedRev = "1" }).reason, "malformed_request")
    T.eq(P.join(p, a, dev, { now = 4 }).reason, "time_regression")
    T.eq(P.join(p, "p1", dev, { now = 6 }).reason, "malformed_actor")
    T.eq(P.join(p, a, nil, { now = 6 }).reason, "malformed_device")
    T.eq(P.work(p, a, dev, { now = 6 }).reason, "not_assigned")
    T.eq(P.leave(p, a, { now = 6 }).reason, "not_assigned")
    T.eq(P.remove(p, a, dev, { now = 6 }).reason, "not_commissioned")
    T.eq(P.join(p, a, gen({ key = "gen:other" }), { now = 6 }).reason, "wrong_device")
    T.eq(P.join(p, a, gen({ kind = "vehicle" }), { now = 6 }).reason, "wrong_device")
    T.eq(P.join(p, actor("novice", nil, { skills = {} }), dev, { now = 6 }).reason, "missing_skill")
    T.eq(P.deliver(p, actor("empty"), dev, { now = 6 }).reason, "missing_module")
    T.eq(P.cancel(p, actor("bare", nil, { noTools = true }), dev, { now = 6 }).reason, "missing_tool")
    T.ok(Tables.deepEqual(p, before), "rejected requests never mutate the project")
    T.eq(P.begin(p, a, dev, { now = 6 }).reason, "not_planned")
    local st = P.status(p, actor("bare", nil, { noTools = true }), dev)
    T.eq(st.state, "InProgress"); T.eq(st.stage, "inspect"); T.eq(st.blocked.reason, "missing_tool")
    T.eq(st.benefits, false)
end)

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------
T.case("conversion: generator flex conversion runs every stage; benefits only after commissioning", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    local seen = {}
    local t = 0
    while p.state == "InProgress" do
        seen[p.stage] = true
        T.eq(P.benefits(p, dev), nil, "no benefit during " .. tostring(p.stage))
        T.eq(P.effectiveProfile(p, dev), "generator_si_stock", "stock profile during " .. tostring(p.stage))
        T.eq(P.status(p, a, dev).benefits, false)
        t = t + 0.25
        p = must(P.work(p, a, dev, { now = t }), "work at " .. tostring(t))
        noProblems(p, "after work at " .. tostring(t))
    end
    for _, s in ipairs(P.STAGES) do T.ok(seen[s], "visited " .. s) end
    T.eq(p.state, "Commissioned")
    T.near(p.commissionedAt, 7.5, 1e-9)
    T.near(t, 7.5, 1e-9)
    local b = P.benefits(p, dev)
    T.eq(b.consumerProfile, "generator_si_flex")
    T.eq(b.fuelStorage.tankProfile, "generator_tank")
    T.eq(b.cargo.massKg, 2)
    T.eq(P.effectiveProfile(p, dev), "generator_si_flex")
    T.eq(Tables.count(p.workers), 0, "workers released at commissioning")
    T.eq(P.benefits(p, nil), nil, "benefits need the device snapshot")
    T.eq(P.join(p, a, dev, { now = 8 }).reason, "already_commissioned")
    -- a converted generator cannot take a second conversion
    T.eq(P.canBegin(P.new({ conversion = "gas_generator" }), a, gen({ project = p, engineProfile = "generator_si_flex" })).reason,
        "already_converted")
end)

T.case("conversion: gas generator conversion yields the gaseous profile and external gas storage", function()
    local dev = gen({ chassis = "Base.Generator_Old" })
    local p, a = prepared("gas_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 4 }))
    T.eq(P.benefits(p, dev), nil)
    p = must(P.work(p, a, dev, { now = 9 }))
    T.eq(p.state, "Commissioned")
    local b = P.benefits(p, dev)
    T.eq(b.consumerProfile, "generator_gas")
    T.eq(b.fuelStorage.tank, "disable")
    T.eq(table.concat(b.fuelStorage.external.storages, ","), "propane_cylinder,gas_holder")
end)

-- 0.4.2 offers no gas conversion (ConversionDevices.offered); a project
-- begun with 0.1.0 to 0.4.1 is left to Cancel and Remove, as any other.
T.case("conversion: a gas project begun before 0.4.2 can be cancelled, and a finished one removed", function()
    local dev = gen()
    local p, a = prepared("gas_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 2 }))
    T.near(p.hours.install, 0.5, 1e-12)
    local r = P.cancel(p, a, dev, { now = 2 })
    T.ok(r.ok)
    T.eq(r.project.state, "Cancelled")
    -- install started (cancelReturn 0.75): hoses 2 -> 1, screws 6 -> 4; configure unstarted: wire 1 -> 1
    T.eq(r.returned["Base.RubberHose"], 1)
    T.eq(r.returned["Base.Screws"], 4)
    T.eq(r.returned["Base.ElectricWire"], 1)
    T.eq(P.effectiveProfile(r.project, dev), "generator_si_stock")
    noProblems(r.project)

    dev = gen()
    p, a = prepared("gas_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 9 }))
    T.eq(p.state, "Commissioned")
    T.eq(P.effectiveProfile(p, dev), "generator_gas")
    r = P.remove(p, a, dev, { now = 10 })
    T.ok(r.ok)
    T.eq(r.project.state, "Removed")
    -- removeReturn 0.5 floored per item: hoses 2 -> 1, screws 6 -> 3, wire 1 -> 0
    T.eq(r.returned["Base.RubberHose"], 1)
    T.eq(r.returned["Base.Screws"], 3)
    T.eq(r.returned["Base.ElectricWire"], nil)
    T.eq(P.benefits(r.project, dev), nil)
    T.eq(P.effectiveProfile(r.project, dev), "generator_si_stock")
    noProblems(r.project)
end)

T.case("conversion: interrupted installation keeps partial hours", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 1.5 }))
    T.eq(p.stage, "install")
    local r = P.work(p, a, dev, { now = 2.75, leave = true })
    p = must(r)
    T.eq(p.stage, "install")
    T.near(p.hours.install, 1.25, 1e-12)
    T.near(r.credited, 1.25, 1e-12)
    T.ok(r.released and p.workers.p1 == nil, "interrupted worker released")
    -- a day without work: nothing accrues, nothing is lost
    p = must(P.join(p, a, dev, { now = 26 }))
    T.near(p.hours.install, 1.25, 1e-12)
    p = must(P.work(p, a, dev, { now = 27 }))
    T.near(p.hours.install, 2.25, 1e-12)
    T.eq(p.stage, "install")
    p = must(P.work(p, a, dev, { now = 27.75 }))
    T.eq(p.stage, "configure")
    T.near(p.hours.install, 3, 1e-12)
    noProblems(p)
end)

T.case("conversion: lost tool or component blocks with a concrete reason; modules are never consumed twice", function()
    local dev = gen()
    local a = actor("p1", { ["Base.RubberHose"] = 1, ["Base.Screws"] = 2, ["Base.ElectricWire"] = 1 })
    local p = start("flex_generator", dev, a, 0)
    local r = P.deliver(p, a, dev, { now = 0 })
    p = must(r)
    take(a, r.consumed)
    T.eq(r.consumed["Base.Screws"], 2)
    T.eq(r.outstanding["Base.Screws"], 2)
    T.eq(r.consumed["Base.ElectricWire"], 1, "later-stage modules can be delivered ahead")
    p = must(P.join(p, a, dev, { now = 0 }))
    r = P.work(p, a, dev, { now = 3 })
    p = must(r)
    T.eq(p.stage, "install")
    T.near(r.credited, 1.5, 1e-12)
    T.near(r.unused, 1.5, 1e-12)
    T.eq(r.blocked.reason, "missing_module")
    T.eq(p.blocked.reason, "missing_module")
    T.eq(p.blocked.missing[1], "Base.Screws")
    T.eq(p.blocked.need["Base.Screws"], 2)
    T.ok(r.released and p.workers.p1 == nil, "blocked worker released")
    T.eq(P.join(p, a, dev, { now = 3 }).reason, "missing_module")
    T.eq(P.status(p, a, dev).blocked.reason, "missing_module")
    -- three screws found: only the two outstanding are consumed
    a.inventory["Base.Screws"] = 3
    r = P.deliver(p, a, dev, { now = 4 })
    p = must(r)
    take(a, r.consumed)
    T.eq(r.consumed["Base.Screws"], 2)
    T.eq(a.inventory["Base.Screws"], 1)
    T.eq(p.blocked, nil, "block cleared once the modules are in")
    T.eq(P.deliver(p, a, dev, { now = 4 }).reason, "nothing_needed")
    -- the wrench is lost in the middle of the installation
    p = must(P.join(p, a, dev, { now = 4 }))
    p = must(P.work(p, a, dev, { now = 5 }))
    T.near(p.hours.install, 1, 1e-12)
    a.inventory["Base.Wrench"] = 0
    r = P.work(p, a, dev, { now = 6 })
    p = must(r)
    T.eq(r.blocked.reason, "missing_tool")
    T.eq(r.blocked.missing[1], "Base.Wrench")
    T.near(r.credited, 0, 1e-12)
    T.near(p.hours.install, 1, 1e-12, "time without the tool is not credited")
    T.eq(p.blocked.reason, "missing_tool")
    local j = P.join(p, a, dev, { now = 6 })
    T.eq(j.reason, "missing_tool")
    T.eq(j.missing[1], "Base.Wrench")
    -- tool found again: work resumes where it stopped
    a.inventory["Base.Wrench"] = 1
    p = must(P.join(p, a, dev, { now = 7 }))
    T.eq(p.blocked, nil)
    p = must(P.work(p, a, dev, { now = 9 }))
    T.eq(p.stage, "configure")
    T.near(p.hours.install, 3, 1e-12)
    T.eq(sumDelivered(p), 1 + 4 + 1, "every module consumed exactly once")
    T.eq(p.delivered.install["Base.Screws"], 4)
    noProblems(p)
end)

T.case("conversion: prepare and install need a drained tank as observed by the caller", function()
    local dev = gen({ tankAmount = 3.5 })
    local p, a = prepared("flex_generator", dev, 0)
    local r = P.work(p, a, dev, { now = 1 })
    p = must(r)
    T.eq(p.stage, "prepare")
    T.near(r.credited, 0.5, 1e-12, "inspection does not need an empty tank")
    T.eq(r.blocked.reason, "tank_not_empty")
    T.near(r.blocked.amount, 3.5, 1e-12)
    T.eq(P.join(p, a, dev, { now = 1 }).reason, "tank_not_empty")
    dev.tankAmount = nil
    T.eq(P.join(p, a, dev, { now = 1 }).reason, "tank_unknown")
    dev.tankAmount = 0 / 0
    T.eq(P.join(p, a, dev, { now = 1 }).reason, "tank_unknown")
    dev.tankAmount = 0.01
    p = must(P.join(p, a, dev, { now = 1 }), "residue below the drain tolerance")
    p = must(P.work(p, a, dev, { now = 2.5 }))
    T.eq(p.stage, "install")
    T.near(p.hours.install, 0.5, 1e-12)
    dev.tankAmount = 2
    r = P.work(p, a, dev, { now = 3 })
    T.eq(r.blocked.reason, "tank_not_empty", "refuelled during the installation")
    T.near(r.project.hours.install, 0.5, 1e-12)
    noProblems(r.project)
end)

T.case("conversion: a device moved during work keeps its project (stable key)", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 1 }))
    local moved = gen({ position = { x = 300, y = 40, z = 1 } })
    p = must(P.work(p, a, moved, { now = 2 }), "work after moving")
    T.near(p.hours.inspect + p.hours.prepare + p.hours.install, 2, 1e-12)
    T.eq(P.work(p, a, gen({ key = "gen:G-2", engineId = "G-2" }), { now = 3 }).reason, "wrong_device")
    T.eq(P.work(p, a, gen({ chassis = "Base.Generator_Blue" }), { now = 3 }).reason, "wrong_device")
    p = must(P.work(p, a, moved, { now = 3 }))
    T.near(p.hours.install, 1.5, 1e-12)
    -- picked up / carried: work stops with a concrete reason, idle time is not credited
    local r = P.work(p, a, gen({ available = false }), { now = 4 })
    T.eq(r.blocked.reason, "device_unavailable")
    T.near(r.credited, 0, 1e-12)
    T.eq(P.join(r.project, a, gen({ available = false }), { now = 4 }).reason, "device_unavailable")
    p = must(P.join(r.project, a, moved, { now = 5 }))
    p = must(P.work(p, a, moved, { now = 5.5 }))
    T.near(p.hours.install, 2, 1e-12)
end)

T.case("conversion: concurrent workers add up to the limit; a worker is never counted twice", function()
    local dev = gen()
    local a, b, c = actor("a", modulesOf("flex_generator")), actor("b"), actor("c")
    local p = start("flex_generator", dev, a, 0)
    local r = P.deliver(p, a, dev, { now = 0 })
    p = must(r)
    take(a, r.consumed)
    p = must(P.join(p, a, dev, { now = 0 }))
    p = must(P.join(p, b, dev, { now = 0 }))
    local full = P.join(p, c, dev, { now = 0 })
    T.eq(full.reason, "project_full")
    T.eq(full.max, 2)
    local same = P.join(p, a, dev, { now = 0 })
    T.ok(same.ok and same.unchanged, "joining twice is idempotent")
    T.eq(same.project.rev, p.rev)
    T.eq(Tables.count(same.project.workers), 2)
    p = must(P.work(p, a, dev, { now = 1 }))
    p = must(P.work(p, b, dev, { now = 1 }))
    T.near(p.hours.inspect + p.hours.prepare + p.hours.install, 2, 1e-12, "two workers' hours add")
    local again = P.work(p, a, dev, { now = 1 })
    T.ok(again.ok and again.unchanged, "a repeated report credits nothing")
    T.eq(again.project.rev, p.rev)
    p = must(P.join(p, a, dev, { now = 1.5 }))
    p = must(P.work(p, a, dev, { now = 2 }))
    T.near(p.credit.a, 1.5, 1e-12, "re-joining forfeits the gap: never the same interval twice")
    T.near(p.credit.b, 1, 1e-12)
    p = must(P.leave(p, b, { now = 2 }))
    p = must(P.join(p, c, dev, { now = 2 }))
    T.eq(Tables.count(p.workers), 2)
    p = must(P.work(p, c, dev, { now = 3 }))
    p = must(P.work(p, a, dev, { now = 3 }))
    T.eq(p.stage, "configure")
    T.near(p.hours.install, 3, 1e-12)
    T.near(p.credit.a + p.credit.b + p.credit.c, 0.5 + 1 + 3, 1e-12)
    noProblems(p)
end)

T.case("conversion: engine replacement never leaves a ghost benefit", function()
    -- vehicle, rule "revert"
    local dev = car()
    local p, a = prepared("flex_car_normal", dev, 0)
    p = must(P.work(p, a, dev, { now = 6 }))
    p = must(P.work(p, a, dev, { now = 13 }))
    T.eq(p.state, "Commissioned")
    T.eq(P.benefits(p, dev).consumerProfile, "engine_si_flex")
    local swapped = car({ engineId = "E-2" })
    T.eq(P.benefits(p, swapped), nil, "no ghost benefit even before reconcile")
    T.eq(P.effectiveProfile(p, swapped), "engine_si_stock")
    local same = P.reconcile(p, dev, { now = 14 })
    T.ok(same.ok and same.unchanged)
    T.eq(same.project.rev, p.rev, "nothing observed: same revision")
    T.eq(P.reconcile(p, car({ key = "veh:7:Base.CarNormal" }), { now = 14 }).reason, "wrong_device")
    local r = P.reconcile(p, swapped, { now = 14 })
    T.ok(r.ok)
    T.eq(r.project.state, "Reverted")
    T.eq(r.project.endReason, "engine_replaced")
    T.eq(r.project.rev, p.rev + 1)
    -- CarNormal modules: hose 2, engine parts 2, screws 6, wire 2; removeReturn 0.5
    T.eq(r.returned["Base.RubberHose"], 1)
    T.eq(r.returned["Base.EngineParts"], 1)
    T.eq(r.returned["Base.Screws"], 3)
    T.eq(r.returned["Base.ElectricWire"], 1)
    T.eq(P.benefits(r.project, swapped), nil)
    T.eq(P.benefits(r.project, dev), nil)
    T.eq(P.effectiveProfile(r.project, swapped), "engine_si_stock")
    noProblems(r.project)
    -- generator, rule "invalidate"
    local g = gen()
    local q, b = prepared("flex_generator", g, 0)
    q = must(P.work(q, b, g, { now = 7.5 }))
    T.eq(q.state, "Commissioned")
    local r2 = P.reconcile(q, gen({ engineId = "G-9" }), { now = 8 })
    T.eq(r2.project.state, "Invalidated")
    T.ok(Tables.isEmpty(r2.returned), "invalidatedReturn = 0")
    T.eq(r2.lost["Base.Screws"], 4)
    noProblems(r2.project)
    -- replaced while the work is in progress
    local w, c = prepared("flex_generator", gen(), 0)
    w = must(P.work(w, c, gen(), { now = 1 }))
    T.eq(P.work(w, c, gen({ engineId = "G-7" }), { now = 2 }).reason, "engine_replaced")
    T.eq(P.deliver(w, c, gen({ engineId = "G-7" }), { now = 2 }).reason, "engine_replaced")
    local r3 = P.reconcile(w, gen({ engineId = "G-7" }), { now = 2 })
    T.eq(r3.project.state, "Cancelled")
    T.eq(r3.project.endReason, "engine_replaced")
    T.eq(r3.returned["Base.RubberHose"], 1, "unstarted install modules come back in full")
    T.eq(r3.returned["Base.Screws"], 4)
    T.eq(r3.returned["Base.ElectricWire"], 1)
    noProblems(r3.project)
end)

T.case("conversion: removal returns the documented fraction of modules and ends the benefit", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 7.5 }))
    T.eq(p.state, "Commissioned")
    local helper = actor("p2")
    helper.inventory["Base.Wrench"] = 0
    local r = P.remove(p, helper, dev, { now = 8 })
    T.eq(r.reason, "missing_tool")
    T.eq(r.missing[1], "Base.Wrench")
    T.eq(P.remove(p, actor("novice", nil, { skills = {} }), dev, { now = 8 }).reason, "missing_skill")
    r = P.remove(p, a, dev, { now = 8 })
    T.ok(r.ok)
    T.eq(r.project.state, "Removed")
    -- removeReturn 0.5 floored per item: hose 1 -> 0, screws 4 -> 2, wire 1 -> 0
    T.eq(r.returned["Base.Screws"], 2)
    T.eq(r.returned["Base.RubberHose"], nil)
    T.eq(r.lost["Base.RubberHose"], 1)
    T.eq(r.lost["Base.ElectricWire"], 1)
    T.eq(r.lost["Base.Screws"], 2)
    T.eq(P.benefits(r.project, dev), nil)
    T.eq(P.effectiveProfile(r.project, dev), "generator_si_stock")
    noProblems(r.project)
    T.eq(P.remove(r.project, a, dev, { now = 9 }).reason, "project_closed")
    T.ok(P.canBegin(P.new({ conversion = "gas_generator" }), a, gen({ project = r.project })).ok,
        "the generator can be converted again")
end)

T.case("conversion: abandoning returns unstarted modules in full and started ones by fraction", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 2 }))
    T.near(p.hours.install, 0.5, 1e-12)
    local r = P.cancel(p, a, dev, { now = 2 })
    T.ok(r.ok)
    T.eq(r.project.state, "Cancelled")
    T.eq(r.project.endReason, "abandoned")
    -- install started (cancelReturn 0.75): hose 1 -> 0, screws 4 -> 3; configure unstarted: wire 1 -> 1
    T.eq(r.returned["Base.Screws"], 3)
    T.eq(r.returned["Base.ElectricWire"], 1)
    T.eq(r.lost["Base.RubberHose"], 1)
    T.eq(Tables.count(r.project.workers), 0)
    noProblems(r.project)
end)

T.case("conversion: destruction cancels the project with the documented salvage", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    p = must(P.work(p, a, dev, { now = 2 }))
    local r = P.destroy(p, { now = 3 })
    T.ok(r.ok)
    T.eq(r.project.state, "Cancelled")
    T.eq(r.project.endReason, "destroyed")
    T.ok(Tables.isEmpty(r.returned), "destroyedReturn = 0: nothing comes back")
    T.eq(r.lost["Base.Screws"], 4)
    T.eq(r.lost["Base.ElectricWire"], 1)
    T.eq(Tables.count(r.project.workers), 0)
    noProblems(r.project)
    T.eq(P.work(r.project, a, dev, { now = 4 }).reason, "project_closed")
    T.eq(P.destroy(r.project, { now = 4 }).reason, "project_closed")
    T.eq(P.benefits(r.project, dev), nil)
    local closed = P.reconcile(r.project, dev, { now = 4 })
    T.ok(closed.ok and closed.unchanged)
    -- the adapter may report the destruction through reconcile as well
    T.eq(P.work(p, a, gen({ destroyed = true }), { now = 3 }).reason, "device_destroyed")
    local r2 = P.reconcile(p, gen({ destroyed = true }), { now = 3 })
    T.eq(r2.project.state, "Cancelled")
    T.eq(r2.project.endReason, "destroyed")
    -- a documented non-zero salvage fraction is honoured (floored)
    local q = Tables.deepCopy(p)
    q.snap.reversalAndSalvageRules.destroyedReturn = 0.5
    local r3 = P.destroy(q, { now = 3 })
    T.eq(r3.returned["Base.Screws"], 2)
    T.eq(r3.lost["Base.RubberHose"], 1)
    noProblems(r3.project)
    -- a commissioned vehicle can burn too
    local c = car()
    local v, m = prepared("flex_car_normal", c, 0)
    v = must(P.work(v, m, c, { now = 6 }))
    v = must(P.work(v, m, c, { now = 13 }))
    T.eq(v.state, "Commissioned")
    local r4 = P.destroy(v, { now = 20 })
    T.eq(r4.project.state, "Cancelled")
    T.eq(r4.project.endReason, "destroyed")
    T.eq(P.benefits(r4.project, c), nil)
    noProblems(r4.project)
end)

------------------------------------------------------------------------------
-- Persistence, revisions and time
------------------------------------------------------------------------------
T.case("conversion: save/load in the middle of work round-trips through a deep copy", function()
    local dev = gen()
    local a, b = actor("a", { ["Base.RubberHose"] = 1, ["Base.Screws"] = 4 }), actor("b")
    local p = start("flex_generator", dev, a, 0)
    local r = P.deliver(p, a, dev, { now = 0 })
    p = must(r)
    take(a, r.consumed)
    p = must(P.join(p, a, dev, { now = 0 }))
    p = must(P.join(p, b, dev, { now = 0.5 }))
    p = must(P.work(p, a, dev, { now = 2 }))
    T.eq(p.stage, "install")
    local saved = Tables.deepCopy(p)
    T.ok(Tables.deepEqual(saved, p), "identical after the round trip")
    T.eq(R.canonical(saved), R.canonical(p))
    local function continueWork(q)
        q = must(P.work(q, b, dev, { now = 3 }))
        local blocked = P.work(q, a, dev, { now = 3.5 })
        q = must(blocked)
        T.eq(blocked.blocked.reason, "missing_module")
        q = must(P.deliver(q, actor("c", { ["Base.ElectricWire"] = 1 }), dev, { now = 3.5 }))
        q = must(P.join(q, a, dev, { now = 3.5 }))
        q = must(P.work(q, a, dev, { now = 4.5 }))
        return q
    end
    local x, y = continueWork(p), continueWork(saved)
    T.ok(Tables.deepEqual(x, y), "same continuation from the saved copy")
    T.eq(R.canonical(x), R.canonical(y))
    T.eq(x.state, "InProgress")
    T.eq(x.stage, "configure")
    noProblems(x)
end)

T.case("conversion: every committed change bumps the revision once; stale requests are rejected", function()
    local dev = gen()
    local a = actor("p1", modulesOf("flex_generator"))
    local draft = P.new({ conversion = "flex_generator" })
    T.eq(P.begin(draft, a, dev, { now = 0, expectedRev = 3 }).reason, "stale")
    local p = must(P.begin(draft, a, dev, { now = 0, expectedRev = 0 }))
    T.eq(p.rev, 1)
    local steps = {
        function(q) return P.deliver(q, a, dev, { now = 0, expectedRev = q.rev }) end,
        function(q) return P.join(q, a, dev, { now = 0, expectedRev = q.rev }) end,
        function(q) return P.work(q, a, dev, { now = 1, expectedRev = q.rev }) end,
        function(q) return P.leave(q, a, { now = 1, expectedRev = q.rev }) end,
        function(q) return P.join(q, a, dev, { now = 2, expectedRev = q.rev }) end,
        function(q) return P.work(q, a, dev, { now = 8.5, expectedRev = q.rev }) end,
        function(q) return P.remove(q, a, dev, { now = 9, expectedRev = q.rev }) end,
    }
    for i, step in ipairs(steps) do
        local r = step(p)
        T.ok(r.ok, "step " .. tostring(i) .. ": " .. tostring(r.reason))
        T.eq(r.project.rev, p.rev + 1, "step " .. tostring(i) .. " bumps once")
        p = r.project
    end
    T.eq(p.state, "Removed")
    -- every mutating operation refuses a stale revision and changes nothing
    local q, b = prepared("flex_generator", gen(), 0)
    local old = q.rev - 1
    local before = Tables.deepCopy(q)
    local stale = {
        P.join(q, actor("x"), gen(), { now = 1, expectedRev = old }),
        P.work(q, b, gen(), { now = 1, expectedRev = old }),
        P.leave(q, b, { now = 1, expectedRev = old }),
        P.deliver(q, actor("y", { ["Base.Screws"] = 1 }), gen(), { now = 1, expectedRev = old }),
        P.cancel(q, b, gen(), { now = 1, expectedRev = old }),
        P.destroy(q, { now = 1, expectedRev = old }),
        P.reconcile(q, gen({ destroyed = true }), { now = 1, expectedRev = old }),
        P.remove(q, b, gen(), { now = 1, expectedRev = old }),
    }
    for i, r in ipairs(stale) do
        T.eq(r.reason, "stale", "operation " .. tostring(i))
        T.eq(r.rev, q.rev, "stale reply carries the current revision")
    end
    T.ok(Tables.deepEqual(q, before), "nothing changed")
    T.ok(P.work(q, b, gen(), { now = 1, expectedRev = q.rev }).ok, "current revision accepted")
end)

T.case("conversion: one large work report equals many small ones (randomized split)", function()
    local rng = TLG.Rng.new(TEST_SEED)
    local dev = gen()
    for _, span in ipairs({ 4.3, 7.5, 11 }) do
        local base, a = prepared("flex_generator", dev, 2)
        local whole = must(P.work(base, a, dev, { now = 2 + span }))
        local stepped, t = base, 2
        while t < 2 + span and stepped.state == "InProgress" do
            t = math.min(2 + span, t + rng:range(0.01, 1.7))
            stepped = must(P.work(stepped, a, dev, { now = t }))
        end
        T.eq(whole.state, stepped.state, "state")
        T.eq(whole.stage, stepped.stage, "stage")
        for _, s in ipairs(P.STAGES) do T.near(whole.hours[s], stepped.hours[s], 1e-9, "hours " .. s) end
        T.near(whole.credit.p1, stepped.credit.p1, 1e-9, "credit")
        if whole.state == "Commissioned" then
            T.near(whole.commissionedAt, 9.5, 1e-9)
            T.near(stepped.commissionedAt, 9.5, 1e-9)
        end
        noProblems(whole)
        noProblems(stepped)
    end
end)

T.case("conversion: late reports credit at most the worker timeout; expired assignments free their slot", function()
    local dev = car()
    local p, a = prepared("flex_car_normal", dev, 0)
    local r = P.work(p, a, dev, { now = 30 })
    p = must(r)
    T.ok(r.expired, "assignment expired")
    T.near(r.credited, P.WORKER_TIMEOUT_HOURS, 1e-9)
    T.eq(p.workers.p1, nil)
    T.eq(p.stage, "test")
    T.near(p.hours.test, 1, 1e-9)
    local b, c, d = actor("b"), actor("c"), actor("d")
    p = must(P.join(p, a, dev, { now = 30 }))
    p = must(P.join(p, b, dev, { now = 30 }))
    p = must(P.join(p, c, dev, { now = 30 }))
    T.eq(P.join(p, d, dev, { now = 31 }).reason, "project_full")
    local j = P.join(p, d, dev, { now = 30 + P.WORKER_TIMEOUT_HOURS + 1 })
    T.ok(j.ok)
    T.eq(#j.evicted, 3)
    T.eq(Tables.count(j.project.workers), 1)
    noProblems(j.project)
end)

T.case("conversion: a caller's tighter worker timeout limits credit for time away from the device", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    -- reporting every quarter hour while present: everything is credited
    for i = 1, 4 do p = must(P.work(p, a, dev, { now = i * 0.25, workerTimeoutHours = 1 })) end
    T.near(p.credit.p1, 1, 1e-12)
    -- three hours away, then a report: at most the timeout, and the worker is out
    local r = P.work(p, a, dev, { now = 4, workerTimeoutHours = 1 })
    p = must(r)
    T.ok(r.expired and r.released, "late report ends the assignment")
    T.near(r.credited, 1, 1e-12)
    T.eq(P.work(p, a, dev, { now = 4.25, workerTimeoutHours = 1 }).reason, "not_assigned")
    -- re-joining forfeits the gap; stale helpers are evicted after the same timeout
    local b = actor("b")
    p = must(P.join(p, b, dev, { now = 4, workerTimeoutHours = 1 }))
    p = must(P.join(p, a, dev, { now = 5.5, workerTimeoutHours = 1 }))
    T.eq(p.workers.b, nil, "b reported last at 4: evicted at 5.5")
    p = must(P.work(p, a, dev, { now = 5.75, workerTimeoutHours = 1 }))
    T.near(p.credit.p1, 2.25, 1e-12, "the 1.5 h before re-joining are not credited")
    for _, bad in ipairs({ 0, -1, 0 / 0 }) do
        T.eq(P.work(p, a, dev, { now = 6, workerTimeoutHours = bad }).reason, "malformed_request")
    end
    noProblems(p)
end)

T.case("conversion: content updates never reinterpret an active project", function()
    local dev = gen()
    local p, a = prepared("flex_generator", dev, 0)
    local def = R.get("conversion", "flex_generator")
    local old = def.workStages[3].hours
    local fp = p.fp
    def.workStages[3].hours = 99
    local changed = R.fingerprint("conversion", "flex_generator")
    local ok, err = pcall(function() p = must(P.work(p, a, dev, { now = 7.5 })) end)
    def.workStages[3].hours = old
    T.ok(ok, tostring(err))
    T.eq(p.state, "Commissioned", "the snapshot (install 3 h) was used")
    T.ok(changed ~= fp, "a content change is visible through the fingerprint")
    T.eq(R.fingerprint("conversion", "flex_generator"), fp)
end)

T.case("conversion: randomized operations keep every invariant and conserve modules", function()
    local rng = TLG.Rng.new(TEST_SEED + 11)
    for round = 1, 6 do
        local conv = Num.mod(round, 2) == 1 and "flex_generator" or "flex_car_normal"
        local dev = conv == "flex_generator" and gen() or car()
        local actors = { actor("a"), actor("b"), actor("c") }
        local p = start(conv, dev, actors[1], 0)
        local mods = Tables.sortedKeys(modulesOf(conv))
        local consumed = {}
        local t = 0
        for step = 1, 160 do
            if p.state ~= "InProgress" then break end
            t = t + rng:range(0, 1.2)
            local who = actors[rng:int(1, 3)]
            who.inventory["Base.Wrench"] = (rng:int(0, 5) > 0) and 1 or 0
            for _, item in ipairs(mods) do who.inventory[item] = rng:int(0, 2) end
            dev.tankAmount = (rng:int(0, 5) > 0) and 0 or 2
            local op = rng:int(1, 7)
            local r
            if op == 1 or op == 2 then
                r = P.join(p, who, dev, { now = t })
            elseif op == 3 or op == 4 then
                r = P.work(p, who, dev, { now = t })
            elseif op == 5 then
                r = P.deliver(p, who, dev, { now = t })
            elseif op == 6 then
                r = P.leave(p, who, { now = t })
            else
                r = P.work(p, who, dev, { now = t, leave = true })
            end
            if r.ok then
                if r.unchanged then
                    T.eq(r.project.rev, p.rev, "unchanged keeps the revision")
                else
                    T.eq(r.project.rev, p.rev + 1, "one commit, one revision")
                end
                for _, item in ipairs(Tables.sortedKeys(r.consumed or {})) do
                    consumed[item] = (consumed[item] or 0) + r.consumed[item]
                end
                p = r.project
            end
            noProblems(p, "round " .. tostring(round) .. " step " .. tostring(step))
            T.eq(P.benefits(p, dev) ~= nil, p.state == "Commissioned", "benefits exactly when commissioned")
        end
        for _, item in ipairs(mods) do
            local held = 0
            for _, stage in ipairs(P.STAGES) do held = held + (p.delivered[stage][item] or 0) end
            T.eq(held, consumed[item] or 0, "consumed equals held for " .. item)
        end
        local r = P.destroy(p, { now = t + 1 })
        if r.ok then
            noProblems(r.project, "after destruction")
            for _, item in ipairs(mods) do
                T.eq((r.returned[item] or 0) + (r.lost[item] or 0), consumed[item] or 0, "salvage balance " .. item)
            end
        end
    end
end)
