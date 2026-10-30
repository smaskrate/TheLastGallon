-- FuelDefinition content. Values are game-design numbers documented in
-- docs/balance.md, not real-world shelf-life claims.
--   energyMJ        nominal energy per canonical unit (MJ/L, MJ/Nm3, MJ/kg)
--   aging.rate      degradation index growth per hour at 20 C, sealed, deg 0
--   aging.autocat   self-acceleration a in d(deg)/dt = k (1 + a deg)
--   aging.q10       rate multiplier per +10 C
--   aging.unsealed  multiplier when the container is open/unsealable
--   aging.stabilizerMax  largest fraction of the rate a full stabilizer dose removes
--   waterSolubility litres of water held in solution per litre of component
--   hygroscopic     relative moisture uptake when storage breathes
--   coldLimitC      below this storage temperature the fuel gels/waxes
--   nativeFluid     B42 fluid type string used in item containers
require "TLG/Domain/Fuel/Defs"
local R = TLG.Registry

R.define("fuel", {
    id = "gasoline", phase = "liquid", role = "fuel", ignition = "spark",
    nativeFluid = "Petrol", energyMJ = 32.0, density = 0.745,
    aging = { rate = 4.0e-4, autocat = 0.35, q10 = 2.0, unsealed = 2.5, stabilizerMax = 0.75 },
    waterSolubility = 0.0002, hygroscopic = 0.05,
})

R.define("fuel", {
    id = "ethanol", phase = "liquid", role = "fuel", ignition = "spark",
    nativeFluid = "TLG_Ethanol", energyMJ = 21.2, density = 0.789,
    aging = { rate = 0.6e-4, autocat = 0.10, q10 = 1.8, unsealed = 1.5, stabilizerMax = 0.5 },
    waterSolubility = 0.07, hygroscopic = 1.0,
})

R.define("fuel", {
    id = "diesel", phase = "liquid", role = "fuel", ignition = "compression",
    nativeFluid = "TLG_Diesel", energyMJ = 36.0, density = 0.835,
    aging = { rate = 1.5e-4, autocat = 0.30, q10 = 2.0, unsealed = 2.0, stabilizerMax = 0.7 },
    waterSolubility = 0.0002, hygroscopic = 0.1, coldLimitC = -8, microbial = true,
})

R.define("fuel", {
    id = "biodiesel", phase = "liquid", role = "fuel", ignition = "compression",
    nativeFluid = "TLG_Biodiesel", energyMJ = 33.0, density = 0.88,
    aging = { rate = 7.0e-4, autocat = 0.60, q10 = 2.2, unsealed = 3.0, stabilizerMax = 0.8 },
    waterSolubility = 0.0015, hygroscopic = 0.5, coldLimitC = 0, microbial = true,
})

R.define("fuel", {
    id = "water", phase = "liquid", role = "contaminant", nativeFluid = "TLG_FuelWater", density = 1.0,
})

R.define("fuel", {
    id = "sediment", phase = "liquid", role = "contaminant", nativeFluid = "TLG_FuelSediment", density = 1.6,
})

-- Process liquids (not engine fuels).
R.define("fuel", { id = "plant_oil", phase = "liquid", role = "feedstock", nativeFluid = "TLG_PlantOil", density = 0.92 })
R.define("fuel", { id = "methanol", phase = "liquid", role = "feedstock", nativeFluid = "TLG_Methanol", density = 0.79 })
R.define("fuel", { id = "glycerin", phase = "liquid", role = "product", nativeFluid = "TLG_Glycerin", density = 1.26 })
R.define("fuel", { id = "mash", phase = "liquid", role = "feedstock", density = 1.05 })

-- Gases (Nm3). Propane is displayed in kg at 2.01 kg/Nm3.
R.define("fuel", { id = "propane", phase = "gas", role = "fuel", ignition = "gaseous", energyMJ = 93.0, density = 2.01 })
R.define("fuel", { id = "biogas", phase = "gas", role = "fuel", ignition = "gaseous", energyMJ = 21.5, density = 1.15 })
R.define("fuel", { id = "woodgas", phase = "gas", role = "fuel", ignition = "gaseous", energyMJ = 5.0, density = 1.1 })

-- Solids (kg).
R.define("fuel", { id = "firewood", phase = "solid", role = "fuel", ignition = "none", energyMJ = 15.0 })
R.define("fuel", { id = "wood_chips_dry", phase = "solid", role = "fuel", ignition = "none", energyMJ = 16.5 })
R.define("fuel", { id = "charcoal", phase = "solid", role = "fuel", ignition = "none", energyMJ = 29.0 })
R.define("fuel", { id = "sugar_eq", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "manure", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "food_waste", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "oilseed", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "wood_ash", phase = "solid", role = "product" })
R.define("fuel", { id = "lye", phase = "solid", role = "feedstock" })
R.define("fuel", { id = "digestate", phase = "solid", role = "product" })
R.define("fuel", { id = "stillage", phase = "solid", role = "product" })

return true
