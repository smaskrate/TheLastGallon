-- ConversionDefinition content (spec §11). Hours, counts and fractions are
-- game-design values; every chassis, item and knowledge id was checked
-- against the installed 42.21.0 scripts. Evidence paths are relative to
-- <game>/media/scripts/generated. Vehicles are `vehicle <Name>` blocks inside
-- `module Base`, so their script full name is Base.<Name>; generators and
-- tools/modules are items in `module Base` (items/normal.txt:1,
-- items/weapon.txt:1).
--
-- Runtime status: domain-tested (tests/domain/test_conversions.lua).
-- flex_generator on Base.Generator and flex_car_normal on Base.CarNormal were
-- verified in a single-player client (RT-SP 2026-10-31, run 8: commissioned,
-- ran on ethanol, survived reload); every other route below is
-- "domain-tested, runtime NOT RUN" in the conversion matrix
-- (docs/support-matrix.md). Profession/police variants that share these
-- templates are deliberately not listed until tested.
require "TLG/Domain/Conversions/Project"
require "TLG/Content/Fuels"
require "TLG/Content/Storage"
require "TLG/Content/Consumers"
local R = TLG.Registry

-- Tools and modules (vanilla items).
local WRENCH = "Base.Wrench"                -- items/weapon.txt:5756 (tag base:wrench)
local PIPE_WRENCH = "Base.PipeWrench"       -- items/weapon.txt:4167
local SCREWDRIVER = "Base.Screwdriver"      -- items/weapon.txt:18169 (tag base:screwdriver)
local PLIERS = "Base.Pliers"                -- items/normal.txt:11168
local RUBBER_HOSE = "Base.RubberHose"       -- items/normal.txt:11180
local SCREWS = "Base.Screws"                -- items/normal.txt:3455
local SMALL_SHEET = "Base.SmallSheetMetal"  -- items/normal.txt:8493
local METAL_PIPE = "Base.MetalPipe"         -- items/weapon.txt:3805
local ELECTRIC_WIRE = "Base.ElectricWire"   -- items/normal.txt:4525
local ENGINE_PARTS = "Base.EngineParts"     -- items/normal.txt:11818

-- Knowledge (vanilla recipe names taught by magazines).
local GENERATOR_RECIPE = "Generator"                  -- items/literature.txt:5362 (ElectronicsMag4)
local BASIC_MECHANICS = "Basic Mechanics"             -- items/literature.txt:5782 (MechanicMag1);
                                                      -- vehicle part installs: vehicles/template_gastank.txt:46
local INTERMEDIATE_MECHANICS = "Intermediate Mechanics" -- items/literature.txt:5798 (MechanicMag2);
                                                      -- pickup gas tank: vehicles/vehicle_pickuptruck_template.txt:149

local function generatorTypes()
    return {
        "Base.Generator",        -- items/normal.txt:4800
        "Base.Generator_Yellow", -- items/normal.txt:4817
        "Base.Generator_Blue",   -- items/normal.txt:4834
        "Base.Generator_Old",    -- items/normal.txt:4851
    }
end

local function stages(h)
    return {
        { id = "inspect", hours = h[1] },
        { id = "prepare", hours = h[2] },    -- drain/isolate: the tank must be empty
        { id = "install", hours = h[3] },
        { id = "configure", hours = h[4] },
        { id = "test", hours = h[5] },
        { id = "commission", hours = h[6] },
    }
end

------------------------------------------------------------------------------
-- (a) Ethanol/flex conversion of the spark-ignition generators
------------------------------------------------------------------------------
R.define("conversion", {
    id = "flex_generator",
    deviceKind = "generator",
    chassisClass = "generator",
    supportedChassis = generatorTypes(),
    originalEngineProfile = "generator_si_stock",
    targetConsumerProfile = "generator_si_flex",
    requiredKnowledge = { skills = { Mechanics = 2, Electricity = 2 }, recipes = { GENERATOR_RECIPE } },
    workStages = stages({ 0.5, 1.0, 3.0, 1.5, 1.0, 0.5 }),
    requiredTools = {
        inspect = { SCREWDRIVER },
        prepare = { WRENCH },
        install = { WRENCH, SCREWDRIVER },
        configure = { SCREWDRIVER, PLIERS },
        test = {},
        commission = {},
    },
    requiredModules = {
        install = { [RUBBER_HOSE] = 1, [SCREWS] = 4 },   -- alcohol-rated fuel line, enlarged jet carrier
        configure = { [ELECTRIC_WIRE] = 1 },             -- cold-start enrichment circuit
    },
    cargoAndWeightImpact = { massKg = 2, cargoLitres = 0 },
    fuelStorageChanges = { drainRequired = true, tank = "keep", tankProfile = "generator_tank" },
    visualConfiguration = { labelKey = "IGUI_TLG_Conversion_flex_generator", badge = "flex" },
    reversalAndSalvageRules = {
        removeReturn = 0.5, cancelReturn = 0.75, destroyedReturn = 0, invalidatedReturn = 0,
        onEngineReplaced = "invalidate", removeHours = 2, tools = { WRENCH, SCREWDRIVER },
    },
    maxWorkers = 2,
})

