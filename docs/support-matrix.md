# Support matrix

Build: 42.22.2 (`3d39148846`) only. Nothing here is supported on another
build until it is tested there again. The rows below were verified on
42.21.0 (`4a0e9546ec`), in the run each one cites. On 42.22.2 nine harness
modes were run again and all passed (launches 216–226, `test-results.md`);
the other modes have not been run again on this build. The biodiesel
pathway, the diesel generator, the diesel vehicles and the diesel pumps
(version 0.2.0, D-036) were built and run on 42.22.2 (launches 229–250), wrong-fuel damage (version 0.3.0, D-037) in launches 261–282, the menus that follow the click (version 0.3.1) in launches 289–294, and the Diesel Generator's sprite given back (version 0.3.2) in launches 299–302.

Evidence levels:

- **Verified RT-SP**: passed in a single-player game, run by the mod's test
  harness on this build.
- **Verified RT-MP**: passed on a dedicated server with harness clients,
  all on one computer.
- **Verified RT-DS**: passed on a dedicated server alone.
- SRC: read in the game's own Lua; BC: read in the game's compiled code.
  Neither is a test in game.
- Domain-tested: passed in the mod's own test suite on the game's Lua VM,
  outside the game.
- NOT RUN: not tested.

## Transfer paths

| Path | Mechanism | Condition carried | Quantity owner | Evidence |
| --- | --- | --- | --- | --- |
| Item ↔ item pour (the game's **Transfer Liquid** window, `ISFluidTransferAction`) | action wrap: its slices go to the game, the whole pour is followed once, when it completes or is stopped (D-035) | yes, incl. water/sediment | native | **Verified RT-SP** (run 215: two full pours and one stopped part-way, water and sediment carried; multiplayer NOT RUN) |
| Any other Lua code calling `FluidContainer.Transfer` | wrapped `FluidContainer.Transfer`, once per call | yes, except a component under 0.0002 L per call that the target lacks (below) | native | **Verified RT-DS** |
| Java-side fluid moves (not via Lua) | none | no → reconciled as untracked inflow at baseline | native | SRC/BC reasoning |
| Pump → can (`ISTakeFuel`) | action wrap; pump corrected (1 L/unit, no duplicate increment); can fluids set to reservoir blend | yes, incl. water/sediment | pump: TLG-corrected native units | **Verified RT-SP** (runs 3–5: 10 L = −10 units) |
| Can → vehicle (`ISAddGasolineToVehicle`) | action wrap (new/complete/stop/serverStop) | yes | native | **Verified RT-SP** (station fuel; E25 blend 8 L) |
| Vehicle → can siphon (`ISTakeGasolineFromVehicle`) | action wrap; can fluids corrected from Petrol to the tank blend | yes | native | **Verified RT-SP** |
| Pump → vehicle (`ISRefuelFromGasPump`) | action wrap; pump corrected from 1.25 L/unit to 1 L/unit | yes | same | **Verified RT-SP** (run 5: 59 L = −59 units) |
| Can → generator (`ISAddFuel`) | action wrap | yes | native | **Verified RT-SP** |
| Station → can → vehicle → can → generator | all of the above, one batch | yes, end to end | — | **Verified RT-SP** (runs 3–5: 10.00000 L every hop) |
| TLG pour (`ISTLGPourFuel`, any fuel) | authoritative transfer | yes | TLG sets native | **Verified RT-SP** into generators and a car: petrol accepted, an incompatible result refused without confirmation (nothing moved), accepted with confirmation; dried ethanol accepted without confirmation by a flex-converted generator and car (run 8) |
| Generator pickup (`ISTakeGenerator`) | wrap copies sidecar to the new hand item | yes | native fuel copied by vanilla | **Verified RT-SP**, incl. taking a second generator while carrying one (the action queued directly in phase A; from the world menu in run 85) |
| Generator drop: drop action, the menus' unequip (`ISUnequipAction`: a second generator or a heavy item taken, a weapon equipped), `forceDropHeavyItems`, inventory drag to the floor; `IsoGenerator.new` | wraps re-attach the sidecar to the converted object | yes | native | **Verified RT-SP** (the drop action, `forceDropHeavyItems` and the drag; the menus' unequip in run 85: a second generator taken from the world menu, a bat equipped from the inventory menu); drops done by Java alone are not seen |
| Can left on the ground, save and reload | record stays in item modData; adapter reads the fluid from the item or its world object | yes | native | **Read verified RT-SP** (run 5: record found after reload, the fluid sits on the world object). **Pour into the generator** from a placed can's menu **verified RT-SP** (2026-11-08): the character picked the can up, then poured |
| Still → can (TLG command) | TLG writes native fluids + sidecar | yes (fresh) | TLG then native | **Verified RT-SP** (run 7, reflux still: 3.036 L ethanol + 0.194 L water; can fluids and record match) |
| Can → drying column → can (`machine.loadDry`, `machine.collect`) | TLG takes the can's ethanol and water and the quicklime; bottles dried ethanol | yes (degradation kept) | TLG then native | **Verified RT-SP** (run 7, 2026-10-31: water 6 % → 0.5 %, degradation 0.8 kept) |
| Fermentation vessel → still (TLG command) | machine-to-machine | n/a (wash) | TLG | **Verified RT-SP** (run 7: 33.3 L wash; yeast starter returned) |
| Third-party mods | not tested | — | — | NOT RUN |

