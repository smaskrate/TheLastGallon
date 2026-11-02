# Architecture decisions

Each entry: decision, reason, evidence, consequences. Superseded decisions stay
listed with their replacement.

## D-001 Pin one build (42.21.0)
* Decision: support exactly 42.21.0 (`4a0e9546ec`). `mod.info` uses
  `versionMin=42.21` and no `versionMax`; on other builds the mod logs a
  warning (and the UI shows it) instead of refusing to load.
* Reason: the specification forbids advertising generic B42 compatibility;
  a hard `versionMax` would block development the day the game updates.
* Evidence: `environment.md`.

## D-002 Repository and package layout
* Decision: repository root = `<game>/mods/TheLastGallon` (chosen by the
  user). Runtime package = `Contents/mods/TheLastGallon/{42,common}` (Workshop
  layout). Development experiments live in a separate mod
  `tests/ingame/TheLastGallonHarness` that is never packaged.
* Reason: the spec keeps tests, tools and art sources out of the package.
* Evidence: BC `getAllModFoldersAux` / `getModVersionDirName` (G01).

## D-003 Domain tests on the game's Kahlua VM
* Decision: `tools/kahlua-runner` (reflection only, JDK 17 `--release 17`) runs
  Lua on `se.krka.kahlua` from `projectzomboid.jar` with the shipped
  `stdlib.lua`, launched by the game's Java 25.
* Reason: no standalone Lua is installed and the shipped VM is the real target
  dialect (Kahlua quirks would be missed by PUC Lua).

## D-004 Isolated dev cache outside `<game>/mods`, mirror deployment
* Decision: `%LOCALAPPDATA%\TheLastGallon\devcache`, `options.ini`
  pre-created, mods deployed with `robocopy /MIR`, no junctions.
* Reason: incident of 2026-10-30 (`environment.md`): first-run
  `copyPasteFolders("mods")` copied the repository into itself through a
  junction.

## D-005 Lua subset rules
* No `next`, `math.random`, `table.unpack`, `goto`, bit operations; floored
  modulo through `TLG.Num.mod`; no recursion deeper than a few hundred frames;
  deterministic iteration through `TLG.Tables.sortedKeys`; no structured error
  values (functions return `{ok=false, reason=...}` tables).
* Evidence: runtime probes (engine-capabilities, "Lua runtime").

## D-006 Quantity, composition and consumption ownership per adapter
| Adapter | Quantity owner | Composition owner | Consumption owner | Sidecar store |
| --- | --- | --- | --- | --- |
| Item fluid container | native `FluidContainer` | native fluids (TLG fluids for alternatives and contaminants) | native (any vanilla use) | item modData `tlg` |
| Vehicle tank | native part content amount | TLG sidecar | native engine | part modData `tlg` |
| Generator | native `IsoGenerator.fuel` | TLG sidecar | native burn | object modData `tlg`; item modData while carried |
| Station reservoir | TLG reservoir record (litres) | TLG | TLG dispensing (managed pumps) | global ModData `TLG_Sites` |
| Mod machines/tanks | TLG | TLG | TLG | object modData / global ModData |

* TLG never subtracts fuel that a native owner consumes. Changes TLG did not
  initiate are reconciled: a decrease removes all components proportionally;
  an increase of unknown origin is mixed in as "untracked inflow" with the
  pessimistic world-baseline condition (never fresh). Diagnostics are logged.
* Reason: spec §8 (one consumption owner, reconciliation, no fresh fuel from
  unknown changes).
* Amendment (2026-11-02): untracked inflow mixes in when it is found. The
  changes are measured against the record as last written, never against
  the record aged since: aging turns fuel into water that native fluids
  never show, which would read as inflow. What left goes first, from the
  record as written. The record is then advanced to the read and the
  inflow mixes in there, at that moment's baseline (`Tx.reconcile`'s `at`,
  in all four adapters). It used to mix in at the last write, and the
  caller's advance then aged it a second time over the time it went
  unseen. A can topped up with 3 L while the mod was away for a game day
  read 0.049706 instead of 0.044565, 11.5 % more degraded (RT-SP run 54).
  Verified RT-SP run 55 (5/0 on return): the same scenario read the rule
  exactly, 0.313571525, where the old order gives 0.319523279.

## D-007 Native fluids for alternative fuels and contaminants
* Decision: script fluids `TLG_Ethanol`, `TLG_Diesel`, `TLG_Biodiesel` (and,
  for contamination, `TLG_FuelWater`, `TLG_FuelSediment`) in category `Fuel`
  with a Fuel blend whitelist.
* Reason: native item containers then carry composition through every native
  transfer, including code paths TLG cannot hook; only chemical condition
  needs a sidecar. Vanilla `Water` cannot blend with `Petrol` (RT-DS), so water
  contamination needs its own fuel-category fluid.
* Consequence: vanilla refuel menus only accept containers that contain
  `Petrol`; TLG adds its own menu entries for other fuels (G03).
