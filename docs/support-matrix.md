# Support matrix

Build: 42.21.0 (`4a0e9546ec`) only. "Verified" means a runtime experiment on
this build passed; everything else lists its evidence level. Nothing here is
compatible with another build until re-tested.

## Transfer paths

| Path | Mechanism | Condition carried | Quantity owner | Evidence |
| --- | --- | --- | --- | --- |
| Item ↔ item pour (`ISFluidTransferAction`) | wrapped `FluidContainer.Transfer` | yes | native | **Verified RT-DS** (adapter calls without a character action); vanilla action itself NOT RUN |
| Any Lua code calling `FluidContainer.Transfer` | same wrapper | yes | native | Verified RT-DS |
| Java-side fluid moves (not via Lua) | none | no → reconciled as untracked inflow at baseline | native | SRC/BC reasoning |
| Pump → can (`ISTakeFuel`) | action wrap; pump corrected (1 L/unit, no duplicate increment); can fluids set to reservoir blend | yes, incl. water/sediment | pump: TLG-corrected native units | **Verified RT-SP** (runs 3–5: 10 L = −10 units) |
| Can → vehicle (`ISAddGasolineToVehicle`) | action wrap (new/complete/stop/serverStop) | yes | native | **Verified RT-SP** (station fuel; E25 blend 8 L) |
| Vehicle → can siphon (`ISTakeGasolineFromVehicle`) | action wrap; can fluids corrected from Petrol to the tank blend | yes | native | **Verified RT-SP** |
| Pump → vehicle (`ISRefuelFromGasPump`) | action wrap; pump corrected from 1.25 L/unit to 1 L/unit | yes | same | **Verified RT-SP** (run 5: 59 L = −59 units) |
| Can → generator (`ISAddFuel`) | action wrap | yes | native | **Verified RT-SP** |
| Station → can → vehicle → can → generator | all of the above, one batch | yes, end to end | — | **Verified RT-SP** (runs 3–5: 10.00000 L every hop) |
| TLG pour (`ISTLGPourFuel`, any fuel) | authoritative transfer | yes | TLG sets native | **Verified RT-SP** into generators and a car: petrol accepted, an incompatible result refused without confirmation (nothing moved), accepted with confirmation; dried ethanol accepted without confirmation by a flex-converted generator and car (run 8) |
| Generator pickup (`ISTakeGenerator`) | wrap copies sidecar to the new hand item | yes | native fuel copied by vanilla | **Verified RT-SP**, incl. taking a second generator while carrying one |
| Generator drop: drop action, `forceDropHeavyItems`, inventory drag to the floor; `IsoGenerator.new` | wraps re-attach the sidecar to the converted object | yes | native | **Verified RT-SP** (all three drop paths); drops done by Java alone are not seen |
| Can left on the ground, save and reload | record stays in item modData; adapter reads the fluid from the item or its world object | yes | native | **Read verified RT-SP** (run 5: record found after reload, the fluid sits on the world object); pouring from a ground can NOT RUN |
| Still → can (TLG command) | TLG writes native fluids + sidecar | yes (fresh) | TLG then native | **Verified RT-SP** (run 7, reflux still: 3.036 L ethanol + 0.194 L water; can fluids and record match) |
| Can → drying column → can (`machine.loadDry`, `machine.collect`) | TLG takes the can's ethanol and water and the quicklime; bottles dried ethanol | yes (degradation kept) | TLG then native | **Verified RT-SP** (run 7: water 6 % → 0.5 %, degradation 0.8 kept; added 2026-10-31, the column had no command before) |
| Fermenter → still (TLG command) | machine-to-machine | n/a (wash) | TLG | **Verified RT-SP** (run 7: 33.3 L wash; yeast starter returned) |
| Third-party mods | not tested | — | — | NOT RUN |

Vanilla refuel menus only offer containers that contain `Petrol`
(`contains(Fluid.Petrol)`): a station can with water and sediment is still
offered (RT-SP), pure ethanol is not. Non-petrol fuels use the TLG pour
action from the fuel menu. The TLG fuel menu is not shown for cans lying on
the ground (pick the can up first): item commands resolve cans in the
player's inventory only.

## Vehicles

| Chassis | Stock profile | Conversion | Evidence |
| --- | --- | --- | --- |
| Base.CarNormal | engine_si_stock (59 L tank) | — | **RT-SP**: refuel, siphon, idle burn reconciled, tank record survives reload |
| Other vanilla cars | engine_si_stock (assumed: every vanilla tank is "Gasoline") | — | SRC (content type), NOT RUN |
| Base.CarNormal, converted | engine_si_flex | flex_car_normal | **RT-SP** (run 8): commissioned, ran on home-made ethanol (started first try), conversion survives reload |
| Other conversion chassis | see `TLG/Content/Conversions.lua` | flex / others | domain only, NOT RUN |