Vanilla refuses a `FluidContainer.Transfer` between items while the player's
inventory is full (BC `FluidContainer.CanTransfer`, seen in run 10); TLG
follows whatever vanilla moves, so nothing is moved and nothing recorded.

A call through the wrapper follows its own parcel. When the mod writes the
target's record and fluids, a component under 0.0002 L is added to the
target's largest one (`Native.holdable`), since the game drops a fluid
under 0.0001 L. So a single call that brings less than 0.0002 L of a
component the target lacks turns it into the main fuel there, in the
record and in the fluids.

The **Transfer Liquid** window pours in slices of about 0.02 L (3.79 L in
190 calls), so it is followed per pour instead (D-035): its slices go to
the game, and the mod follows what left the source once, when the pour
completes or is stopped. Until then the cans' records stay as they were
before the pour. In run 215 each 3.79 L pour of fuel with 0.8 % water
and 0.3 % sediment carried its 0.03 L of water and 0.01 L of sediment;
followed per slice (run 213), they did not arrive.

Vanilla's refuel menus offer only containers that hold `Petrol`
(`contains(Fluid.Petrol)`): a station can with water and sediment is still
offered (RT-SP), pure ethanol is not. Pour other fuels with the TLG pour,
from the **Fuel (The Last Gallon)** menu. A container placed on the ground
has the same menu, from a right-click on its world model or on its entry in
the floor inventory. Verified RT-SP on 2026-11-08 for a petrol can (holding
petrol, and empty), a water bottle holding petrol and a bucket holding
ethanol: **What I know about it**, **Take a sample (kit)** and a treatment
were each answered for the placed container. A pour into an engine picks
the container up first.

## Vehicles