* Amendment (2026-11-02): every write of a native container's record sets
  its fluids to the record's composition where any component differs by
  more than 1e-5 L, the litres unchanged (`Containers.commit`). That covers
  a pour the mod follows (both cans), a first look (D-024), siphoning and
  pump-to-can, as the mod's own transfers, treatments and machines already
  did. Aging turns fuel into water. Written to the record alone, that water
  was dropped by the next read, which takes the fluids as they are, so an
  opened can never kept what it took up past its next vanilla pour (an
  opened can of ethanol lost 0.0075 L over 60 days in a test with a faked
  game). The tolerance sits below the read's 1e-4 L, which would drop what
  it skips, and above the float precision of native amounts.
* Writing the fluids (BC 42.21 `FluidContainer`): the game drops a fluid
  under 1e-4 L, and within 0.001 L of capacity a container reads as full
  and `addFluid` refuses a new fluid (`adjustSpecificFluidAmount` has no
  such check). `Native.writeComposition` therefore holds the largest fluid
  already there low while new ones go in, smallest first, then sets it.
  A component under 2e-4 L goes to the largest, in the record and in the
  fluids alike (`Native.holdable`), so the litres are kept; the record
  keeps no condition for a fuel folded away (normalized). RT-SP run 57
  found the refusal: a full 10 L petrol can, its petrol lowered by
  1.1e-4 L for a look's water, refused the water and lost those litres
  (run 58 measured it). The same trap was there for a can filled to the
  brim at a clean station, whose last trace of water could be refused.
  Verified RT-SP run 59 (8/0, 300 days on the mod clock). An opened can
  of ethanol kept 0.080075 L of water through a vanilla pour and the
  next read, and a further pour carried water in proportion. A look put
  4.726e-4 L of water into a full petrol can, its 10 L unchanged. A full
  can took a new fluid.

## D-008 Degradation as a mixable concentration with closed-form aging
* Decision: each fuel component carries `deg`, a degradation-product index
  that mixes linearly by volume. Aging follows
  `d(deg)/dt = k(t) * (1 + a * deg)`, integrated in closed form over the
  cumulative driver `K = ∫k dt` (piecewise-constant daily environment).
* Reason: linear mixing makes "a small fresh addition cannot reset a large
  degraded reserve" hold by construction; closed form makes one large advance
  equal to many small ones up to floating-point error (spec §7, §15).
* Consequence: suitability is a separate mapping from `deg` to grades and
  consumer effects (tunable independently of campaign speed).

## D-009 World clock
* Decision: canonical time = `getGameTime():getWorldAgeHours()` (hours since
  world start, double). Calendar/season derived from the world start date.
* Evidence: BC `GameTime.getWorldAgeHours()`; RT-DS shows it frozen on an
  empty paused server, so unloaded catch-up is driven by elapsed world time,
  never wall-clock time.

## D-010 Station dispensing for managed pumps
* Decision: a pump becomes "managed" when TLG initialises its site. Managed
  pumps dispense through TLG actions with one unit convention (reservoir in
  litres); `pipedFuelAmount` mirrors the reservoir for vanilla UI. Vanilla
  `ISTakeFuel`/`ISRefuelFromGasPump` are intercepted for managed pumps.
* Reason: vanilla paths disagree on units (1 L vs 1.25 L per unit) and
  `ISTakeFuel:complete()` duplicates the final increment (G06, SRC).
* Status: implemented in `TLG/Integration/Stations.lua` (both vanilla paths
  are settled after the fact: pump set to reservoir − litres delivered, can
  fluids set to the reservoir blend; fractional remainder kept). Verified
  RT-SP 2026-10-31: 10 L into a can = −10 units, 59 L into a car = −59 units,
  composition and degradation carried.

## D-011 Electrical priorities only where control exists
* Decision: dispatch priorities apply to TLG-owned consumers (chargers,
  machines). Vanilla appliances draw from a vanilla generator in aggregate and
  are shown as "uncontrolled load".
* Reason: no per-appliance control found (G10); the spec forbids showing a
  priority that cannot act.

## D-012 Multiplayer authority protocol
* Decision: clients send `sendClientCommand("TLG", command, args)` with
  `requestId`, object references and expected revisions; the server validates,
  advances participants to a common time, checks revisions/compatibility,
  bounds quantities, commits, increments revisions and replies with
  `sendServerCommand`. A bounded per-player request ledger makes retries
  idempotent. In SP the same handler runs locally.
* Reason: spec §14. Pure validation/commit logic lives in `TLG/Authority`
  and is unit-tested; the network transport is an adapter (G07 NOT RUN).

## D-013 Generator sidecar carried through pickup/placement
* Decision: wrap `ISTakeGenerator.complete` (object → item modData), every
  Lua path that drops a generator item (item → object: Java converts a
  dropped generator item in `IsoGridSquare.AddWorldInventoryItem`, BC) and
  `IsoGenerator.new` (Lua placement paths). The drop paths are
  `ISDropWorldItemAction.complete` (place/drop), `ISUnequipAction.complete`
  (the menus unequip a carried generator before another generator or heavy
  item is taken or a weapon equipped, and the unequip drops a heavy item at
  the feet itself; added 2026-11-02), the global `forceDropHeavyItems` (a
  carried generator is dropped at the character's feet when a vehicle is
  entered, an animal handled, a trap set, and inside the takes; 17 vanilla
  callers) and `ISTransferAction:transferItem` to the floor container
  (inventory drag).
  After the drop the sidecar goes to the generator within one square that has
  no sidecar, the item's `generatorFullType` and the item's fuel. Device
  identity and conversion projects (`tlgDeviceId`, `tlgEngineId`,
  `tlgConv`) travel the same way.
