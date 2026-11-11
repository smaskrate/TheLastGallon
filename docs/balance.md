# Balance

All numbers are game-design values, not real-world shelf-life or chemistry
claims, and all are first estimates from the domain models: campaign
playthroughs (fresh, six-month, one-year, inherited installation) and
multi-pathway comparisons are NOT RUN.

Exposure rates (how fast fuel changes) are separate from the suitability
mapping (what a given state does to an engine), so campaign speed can be
tuned without rewriting consumer behaviour.

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

`preset` is the campaign preset's agingMul and `T` the temperature in °C.
`rate`, `a`, `q10`, `seal` and `stabMax` depend on the fuel (table below);
`seal` is the fuel's unsealed factor unless the container is sealed or
vented, where it is 1.

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

## Fuel energy (`TLG/Content/Fuels.lua`)

Energy per unit (nominal): gasoline 32.0 MJ/L, ethanol 21.2, diesel 36.0,
biodiesel 33.0, propane 93 MJ/Nm³, biogas 21.5, wood gas 5.0, firewood
15 MJ/kg, charcoal 29.

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
The microbial index grows 0.004/h × microbial fraction while free water
exists, and decays 0.001/h when dry.

## Consumers (`TLG/Content/Consumers.lua`)

| Profile | accepts (soft/max) | maxDeg | free water max |
| --- | --- | ---: | ---: |
| engine_si_stock | gasoline 1/1, ethanol 0.15/0.25 | 3.5 | 0.2 % |
| engine_si_flex | gasoline 1/1, ethanol 1/1 (cold start > 85 % below 10 °C) | 3.5 | 0.4 % |
| generator_si_stock | gasoline 1/1, ethanol 0.10/0.15 | 4.0 | 0.3 % |
| generator_si_flex | gasoline 1/1, ethanol 1/1 (cold start below 5 °C) | 4.0 | 0.5 % |
| engine_ci_stock | diesel 1/1, biodiesel 0.2/1 | 3.5 | 0.1 % |
| engine_ci_bio | diesel, biodiesel 1/1, fuel heater | 3.5 | 0.15 % |
| generator_ci_stock | diesel 1/1, biodiesel 0.2/1 | 4.0 | 0.15 % |
| generator_ci_bio (the Diesel Generator) | diesel, biodiesel 1/1 | 4.0 | 0.15 % |
| generator_gas | propane, biogas, woodgas | — | — |

Effects:

* at maxDeg the start factor falls to 0.55 and power to 0.8, and wear rises
  to 2×;
* marginal blends cost up to 40 % start and 15 % power;
* free water halves the start chance;
* phase separation is incompatible for spark engines;
* a vehicle's stall chance per running minute is 4 % × (1 − startFactor),
  and incompatible fuel stalls it on the next minute (verified in game; the
  4 % rate is not measured).

Stalls and refused starts of cars follow the sandbox option **Bad fuel can
stall engines** (D-031).

### Wrong fuel (D-037, from 0.3.0)

A fuel the engine is not built for no longer just blocks the start. Each
rule sums the share of its fuels in the tank and takes the last band the
share is above. All numbers are game values, first estimates; the order
of harm follows real engines (petrol or ethanol in a diesel keeps it
running and wrecks it; diesel in a spark engine mostly stops it).

| Rule | Engines | Share above | Start × | Power × | Wear × | Also |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Diesel + biodiesel in a spark engine | the four `*_si_*` profiles | 1 % | 0.9 | 0.85 | 3 | |
| | | 10 % | 0.4 | 0.6 | 6 | exhaust 0.5 a litre |
| | | 30 % | no start | — | 10 | exhaust 1.0 a litre; 1–2 engine condition and 2 % battery charge at each refused start |
| Petrol in a diesel | the four `*_ci_*` profiles | 2 % | 0.9 | 0.9 | 3 | |
| | | 15 % | 0.5 | 0.7 | 8 | |
| | | 50 % | 0.25 | 0.5 | 15 | failure 2 % a litre |
| Ethanol in a diesel | the four `*_ci_*` profiles | 2 % | 0.5 | 0.7 | 8 | |
| | | 10 % | 0.25 | 0.5 | 15 | failure 2 % a litre |
| | | 30 % | no start | — | 20 | failure 4 % a litre; 1–2 condition at each refused start |
| Ethanol past a stock petrol engine's `max` | `engine_si_stock` (25 %), `generator_si_stock` (15 %) | its max | 0.5 | 0.75 | 4 | |
| | | 60 % | 0.3 | 0.6 | 8 | no start below 10 °C |