| Chassis | Stock profile | Conversion | Evidence |
| --- | --- | --- | --- |
| Base.CarNormal | engine_si_stock (59 L tank in run 5, 37 L in run 60) | — | **Verified RT-SP**: refuel, siphon, idle burn reconciled, driving burn reconciled (runs 175–176), tank record survives reload |
| Base.PickUpTruck | engine_si_stock (75 L tank in run 62) | — | **Verified RT-SP** (run 62): refuel from a can and at a pump, siphon, idle burn reconciled, the mod's own pours, start gate and stall |
| Other vanilla cars | engine_si_stock (assumed: every vanilla tank is "Gasoline") | — | SRC (content type), NOT RUN |
| Base.CarNormal, converted | engine_si_flex | flex_car_normal | **Verified RT-SP** (run 8): commissioned, ran on home-made ethanol (started first try), conversion survives reload |
| Other conversion chassis | see `TLG/Content/Conversions.lua` (no diesel chassis, and not `TLG.DieselGenerator`, is among them) | flex / others | domain-tested only, NOT RUN |
| Base.VanAmbulance, Base.VanSeats, Base.VanRadio, Base.PickUpVanLightsFire, in a world started as a new game with 0.2.0 or later | engine_ci_stock; an unrecorded tank is read as diesel | — | **Verified RT-SP** (launch 240): profile and fuel; the ambulance started on its diesel and took biodiesel through the mod's pour; a petrol pour into the pickup van refused. Refuel at a diesel pump and start, and a pickup van filled at a petrol pump refused at the start (launch 244, `Base.PickUpVan`). **Verified RT-MP** (launch 248): the ambulance read as diesel on the client and started |
| The other variants of `PickUpVan*`, `VanSeats*`, `VanRadio*`, `VanAmbulance*` (`Vehicles.DIESEL_FAMILIES`, by the script name's beginning) | engine_ci_stock, as above | — | domain-tested (the names), NOT RUN in game |
| Any chassis in a world started before 0.2.0, or in a save the mod was added to | engine_si_stock (the world's record has no `dieselVehicles`, or `false`) | — | domain-tested; an ambulance in a save that gained the mod (launch 254) and in a save made with 0.1.2 (launch 257) read as petrol, and the 0.1.2 save's recorded ambulance started on it |

A tank's capacity varies with the condition of the tank fitted
(`conditionAffectsCapacity`, SRC `template_gastank.txt`); the mod reads it
from the part each time.

Per-instance part modData and `setEngineFeature` act on one vehicle only
(G09, RT-SP with two `Base.CarNormal`). Start gate (`ISStartVehicleEngine`):
a blend the engine cannot take is refused and the engine stays off;
station fuel starts. Stall: the per-minute effect handler stalled an engine
running on that blend within a game minute. Since 0.3.0 the blend is over
30 % diesel (launches 263, 272, 278, 279, 282); until 0.2.0 it was 36 % ethanol
(RT-SP run 6, and run 62 on two `Base.PickUpTruck`), which now runs a
stock engine lean (D-037).

Wrong fuel (D-037, launches 271 and 281, `Base.CarNormal`, `Base.VanAmbulance`,
`Base.PickUpVanLightsFire`): the verdict for every band of
`balance.md`'s table; a start refused on 40 % diesel cost the petrol car 1
engine condition and 2 % battery charge and showed the driver a line; on
20 % diesel 4 L cost it 3 engine and 2 exhaust (`Muffler`) condition; the
ambulance on a third petrol lost 2 engine condition for 2 L; the pickup
van on pure petrol failed when the draw was held at 0 (condition 0,
stopped, no restart); the ambulance siphoned with vanilla's
`ISTakeGasolineFromVehicle`, refilled with diesel and started clean. The
draws were held and the litres taken from the tank by the test. NOT RUN:
a flex-converted engine with diesel, driving on a wrong fuel, a stall on
it, an unforced failure, a repair, a server.

Driving (RT-SP run 176, `Base.CarNormal` on a cleared straight road): on
E10, 352 tiles at 25 km/h burned 0.778 L. All of it was the game's own
burn: the mod took nothing, and the tank's record followed the drop in
proportion, keeping the blend. On a blend no stock engine takes, the
engine stalled at 24.7 km/h, burned nothing more, and the car rolled to a
stop. No part was damaged. Not run: other chassis, a converted car on the
move, off-road driving.

Poor fuel on the move (D-031, RT-SP run 179, `Base.CarNormal`): on petrol
aged to 2.6, the engine ran at 3406 of its 4000 power from its first game
minute and had its power back two game minutes after stopping, quality and
loudness unchanged. The Engine part lost the condition its litres owed (at
100 times the rate in the test). With the sandbox option
**Bad fuel can stall engines** off, a blend no stock engine takes ran at
half power with no stall.

On a dedicated server (RT-MP run 188, a `Base.CarNormal` idling), the
server applies these effects and both clients show them: the power lowered
from 4000 to 3406 while the engine runs and back to 4000 after it stops,
and the Engine part's wear. On a blend no stock engine takes, with
**Bad fuel can stall engines** on, the start gate refused the start and a
running engine stalled at the next game minute; with it off, the engine
ran without a stall. Not run: driving in multiplayer, other chassis,
converted engines.

Station fuel and stock engines (D-017): about 9 in 10 stations start with
0–0.15 % water, inside every engine's tolerance; about 1 in 10 start at
0.2–0.4 %, which halves a stock car's start chance (observed before D-017 at
the Gas2Go pump: 0.22–0.23 %, `startFactor=0.5`). The
**Let settle and drain water** can treatment removes free water
(domain-tested; not exercised in game).

## Generators

`Base.Generator`, `Base.Generator_Old`, `Base.Generator_Yellow` and
`Base.Generator_Blue` (item scripts, verified ids) have the stock profile
`generator_si_stock`. Burn is native; the start gate uses `failToStart()`.

- **Verified RT-SP** on `Base.Generator`: max fuel 10 L; idle burn 0.015 L
  in 0.5–1.3 game hours, connected with no appliance drawing; the native
  burn is reconciled proportionally into the record.
- Start gate (`ISActivateGenerator`): activates on petrol, refused on a
  tank of diesel, which costs it condition (launches 263, 272, 278, 279; until
  0.2.0 the refusal was on E100, RT-SP run 6, which now starts 3 times in 10
  and wears: D-037).
- Wrong fuel (D-037, launch 271): on 40 % diesel the start refused, 1
  condition lost, the line shown; drained into a can by the mod's
  transfer, refilled with petrol, the verdict clean. NOT RUN: running on
  10 to 30 % diesel, a flex generator with diesel.
- Flex conversion (RT-SP run 8): commissioned on a `Base.Generator`, which
  then took dried ethanol without confirmation, activated on it and kept
  the conversion and fuel across reload.
- Wear (D-031, RT-SP run 179): a `Base.Generator` on petrol aged to 3.0,
  run 6 game hours, was charged by the next refuel exactly the wear its
  0.012 L owed (at 100 times the rate in the test), and only once. On a
  dedicated server a refuel from the world menu charged the wear due
  exactly, once, and the client showed the server's condition (RT-MP
  run 188). The item's own rate is read from its script
  (`ConditionLowerChanceOneIn` 30, found in game).