Per-instance part modData and `setEngineFeature` act on one vehicle only
(G09, RT-SP with two `Base.CarNormal`). Start gate (`ISStartVehicleEngine`,
RT-SP run 6): a 36 % ethanol blend is refused and the engine stays off;
station fuel starts. Stall: the per-minute effect handler stalled an engine
running on that blend within a game minute.

Station fuel and stock engines (D-017): about 9 in 10 stations start with
0–0.15 % water, inside every engine's tolerance; about 1 in 10 start at
0.2–0.4 %, which halves a stock car's start chance (observed before D-017 at
the Gas2Go pump: 0.22–0.23 %, `startFactor=0.5`). The "Drain water" can
treatment removes free water (domain-tested; not exercised in game).

## Generators

`Base.Generator`, `Base.Generator_Old`, `Base.Generator_Yellow`,
`Base.Generator_Blue` (item scripts, verified ids). Stock profile
`generator_si_stock`. Burn is native; start gate uses `failToStart()`.
RT-SP (`Base.Generator`): max fuel 10 L; idle burn 0.015 L in 0.5–1.3 game
hours, connected with no appliance drawing; the native burn is reconciled proportionally
into the record. Start gate (`ISActivateGenerator`, RT-SP run 6): activates
on petrol, refused on E100. Flex conversion (RT-SP run 8): commissioned on a
`Base.Generator`, which then took dried ethanol without confirmation,
activated on it and kept the conversion and fuel across reload. Other
generator types NOT RUN.

## Stations

Pumps are objects whose `getPipedFuelAmount()` > 0 (amount stored in object
modData). RT-SP: the Muldraugh Gas2Go has 8 such pump objects
(`location_shop_gas2go_01_12/13`, about 4 000–15 000 units each); the
station reservoir record and unit count survive save and reload. B42.21 also
defines a `FuelPump` entity with a 22 000 L FluidContainer; the harness
dispensed from the piped amount and did not check whether map pumps also
carry that entity. Infinite-pump sandbox: quantities are not corrected,
reservoirs still age (NOT RUN).

## Maps

Muldraugh, KY is the only map referenced by tests (Gas2Go at 10639,10615 from
`media/maps/Muldraugh, KY/objects.lua`). RT-SP ran there (pumps at
10636/10654, 10622–10630). No other map is verified at runtime.

## Multiplayer

Architecture: server-authoritative commands with ledger dedupe and revision
checks (domain-tested). Dedicated server loads the mod (verified). Client
connection, replication and concurrency: NOT RUN.

## External mods

None tested. Mods that move fuel in Java, or write fluid containers directly
from Lua without `FluidContainer.Transfer`, bypass condition propagation;
their changes are reconciled conservatively.

## Conversions (`ConversionService.matrix()`)

| Device | Conversion | From → to | Evidence |
| --- | --- | --- | --- |
| Base.Generator | flex_generator | generator_si_stock → generator_si_flex | **Verified RT-SP** (run 8) |
| Base.Generator_Old, _Yellow, _Blue | flex_generator | same | domain-tested; runtime NOT RUN |
| Base.Generator, _Old, _Yellow, _Blue | gas_generator | generator_si_stock → generator_gas | domain-tested; runtime NOT RUN |
| Base.CarNormal | flex_car_normal | engine_si_stock → engine_si_flex | **Verified RT-SP** (run 8) |
| Base.SmallCar | flex_small_car | same | domain-tested; runtime NOT RUN |
| Base.PickUpTruck | flex_pickup_truck | same | domain-tested; runtime NOT RUN |
| Base.StepVan | flex_step_van | same | domain-tested; runtime NOT RUN |

Chassis/item ids were verified in the 42.21 scripts (file:line in
`TLG/Content/Conversions.lua`). "Verified RT-SP" covers begin, parts
delivery, work to `Commissioned` (time from a mod-clock fixture), the flex
profile, running on ethanol and reload, with commands sent directly: the
workshop menu, cancel, remove and engine replacement are NOT RUN. No
electric or wood-gas vehicle conversion is shipped yet (domain data exists
for the vehicle gasifier module only).

## Pathway machines

Biodiesel, wood gas, biogas, propane and electricity are implemented as
domain modules with tests only; no game-facing adapters, placeable items or
UI exist for them yet. They are not advertised as playable.
