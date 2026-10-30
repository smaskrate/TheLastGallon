-- Energy equipment: batteries, producers and loads for electricity and heat
-- networks (docs/balance.md). Numbers are game-design values.
--
-- The shared registry has no battery/producer kind, so these are
-- MachineDefinitions with an `energy` role (battery | solar | wind | hydro |
-- fueled | load); the Energy domain modules validate them.
--
-- Vanilla evidence, build 42.21 (media/scripts/generated/items):
--   drainable.txt:2336  item CarBattery1  VehicleType = 1
--   drainable.txt:2355  item CarBattery2  VehicleType = 2
--   drainable.txt:2374  item CarBattery3  VehicleType = 3
--     each: ItemType = base:drainable, UseDelta = 0.00001, Weight = 5.0,
--     ConditionMax = 100, Tags = base:carbattery, KeepOnDeplete = true
--   normal.txt:11829    item CarBatteryCharger
-- VehicleType matches the vehicle script mechanicType: 2 on vans and pickups
-- (e.g. vehicles/professionVehicles_General/vehicle_van_utility.txt:5), 3 on
-- performance cars (e.g. regionalPoliceVehicles/
-- vehicle_car_modernlights_westpoint_template.txt:5), 1 on standard cars.
-- The battery adapter maps the drainable charge fraction (0..1) to
-- e = fraction x usable capacity and item condition / 100 to `cond`.
require "TLG/Domain/Energy/Dispatch"
require "TLG/Content/Fuels"
require "TLG/Content/Consumers"
local R = TLG.Registry

------------------------------------------------------------------------------
-- Batteries. Lead-acid starter batteries: usable capacity is 60% of nominal
-- 12 V capacity (they are not deep-cycle batteries); charge limit about C/5,
-- discharge limit about 1C through an inverter; charge 0.85 x discharge 0.92
-- = 0.78 round trip; self-discharge 7e-5 of capacity per hour (~5%/month).
------------------------------------------------------------------------------
R.define("machine", {
    id = "car_battery_standard", energy = "battery", item = "Base.CarBattery1", vehicleType = 1,
    capacityKWh = 0.40, maxChargeKW = 0.16, maxDischargeKW = 0.60,   -- 12 V 55 Ah
    etaCharge = 0.85, etaDischarge = 0.92, selfDischargePerHour = 7e-5, reconnectFraction = 0.10,
})
R.define("machine", {
    id = "car_battery_heavy", energy = "battery", item = "Base.CarBattery2", vehicleType = 2,
    capacityKWh = 0.65, maxChargeKW = 0.26, maxDischargeKW = 1.00,   -- 12 V 90 Ah
    etaCharge = 0.85, etaDischarge = 0.92, selfDischargePerHour = 7e-5, reconnectFraction = 0.10,
})
R.define("machine", {
    id = "car_battery_sport", energy = "battery", item = "Base.CarBattery3", vehicleType = 3,
    capacityKWh = 0.50, maxChargeKW = 0.20, maxDischargeKW = 0.80,   -- 12 V 70 Ah
    etaCharge = 0.85, etaDischarge = 0.92, selfDischargePerHour = 7e-5, reconnectFraction = 0.10,
})
-- Battery bank (asset A12): rack of six heavy-duty car batteries with a charge
-- controller and an inverter; better wiring and controlled charging.
R.define("machine", {
    id = "battery_bank", energy = "battery", asset = "A12",
    capacityKWh = 3.9, maxChargeKW = 1.2, maxDischargeKW = 2.5,
    etaCharge = 0.88, etaDischarge = 0.94, selfDischargePerHour = 4e-5, reconnectFraction = 0.10,
})

------------------------------------------------------------------------------
-- Renewable producers
------------------------------------------------------------------------------
-- Solar (asset A17): STC rating; derate covers wiring, controller, heat.
R.define("machine", { id = "solar_panel", energy = "solar", asset = "A17", ratedKW = 0.25, derate = 0.80 })
R.define("machine", { id = "solar_array", energy = "solar", asset = "A17", ratedKW = 1.5, derate = 0.80 })
-- Wind (asset A18): small mast turbine.
R.define("machine", {
    id = "wind_turbine_small", energy = "wind", asset = "A18",
    ratedKW = 1.0, cutInMS = 3.0, ratedMS = 11.0, cutOutMS = 25.0,
})
-- Hydro (asset A19): undershot wheel; default authored flow and head, a site
-- may override flowM3s/headM on the node. 9.81 x 0.08 x 1.5 x 0.55 = 0.65 kW.
R.define("machine", {
    id = "hydro_wheel", energy = "hydro", asset = "A19",
    ratedKW = 0.75, flowM3s = 0.08, headM = 1.5, efficiency = 0.55,
})

------------------------------------------------------------------------------
-- Fueled producers (TLG-owned machines; fuel compatibility comes from the
-- ConsumerProfile). efficiency = electric output / fuel energy at rated
-- load; idleFraction = share of rated-load fuel burned at zero load;
-- heatRecovery = share of the waste heat (fuel - electric) recovered.
------------------------------------------------------------------------------
-- Converted spark generator: gasoline/ethanol. Rated load 22.7 kW fuel
-- = 2.56 L/h of gasoline (32 MJ/L).
R.define("machine", {
    id = "generator_flex_5kw", energy = "fueled", consumer = "generator_si_flex", owner = "tlg",
    ratedKW = 5.0, efficiency = 0.22, idleFraction = 0.30, heatRecovery = 0,
})
-- Diesel/biodiesel generator: 2.14 L/h of diesel (36 MJ/L) at rated load.
R.define("machine", {
    id = "generator_diesel_6kw", energy = "fueled", consumer = "generator_ci_stock", owner = "tlg",
    ratedKW = 6.0, efficiency = 0.28, idleFraction = 0.25, heatRecovery = 0,
})
-- Gas engine with coolant/exhaust heat exchanger (combined heat and power):
-- propane 0.65 Nm3/h (1.3 kg/h), biogas 2.8 Nm3/h at rated load; recovers
-- 6.3 kW of heat at rated load (38% of the fuel energy).
R.define("machine", {
    id = "generator_gas_chp", energy = "fueled", consumer = "generator_gas", owner = "tlg",
    ratedKW = 4.0, efficiency = 0.24, idleFraction = 0.30, heatRecovery = 0.50,
})

------------------------------------------------------------------------------
-- Loads (optional consumer definitions; demand above maxKW is rejected)
------------------------------------------------------------------------------
R.define("machine", { id = "battery_charger", energy = "load", item = "Base.CarBatteryCharger", maxKW = 0.20 })
-- Heat loop for digesters, greenhouses and process preheating.
R.define("machine", { id = "heat_loop", energy = "load", heat = true, maxKW = 8.0 })

return true
