# Balance

All numbers are game-design values (not real-world shelf-life or chemistry
claims). Exposure rates (how fast fuel changes) are separate from the
suitability mapping (what a given state does to an engine), so campaign speed
can be tuned without rewriting consumer behaviour.

## Campaign presets (`TLG/Domain/Balance.lua`, sandbox "Fuel ageing speed")

| Preset | agingMul | breathingMul | microbialMul |
| --- | ---: | ---: | ---: |
| Default | 1.0 | 1.0 | 1.0 |
| Slow | 0.5 | 0.7 | 0.7 |
| Fast | 2.0 | 1.5 | 1.5 |
| Off | 0 | 0 | 0 |

A preset change is appended to the world's dated `balanceHistory`; past
intervals keep the preset that was active then (no retroactive rewrite).

## Degradation index (`deg`)

`d(deg)/dt = k (1 + a·deg)`, `k = rate · preset · storage.agingMul ·
(1 + 0.5·(1 − condition)) · q10^((T − 20)/10) · seal · (1 − stabMax·min(stab, 1))`.

| Fuel | rate /h @20 °C | autocat a | q10 | unsealed × | stabilizer max |
| --- | ---: | ---: | ---: | ---: | ---: |
| gasoline | 4.0e-4 | 0.35 | 2.0 | 2.5 | 0.75 |
| ethanol | 0.6e-4 | 0.10 | 1.8 | 1.5 | 0.50 |
| diesel | 1.5e-4 | 0.30 | 2.0 | 2.0 | 0.70 |
| biodiesel | 7.0e-4 | 0.60 | 2.2 | 3.0 | 0.80 |

Grades (blend `deg`, volume-weighted): good < 1.0 ≤ weathered < 2.0 ≤ poor;
"unsuitable" is consumer-specific (`maxDeg`, 3.5 engines, 4.0 generators).
UI hysteresis 0.08 when improving.

### Calibration measured by the test suite (default preset, July start)

`tests/domain/test_aging.lua` ("calibration targets"), gasoline 20 L:

| Storage | Weathered | Unsuitable (3.5) | Target |
| --- | ---: | ---: | --- |
| Station UST (ground, 12–16 °C) | day 150 | day 415 | 100–200 / 240–480 |
| Vehicle tank (vented, outdoor) | day 50 | — | 30–90 |
| Sealed steel jerrycan (sheltered) | day 93 | — | 60–150 |

## Storage profiles (`TLG/Content/Storage.lua`)

| Profile | agingMul | breathing /h | thermal | notes |
| --- | ---: | ---: | --- | --- |
| jerrycan_steel | 1.0 | 2e-6 | sheltered | sealable, 20 L |
| gascan_plastic | 1.15 | 4e-6 | sheltered | sealable, 10 L (permeation) |
| drum_steel | 0.95 | 1.5e-6 | sheltered | sealable, 200 L |
| vehicle_tank | 1.25 | 3e-6 | outdoor | vented |
| generator_tank | 1.3 | 3e-6 | outdoor | vented |
| station_ust | 0.9 | 1e-6 | ground | vented, 10 000 L |
| open_vessel | 1.0 | 2e-5 | sheltered | never sealed |
| unknown | 1.3 | 5e-6 | outdoor | pessimistic default |

Sealed containers breathe at 5 % of the listed rate. Breathing exchanges
evaporated fuel for moisture at constant volume, scaled by the blend's
hygroscopicity (gasoline 0.05, diesel 0.1, biodiesel 0.5, ethanol 1.0).
Microbial index grows 0.004/h × microbial fraction while free water exists,
decays 0.001/h when dry.

## Consumers (`TLG/Content/Consumers.lua`)

| Profile | accepts (soft/max) | maxDeg | free water max |
| --- | --- | ---: | ---: |
| engine_si_stock | gasoline 1/1, ethanol 0.15/0.25 | 3.5 | 0.2 % |
| engine_si_flex | gasoline 1/1, ethanol 1/1 (cold start > 85 % below 10 °C) | 3.5 | 0.4 % |
| generator_si_stock | gasoline 1/1, ethanol 0.10/0.15 | 4.0 | 0.3 % |
| generator_si_flex | gasoline 1/1, ethanol 1/1 (cold start below 5 °C) | 4.0 | 0.5 % |
| engine_ci_stock | diesel 1/1, biodiesel 0.2/1 | 3.5 | 0.1 % |
| engine_ci_bio | diesel, biodiesel 1/1, fuel heater | 3.5 | 0.15 % |
| generator_gas | propane, biogas, woodgas | — | — |