* Evidence: SRC `ISTakeGenerator.lua:41-53`, `ISDropWorldItemAction.lua:81`,
  `ISEquipWeaponAction.lua:75-98`, `ISTransferAction.lua:95-112`;
  BC `setInfoFromItem` (copies condition and `modData.fuel`, sets
  `modData.generatorFullType`, nothing else), `IsoGridSquare.AddWorldInventoryItem`.
* Limitation: a drop performed by Java alone (no Lua caller) is not seen; the
  generator then reads as untracked fuel at the pessimistic baseline (D-006).
* Status: verified RT-SP 2026-10-31 on `Base.Generator`: pickup, drop
  action, `forceDropHeavyItems` (taking a second generator while carrying
  one, the action queued directly), drag to the floor and
  `IsoGenerator.new` all carry the record. The menus' unequip was missed
  until 2026-11-02: in run 83 a generator put down by a bat equipped from
  the inventory menu lost its record; with the `ISUnequipAction` wrap, run
  85 (8/0) kept both records, of one put down by taking a second generator
  from the world menu and of one put down by equipping the bat.

## D-015 Production machines are placeable items
* Decision: fermenter, stills and drying column are inventory items placed on
  the ground; the process record lives in item modData (`tlgProc`) and
  processing only advances while placed. B42 `entity` world objects were
  considered but their build/placement path is unverified at runtime.
* Reason: item modData travels with pickup (spec "picking up a processing
  machine"), vanilla placement/pickup need no new code, and vanilla models
  serve as placeholders (asset target: zero bespoke models for the first
  playable).
* Consequence: picking a running machine up pauses it on next access without
  crediting the carried time (conservative). A placed fermenter, reflux still
  and drying column each ran a batch in game and kept their records across
  save and reload (RT-SP 2026-10-31, runs 7 and 12); on the game clock a
  fermenter whose chunk was unloaded for 24 game hours caught up exactly on
  the next access (runs 13–14).
* As first built, this rule did not hold (RT-SP run 26, 3 FAIL). The
  adapter saw a move only at the next access, so it could not tell placed
  hours from carried ones: an access while carried paused the batch from
  the previous access, dropping the hours it stood placed before the
  pickup; the first access after it was put down started it from that
  access, dropping the hours since; with no access while carried, the
  carried hours counted as if it had stood at its new place. The record
  itself travelled with the item through both pickup paths and both
  put-down paths of the run.
* Fix: the adapter wraps the moves the game's Lua makes (the world menu's
  Grab, every transfer to or from the floor, the place action) and brings
  the batch to the moment of the pickup at its site, then marks it carried;
  putting it down starts it again from that moment and lists it for the
  hourly reading at once. The site keeps its tile and the record the last
  time the authority found it placed (`seen`, every access, hourly reading
  and ten-minute note). A move no Lua sees (in multiplayer the server grabs
  in a Java item transaction) is found at the next access or put-down: the
  batch counts up to `seen`, at most ten minutes short while the area is
  loaded, and not past it. Verified RT-SP run 27 (34/0): fermenters picked
  up with the Grab and the loot window and put down with the place action
  and Drop did the work of their placed hours exactly; one lifted with the
  grab's own calls outside its Lua (standing in for multiplayer) was
  credited up to 0.10 h before the grab. Verified on the stills and the
  drying column in RT-SP run 45 (41/0). A pot still picked up while
  distilling, a reflux still while heating up (grabbed unseen) and a drying
  column were carried two hours and put down again. Each then finished its
  remaining stage hours with exactly the wood and spirit of its
  definitions: no wood burned and no paused hours counted while carried.
  The unseen grab lost the 0.15 h since the last note. A move in
  multiplayer itself is NOT RUN.
* Amendment (2026-11-01): a carried machine answers Status only. Until
  then the authority refused loading a carried machine but took Feed the
  firebox, Collect, Pause, Resume and Abort batch, which the menu hides
  while it is carried (found reading the handlers after run 45). A Resume
  sent for a carried machine made the batch count from that moment.
  Put back on the tile it came from, the machine then counted its carried
  hours as work and burned wood for them (shown against the old handler:
  4 h of work for 2 h placed). All five now return `not_placed`. Verified
  by `tests/authority/test_machine_commands.lua` and RT-SP run 46 (46/0):
  the five, sent as requests for a carried pot still and drying column,
  were refused and the records left untouched.
* Across a save (RT-SP run 48, 29/0 and 24/0): a pot still, a reflux
  still grabbed unseen and a drying column were saved and exited to the
  menu while carried, and the save was continued. Their records came back
  from the inventory exactly as saved, still marked carried, or for the
  unseen one, unchanged. After another carried hour and the put-downs,
  each finished at its due time with exactly its wood and spirit.