- Other generator types NOT RUN; the other three models' rates (25, 36,
  24) were not run.

`TLG.DieselGenerator` (D-036) is the mod's own generator item: vanilla's
`Base.Generator` values, the profile `generator_ci_bio` (diesel and
biodiesel at any share), its own tile sprite `tlg_generators_01_0`
(vanilla's red generator turned green) and icon. It comes from loot: every
list that offers `Base.Generator` offers it at half that weight.

- **Verified RT-SP** (launches 236–243): put down, it is an `IsoGenerator`
  that keeps its item type; biodiesel through the mod's pour, started, run
  two game hours with its record following; petrol through vanilla's
  `ISAddFuel` recorded as petrol (its start is refused when the roll is
  lost, launch 264; under 0.2.0 always); taken with
  vanilla's `ISTakeGenerator` as itself, a vanilla generator beside it as
  `Base.Generator`; on pure petrol (launch 271, D-037) it started, 1 L
  gone cost it 46 condition (67 hours at the reference load with
  `GeneratorFuelConsumption` 0.1), it failed when the draw was held at 0,
  was switched off and vanilla's switch-on was invalid at condition 0;
  sprite, type, profile and fuel kept through a save and
  a reload; rolled from `CrateGenerator`'s list as the game fills a
  container (27 in 500 fills, launch 239).
- **Verified RT-MP** (launch 248): drawn on the client with its sprite;
  fuelled, started, taken and put down again, the server and the client
  agreeing on its type and record.
- NOT RUN: powering anything; its info window; one found in a container of
  the map or a truck bed; a server restart with one placed; another mod
  using tile file number 7341.

## Stations

Pumps are objects whose `getPipedFuelAmount()` > 0 (amount stored in object
modData). RT-SP: the Muldraugh Gas2Go has 8 such pump objects
(`location_shop_gas2go_01_12/13`, about 4 000–15 000 units each); the
station reservoir record and unit count survive save and reload. B42.21 also
defines a `FuelPump` entity with a 22 000 L FluidContainer; the harness
dispensed from the piped amount and did not check whether map pumps also
carry that entity. Infinite-pump sandbox: quantities are not corrected,
reservoirs still age (NOT RUN).

Diesel pumps (D-036): in a world started as a new game with 0.2.0 or
later, a pump's first record holds diesel for about one pump in four
(`WorldInit.stationProduct`, seeded per pump) and petrol otherwise; the
record keeps what the pump gives. The pump's menu has **Read what this
pump gives**. **Verified RT-SP** (launch 244): the entry on a diesel and
on a petrol pump; vanilla's `ISTakeFuel` into an empty can (the can's
fluids `TLG_Diesel`, no `Petrol`) and `ISRefuelFromGasPump` into an empty
tank, litre for litre. **Verified RT-MP** (launch 248): the entry's answer
and a can filled, on the client. In both the pump was made a diesel pump
by the test. NOT RUN: a pump left to the world's draw filled from; a can
holding diesel topped up (vanilla offers its pump entry for an empty can
or one with `Petrol`); **Pour into the station reservoir** at a diesel
pump.