* The first threshold of each rule is the profile's `foreignMax`, the
  trace tolerated before. A fuel no rule covers (methanol, plant oil,
  glycerin) still blocks the start above it, and a ruled fuel below its
  first band still counts toward it.
* Biodiesel in a spark engine wears a fifth more than diesel, in
  proportion to its share of the wrong fuel.
* Where two rules apply (petrol and ethanol in a diesel; diesel and too
  much ethanol in a stock petrol engine) the worse value of each factor
  counts; they do not multiply. The wrong-fuel wear factor does multiply
  with the factors of stale or dirty fuel.
* The ethanol row starts at 0.5 so that the start factor does not rise
  where the marginal blend, which ends at 0.6, passes the limit.
* The wear multiplies `wearFactor`, so it is charged like any other wear
  (the table below): a car at × 8 loses (8 − 1) × 0.15 = 1.05 condition a
  litre, 3.5 an hour of driving; a generator at × 15 about 0.7 an hour at
  a fridge's load.
* The numbers of a no-start band are for an engine kept running with
  **Bad fuel can stall engines** off: there is no start gate then.
* Failure: the chance is for a car's litre at the sandbox's normal
  consumption, 6.4 % for an hour's driving (3.3 L) at 2 %, a little over
  half for a 40 L tank. A generator's litres count as the hours they
  lasted at the reference load, so its odds for an hour are the same as
  a car's. A failure sets the engine's (or the generator's) condition to
  0 and stops it.
* The exhaust wear applies to the vehicle's `Muffler` part, when one is
  fitted, for a car's litre as above.
* The sandbox option **Wrong fuel damages engines** off: none of this;
  such fuel blocks the start, as before 0.3.0.
* Not tuned against play. The ethanol row keeps the flex conversion worth
  doing only if its wear deters: a stock car loses 0.45 condition a litre
  between its limit and 60 % ethanol and 1.05 above, 18 and 42 points for
  a 40 L tank.

### Engine effects (`TLG/Domain/EngineEffects.lua`, D-031)

What the adapters apply of those factors:

| Effect | Applied to | Rule |
| --- | --- | --- |
| Power | a running car | engine power × powerFactor, never below 0.5 × (`POWER_FLOOR`); the car's own power again within a game minute of stopping or of good fuel |
| Wear | a running car | per litre burned: (wearFactor − 1) × 0.15 ÷ `CarGasConsumption` condition points of the Engine part |
| Wear | a generator | per litre burned: (wearFactor − 1) × 1.5 ÷ N ÷ (0.15 × `GeneratorFuelConsumption`), N the item's `ConditionLowerChanceOneIn` (Base.Generator 30, _Old 25, _Yellow 36, _Blue 24) |

* Vanilla car engines never lose condition from running, so the car rate is
  the mod's own. At wearFactor 2 (fuel close to unusable) and 25 km/h
  (3.3 L an hour, RT-SP run 176) it is about half a point an hour of
  driving; a 40 L tank of such fuel costs about 6 points.
* A vanilla generator loses 1–2 points (1.5 on average) once in N running
  hours. The generator rate makes the extra wear at wearFactor 2 equal to
  vanilla's own at the reference load of 0.15 L an hour, a fridge's (the
  power constants 0.02 base + 0.13 fridge-freezer, BC `IsoGenerator`; not
  measured with a fridge). The extra wear follows the fuel burned, so a
  generator with little plugged in wears little extra: run 177's burned
  0.012 L in 6 game hours at the roadside. A 10 L tank at wearFactor 1.75
  (Base.Generator) costs 2.5 points.
* The power floor only matters for fuel the engine cannot take
  (powerFactor 0) when the sandbox option **Bad fuel can stall engines** is
  off; with it on, such an engine stalls within a game minute.
* Generators have no power the mod can lower.

## World initialisation

Pre-outbreak fuel age is up to 30 days (portable/vehicles) and 75 days
(stations), seeded by world seed and stable identity. Station tanks start
with up to 0.1 % sediment and, per station (`WorldInit.STATION_WATER`):

* about 9 in 10: 0–0.15 % water, inside every engine's free-water tolerance;
* about 1 in 10: 0.2–0.4 % water ("contaminated"): a stock car's start
  chance is halved, and from 0.3 % a stock generator's too.

The sandbox option **Station tanks start with water and sediment** switches
contamination off. Existing saves default to a 30-day transition.

Reason for the two tiers (D-017): until 2026-10-31 water was uniform on
0–0.4 %, so about half of all stations exceeded the stock car tolerance from
the first day (seen in game at the Gas2Go pump: 0.22–0.23 %,
`startFactor=0.5`). With the tiers, fuel trouble grows mainly with age, while
a few bad stations remain to be found. Only stations initialised after the
change use the new draw; existing reservoir records keep their water.

## Ethanol chain (`TLG/Content/Production.lua`)

| Step | Machine | Inputs | Output | Time / energy |
| --- | --- | --- | --- | --- |
| Ferment | fermentation vessel (160 L) | 2–30 kg sugar eq., 8–130 L water, yeast | wash: water + 0.55 L ethanol per kg sugar | 1 h prep + 96 h (40 % speed below 18 °C or above 32 °C, stalls below 8 °C, spoils after 72 h stalled) |
| Distil | pot still (60 L) / reflux still (120 L) | wash | hydrous ethanol 80 % / 94 % purity, recovery 0.88 / 0.92 | 1 h heat-up + wash ÷ 8 or 12 L/h at 6 kW; firebox 30 / 50 kg, 4.2 kWh/kg, 45 % / 55 % efficient |
| Dry | drying column | hydrous ethanol + quicklime | water down to 0.5 % | 12 h, 0.3 L water per kg quicklime |

### Temperature at the machine

Machine rates use the day's mean temperature at the machine, not the hour's
reading: a batch has a day's thermal mass, so a few warm hours lift the whole
day. That mean is the mean air temperature where the machine stands over the
day's hours of the batch (D-021), weather included (D-020):

* while the area is loaded, the game's own hourly value at the machine's
  tile (rooms, grid power, fires);
* while it is not, the day's unheated value for its site, except that a fire
  noted warming the machine keeps doing so while its noted fuel lasts
  (D-022);
* the hour in progress takes the previous hour's reading.

A fermentation vessel slows below 18 °C and stops below 8 °C:

| Where it stands | Its temperature | Slows below (outdoor day mean) | Stops below |
| --- | --- | --- | --- |
| Outdoors | the outdoor air | 18 °C | 8 °C |
| Room, ground floor, grid off | T + k (22 − T), T the outdoor air, k = 0.4–0.6 with the daylight; 0.435 on January days (runs 17–19) | about 15 °C | about −3 °C in January |
| Room upstairs, grid off | 0.85 of that pull | about 16 °C | about 0 °C in January |
| Room, grid on | 22 °C | never | never |
| Near a lit fireplace, wood stove, campfire or barbecue (while away: as long as its fuel lasts) | the game's value (below) | — | — |

A fireplace with an hour of fuel reaches 8 tiles in sight: in an 8 °C room
about 25 °C one tile away, 20 °C three tiles away (28 °C on its own tile).
Measured beside a map fireplace kept fed in January: 20.7 °C or more at
2.24 tiles (run 21).

Days recorded before D-021 have no room means; for them a room assumes
k = 0.5. Before D-021 every machine counted as "sheltered", (outdoor mean
+ 16 °C) / 2, wherever it stood; a record keeps that until its first access
since.

Fermentation batches measured on the game clock (RT-SP):

| Setting | Result |
| --- | --- |
| July, sheltered (run 13) | 97.2 h, the full-rate time |
| January on the season curve (run 15) | 0.4 all through, 241.7 h |
| January with the weather, sheltered (run 16) | stopped from the first day; spoiled 73.2 h after loading, at 72 paused hours |
| January by site, grid off, day means −8.1 to +1.7 °C (runs 17–19): outdoors | stopped; spoiled at 72 paused hours |
| Same, ground-floor room | 9.5–13.1 °C above the outdoor air (4.5–11.4 °C at the machine); slow on the first day, then mostly stopped; spoiled every time |
| Same, a tile warmed by a 35 °C heat source | 28 °C every hour; the batch finished, its only pauses the hours of a morning spent unloaded |
| Beside a map fireplace kept fed with logs (run 21, 2.24 tiles from the fire, outdoor day means −9.4 to −1.1 °C) | 20.7 °C or more every hour; finished after 114.3 game hours for 97 hours of work. The 12 hour trip in it cost about 17 hours (unheated room value while away, a cold day mean after the return); 18 logs burned |
| The same setup with the fire's fuel counted while away (D-022), a milder January (run 23) | the fire's 365 minutes covered 6.08 of the 12 hours away; finished after 109.2 hours with 17 logs |

Spoilage counts the batch's total paused hours, also across separate cold
spells (not yet seen in game).

Fire fuel (vanilla, default sandbox): a log adds 6 hours, and a fireplace
holds at most 8 (`MaximumFireFuelHours`; the menu offers no fuel past it),
so a log only goes in once 2 hours or less are left. A fire kept going burns
4 logs a game day. It burns its fuel while you are away too, and its warmth
counts for those minutes (D-022): a fire fed before leaving keeps a machine
warm for up to 8 hours away.

### Condition, yields and examples

Condition through production: distillate leaves the still fresh (ageing
products stay in the stillage), while dried ethanol keeps the degradation it
went in with (quicklime removes water only). Reflux spirit (94 %) holds its
water in solution and runs flex engines without drying; pot-still spirit
(80 %) carries free water and must be dried first.

Example (RT-SP run 28): 12 kg sugar + 60 L water → 66.6 L of wash, two
pot-still loads.

* 60 L: 1 h + 7.5 h, 26.98 kg of wood, 5.23 L ethanol and 1.31 L water.
* The other 6.6 L: 2 h (the 1 h minimum), 6.35 kg, 0.57 L ethanol at 0.994
  efficiency (condition 0.98 after the first run).
* The 7.26 L of spirit held 1.04 L of free water (14 %); 5 kg of quicklime
  brought it to 5.80 L ethanol and 0.03 L water in 12 h.

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

* Oil press: 0.30 kg oil/kg seed (+0.003/skill, max 0.33).
* Wood retort, per kg firewood: methanol 0.04 kg, charcoal 0.28, tar 0.07,
  liquor water 0.32, off-gas 0.29 (loss).
* Lye: 0.15 kg per kg ash.
* Reactor: 0.15 L methanol and 0.0125 kg lye per L oil, conversion 98.5 %
  (+0.1 %/skill); per L oil 0.985 L biodiesel + 0.099 L glycerin.
* Wash: removes 92 % soap, 97 % methanol.

40 kg oilseed → 12.85 L "good" biodiesel.

## Wood gas (`TLG/Content/WoodGas.lua`, `TLG/Domain/Gas.lua`)

Gas per kg: firewood 2.2 Nm³, dry chips 2.4, charcoal 4.2. Loads above 30 %
moisture are refused.

* Stationary gasifier: 120 kg hopper, 8 kg/h, 0.5 h warm-up, 2 Nm³ buffer,
  filter 400 kg.
* Vehicle module: 60 kg, 15 kg/h, 0.3 h warm-up, 180 kg installed, 35 % cargo
  loss, power factor 0.65.

## Biogas (`TLG/Content/Biogas.lua`)

Manure 0.05 Nm³/kg, food waste 0.15 Nm³/kg (souring above 50 % share).
48 h inoculation, 360 h digestion unheated / 300 h heated (0.4 kW). Stalls
below 10 °C, slow 10–20 °C and 40–50 °C. Yield cap 5.5 Nm³ per digester-day
(documented anti-loop limit).

## Propane (`TLG/Content/Propane.lua`)

Vanilla `Base.PropaneTank` 5000 uses = 4.48 Nm³ = 9 kg = 417 MJ; propane does
not age. Bulk tank profile 380 Nm³.
