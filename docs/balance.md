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
stall chance per running minute = 4 % × (1 − startFactor) (SRC-ONLY).

Energy per unit (nominal): gasoline 32.0 MJ/L, ethanol 21.2, diesel 36.0,
biodiesel 33.0, propane 93 MJ/Nm³, biogas 21.5, wood gas 5.0, firewood
15 MJ/kg, charcoal 29.

## World initialisation

Pre-outbreak fuel age up to 30 days (portable/vehicles) and 75 days
(stations), seeded by world seed and stable identity. Station tanks start
with up to 0.4 % water and 0.1 % sediment (sandbox toggle). Existing saves
default to a 30-day transition.

## Ethanol chain (`TLG/Content/Production.lua`)

| Step | Machine | Inputs | Output | Time / energy |
| --- | --- | --- | --- | --- |
| Ferment | fermentation vessel (160 L) | 2–30 kg sugar eq., 8–130 L water, yeast | wash: water + 0.55 L ethanol per kg sugar | 1 h prep + 96 h (40 % speed below 18 °C or above 32 °C, stalls below 8 °C, spoils after 72 h stalled) |
| Distil | pot still (60 L) / reflux still (120 L) | wash | hydrous ethanol 80 % / 94 % purity, recovery 0.88 / 0.92 | 1 h heat-up + wash ÷ 8 or 12 L/h at 6 kW; firebox 30 / 50 kg, 4.2 kWh/kg, 45 % / 55 % efficient |
| Dry | drying column | hydrous ethanol + quicklime | water down to 0.5 % | 12 h, 0.3 L water per kg quicklime |

Feedstock sugar equivalents per vanilla item: Sugar 1.0 kg, Brown sugar 0.9,
Sugar beet 0.16, Corn 0.12, Potato 0.09, Pumpkin 0.15, Watermelon 0.25,
Apple 0.02, Grapes 0.03 (`TLG/Content/Feedstocks.lua`).

Example: 20 kg sugar eq. + 100 L water → 11 L ethanol in the wash → reflux
still → 10.12 L ethanol at 94 % (0.65 L water) using 1 h + 111 L ÷ 12 L/h
= 10.25 h of 6 kW heat = 61.5 kWh (≈ 27 kg firewood at 55 %). The reflux
still's 50 kg firebox covers one full batch.

## Pending balance work

Biodiesel, wood gas, biogas, propane and electricity numbers arrive with
their modules; campaign playthrough results (fresh, six-month, one-year,
inherited installation) are NOT RUN.