## Maps

Muldraugh, KY is the only map referenced by tests (Gas2Go at 10639,10615 from
`media/maps/Muldraugh, KY/objects.lua`). RT-SP ran there (pumps at
10636/10654, 10622–10630). No other map is verified at runtime.

## Multiplayer

Architecture: server-authoritative commands with ledger dedupe and revision
checks (domain-tested). Checked on a dedicated server with two players,
both on one computer (RT-MP, 2026-11-03 to 2026-11-06):
- **Verified:**
  - a fuel sample and a stabilizer treatment asked from a client and
    answered by the server;
  - the same request sent again, answered from the ledger without using
    a second stabilizer;
  - the can's record, the same on the client and on the server;
  - a machine's status, asked by either player within reach;
  - the field manual in the server's loot, read through **Inspect**;
  - the small items' floor models, seen by both players and after one
    leaves and joins again;
  - the fermentation vessel's carry pose, seen on the other player's
    screen at every gait;
  - the fermentation vessel taken off the floor into both arms through
    the loot window, its batch paused while carried and running again
    where it is put down; when two players take it at once, one gets it
    and the other's action is refused;
  - all of the above with both players without admin rights;
  - two players loading one fermentation vessel at once: one load is
    taken, the other refused ("It is busy with another batch.") with the
    player's ingredients kept;
  - a running fermentation vessel taken with the world menu's **Grab**:
    the server does not see that move, so the batch pauses at the next
    look at it, credited up to the last time it was seen standing;
    dropped from the inventory, it runs again at once where it lands;
  - at the pumps: a pump into a can, a can into a car, a pump into a car,
    a can into a generator, each with its fuel's record; the TLG pour
    into a generator, diesel refused into a petrol one and poured on
    confirmation into another, with the result shown to the player
    (launches 269 and 277; ethanol until 0.2.0);
  - a generator started on petrol and refused on diesel, the refusal's
    line reaching the player's client from the server (launch 277), its burn
    followed, its record carried when it is taken and put back; a car
    started with its key and idling, its burn followed;
  - a generator converted to flex fuel at the workshop
    (**Start: Flex-fuel generator conversion**, **Hand over parts**,
    **Work on it** to Commissioned), then fed ethanol without a
    confirmation and started on it; a car the same way, the ethanol poured
    at its filler;
  - siphoning a car into a can, each record following;
  - a fermentation vessel taken out of a container (a bin) into both
    arms;
  - both stills and the drying column: firewood, wash from a finished
    fermentation vessel, distilling (the pot still fed again when its fire
    ran out), each run collected into a can, the reflux run dried and
    collected (80 %, 94 % and dried to under 0.5 % water);
  - a server restart: both players' floor, a can's record and a running
    fermentation vessel's batch the same afterwards;
  - poor fuel's engine effects, applied by the server and seen by both
    clients: a car's power lowered while its engine runs and given back
    when it stops, the Engine part's wear, the start gate, the stall
    option, and a generator's wear charged at a refuel;
  - the machines' hourly readings and ten-minute notes, beside a campfire
    the server lit;
  - **What I know about it** from a client's Fuel menu, answered by the
    server: a kit sample and a look listed with their ages, and the open
    note once the can was opened; both tests still known after the player
    left and the server was saved, stopped and started again;
  - a carrier's death: the fermentation vessel put down where the player
    died, from the death, and working on;
  - the biodiesel pathway (launch 248, one client): each of the five
    machines loaded from the client, the leacher, the reactor and the wash
    tank from a finished machine beside them; washed biodiesel collected
    into the client's can, a retort's methanol refused to one; the diesel
    generator, a diesel ambulance and a diesel pump as their sections say.
- **The game's own limit (42.21):** on a dedicated server no heavy item can
  be taken off the floor through the loot window (double-click or drag);
  the server fails the action and the item stays where it is. Vanilla's
  meteorite fails the same way without the mod. For the fermentation
  vessel the mod does the server's part itself (D-030); the game's own
  heavy items are left as the game leaves them.
- Reading print media, the field manual included, is recorded on the
  server and not on the reading player's client, as for the game's own
  fliers.
- A server must reach the mod's folder by its real path. Through a
  junction the game cannot start a server with a mod that ships animation
  files, as this one does for its carry pose (tried; a symbolic link was
  not).