* Amended 2026-11-02, the fermentation vessel is carried in both hands
  (the user's request). It is scripted as vanilla's heavy items are
  (`Tags = base:heavyitem`, `RequiresEquippedBothHands = true`, as
  `Base.LargeMeteorite` and the anvils; BC
  `InventoryItem.isForceDropHeavyItem`): a double-click or drag in the
  loot window takes it into both hands (`ISEquipHeavyItem`), one heavy
  item at a time. It goes down at the character's feet when another heavy
  item is taken or a weapon equipped from the menus, which unequip the
  hands first (`ISUnequipAction` drops a heavy item itself, SRC
  `ISUnequipAction.lua:134`), and when a vehicle is entered, an animal
  handled or a trap set (`forceDropHeavyItems`). `Machines.install`
  follows all three, as it follows Grab, transfers and the place action.
  42.21 leaves a heavy item's world object on the square when
  `ISEquipHeavyItem` takes it off the floor in single player (vanilla's
  meteorite too, RT-SP run 78: `sendRemoveItemFromContainer` acts only in
  multiplayer), so the item would be carried and still standing. For the
  mod's machines the hook then takes the world object off as the floor
  transfer does (`ISTransferAction.lua:131-158`); vanilla's own heavy
  items are left as vanilla leaves them. The loot window's Grab button
  stays a plain transfer into the inventory: vanilla does not check it
  for heavy items. An idle character draws no carried item but a weapon,
  vanilla's heavy items included (runs 73–75), so the carry has no pose.
  Verified by `tests/integration/test_machine_sites.lua` and RT-SP runs
  79 (39/0: a running vessel taken the double-click way, carried an hour
  and dropped by `forceDropHeavyItems`, its carried hour not counted) and
  81 (43/0: taken again, carried half an hour and put down by taking a
  meteorite the double-click way, which unequipped it at the feet; it
  resumed at once and its carried half hour did not count). Until run 81
  the mod followed only `forceDropHeavyItems`, which the menus' take
  reaches with the hands already empty (found by reading
  `equipHeavyItem`).

## D-016 UI feedback through rich-text dialogs
* Decision: inspection and machine results are shown in `ISModalRichText`
  dialogs built from translated keys; unknown condition has its own wording.
* Reason: readable without relying on colour or tiny world labels (spec §16).

## D-014 Gas fuels are not liquids
* Decision: gases use normal cubic metres (Nm³); propane is displayed in kg
  (2.01 kg/Nm³). Vanilla `Base.PropaneTank` is a drainable with 5000 uses and
  no fluid container (RT-DS); the propane adapter maps uses ↔ Nm³.
* Reason: spec §5 forbids interchangeable liquid litres for gases.

## D-017 Station water: mostly clean, a few contaminated stations
* Decision: station reservoirs start with 0–0.15 % water at about 9 in 10
  sites and 0.2–0.4 % at about 1 in 10 (`WorldInit.STATION_WATER`), instead
  of a uniform 0–0.4 %. Sediment is unchanged (0–0.1 %).
* Reason: with the uniform draw about half of all stations exceeded the
  stock car's 0.2 % free-water tolerance from day one, halving start chance
  before any progression route (ethanol, conversions, treatment) is
  reachable (RT-SP 2026-10-31, `startFactor=0.5` at the Gas2Go pump). The
  user chose the middle ground: keep a few bad stations to discover, let
  ageing drive the decline.
* Consequences: deterministic per world seed and pump position (domain test:
  404 of 4000 grid sites contaminated); existing reservoir records keep their
  water; no schema change.

## D-018 Conversion work is a timed action at the device
* Decision: "Work on it" queues the timed action `ISTLGConversionWork`. The
  character walks to the engine area or next to the generator, joins the
  project (which forfeits any unreported gap) and reports every 15 minutes
  of world time while staying in reach (4 tiles from a vehicle, 2.5 tiles
  from a generator). Leaving stops the action with a final report. The menu
  no longer offers "Report progress" or "Stop working". The authority passes
  a 1 h worker timeout with every request
  (`ConversionDevices.WORKER_TIMEOUT_HOURS`), so a report after a longer gap
  credits at most 1 h and ends the assignment.
* Reason: "Report progress" credited all the time since the previous report
  (up to 12 h) as long as the player stood in reach at that moment, so a
  player could start the work, leave and collect the hours later; the domain
  assumed an hourly adapter report that nothing sent. Found reading the code
  on 2026-10-31; the user asked to require the player to stay.
* Consequences: the domain default timeout stays 12 h
  (`Project.WORKER_TIMEOUT_HOURS`) for callers that pass none, because its
  tests use multi-hour single reports; the in-game handlers always pass 1 h.
  A modified client sending bare reports gains at most 1 h per visit and has
  to be in reach when it reports. The action shows no progress bar:
  `setJobDelta` on an open-ended action makes vanilla's queue drop it as
  stalled (BC `BaseAction`, found in run 11); "Project status" shows the
  stage reached. Verified RT-SP (2026-10-31): a bare report after 3 h credited
  1 h; leaving reach stopped the action through `isValid()`; time away was
  not credited (run 9); from the menu, the walk to the engine area, a
  refused start and the ending on a missing tool (run 12).

## D-019 Where each TLG recipe is crafted
* Decision: every TLG craft recipe carries vanilla's place tags. The
  fermentation vessel `AnySurfaceCraft;Carpentry` (as vanilla
  `MakeOilPress`), the pot still and drying column `AnySurfaceCraft` (as the
  screwdriver assemblies in `recipes_electrical`/`recipes_radio`), the
  reflux still `InHandCraft;Welding` (as `MakeMetalSheet`), the sampling kit
  and filter `InHandCraft`, the stabilizer `InHandCraft;Cooking`.
  `AnySurfaceCraft` needs a table or counter within two tiles. Pot and jar
  inputs say `mode:destroy`.
* Reason: the crafting window and the inventory "craft" menu only list
  recipes with one of the two place tags (SRC `ISHandcraftWindow.lua:53`,
  BC `CraftRecipeManager.getUniqueRecipeItems`); the recipes loaded but none
  could be crafted. Container inputs are kept unless `mode:destroy`, so the
  crafts handed the pot and jars back (RT-SP run 11).
* Consequence: verified RT-SP 2026-10-31 (run 12) for the four machine
  recipes through the inventory craft menu; the sampling kit, filter and
  stabilizer are listed but were not crafted in game.

## D-020 The recorded day temperature is the mean of the air, weather included
* Decision: every game hour the authority records today's temperature and
  humidity as the running mean of `ClimateManager.getTemperature()` and
  `getHumidity()` (`World.recordClimate`, accumulator `climateAcc` in the
  world record). Machines and fuel ageing read these day means through the
  climate model as before.
* Reason: the recorder used `getDayMeanTemperature()`, which is the season
  curve (BC: `currentDay.season.getDayMeanTemperature`), so the day means
  barely moved (0.5–0.6 °C for eleven January days, RT-SP run 15) and no
  cold snap or heat wave ever reached a machine or a tank. The comment said
  "today's mean temperature"; the code did not do that.
* Consequences: fermenters, stills and stored fuel now feel the weather. A
  fermenter stops on days averaging below 0 °C outdoors and spoils after 72
  paused hours (RT-SP run 16: four freezing January days, spoiled 73.2 h
  after loading). Where it stands makes no difference: machine temperature
  comes from the outdoor day mean only (`thermal = "sheltered"`), so in a
  long cold spell the player cannot keep a batch going. Early in a day the
  mean rests on few readings, and an advance made then is not redone: a
  machine read through the day and one caught up after midnight can differ
  slightly for that day (the exact G12 catch-up of runs 13–14 was in July,
  at full rate, where the temperature did not matter). Days recorded before
  the change keep their season values; no migration.
* Superseded in part by D-021: a placed machine now takes the temperature
  of where it stands; the sentence above on placement no longer holds.

## D-021 A machine's temperature is the air where it stands
* Decision: a placed machine's day temperature is the mean air temperature
  at its tile over the day's hours of the batch. While its area is loaded
  the authority reads the game's own value there every game hour
  (`ClimateManager.getAirTemperatureForSquare`: what a character standing
  there would feel, rooms, grid power and lit fires, fireplaces and
  barbecues included). Hours without a reading take the site's unheated
  value: outdoors the day's mean air temperature, in a room the day's mean
  of the game's room formula, which the climate recorder now logs for the
  ground and upper floors (`r0`, `r1`). The site (in a room or not, floor)
  is recorded on every access. Records without a site keep the
  definition's thermal exposure (`sheltered`). Fuel containers and tanks
  keep their storage profiles.
* Reason: after D-020 the weather reached the machines and nothing the
  player did could keep a batch going through a cold spell, while the
  status said "too cold here". The game already computes a temperature per
  tile for its characters; using it makes rooms, the grid and fires matter
  the way a player expects.
* The game's formula (BC 42.21): outdoors `getTemperature()` (a tile gets
  no wind chill); in a room (`IsoGridSquare.isInARoom()`, map rooms and
  player-built rooms) 22 °C while `IsoWorld.isHydroPowerOn()`, otherwise
  T + (22 − T) × (0.4 + 0.2 × lagged daylight) on the ground floor, 0.85 of
  that pull above it, mirrored above 22 °C; then the hottest heat source
  within its radius R in clear line of sight raises it to
  T + (1 − d/R) × (T_source + clamp(T − 30, −7, 7) − T) (outdoor sources
  clamp to −15..5): `IsoFire` 35 °C with its light radius, `IsoFireplace`
  35 °C, `IsoBarbecue` 25 °C with radius 3.