------------------------------------------------------------------------------
-- (d) Gaseous fuel (propane / biogas / wood gas) generator conversion
------------------------------------------------------------------------------
R.define("conversion", {
    id = "gas_generator",
    deviceKind = "generator",
    chassisClass = "generator",
    supportedChassis = generatorTypes(),
    originalEngineProfile = "generator_si_stock",
    targetConsumerProfile = "generator_gas",
    requiredKnowledge = { skills = { Mechanics = 3, Electricity = 3 }, recipes = { GENERATOR_RECIPE } },
    workStages = stages({ 0.5, 1.0, 4.0, 2.0, 1.0, 0.5 }),
    requiredTools = {
        inspect = { SCREWDRIVER },
        prepare = { WRENCH },
        install = { PIPE_WRENCH, WRENCH, SCREWDRIVER },
        configure = { SCREWDRIVER, PLIERS },
        test = {},
        commission = {},
    },
    requiredModules = {
        -- gas line, mixer body and plate, fasteners
        install = { [RUBBER_HOSE] = 2, [METAL_PIPE] = 1, [SMALL_SHEET] = 1, [SCREWS] = 6 },
        configure = { [ELECTRIC_WIRE] = 1 },             -- shut-off solenoid
    },
    cargoAndWeightImpact = { massKg = 4, cargoLitres = 0 },
    -- The liquid tank is isolated; gas comes from an external vessel.
    fuelStorageChanges = { drainRequired = true, tank = "disable",
        external = { storages = { "propane_cylinder", "gas_holder" } } },
    visualConfiguration = { labelKey = "IGUI_TLG_Conversion_gas_generator", badge = "gas" },
    reversalAndSalvageRules = {
        removeReturn = 0.5, cancelReturn = 0.75, destroyedReturn = 0, invalidatedReturn = 0,
        onEngineReplaced = "invalidate", removeHours = 2.5, tools = { PIPE_WRENCH, SCREWDRIVER },
    },
    maxWorkers = 2,
})

------------------------------------------------------------------------------
-- (b) Flex conversion of the first verified passenger car and
-- (c) chassis expansion: small car, pickup/utility, van/heavier hauler
------------------------------------------------------------------------------
local function flexVehicle(o)
    return {
        id = o.id,
        deviceKind = "vehicle",
        chassisClass = o.class,
        supportedChassis = { o.chassis },
        originalEngineProfile = "engine_si_stock",
        targetConsumerProfile = "engine_si_flex",
        requiredKnowledge = { skills = { Mechanics = o.mechanics }, recipes = { o.recipe } },
        workStages = stages(o.hours),
        requiredTools = {
            inspect = { SCREWDRIVER },
            prepare = { WRENCH },
            install = { WRENCH, SCREWDRIVER },
            configure = { SCREWDRIVER, PLIERS },
            test = {},
            commission = {},
        },
        requiredModules = {
            install = { [RUBBER_HOSE] = o.hoses, [ENGINE_PARTS] = o.engineParts, [SCREWS] = o.screws },
            configure = { [ELECTRIC_WIRE] = o.wires },
        },
        cargoAndWeightImpact = { massKg = o.massKg, cargoLitres = 0 },
        fuelStorageChanges = { drainRequired = true, tank = "keep", tankProfile = "vehicle_tank" },
        visualConfiguration = { labelKey = "IGUI_TLG_Conversion_flex_vehicle", badge = "flex" },
        reversalAndSalvageRules = {
            removeReturn = 0.5, cancelReturn = 0.75, destroyedReturn = 0, invalidatedReturn = 0,
            onEngineReplaced = "revert", removeHours = o.removeHours, tools = { WRENCH, SCREWDRIVER },
        },
        maxWorkers = o.maxWorkers,
    }
end

-- (b) First verified passenger car.
R.define("conversion", flexVehicle({
    id = "flex_car_normal", class = "passenger",
    chassis = "Base.CarNormal", -- vehicles/vehicle_car_normal.txt:3 (module Base :1); template
                                -- vehicles/vehicle_car_normal_template.txt:3, mass 800 at :30
    mechanics = 4, recipe = BASIC_MECHANICS,
    hours = { 1.0, 2.0, 6.0, 2.0, 1.5, 0.5 },
    hoses = 2, engineParts = 2, screws = 6, wires = 2,
    massKg = 10, removeHours = 3, maxWorkers = 3,
}))

-- (c) Small car.
R.define("conversion", flexVehicle({
    id = "flex_small_car", class = "small_car",
    chassis = "Base.SmallCar", -- vehicles/vehicle_car_small.txt:3 (module Base :1); template
                               -- vehicles/vehicle_car_small_template.txt:3, mass 650 at :26
    mechanics = 4, recipe = BASIC_MECHANICS,
    hours = { 1.0, 1.5, 5.0, 2.0, 1.5, 0.5 },
    hoses = 2, engineParts = 2, screws = 5, wires = 2,
    massKg = 8, removeHours = 2.5, maxWorkers = 2,
}))

-- (c) Pickup / utility.
R.define("conversion", flexVehicle({
    id = "flex_pickup_truck", class = "pickup",
    chassis = "Base.PickUpTruck", -- vehicles/vehicle_pickuptruck.txt:3 (module Base :1); template
                                  -- vehicles/vehicle_pickuptruck_template.txt:3, mass 1030 at :26
    mechanics = 5, recipe = INTERMEDIATE_MECHANICS,
    hours = { 1.0, 2.5, 7.0, 2.5, 2.0, 0.5 },
    hoses = 3, engineParts = 3, screws = 8, wires = 2,
    massKg = 12, removeHours = 3.5, maxWorkers = 3,
}))

-- (c) Van / heavier hauler (heaviest van chassis: StepVan 1160 vs Van 816).
R.define("conversion", flexVehicle({
    id = "flex_step_van", class = "heavy_van",
    chassis = "Base.StepVan", -- vehicles/vehicle_stepvan.txt:3 (module Base :1); template
                              -- vehicles/vehicle_stepvan_template.txt:3, mass 1160 at :17
    mechanics = 5, recipe = INTERMEDIATE_MECHANICS,
    hours = { 1.5, 3.0, 8.0, 3.0, 2.0, 1.0 },
    hoses = 3, engineParts = 4, screws = 10, wires = 3,
    massKg = 15, removeHours = 4, maxWorkers = 3,
}))

return true
