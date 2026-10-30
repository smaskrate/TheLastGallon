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
| Can → vehicle (`ISAddGasolineToVehicle`) | action wrap (new/complete/stop/serverStop) | yes | native | SRC-ONLY |
| Vehicle → can siphon (`ISTakeGasolineFromVehicle`) | action wrap; can fluids corrected from Petrol to the tank blend | yes | native | SRC-ONLY |
| Pump → can (`ISTakeFuel`) | action wrap; pump corrected (1 L/unit, no duplicate increment); can fluids set to reservoir blend | yes | pump: TLG-corrected native units | SRC-ONLY |
| Pump → vehicle (`ISRefuelFromGasPump`) | action wrap; pump corrected from 1.25 L/unit to 1 L/unit | yes | same | SRC-ONLY |
| Can → generator (`ISAddFuel`) | action wrap | yes | native | SRC-ONLY |
| Generator pickup (`ISTakeGenerator`) | wrap copies sidecar to item | yes | native fuel copied by vanilla | SRC-ONLY |
| Generator drop (`ISDropWorldItemAction`) / `IsoGenerator.new` | wrap copies sidecar to object | yes | native | SRC-ONLY |
| Still → can (TLG command) | TLG writes native fluids + sidecar | yes (fresh) | TLG then native | SRC-ONLY |
| Fermenter → still (TLG command) | machine-to-machine | n/a (wash) | TLG | Domain tests |
| Third-party mods | not tested | — | — | NOT RUN |

Vanilla refuel menus only offer containers that contain `Petrol`; pure
ethanol cannot be poured into vehicles/generators through vanilla menus. A
TLG pour action for non-petrol fuels is pending (see release checklist).

## Vehicles

| Chassis | Stock profile | Conversion | Evidence |
| --- | --- | --- | --- |
| All vanilla cars | engine_si_stock (assumed: every vanilla tank is "Gasoline") | — | SRC (content type), NOT RUN |
| Conversion chassis | see `TLG/Content/Conversions.lua` | flex / others | domain only, NOT RUN |

Per-instance part modData and `setEngineFeature` are expected per vehicle
(G09) but NOT RUN.

## Generators

`Base.Generator`, `Base.Generator_Old`, `Base.Generator_Yellow`,
`Base.Generator_Blue` (item scripts, verified ids). Stock profile
`generator_si_stock`. Burn is native; start gate uses `failToStart()`.
Runtime NOT RUN.

## Stations

Pumps are objects whose `getPipedFuelAmount()` > 0 (amount stored in object
modData). B42.21 also defines a `FuelPump` entity with a 22 000 L
FluidContainer; which one map pumps use is NOT RUN. Infinite-pump sandbox:
quantities are not corrected, reservoirs still age.

## Maps

Muldraugh, KY is the only map referenced by tests (Gas2Go at 10639,10615 from
`media/maps/Muldraugh, KY/objects.lua`). No map is verified at runtime.

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
| Base.Generator, _Old, _Yellow, _Blue | flex_generator | generator_si_stock → generator_si_flex | domain-tested; runtime NOT RUN |
| Base.Generator, _Old, _Yellow, _Blue | gas_generator | generator_si_stock → generator_gas | domain-tested; runtime NOT RUN |
| Base.CarNormal | flex_car_normal | engine_si_stock → engine_si_flex | domain-tested; runtime NOT RUN |
| Base.SmallCar | flex_small_car | same | domain-tested; runtime NOT RUN |
| Base.PickUpTruck | flex_pickup_truck | same | domain-tested; runtime NOT RUN |
| Base.StepVan | flex_step_van | same | domain-tested; runtime NOT RUN |

Chassis/item ids were verified in the 42.21 scripts (file:line in
`TLG/Content/Conversions.lua`). No electric or wood-gas vehicle conversion is
shipped yet (domain data exists for the vehicle gasifier module only).

## Pathway machines

Biodiesel, wood gas, biogas, propane and electricity are implemented as
domain modules with tests only; no game-facing adapters, placeable items or
UI exist for them yet. They are not advertised as playable.