* Consequences: an unheated ground-floor room pulls the outdoor air
  0.4–0.6 of the way to 22 °C with the daylight, 0.435 on January days, so
  a fermenter there stops below about −3 °C outdoor day mean in January
  and slows below about 15 °C; outdoors it slows below 18 °C and stops
  below 8 °C; with the grid on, or warmed by a fire, it can run at full
  rate. In three January runs a room alone was not enough (4.5–11.4 °C at
  the machine; the batch spoiled each time) and a warmed tile was. Heat
  counts only while the area is loaded: hours away take the unheated
  value (until D-022: a fire's noted fuel now counts while away). The day mean averages its hours, so a few warm hours lift the
  whole day (the batch has a day's thermal mass); the hour in progress
  takes the previous hour's reading, otherwise a warmed machine paused
  after every midnight (run 17). A moved machine counts where it stood up
  to the pickup and at its new place from the put-down (D-015). Within the
  current day
  the value moves as readings arrive (as in D-020).
* Verified RT-SP 2026-10-31 runs 17–19: the room formula matched the
  game's own room value exactly over 94–96 hours per run; the readings
  filed, the day temperatures reported and the hourly work matched the
  harness exactly in run 19. Run 21 (2026-11-01) did the same beside a
  fireplace of the map, tended with logs: the heat formula matched every
  tile around it at four fuel levels and the machine's air every hour,
  and the batch finished in January (20.7 °C or more at 2.24 tiles from
  the fire). A 12 hour absence cost it about 17 hours: the hours away took
  the unheated room value, and the fire, which burns its fuel during an
  absence all the same (vanilla), was out on the return. Superseded in
  part by D-022 (a fire's fuel now counts while away).

## D-022 A fire left burning keeps warming a machine while its fuel lasts
* Decision: every ten game minutes the authority notes, for each loaded,
  placed machine with a batch running, the fire that gives its tile its
  air: a lit fireplace (any `IsoFireplace`: fireplace, wood stove, the
  map's campfire tiles, brazier, barrel oven), barbecue (`IsoBarbecue`) or
  campfire a player built (an `SCampfireSystem` campfire: the permanent
  `IsoFire` it keeps lit, its fuel read from the "Campfire" object's mod
  data) on the same floor within 18 tiles whose heat by the game's formula
  is the air read there, with its fuel, its offset and whether its tile is
  in a room (the one with most fuel if several match). Notes are kept per
  hour, the hour's last one standing, "none" when no fire warms the
  machine. An hour without a reading (its area was not loaded) takes the
  warmth of the fire in the last note before it, from the start of the
  noted hour until that fuel would have burned out at one minute a minute:
  the formula applied to the site's unheated day value (D-021's value for
  unread hours), with the radius at the fuel left at the start of each
  hour (a campfire's max(2, R × min(fuel, 360) / 360) truncated, R 10
  outdoors and 18 inside). After that the unheated value.
* Reason: vanilla burns a fire's fuel while its area is not loaded: on
  reload `IsoFireplace.update` and `IsoBarbecue.update` use up every
  minute since their saved `lastUpdateTime` in one step (BC 42.21), and
  `SCampfireSystem` takes a minute off every lit campfire per minute
  event, loaded or not (SRC 42.21). In run
  21 a fire left with 365 minutes was out on the return while the machine
  had been counted unheated for all 12 hours, and the batch lost about 17
  hours. Crediting the warmth for the minutes the game spends the fuel
  keeps the two accounts the same.
* Consequences: with the default cap of 8 hours of fuel, a fire fed before
  leaving keeps a machine warm for up to 8 hours away; longer absences cool
  it as before. Fuel added after the last note (at most ten minutes old) is
  not counted, so feed the fire a few minutes before you go. Only the fire
  that gave the air at the last note counts: a second fire within reach
  that would outlast it does not take over. Other open fires (an `IsoFire`
  without a campfire has no fuel) and other mods' heat sources never
  count, and the unheated value is the day's, not the hour's. The game
  fires the minute event at most once per tick, so where a tick spans
  more than a game minute (fast speeds) a campfire outlasts its noted
  minutes: the credit can then fall short of the warmth, never exceed it.
  Notes stay on the authority and are not sent to clients.
* Verified RT-SP 2026-11-01 run 23 (21/0), beside run 21's fireplace: the
  notes the mod took matched the harness's in all 99 hours, none was taken
  while the area was unloaded, the last note before a 12 hour trip (365
  minutes) covered 6.08 hours of it, and the work over the trip matched the
  rule fed by the credited day temperatures exactly. The batch finished
  after 109.2 game hours (run 21, without the credit and in a colder
  January: 114.3). A barbecue as the noted fire was covered by unit tests
  only until runs 34–35 (below). A `false` note survives a save: item mod data saves boolean values
  (BC `KahluaTableImpl.save`), and in run 25 a record saved with two "no
  fire" notes came back from save, exit and continue unchanged; the credit
  then worked as before (a 424 minute note covered 7.07 hours of a trip).
* Campfires (RT-SP 2026-11-01, runs 34–35). Run 34 (35/4) found the
  campfire a player builds never noted. It is not an `IsoFireplace` but a
  Lua global object (`SCampfireSystem`) whose warmth comes from a
  permanent `IsoFire`: 35 °C, radius the fire's light radius,
  max(2, 10 × min(fuel, 360) / 360) truncated outdoors. A fermenter one
  tile from one got no warmth for the hours away: 0 of the 6.48 hours its
  fuel covered, and the batch stopped for the rest of the day. Fixed as
  described above (commit `7b4f31d`). In run 35 (39/0) its notes matched
  the harness's in all 44 hours, the last before a 12 hour trip (397
  minutes) covered 6.48 hours, and the work over the trip matched the
  rule exactly (3.0312 hours). A charcoal barbecue was noted in all 44
  hours and credited exactly (6.02 hours) in both runs. On a dedicated
  server a barbecue has no heat source at all (BC `IsoBarbecue.update`),
  so there it warms nothing (not run).

## D-023 Abort batch keeps what the batch made
* Decision: aborting a running or paused batch keeps what it made so far in
  the machine as output to collect, marked stopped early: a fermenter's
  wash, weaker and with its unfermented sugar, for a still; a still's
  spirit; a drying column's ethanol, partly dried. What cannot be kept is
  thrown away and listed: a still's undistilled wash (its converter
  reports it as `rest`) and every byproduct (stillage, spent lime). Kept
  plus thrown away account for the whole batch. A second Abort throws the
  kept output away; Abort also empties a spoiled batch. A finished batch's
  output is collected, not aborted. The menu offers Pause while a batch
  works, Resume while it is paused by hand, and Abort while a batch runs,
  was stopped early or has spoiled, judged on the record brought to now.
* Reason: until run 31 the handler only reported the partial result, so
  an abort lost the whole batch without a word (4 L of ethanol from a
  drying column in that run), and a spoiled fermenter could be neither
  aborted nor loaded again: a dead machine, while the winter design makes
  spoiling routine (runs 16-19 each spoiled one).
* Consequences: a misclicked Abort keeps the output; losing it takes a
  second Abort. A fermenter stopped early holds its wash until a still
  takes it or a second Abort throws it away. An aborted batch hands out no
  starter culture, and not the last finished batch's either (the record's
  byproducts are cleared). Verified RT-SP run 33 (32/0): a pot still took
  a stopped wash, a drying column's ethanol was collected after an abort,
  a spoiled fermenter was emptied and loaded again.
