-- Bootstrap audit for every energy route (spec §10, "Bootstrap requirement
-- for every route"). One record per route publishes knowledge and skills,
-- equipment, initial external energy, renewable inputs, finite dependencies,
-- recovery after power loss, late-world acquisition and a classification:
--   renewable     every input consumed in steady operation has a renewable
--                 source, directly or through a recipe whose own required
--                 inputs are renewable; equipment is a one-time build
--   transitional  depends on at least one finite, scavenged input
--
-- Routes.audit() checks the records against the registry content:
--   * listed recipes and machines exist
--   * every required recipe input (min > 0) and the firebox fuel of heated
--     stages is declared in `consumes` or produced inside the route, so a
--     route cannot hide a finite input by leaving it out
--   * a renewable route consumes nothing without a renewable source
--   * a transitional route really has a finite input (labels stay honest)
--   * no route needs its own finished product to start
-- The walk over source recipes is iterative with a visited set (the
-- firewood -> firebox -> firewood cycle is real).
require "TLG/Registry/Registry"
require "TLG/Util/Tables"
require "TLG/Content/Fuels"
require "TLG/Content/Production"
require "TLG/Content/Biodiesel"
require "TLG/Content/WoodGas"
require "TLG/Content/Biogas"
require "TLG/Content/Propane"

TLG.Domain = TLG.Domain or {}
TLG.Domain.Routes = TLG.Domain.Routes or {}
local Routes = TLG.Domain.Routes
local Registry, Tables = TLG.Registry, TLG.Tables

Routes.CLASSES = { renewable = true, transitional = true }
-- Fireboxes burn solid wood fuel; a heated stage consumes it.
Routes.HEAT_FUEL = "firewood"
Routes.REQUIRED_FIELDS = { "knowledge", "skills", "equipment", "initialEnergy", "renewableInputs",
    "finiteDependencies", "recovery", "lateWorld" }

-- Where each consumed id comes from. `recipe` = produced by that recipe (its
-- required inputs must be renewable too); otherwise `origin` describes a
-- primary world source.
Routes.sources = {
    sugar_eq = { renewable = true, origin = "crops: sugar beet, corn, potato, pumpkin, fruit" },
    water = { renewable = true, origin = "rain collectors, wells, rivers" },
    firewood = { renewable = true, origin = "trees: logs, planks, branches" },
    wood_chips_dry = { renewable = true, origin = "chopped and dried wood" },
    charcoal = { renewable = true, recipe = "methanol_wood_distill" },
    oilseed = { renewable = true, origin = "crops: sunflower, soybean" },
    manure = { renewable = true, origin = "livestock (animal husbandry)" },
    food_waste = { renewable = true, origin = "kitchen scraps and spoiled harvest" },
    yeast = { renewable = true, origin = "starter culture kept from each fermentation (yeast_starter)" },
    ethanol = { renewable = true, recipe = "ethanol_ferment" },
    plant_oil = { renewable = true, recipe = "press_oilseed" },
    methanol = { renewable = true, recipe = "methanol_wood_distill" },
    wood_ash = { renewable = true, recipe = "ash_burn" },
    lye = { renewable = true, recipe = "lye_leach" },
    biodiesel = { renewable = true, recipe = "biodiesel_react" },
    quicklime_kg = { renewable = false, origin = "scavenged Base.Quicklime (no lime kiln in this release)" },
    propane = { renewable = false, origin = "scavenged cylinders and bulk tanks; never respawns" },
    gasoline = { renewable = false, origin = "scavenged fuel and station reserves" },
    diesel = { renewable = false, origin = "scavenged fuel and station reserves" },
}

Routes.list = {
    {
        id = "ethanol", label = "Fuel ethanol", classification = "renewable", early = true,
        products = { "ethanol" },
        recipes = { "ethanol_ferment", "ethanol_distill" },
        optionalRecipes = { "ethanol_dry" },
        consumes = { "sugar_eq", "water", "firewood", "yeast" },
        startup = { heat = "firewood", electricity = false },
        knowledge = { "Fermentation and distillation of fuel alcohol", "Flex-fuel conversion of spark engines" },
        skills = { "Cooking: mash preparation (labour stages are faster with skill)",
            "Metalworking: still and drying column", "Mechanics: flex-fuel engine conversion" },
        equipment = { machines = { "fermenter_barrel", "pot_still", "reflux_still", "drying_column" },
            items = { "flex-fuel generator or vehicle (generator_si_flex / engine_si_flex)" } },
        initialEnergy = "Manual labour plus an independent wood fire under the still; no electricity, no finished fuel.",
        renewableInputs = { "sugar_eq", "water", "firewood", "yeast" },
        finiteDependencies = {
            "Base.Yeast for the first batch, until a starter culture is kept (yeast_starter byproduct)",
            "Base.Quicklime only for anhydrous ethanol (gasoline blends, optional ethanol_dry); hydrous ethanol runs flex engines",
            "Still parts from salvaged drums, pipe and sheet metal (one-time build)",
        },
        recovery = "No electricity in the chain. A still that loses its fire pauses (no_heat) and resumes when the "
            .. "firebox is refilled; fermentation stalls when too cold and spoils after 72 h paused; outputs wait "
            .. "in the machine until collected.",
        lateWorld = "Crops, water and wood stay renewable indefinitely; stills can be rebuilt from scrap metal.",
    },
    {
        id = "biodiesel", label = "Biodiesel", classification = "renewable", early = false,
        products = { "biodiesel" },
        recipes = { "press_oilseed", "methanol_wood_distill", "ash_burn", "lye_leach", "biodiesel_react",
            "biodiesel_wash" },
        consumes = { "oilseed", "firewood", "water" },
        startup = { heat = "firewood", electricity = false },
        knowledge = { "Oil pressing, wood distillation, lye leaching and transesterification",
            "Explicit diesel consumer profiles (original diesel engines only)" },
        skills = { "Farming: oilseed crops", "Cooking: reactor mixing and washing (skill raises conversion and soap removal)",
            "Metalworking: retort, reactor and wash tank" },
        equipment = { machines = { "oil_press", "wood_retort", "ash_pit", "lye_leacher", "biodiesel_reactor",
            "biodiesel_wash_tank" }, items = { "diesel engine or generator (engine_ci_bio / generator_ci_stock)" } },
        initialEnergy = "Manual labour and independent wood fires (retort, leacher, reactor, drying); no electricity.",
        renewableInputs = { "oilseed", "firewood", "water" },
        finiteDependencies = {
            "Scavenged cooking oil and lard: optional finite shortcut into the reactor",
            "Diesel engines and generators are original, finite equipment",
            "Salvaged drums, pipe and a hand pump for reactor and wash tank (one-time build)",
        },
        recovery = "Fire-heated stages pause (no_heat) and resume when refuelled; settling slows below 10 C and "
            .. "stalls below 0 C (too_cold) without spoiling; no electricity needed.",
        lateWorld = "Oilseed, wood and water are renewable; methanol from wood distillation and lye from wood ash "
            .. "replace the last scavenged processing inputs.",
    },
    {
        id = "woodgas", label = "Wood gas", classification = "renewable", early = false,
        products = { "woodgas" },
        recipes = { "woodgas_gasify" },
        consumes = { "firewood" },
        startup = { heat = "firewood", electricity = false },
        knowledge = { "Gasifier construction, lighting and filter service", "Gas engine conversion (stationary or vehicle)" },
        skills = { "Metalworking: hearth, cooler and filter", "Mechanics: vehicle mounting and engine conversion",
            "Axe work: dry, sized fuel" },
        equipment = { machines = { "gasifier_stationary", "gasifier_vehicle" },
            items = { "gas engine generator (generator_gas) or a converted vehicle" } },
        initialEnergy = "Kindling and an ignition source to light the hearth; the warm-up burns hopper feed and "
            .. "flares its gas. No electricity, no finished fuel.",
        renewableInputs = { "firewood", "wood_chips_dry", "charcoal" },
        finiteDependencies = {
            "Salvaged steel cylinders, pipe and a radiator-type cooler (one-time build)",
            "Matches or a lighter to light it (an existing fire works too)",
        },
        recovery = "Gas is never stored: with no draw the gasifier pauses (buffer_full) and goes out after its hold "
            .. "time (3 h stationary, 1 h vehicle); it is then relit and warmed up again. A loaded filter pauses it "
            .. "(filter_full) until serviced.",
        lateWorld = "Wood is renewable; charcoal from the wood retort is a cleaner feed; the gasifier is built from scrap.",
    },
    {
        id = "biogas", label = "Biogas", classification = "renewable", early = false,
        products = { "biogas" },
        recipes = { "biogas_digest" },
        optionalRecipes = { "biogas_digest_heated" },
        consumes = { "manure" },
        startup = { heat = "none", electricity = false },
        knowledge = { "Digester construction, inoculation and low-pressure gas handling",
            "Gas engine conversion for stationary generators" },
        skills = { "Animal care: manure collection", "Metalworking/plumbing: digester, gas holder and piping" },
        equipment = { machines = { "biogas_digester", "biogas_digester_heated" },
            items = { "low-pressure gas holder (gas_holder)", "gas engine generator (generator_gas)" } },
        initialEnergy = "None for the unheated digester (manure carries the culture); the heated digester needs an "
            .. "independent wood fire. No electricity.",
        renewableInputs = { "manure", "food_waste", "water" },
        finiteDependencies = { "Tanks (IBC or drums), hoses and a low-pressure gas holder (one-time build)" },
        recovery = "No electricity. Digestion stalls below 10 C and resumes when warm (no spoilage); the heated "
            .. "digester pauses (no_heat) without firebox fuel; the gas holder leaks slowly and a full holder "
            .. "leaves the rest waiting in the digester.",
        lateWorld = "Livestock and kitchen waste are renewable; output per digester is capped "
            .. "(MAX_NM3_PER_DIGESTER_DAY), so more gas needs more digesters, never respawned inputs.",
    },
    {
        id = "propane", label = "Propane", classification = "transitional", early = false,
        products = {},
        recipes = {},
        consumes = { "propane" },
        startup = { heat = "none", electricity = false },
        knowledge = { "Cylinder handling, regulators and gas-tight connections", "Gas engine conversion" },
        skills = { "Mechanics: regulator and engine conversion" },
        equipment = { machines = {}, items = { "Base.PropaneTank cylinders (propane_cylinder)", "bulk tanks (propane_bulk)",
            "regulator and hoses", "converted gas engine (generator_gas)" } },
        initialEnergy = "None: scavenged propane is a ready-to-use finished fuel.",
        renewableInputs = {},
        finiteDependencies = { "All propane: scavenged cylinders and bulk tanks; no production route, never respawns" },
        recovery = "Propane does not degrade in storage; damaged cylinders cannot be refilled (vessel_unsafe) but "
            .. "can still be emptied.",
        lateWorld = "Only what is left in cylinders and bulk tanks: a transitional supply and emergency reserve "
            .. "while a renewable route is built.",
    },
    {
        id = "generator_battery", label = "Fueled generator and battery storage", classification = "transitional",
        early = false,
        products = {},
        recipes = {},
        consumes = { "gasoline" },
        startup = { fuel = "gasoline", electricity = false },
        note = "A battery stores energy and never creates it. Charging from a fueled generator keeps the "
            .. "generator's upstream fuel requirement: stored energy is renewable only when the generator's fuel "
            .. "route is (Routes.chargingClass). This record assumes a stock generator on scavenged gasoline.",
        knowledge = { "Generator operation and battery bank wiring" },
        skills = { "Electrical: battery bank, controller and charging" },
        equipment = { machines = {}, items = { "generator (stock or converted)", "battery bank, controller and wiring" } },
        initialEnergy = "Fuel for the generator: the fuel's route sets the bootstrap.",
        renewableInputs = {},
        finiteDependencies = { "Scavenged gasoline for a stock generator", "Batteries wear out (salvaged, finite)" },
        recovery = "The bank carries loads through generator downtime and waits for the generator when "
            .. "discharged; the fuel route sets everything else.",
        lateWorld = "Only as renewable as the generator's fuel: run a flex (ethanol), gas (biogas, wood gas) or "
            .. "diesel (biodiesel) generator.",
    },
}

function Routes.get(id)
    for _, r in ipairs(Routes.list) do
        if r.id == id then return r end
    end
    return nil
end

-- Steady-state consumption of one recipe: inputs with min > 0 plus the
-- firebox fuel when a stage needs heat. Sorted ids.
function Routes.requiredInputs(def)
    local set = {}
    for _, id in ipairs(Tables.sortedKeys(def.inputs or {})) do
        if (def.inputs[id].min or 0) > 0 then set[id] = true end
    end
    for _, st in ipairs(def.stages or {}) do
        if st.heatKW and st.heatKW > 0 then set[Routes.HEAT_FUEL] = true end
    end
    return Tables.sortedKeys(set)
end

-- Is `id` renewable all the way down? Returns ok and, when not, the first id
-- without a renewable source.
function Routes.isRenewable(id)
    local stack, seen = { id }, {}
    while #stack > 0 do
        local cur = stack[#stack]
        stack[#stack] = nil
        if not seen[cur] then
            seen[cur] = true
            local src = Routes.sources[cur]
            if src == nil or src.renewable ~= true then return false, cur end
            if src.recipe ~= nil then
                local def = Registry.get("recipe", src.recipe)
                if def == nil then return false, cur end
                local req = Routes.requiredInputs(def)
                -- A source recipe with only optional inputs proves nothing.
                if #req == 0 then return false, cur end
                for _, r in ipairs(req) do stack[#stack + 1] = r end
            end
        end
    end
    return true, nil
end

-- Audits one route record without modifying it; returns a list of problems.
function Routes.auditRoute(route)
    local problems = {}
    local function problem(msg) problems[#problems + 1] = tostring(route.id) .. ": " .. msg end
    if type(route.id) ~= "string" then problem("route needs a string id") end
    if not Routes.CLASSES[route.classification] then problem("classification must be renewable or transitional") end
    for _, f in ipairs(Routes.REQUIRED_FIELDS) do
        if route[f] == nil or route[f] == "" then problem("missing " .. f) end
    end
    local inRoute, consumes, needed = {}, {}, {}
    for _, rid in ipairs(route.recipes or {}) do inRoute[rid] = true end
    for _, id in ipairs(route.consumes or {}) do
        consumes[id] = true
        needed[id] = true
    end
    for _, rid in ipairs(route.recipes or {}) do
        local def = Registry.get("recipe", rid)
        if def == nil then
            problem("unknown recipe " .. tostring(rid))
        else
            local req = Routes.requiredInputs(def)
            if #req == 0 then
                local any = false
                for _, id in ipairs(Tables.sortedKeys(def.inputs or {})) do
                    if consumes[id] then any = true end
                end
                if not any then problem("recipe " .. rid .. " consumes none of its declared inputs") end
            end
            for _, id in ipairs(req) do
                local src = Routes.sources[id]
                local internal = src ~= nil and src.recipe ~= nil and inRoute[src.recipe] == true
                if not internal and not consumes[id] then
                    problem("undeclared input " .. id .. " (" .. rid .. ")")
                end
                needed[id] = true
            end
        end
    end
    for _, rid in ipairs(route.optionalRecipes or {}) do
        if Registry.get("recipe", rid) == nil then problem("unknown recipe " .. tostring(rid)) end
    end
    local eq = route.equipment or {}
    for _, mid in ipairs(eq.machines or {}) do
        if Registry.get("machine", mid) == nil then problem("unknown machine " .. tostring(mid)) end
    end
    if route.classification == "renewable" then
        if #(route.consumes or {}) == 0 then problem("renewable route declares no consumed input") end
        for _, id in ipairs(Tables.sortedKeys(needed)) do
            local ok, where = Routes.isRenewable(id)
            if not ok then
                problem("renewable route consumes " .. id .. " with no renewable source (" .. tostring(where) .. ")")
            end
        end
    elseif route.classification == "transitional" then
        local finite = false
        for _, id in ipairs(Tables.sortedKeys(needed)) do
            if not Routes.isRenewable(id) then finite = true end
        end
        if not finite then problem("transitional route has no finite input; classify it renewable") end
    end
    for _, id in ipairs(route.renewableInputs or {}) do
        if not Routes.isRenewable(id) then problem("listed renewable input " .. id .. " has no renewable source") end
    end
    local products = {}
    for _, id in ipairs(route.products or {}) do products[id] = true end
    local s = route.startup or {}
    if s.heat ~= nil and products[s.heat] then problem("startup heat needs its own product " .. s.heat) end
    if s.fuel ~= nil and products[s.fuel] then problem("startup needs its own product " .. s.fuel) end
    return problems
end

-- Audits a list of routes (default: the shipped list). Sorted problems.
function Routes.audit(list)
    local problems, seen = {}, {}
    for _, r in ipairs(list or Routes.list) do
        if seen[r.id] then problems[#problems + 1] = tostring(r.id) .. ": duplicate route" end
        seen[r.id] = true
        for _, p in ipairs(Routes.auditRoute(r)) do problems[#problems + 1] = p end
    end
    return Tables.sort(problems)
end

-- Classification of energy stored in a battery charged from `routeId`: a
-- battery inherits the route of whatever charges it.
function Routes.chargingClass(routeId)
    local r = Routes.get(routeId)
    return r and r.classification or nil
end

return Routes