Effects: start factor falls to 0.55 at maxDeg, power to 0.8, wear rises to
2×; marginal blends cost up to 40 % start, 15 % power; free water halves
start chance; phase separation is incompatible for spark engines. Vehicle
stall chance per running minute = 4 % × (1 − startFactor); incompatible fuel
stalls on the next minute (verified in game; the 4 % rate is not measured).

Energy per unit (nominal): gasoline 32.0 MJ/L, ethanol 21.2, diesel 36.0,
biodiesel 33.0, propane 93 MJ/Nm³, biogas 21.5, wood gas 5.0, firewood
15 MJ/kg, charcoal 29.

## World initialisation

Pre-outbreak fuel age up to 30 days (portable/vehicles) and 75 days
(stations), seeded by world seed and stable identity. Station tanks start
with up to 0.1 % sediment and, per station (`WorldInit.STATION_WATER`):

* about 9 in 10: 0–0.15 % water, inside every engine's free-water tolerance;
* about 1 in 10: 0.2–0.4 % water ("contaminated"): a stock car's start
  chance is halved, and from 0.3 % a stock generator's too.

Contamination can be switched off in the sandbox options. Existing saves
default to a 30-day transition.

History: until 2026-10-31 water was uniform on 0–0.4 %, so about half of all
stations exceeded the stock car tolerance from the first day (seen in game at
the Gas2Go pump: 0.22–0.23 %, `startFactor=0.5`). Changed to the two tiers
above (D-017) so that fuel trouble grows mainly with age, while a few bad
stations remain to be found. Only stations initialised after the change use
the new draw; existing reservoir records keep their water.

## Ethanol chain (`TLG/Content/Production.lua`)

| Step | Machine | Inputs | Output | Time / energy |
| --- | --- | --- | --- | --- |
| Ferment | fermentation vessel (160 L) | 2–30 kg sugar eq., 8–130 L water, yeast | wash: water + 0.55 L ethanol per kg sugar | 1 h prep + 96 h (40 % speed below 18 °C or above 32 °C, stalls below 8 °C, spoils after 72 h stalled) |
| Distil | pot still (60 L) / reflux still (120 L) | wash | hydrous ethanol 80 % / 94 % purity, recovery 0.88 / 0.92 | 1 h heat-up + wash ÷ 8 or 12 L/h at 6 kW; firebox 30 / 50 kg, 4.2 kWh/kg, 45 % / 55 % efficient |
| Dry | drying column | hydrous ethanol + quicklime | water down to 0.5 % | 12 h, 0.3 L water per kg quicklime |

Temperature: machine rates use the day's mean temperature, not the hour's
reading; since D-020 that is the mean of the day's hourly air temperature,
weather included (before, the season curve). The machines are "sheltered"
wherever they stand: (outdoor day mean + 16 °C) / 2, so a fermenter slows
(below 18 °C) on days averaging under 20 °C outdoors and stops (below 8 °C)
on days averaging under 0 °C; being indoors or near a heater changes
nothing. Measured on the game clock (RT-SP): July, 97.2 h, the full-rate
time (run 13); January on the season curve, 0.4 rate all through, 241.7 h
(run 15); January with the weather, −0.8 to −4.7 °C day means, stopped from
the first day and spoiled 73.2 h after loading, at 72 paused hours (run 16).
Spoilage counts the batch's total paused hours, also across separate cold
spells (not yet seen in game).

Condition through production: distillate leaves the still fresh (ageing
products stay in the stillage), while dried ethanol keeps the degradation it
went in with (quicklime removes water only). Reflux spirit (94 %) holds its
water in solution and runs flex engines without drying; pot-still spirit
(80 %) carries free water and must be dried first.

Feedstock sugar equivalents per vanilla item: Sugar 1.0 kg, Brown sugar 0.9,
Sugar beet 0.16, Corn 0.12, Potato 0.09, Pumpkin 0.15, Watermelon 0.25,
Apple 0.02, Grapes 0.03 (`TLG/Content/Feedstocks.lua`).