* Amendment (2026-11-01): what a batch made is the share done of the
  stages that make its result, marked `makes` in the recipes. Those are a
  fermenter's fermenting, a still's distilling and a column's drying;
  preparing and heating up make nothing. Every stage used to count, so a
  still aborted an hour into distilling kept 1.61 L of spirit where 1.10 L
  had distilled (RT-SP run 49), and a fermenter's hour of preparing counted
  as 1/97 of its ethanol. A batch whose recipe snapshot marks no stage
  (started before the change) still counts every stage. The recipes of the
  other pathways (biodiesel, biogas, the wood retort and ash pit) mark none
  yet, and their making stages are to be marked with their machines.
  Verified RT-SP run 50 (28/0): a reflux still aborted an hour into
  distilling kept exactly the 1.10 L it had distilled. Run 51 (32/0)
  repeated run 33's controls under the rule, a fermenter's preparing hour
  making no ethanol.

## D-024 A first look records the fuel it looks at
* Decision: Look and smell (and a sample with the kit) on fuel the mod
  has not recorded yet writes the fuel's record: the baseline its policy
  gives at that moment, with the id the observation is filed under. Only
  the record is written (each endpoint's `record`), never the fuel
  itself; the look still changes nothing about the fuel. A look at fuel
  already recorded, or one refused (no kit), writes nothing.
* Reason: runs 39–40 found that a look read the baseline and allocated
  an id without writing it, so the observation was filed under an id the
  fuel never got: What I know about it said "unknown" right after a look,
  and every later look allocated another id. In a world the mod has just
  joined, nearly all fuel is unrecorded.
* Consequences: a look counts as the first contact for the existing-save
  policy (docs/migrations.md), like a pour or refuel. Looking first fixes
  the fuel's condition at that moment; the transition no longer applies
  to it later. Verified RT-SP 2026-11-01 run 41 (17/0, an existing save
  gaining the packaged mod): the look recorded a can that the mod had not
  recorded, What I know about it found the observation under its id, the
  can's condition was exactly the transition rule at the moment of the
  look, and a later pour and a save with reload kept that record. A look
  with the sample kit (the same path past the kit check) and looks at
  vehicles, pumps or generators (no menu sends one) are not run in game.
* Amendment (2026-11-02): in a can or other native container, the record
  a look writes also sets the fluids to its composition where they
  differ (D-007 amendment); the litres stay the same, so the look still
  moves and creates no fuel. The baseline can hold water the fuel took up
  before it was found, and written to the record alone that water was
  dropped by the next read. Vehicle tanks, pumps and generators keep their
  composition in the record only (D-006) and are unchanged.

## D-025 The fermentation vessel is shown carried in both arms
* Decision: the vessel's script names a hold pose of the mod's own
  (`primaryAnimMask = tlgcarryvessel`). Its pose file
  `AnimSets/player/maskingright/tlgcarryvessel.xml` plays the clip
  `anims_X/Bob/Bob_TLG_CarryVessel.x` on both clavicles' subtrees and the
  prop bones. The hand model `TLG.FermenterHeld` is the floor model at
  true size (0.75 m), centred on `Bip01_Prop1` with the hurricane
  lantern's turn. The clip's arms come from two Mixamo "Carrying" clips
  the user supplied (arm spacings 0.45 m and 0.95 m), blended halfway
  and retargeted onto the game's skeleton by `tools/blender/pz_arms.py`.
  The clip also places `Bip01_Prop1` 0.17 file units in front of the
  hands and 0.06 down, with the barrel's tap forward.
* Reason: the user asked for the vessel to be carried with two hands
  (D-015 amendment). A standing character draws a carried non-weapon only
  through a hand pose (BC `ModelManager.addEquippedModelInstance`), and
  the game's poses are one-armed (runs 86–90). A mod's own pose file loads
  and can drive both arms (runs 89–90). Each placement was chosen in game
  with the user. The first clip held a 0.6 m barrel (run 92). The wider
  clip left the hands beside the true-size barrel (run 93). The halfway
  blend held it at its sides (run 94). At 0.17 forward its back cleared
  the chest (run 95).
* Consequences: verified RT-SP run 96 (6/0) with the shipped vessel,
  standing, from the side and walking. An action that plays its own
  animation replaces the pose on that layer. A harness action that drew
  the vessel as its hand model during "Loot" showed the barrel on the
  action's prop bone, tilted up beside the head (see the amendment).
  Placing the vessel plays no animation and keeps the pose. Running,
  sprinting and sneaking keep it too (run 108), but crouched the barrel
  tipped forward and the torso sank into it (see the second amendment).
  Multiplayer is not run. The clip ships with Mixamo's terms recorded
  (`art-src/carry/PROVENANCE.md`); the source FBX files, which hold
  Mixamo's character, stay out of the repository and the package.
* Amendment (2026-11-02, run 99): an action that plays its own animation
  first puts the vessel down at the character's feet. The user asked for
  it to be dropped on the ground, as they expected of a generator. Every
  Lua action plays its animation through `ISBaseTimedAction.setActionAnim`,
  which the mod wraps. When the character carries a mod machine that is
  a heavy item and the action is not about that item, `forceDropHeavyItems`
  puts it down. From a multiplayer client, the server's `onDropHeavyItem`
  command does it, as `ISEnterVehicle` asks. The move hooks account the
  put-down. The game keeps a carried generator in both hands through
  such actions, undrawn (run 99, and SRC), so here the vessel differs
  from a generator. Left to the game: the vessel's own unequip (nothing
  is drawn in the arms while it plays, run 99) and the transfers that
  move it. Not covered: animations the game starts without a Lua action
  (doors, shoving, emotes). Multiplayer not run.