- **NOT RUN:** a real network (everything ran on one computer; testing
  across machines is set aside for now); a still or drying column picked
  up while working, in multiplayer; driving on poor fuel, in multiplayer;
  a biodiesel batch running through its hours on a server (the machines
  the test loaded from were set up finished).

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
delivery, work to `Commissioned`, the flex profile, running on ethanol and
reload; the work ran with a mod-clock fixture (runs 8–12) and on the game
clock at vanilla x40 (run 13). The work runs through the timed action
`ISTLGConversionWork` (D-018): it stops when the worker leaves, and time
away is not credited (run 9). Every step is taken from the workshop menu,
including the walk to the engine area, a refused start and the ending on a
missing tool (run 12). Cancel, remove and engine replacement are
NOT RUN. No electric or wood-gas vehicle conversion is shipped yet (domain
data exists for the vehicle gasifier module only).

## Crafting (`TLG_machines.txt`, D-019)

| Recipe | Where | Evidence |
| --- | --- | --- |
| Make Fermentation Vessel (`TLG_MakeFermenterVessel`) | table or counter (`AnySurfaceCraft;Carpentry`) | **Verified RT-SP**: inventory craft menu (run 12), crafting window (run 193) |
| Make Pot Still (`TLG_MakePotStill`) | table or counter (`AnySurfaceCraft`) | **Verified RT-SP**: inventory craft menu (run 12), crafting window (run 193) |
| Make Reflux Column Still (`TLG_MakeRefluxStill`) | in hand (`InHandCraft;Welding`) | **Verified RT-SP**: inventory craft menu (run 12), crafting window (run 193) |
| Make Ethanol Drying Column (`TLG_MakeDryingColumn`) | table or counter (`AnySurfaceCraft`) | **Verified RT-SP**: inventory craft menu (run 12), crafting window (run 193) |
| Make Fuel Sampling Kit, Make Fuel Filter Cartridge, Make Fuel Stabilizer (`TLG_MakeSampleKit`, `TLG_MakeFuelFilter`, `TLG_MakeFuelStabilizer`) | in hand | **Verified RT-SP** in the crafting window (run 193); listed for crafting in runs 10–12 |
| Make Wood Retort, Make Biodiesel Reactor, Make Biodiesel Wash Tank (`TLG_MakeWoodRetort`, `TLG_MakeBiodieselReactor`, `TLG_MakeBiodieselWashTank`) | in hand (`InHandCraft;Welding`) | **Verified RT-SP** in the crafting window (launch 249) |
| Make Ash Barrel (`TLG_MakeAshBarrel`) | in hand (`InHandCraft`) | **Verified RT-SP** in the crafting window (launch 249) |
| Make Lye Leacher (`TLG_MakeLyeLeacher`) | table or counter (`AnySurfaceCraft;Carpentry`) | **Verified RT-SP** in the crafting window (launch 249) |

Verified in the inventory craft menu (run 12): offered by the menu, crafted
next to a counter (or in hand), output in the inventory, consumed inputs
gone (pot and jars included) and kept tools still there.

Verified in the crafting window (run 193), opened with the button beside
the equipped items, at a workbench: all seven recipes listed by the names
above, each found by typing its name and made with **Craft** (the drying
column by double-clicking its row), with its output counted, inputs used
and tools kept. Picked with its nails missing, the fermentation vessel
showed **Craft** disabled, and nothing started. Not looked at: the craft
menu's option labels, which come from the same names. The crafting window
in Italian NOT RUN. Launch 249 repeated the window's checks for all twelve
recipes, the five biodiesel machines among them; those five were not tried
from the inventory craft menu.

With a full inventory vanilla drops the output on the floor
(`Actions.addOrDropItem`).

## Moving machines (D-015)

