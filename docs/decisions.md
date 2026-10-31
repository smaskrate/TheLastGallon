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
  `ISDropWorldItemAction.complete` (place/drop), the global
  `forceDropHeavyItems` (a carried generator is dropped at the character's
  feet when another heavy item is taken; 17 vanilla callers) and
  `ISTransferAction:transferItem` to the floor container (inventory drag).
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
  one), drag to the floor and `IsoGenerator.new` all carry the record.

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
  save and reload (RT-SP 2026-10-31, run 7; elapsed time from a mod-clock
  fixture). Picking up a running machine is NOT RUN.

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
  stalled (BC `BaseAction`, found in run 11); progress is in "Project
  status". Verified RT-SP (2026-10-31): a bare report after 3 h credited
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