* Second amendment (2026-11-03, runs 108–113): crouched, the vessel has
  a pose of its own. The user asked for it after run 108 showed the
  barrel tipping into the crouched torso. Run 110 found why. A player's
  arms hang from `Bip01_Spine1` and the item's bone from the right hand
  (BC `IsoPlayer.onAnimPlayerCreated`), so the vessel turns with the
  chest, which a crouch bends far forward. Two more pose files, with one
  and two conditions more than the standing node, play while crouched
  (`tlgcarryvesselsneak.xml`) and crouched and still
  (`tlgcarryvesselsneakidle.xml`). Their clips are made the same way,
  keyed for the game's `Bob_WalkSneak` and `Bob_IdleSneak`
  (`pz_arms.py --body`). The arms keep their standing directions and the
  vessel stands upright, 0.17 file units in front of the hands and 0.12
  down. Chosen in game from six candidates (runs 111–112): 0.06 down put
  the lid at her chin, 0.16 down put her hands at the rim, and 0.20
  forward brought her face back to the lid. Verified with the gait mode
  (run 113).

## D-026 The field manual is print media found in loot
* Decision: `TLG.ManualFuelSystems` is read as the game reads its
  newspapers and fliers. The item script's `OnCreate`
  (`TLG.Integration.Manual.onCreate`) gives every new manual the mod data
  the game gives its own print media (`printMedia` with id, title, page
  and text keys, and `literatureTitle`). The inventory menu then offers
  Inspect, and reading it shows one page in the game's print media
  window: start-up, fuel compatibility and troubleshooting of the
  ethanol loop, in three columns, EN and IT. The window's notebook button
  shows the same text in larger print. The manual is added on
  `OnPreDistributionMerge` to 11 vanilla procedural lists that hold the
  game's mechanics, farming or generator magazines (gas station storage,
  garage and mechanic shelves, farms and homesteads, generator crates,
  blue-collar bookstores, tool stores, libraries). Each takes that
  magazine's weight there; in generator crates it is a third of it.
* Reason: the manual could not be obtained and did nothing when read
  (asset review, 2026-11-02). The spec asks for manuals that explain
  start-up, compatibility and troubleshooting in game, for more than one
  way to learn, and for an attainable way to learn inherited equipment.
  The print media window is the game's own way to show a document (SRC
  `ISReadABook`, BC `RecipeCodeHelper.setPrintMediaInfo`), so the mod adds
  no window of its own. The manual teaches no recipe and gates nothing:
  everything on its page is also in the player guide and the menus.
* Consequences: verified RT-SP runs 101–103. The lists held it after the
  merge. The game's loot roller filled containers with it from seven of
  the lists (137, 154 and 147 manuals in 3500 fills), each one already
  print media. Inspect read it and the game recorded it read, in EN and IT. A
  manual made before this change has no page (none could be obtained).
  Its icon and cover are still vanilla placeholders (A29, I03).