| Move | Paths | Evidence |
| --- | --- | --- |
| Pick up | world menu **Grab**, the loot window's **Grab** button; a grab no Lua sees (multiplayer's) is credited up to the last time the machine was found placed | **Verified RT-SP** (runs 27, 45, 79) |
| Put down | place action, inventory **Drop** | **Verified RT-SP** (runs 27, 45, 79) |
| The fermentation vessel taken into both hands (a heavy item) | loot window double-click or drag (`ISEquipHeavyItem`; the mod lifts the world object 42.21 leaves on the square); on a dedicated server, where that action fails, the mod takes it itself (D-030) | **Verified RT-SP** (run 79: taken, carried an hour; run 81: taken again, carried half an hour). **Verified RT-MP** (runs 146–147, dedicated server: taken off the floor the double-click way, its batch carried on the server and on the player's client; two players taking it at once, the second refused) |
| The fermentation vessel put down at the feet | the menus' unequip (`ISUnequipAction`: another heavy item taken, a weapon equipped); `forceDropHeavyItems` (a vehicle entered, an animal handled, a trap set); the mod, when an action that plays its own animation starts (D-025 amendment) | **Verified RT-SP** (run 79: dropped by `forceDropHeavyItems` called directly; run 81: put down by taking a meteorite the double-click way; run 99: put down when a loot from a bag on the floor started, and by the menus' unequip when a bat was equipped from the inventory menu). **Verified RT-MP** (runs 146–147: put down at the feet by the server's command and running again there). Entering a vehicle, and a drop when climbing, NOT RUN |
| The fermentation vessel at its carrier's death | dropped by the game where its carrier dies, and put down by the mod from the death: in single player at the death event; on a dedicated server, which tells no death, when it leaves the player's hands (D-015 amendment) | **Verified RT-SP** (run 202: put down at the death, worked as a placed one). **Verified RT-MP** (run 210, dedicated server: put down where the player died, from the death, and worked on) |
| The fermentation vessel carried at each gait (its carry pose, D-025) | walking, running; sprinting, crouched or not, with a sprint pose of its own; crouched, still or moving, with a crouched pose of its own | **Verified RT-SP**: kept in both hands with the pose on at every gait (run 108); the crouched pose holds it upright, crouched still, walking and running (run 113); the sprint pose holds it upright and steady through the stride, sprinting standing or crouched, and running tilts it with the lean (run 117). **Verified RT-MP** (runs 145–147: the other player's client draws the pose at every gait) |

## Pathway machines

Biodiesel is playable from 0.2.0 (D-036): five placeable machines, each
loaded from its menu (`machine.load`), the last collected into a can.

| Machine | Load | Evidence |
| --- | --- | --- |
| Wood Retort (`TLG.WoodRetort`, `wood_retort`) | wood from the inventory; firebox | **Verified RT-SP** (launch 231): 99 kg, 17.4 h, 5.01 L of methanol, 24.6 kg of firebox wood. **Verified RT-MP** (launch 248): the load |
| Ash Barrel (`TLG.AshBarrel`, `ash_pit`) | wood from the inventory | **Verified RT-SP** (launch 231): 99 kg, 16.95 h, 1.485 kg of ash. **Verified RT-MP** (launch 248): the load |
| Lye Leacher (`TLG.LyeLeacher`, `lye_leacher`) | ash from a finished ash barrel within two tiles, water; firebox | **Verified RT-SP** (launch 231): 28 h, 0.223 kg of lye. **Verified RT-MP** (launch 248): the load |
| Biodiesel Reactor (`TLG.BiodieselReactor`, `biodiesel_reactor`) | oil from the inventory, methanol and lye from a finished retort and leacher within two tiles; firebox | **Verified RT-SP** (launch 231): 19 bottles of `Base.OilVegetable` (17.1 L), 10.5 h, 16.84 L of biodiesel in the crude. **Verified RT-MP** (launch 248): the load and the firebox |
| Biodiesel Wash Tank (`TLG.BiodieselWashTank`, `biodiesel_wash_tank`) | the crude of a finished reactor within two tiles, water; firebox; **Collect biodiesel into a fuel can** | **Verified RT-SP** (launch 231): 28 h, grade good, 17.07 L collected into a jerry can, fit for `engine_ci_bio`. **Verified RT-MP** (launch 248): the load, and the collection from a finished tank |

Launch 231 ran the chain with the shape-built models the mod had then;
launch 253 ran it again with the supplied models, from the installed
0.2.0 package, with the same results. NOT RUN: `Base.OilOlive`, `Base.Lard` and a part-used
bottle; a batch limited by the methanol; the retort's charcoal; a firebox
running out; Pause, Resume and Abort; a machine picked up while working; a
save with a batch running; settling in the cold; a batch through its hours
on a server.

The mod's own oil press is not shipped: vanilla's gives the oil. Wood gas,
biogas, propane and electricity are implemented as domain modules with
tests only; no game-facing adapters, placeable items or UI exist for them
yet. They are not advertised as playable.
