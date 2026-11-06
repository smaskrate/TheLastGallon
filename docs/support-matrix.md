# Support matrix

Build: 42.21.0 (`4a0e9546ec`) only. Nothing here is supported on another
build until it is tested there again.

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
| Item ↔ item pour (`ISFluidTransferAction`) | wrapped `FluidContainer.Transfer` | yes | native | **Verified RT-DS** (adapter calls without a character action); vanilla action itself NOT RUN |
| Any Lua code calling `FluidContainer.Transfer` | same wrapper | yes | native | **Verified RT-DS** |
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
| Can left on the ground, save and reload | record stays in item modData; adapter reads the fluid from the item or its world object | yes | native | **Read verified RT-SP** (run 5: record found after reload, the fluid sits on the world object); pouring from a ground can NOT RUN |
| Still → can (TLG command) | TLG writes native fluids + sidecar | yes (fresh) | TLG then native | **Verified RT-SP** (run 7, reflux still: 3.036 L ethanol + 0.194 L water; can fluids and record match) |
| Can → drying column → can (`machine.loadDry`, `machine.collect`) | TLG takes the can's ethanol and water and the quicklime; bottles dried ethanol | yes (degradation kept) | TLG then native | **Verified RT-SP** (run 7, 2026-10-31: water 6 % → 0.5 %, degradation 0.8 kept) |
| Fermentation vessel → still (TLG command) | machine-to-machine | n/a (wash) | TLG | **Verified RT-SP** (run 7: 33.3 L wash; yeast starter returned) |
| Third-party mods | not tested | — | — | NOT RUN |

Vanilla refuses a `FluidContainer.Transfer` between items while the player's
inventory is full (BC `FluidContainer.CanTransfer`, seen in run 10); TLG
follows whatever vanilla moves, so nothing is moved and nothing recorded.

Vanilla's refuel menus offer only containers that hold `Petrol`
(`contains(Fluid.Petrol)`): a station can with water and sediment is still
offered (RT-SP), pure ethanol is not. Pour other fuels with the TLG pour,
from the **Fuel (The Last Gallon)** menu. That menu is not shown for a can
lying on the ground: pick the can up first, since the mod's item commands
find cans in the player's inventory only.

## Vehicles

| Chassis | Stock profile | Conversion | Evidence |
| --- | --- | --- | --- |
| Base.CarNormal | engine_si_stock (59 L tank in run 5, 37 L in run 60) | — | **Verified RT-SP**: refuel, siphon, idle burn reconciled, driving burn reconciled (runs 175–176), tank record survives reload |
| Base.PickUpTruck | engine_si_stock (75 L tank in run 62) | — | **Verified RT-SP** (run 62): refuel from a can and at a pump, siphon, idle burn reconciled, the mod's own pours, start gate and stall |
| Other vanilla cars | engine_si_stock (assumed: every vanilla tank is "Gasoline") | — | SRC (content type), NOT RUN |
| Base.CarNormal, converted | engine_si_flex | flex_car_normal | **Verified RT-SP** (run 8): commissioned, ran on home-made ethanol (started first try), conversion survives reload |
| Other conversion chassis | see `TLG/Content/Conversions.lua` | flex / others | domain-tested only, NOT RUN |

A tank's capacity varies with the condition of the tank fitted
(`conditionAffectsCapacity`, SRC `template_gastank.txt`); the mod reads it
from the part each time.

Per-instance part modData and `setEngineFeature` act on one vehicle only
(G09, RT-SP with two `Base.CarNormal`). Start gate (`ISStartVehicleEngine`,
RT-SP run 6): a 36 % ethanol blend is refused and the engine stays off;
station fuel starts. Stall: the per-minute effect handler stalled an engine
running on that blend within a game minute. Run 62 repeated all of these
on two `Base.PickUpTruck`.

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
- Start gate (`ISActivateGenerator`, RT-SP run 6): activates on petrol,
  refused on E100.
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
    into a generator, ethanol refused into a petrol one and poured on
    confirmation into another, with the result shown to the player;
  - a generator started on petrol and refused on ethanol, its burn
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
    died, from the death, and working on.
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
  up while working, in multiplayer; driving on poor fuel, in multiplayer.

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
in Italian NOT RUN.

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

Biodiesel, wood gas, biogas, propane and electricity are implemented as
domain modules with tests only; no game-facing adapters, placeable items or
UI exist for them yet. They are not advertised as playable.