Example: 20 kg sugar eq. + 100 L water → 11 L ethanol in the wash → reflux
still → 10.12 L ethanol at 94 % (0.65 L water) using 1 h + 111 L ÷ 12 L/h
= 10.25 h of 6 kW heat = 61.5 kWh (≈ 27 kg firewood at 55 %). The reflux
still's 50 kg firebox covers one full batch.

## Electricity (`TLG/Content/Energy.lua`, `TLG/Domain/Energy/*`)

| Device | Capacity / rating | Charge / discharge | Efficiency | Notes |
| --- | --- | --- | --- | --- |
| Base.CarBattery1 | 0.40 kWh usable | 0.16 / 0.60 kW | 0.85 × 0.92 (round trip 0.78) | self-discharge 7e-5/h, reconnect at 10 % |
| Base.CarBattery2 | 0.65 kWh | 0.26 / 1.00 kW | same | heavy duty |
| Base.CarBattery3 | 0.50 kWh | 0.20 / 0.80 kW | same | sport |
| battery_bank (A12) | 3.9 kWh | 1.2 / 2.5 kW | 0.88 × 0.94 (0.83) | 4e-5/h |
| solar_panel / solar_array | 0.25 / 1.5 kW | — | derate 0.8 | ≈5.6 kWh/kW/day July, 3.4 December (clear) |
| wind_turbine_small | 1.0 kW | — | cut-in 3, rated 11, cut-out 25 m/s | |
| hydro_wheel | 0.75 kW | — | 0.65 kW at the default site | authored sites only |
| generator_flex_5kw | 5 kW | — | 22 % | 2.56 L/h at rated load, idle 0.77 L/h |
| generator_diesel_6kw | 6 kW | — | 28 % | 2.14 L/h |
| generator_gas_chp | 4 kW | — | 24 %, heat recovery 0.5 | 0.65 Nm³/h propane, 2.8 Nm³/h biogas |

Auto-start: start ≤ 25 % state of charge, stop ≥ 90 % after ≥ 1 h. Wood gas
derates a gas generator to 60 % power.

## Biodiesel (`TLG/Content/Biodiesel.lua`)

Oil press 0.30 kg oil/kg seed (+0.003/skill, max 0.33). Wood retort per kg
firewood: methanol 0.04 kg, charcoal 0.28, tar 0.07, liquor water 0.32,
off-gas 0.29 (loss). Lye 0.15 kg per kg ash. Reactor: 0.15 L methanol and
0.0125 kg lye per L oil, conversion 98.5 % (+0.1 %/skill), per L oil 0.985 L
biodiesel + 0.099 L glycerin. Wash removes 92 % soap, 97 % methanol. 40 kg
oilseed → 12.85 L "good" biodiesel.

## Wood gas (`TLG/Content/WoodGas.lua`, `TLG/Domain/Gas.lua`)

Gas per kg: firewood 2.2 Nm³, dry chips 2.4, charcoal 4.2. Stationary
gasifier 120 kg hopper, 8 kg/h, 0.5 h warm-up, 2 Nm³ buffer, filter 400 kg;
vehicle module 60 kg, 15 kg/h, 0.3 h warm-up, 180 kg installed, 35 % cargo
loss, power factor 0.65. Loads above 30 % moisture are refused.

## Biogas (`TLG/Content/Biogas.lua`)

Manure 0.05 Nm³/kg, food waste 0.15 Nm³/kg (souring above 50 % share).
48 h inoculation, 360 h digestion unheated / 300 h heated (0.4 kW). Stalls
below 10 °C, slow 10–20 °C and 40–50 °C. Yield cap 5.5 Nm³ per digester-day
(documented anti-loop limit).

## Propane (`TLG/Content/Propane.lua`)

Vanilla `Base.PropaneTank` 5000 uses = 4.48 Nm³ = 9 kg = 417 MJ; propane does
not age. Bulk tank profile 380 Nm³.

## Not yet balanced

Campaign playthroughs (fresh, six-month, one-year, inherited installation)
and multi-pathway comparisons are NOT RUN; all values above are first
estimates from the domain models.
