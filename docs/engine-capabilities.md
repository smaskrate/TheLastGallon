# Engine capabilities and verification gates

Build: Project Zomboid **42.21.0** (`4a0e9546ec`). Evidence types:

* **SRC** – shipped Lua/script source in `<game>/media` (path:line).
* **BC** – `javap` of `projectzomboid.jar` (method signatures/bytecode).
* **RT-DS** – runtime experiment on the isolated dedicated server
  (`tests/ingame/TheLastGallonHarness`, result file `TLG_harness_server.txt`).
* **RT-SP** – runtime experiment in a single-player client
  (`tools/run-sp-harness.ps1`, result file `TLG_harness_sp.txt`; runs of
  2026-10-31 in `docs/evidence/2026-10-31_rt-sp_harness_run*.txt`).
* **RT-MP** – runtime experiment with a server and two clients.

Status values: **PASS** (verified at runtime), **SRC-ONLY** (source evidence,
runtime NOT RUN), **PARTIAL**, **FAIL** (capability unavailable; see
alternative), **NOT RUN**.

## Gate summary

| Gate | Question | Status | Evidence / result |
| --- | --- | --- | --- |
| G01 Packaging | What structure loads? | **PASS (DS + SP)** | `common/` + `42/` layout loads; all TLG items, 7 craft recipes, fluids and custom sandbox options load (boot 4); translations resolve on the client (RT-SP), in English and in Italian (runs 43–44), not on the DS |
| G02 Fluids | Type, mixtures, metadata | **PASS (DS + SP)** | Mod fluids register and blend; transfers proportional; condition carried through the wrapped `FluidContainer.Transfer` (RT-DS) and every vanilla fuel action (RT-SP); a can on the ground keeps its fluid on the world object after reload |
| G03 Vehicle consumption | Where does driving/idling change quantity? | **PASS (SP)** idle, start gate, stall; driving NOT RUN | Native idle burn reconciled proportionally; `ISStartVehicleEngine` refused on a 36 % ethanol blend, allowed on station fuel; the blend stalled a force-started engine within a game minute; mod never subtracts |
| G04 Generator consumption | Extend fuel/burn? | **PASS (SP)** burn and start gate | Native burn (0.015 L; connected, no appliance drawing) reconciled proportionally; `ISActivateGenerator` activates on petrol and is refused on E100 |
| G05 Generator lifecycle | State survives pickup? | **PASS (SP)** with adapter | Pickup, drop action, `forceDropHeavyItems` (taking a second generator) and drag to the floor all carry the record |
| G06 Stations | Per-pump or shared? | **PASS (SP)** | Per-object piped units; TLG corrects both vanilla paths to 1 L/unit (10 L = −10 units, 59 L = −59 units) |
| G07 Action authority | Which stage mutates on the server? | SRC-ONLY | B42 actions mutate in `update()`/`animEvent` (server) and `complete()`; MP NOT RUN |
| G08 Persistence | Reliable stores/IDs | **PASS (DS + SP)** single player | Global ModData (DS, SP); item, world item, vehicle part, generator object and pump object modData, fluids and TLG records survive save and reload (RT-SP runs 4–5), as do machine records and conversion projects (runs 7–8); MP reconnect NOT RUN |
| G09 Per-instance vehicles | Modify one vehicle independently | **PASS (SP)** | Part modData and `setEngineFeature` change one of two identical `Base.CarNormal` only |
| G10 Electricity | Independent consumer control | NOT RUN | Only aggregate `getTotalPowerUsing`/`setTotalPowerUsing` and `getItemsPowered` found |
| G11 Vehicle visuals | Extra parts/model variants | NOT RUN | — |
| G12 Unloaded machines | What simulates unloaded? | **PASS (SP)** for TLG machines, once | Nothing runs while the chunk is unloaded; the process record catches up on the next access. A fermenter whose chunk was unloaded for 24 game hours had done exactly 24 h more on return (RT-SP runs 13–14; the check passed in run 14). Vanilla generators: `IsoGenerator.chunkLoaded(IsoChunk)` suggests catch-up on load (BC), not instrumented |
| G13 Assets | Which props/sounds exist? | PARTIAL (catalogue from scripts) | See `asset-audit.csv`; runtime spawn/texture checks NOT RUN |
| G14 Compatibility | What bypasses adapters? | SRC-ONLY | Java-side fluid moves and any code not calling `FluidContainer.Transfer` |

## Lua runtime

Domain tests run on the game's own Kahlua VM (`tools/kahlua-runner`), using
`J2SEPlatform` with the install-dir `stdlib.lua`, exactly as loaded by the game.
Probe: `tests/support/runtime_probe.lua` (runner) and
`TLGHarness/LuaProbe.lua` (RT-DS). Both agree on every shared item:

| Feature | Result | Consequence for the codebase |
| --- | --- | --- |
| `a % b` | Java remainder: `-7 % 3 == -1` | Use `TLG.Num.mod` (floored) |
| `next` | **nil** (runner and RT-DS) | Emptiness via `pairs` loop (`TLG.Tables.isEmpty`) |
| `math.random` | **nil** | Deterministic `TLG.Rng` (Park–Miller) |
| `table.unpack` | nil (`unpack` exists) | Use `unpack` |
| `error(table)` | arrives as a **string** | No structured errors; return result tables |
| `string.format("%s", nil)` | error | Always `tostring` |
| Recursion | overflow below 3000 frames (RT-DS); 5000 in runner | No deep recursion; iterative merge sort |
| `table.sort` | `stdlib.lua` recursive left-pivot quicksort, unstable | `TLG.Tables.sort` (iterative, stable) for state |
| `tostring(1e20)` | `1.0E20` (Java formatting) | Never round-trip numbers through strings |
| `goto`, `//`, bitwise ops, `bit32` | not available | Lua 5.1 subset only |
| `require` | returns the module's return value (RT-DS) | Modules also register under `TLG.*` |
| `loadstring`, `getfenv`, `os.time` | available | Not used by domain code |
| `io`, `debug`, `load`, `dofile` | nil | — |

## G01 Packaging — PASS (dedicated server and client)

* **BC** `ZomboidFileSystem.getAllModFolders`: scan order `workshop,steam,mods`;
  `mods` = `getCacheDirSub("mods")` only. `workshop` (staged items,
  `getStagedItemModsFolders`) and `steam` (subscribed items,
  `getInstalledItemModsFolders`) are scanned only when
  `SteamUtils.isSteamModeEnabled()`: with `-nosteam` a client sees
  `<cachedir>/mods` alone, so the manual install from the release zip is
  the path a launch without Steam can rehearse (`tools/rehearse-install.ps1`). `getAllModFoldersAux` skips a folder
  named `examplemod` and accepts a mod when `common/mod.info` or
  `<versionDir>/mod.info` exists. `getModVersionDirName` picks the highest
  folder whose `getGameVersionIntFromName` (`major*1000 + min(minor, 999)`) is
  between `ChooseGameInfo.getMinRequiredVersion()` and the current version, so
  `42/` (= 42000) is selected on 42.21.
* **BC** `ChooseGameInfo.readModInfoAux` keys: `name= id= author= description=
  poster= url= modversion= icon= category= require= incompatible=
  loadModAfter= loadModBefore= versionMin= versionMax= pack= tiledef=`;
  `require=`/`incompatible=` strip `\`.
* **BC** first-run copy: `Core.loadOptions()` → `initOptionsINI()` →
  `copyPasteFolders("mods")` when `<cachedir>/options.ini` is missing (caused
  the 2026-10-30 incident, `environment.md`).
* **RT-DS** (2 boots): `TLG` namespace loaded; `instanceItem("TLG.FuelSampleKit")`
  returns `TLG.FuelSampleKit`; activated mods `TheLastGallon;TheLastGallonHarness`.
* **RT-DS** translations: `getText("IGUI_TLG_ModName")`, item display name and
  `Fluid_Name_TLG_Ethanol` all returned their keys on the dedicated server.
  **BC** `Translator` loads `%s/media/lua/shared/Translate/%s/%s.json`.
  Whether a dedicated server loads mod translations at all is unverified.
* **RT-SP** Italian (runs 43–44): with `language=IT` in `options.ini`,
  `Translator.getLanguage():name()` is `IT`. The mod's Italian JSON files
  (UTF-8 without a byte-order mark) load with their accents intact: all
  237 strings, item display names included. The game stores a placeholder
  `%N` as `%N$s`, so `getText(key)` without arguments returns `"Avvia:
  %1$s"` for a shipped `"Avvia: %1"`, while `getText(key, ...)` fills it.
* **RT-SP** (runs 3–5): on the client `IGUI_TLG_ModName`, `Fluid_Name_TLG_Ethanol`,
  `ContextMenu_TLG_Fuel` and the `TLG.FuelSampleKit` display name all resolve
  to their English text. Mod and harness load from `<cachedir>/mods` once
  `mods/default.txt` lists them (see "Client harness status").

## G02 Fluids — PASS (DS + SP)

RT-DS results (`TLG_harness_server.txt`):

* Mod fluids defined in `module TLG { fluid TLG_Ethanol {...} }` register with
  type `Modded` and are found by `Fluid.Get("TLG_Ethanol")`;
  `Fluid.Get("TLG.TLG_Ethanol")` returns nil (lookup key is the bare name).
* `Categories { Fuel }` + `BlendWhiteList { Fuel }`: Petrol and TLG_Ethanol
  blend both ways; Petrol does **not** blend with Water and
  `canAddFluid(Water)` on a petrol container is false.
* Spawned `Base.PetrolCan` has capacity 10 and starts full of Petrol (10 L).
  `Base.JerryCan` capacity 20 (SRC `items/normal.txt`).
* `FluidContainer.Transfer(a, b, 4)` from 6 Petrol + 2 Ethanol moved 3 + 1
  (proportional); `adjustAmount(2)` scaled 3+1 to 1.5+0.5 (proportional);
  transfers clamp to destination capacity.
* 1000 × 0.001 L there and back: total stayed 13.0000000 (no visible drift at
  1e-7). Native amounts are Java floats; reconciliation tolerance must allow
  float precision (~1e-6 relative).
* Item modData nested tables round-trip in memory.
* **`FluidContainer.Transfer` can be replaced from Lua**: a wrapper installed
  on the `FluidContainer` class table was called and the transfer executed.
  SRC `ISFluidTransferAction.lua:29,73` calls `FluidContainer.Transfer`
  incrementally in `update()` (when not client) and in `complete()`.
* `Base.PropaneTank` is a drainable with 5000 uses and no FluidContainer
  (`getCurrentUses()` = 5000).
* RT-DS boot 3 (`docs/evidence/2026-10-30_rt-ds_harness_boot3.txt`), TLG
  container adapter on real native containers:
  * `fc:adjustSpecificFluidAmount(fluid, x)` **sets** that fluid to `x`
    (5 → 3), it does not add.
  * `TLG_FuelWater` and `TLG_FuelSediment` (category Fuel) share a container
    with Petrol natively; `Native.writeComposition` round-trips
    gasoline/ethanol/water/sediment exactly.
* Small amounts and full containers (BC 42.21 `FluidContainer`, read with
  `javap`; RT-SP run 58). `getAmount()` reads as the capacity when the
  fluids are within 0.001 L of it (`recalculateCaches`), and `isFull()` is
  the amount within 1e-4 L of capacity (`PZMath.equal`, strict). `addFluid`
  does nothing on a full container and clips to the room left;
  `adjustSpecificFluidAmount` returns on an empty container, clamps to
  [0, capacity] and has no fullness check. A fluid holding less than
  1e-4 L is removed as empty (`removeFluidInstanceIfEmpty`, called after
  an adjust). Reading has no threshold (`createFluidSample` copies every
  fluid). Run 58: a full 10 L petrol can lowered to 9.9998884 L of Petrol
  read `amount 10.0000000`, `full=true`, and refused 1.117e-4 L of
  `TLG_FuelWater`; a 5 L can took the same water.
  * Through the wrapped `FluidContainer.Transfer`, 4 L from a can with
    deg 1.2/0.3 and stabilizer 0.5 arrived with the same deg, stabilizer and
    proportional composition; source revision 5 → 6, destination 0 → 1,
    provenance recorded.
  * 200 hooked transfers of 0.01 L: sidecar composition stayed consistent
    (rev 200, deg unchanged). Native total drifted 10 → 9.99995 L (Java float
    rounding destroys ~2.5e-7 L per transfer; never creates). Reconciliation
    tolerance is therefore 1e-4 L.
  * A water bottle is ignored (`foreign_fluid`).
* RT-SP (runs 4–5): fluids and modData of a can in the inventory and of a
  can on the ground survive save and reload. **After reload a can on the
  ground has no item FluidContainer: the fluid sits on its
  `IsoWorldInventoryObject`** (`itemOwnContainer=false
  ownerIsWorldObject=true`); `InventoryItem.getFluidContainerFromSelfOrWorldItem()`
  (BC) returns it. Before the fix of 2026-10-31 the adapter treated such a
  container as a world object (storage `drum_steel`, record written to the
  world object instead of the item); it now resolves both to the item, and
  run 5 found the ground can's TLG record after reload (`status=ok`).
* NOT RUN: world-object containers (rain barrels, FuelPump entity), the
  vanilla `ISFluidTransferAction` driven by a character.

## G03 Vehicle fuel — PASS (SP) for refuel, siphon, idle, start gate and stall

RT-SP (runs 3–5, `Base.CarNormal`, 59 L tank):

* Can → tank (`ISAddGasolineToVehicle`) and tank → can (`ISTakeGasolineFromVehicle`)
  move exactly the litres taken and carry composition, contaminants and
  degradation (largest deviation 2e-8); an E25 blend (6 L petrol + 2 L
  ethanol) arrives as 6 + 2 in the tank record.
* A station can with `TLG_FuelWater`/`TLG_FuelSediment` still satisfies the
  vanilla menu predicate `contains(Fluid.Petrol)`.
* Idle on station fuel (profile `engine_si_stock`, grade good, compatible):
  0.0148 L burned in 0.5 game hours at game speed 4; the next read reported
  `reconciled`, totals equal to the native amount and unchanged proportions.
  Driving consumption: NOT RUN.
* Start gate (run 6, player as driver, hotwired, vanilla
  `ISStartVehicleEngine`): on a 36 % ethanol blend (`compatible=false`,
  reason `too_much_ethanol`) the gate called `engineDoStartingFailed` and the
  engine stayed `Idle`; on station fuel the start went through to `Running`.
  That station fuel rated `startFactor=0.5` (reason `water`), so the allowed
  start depended on the 50 % roll; the deterministic evidence is the refusal.
* Stall (run 6): the same blend, started directly to bypass the gate, was
  stalled by the per-minute effect handler 0.6 game minutes later
  (`Stalling`).
* **Balance observation → D-017:** station water was drawn uniformly from
  0–0.4 % while `engine_si_stock` tolerates 0.2 % free water, so about half
  of all stations halved the start chance of stock cars from the first day
  (runs 5–6: 0.216 % and 0.229 % water at the Gas2Go pump). Since D-017 about
  9 in 10 stations start at 0–0.15 % and about 1 in 10 at 0.2–0.4 %
  (domain-tested; not re-run in game).
* `IsoCell.getVehicles()` returns a `java.util.HashSet` on 42.21 (BC); use
  `ipairs(set:toArray())`.

Source evidence:

* SRC `ISAddGasolineToVehicle.lua`: tank = `part:setContainerContentAmount`
  (floored litres during `update()`, exact target in `complete()`); the can is
  reduced with `fluidCont:adjustAmount` (proportional, so mixtures leave in
  proportion); `serverStop` only syncs (a cancelled pour keeps the partial
  amounts already applied).
* SRC predicates (`ISVehiclePartMenu.lua:9-22`, `ISVehicleMenu.lua:9-18`):
  vanilla offers refuelling only from containers that `contains(Fluid.Petrol)`.
  A pure `TLG_Ethanol` can is not offered; an E10 blend is.
* BC `VehiclePart`: `getContainerContentAmount/setContainerContentAmount(float)`,
  `getContainerCapacity`, `getContainerContentType`, `getModData`;
  `BaseVehicle.transmitPartModData(part)`.
* BC `BaseVehicle`: engine state methods (`tryStartEngine`,
  `engineDoStartingFailed(reason)`, `engineDoStalling`, `isEngineRunning`) and
  per-instance `setEngineFeature(quality, loudness, power)`.
* Consumption is Java-side; the adapter design never subtracts fuel itself.

## G04/G05 Generators — PASS (SP)

RT-SP (runs 3–6, `Base.Generator`, max fuel 10 L):

* Can → generator (`ISAddFuel`) moves exactly the litres and carries the
  record; native burn (0.015 L; connected with no appliance drawing,
  `getTotalPowerUsing` 0.015; `GeneratorFuelConsumption`
  0.1) is reconciled proportionally on the next read.
* Start gate (run 6, vanilla `ISActivateGenerator`): a generator on petrol
  (grade good) activated; a generator holding 3 L of E100, filled through the
  confirmed TLG pour, was refused (`too_much_ethanol`, `failToStart`) and
  stayed off.
* Pickup carries the record to the new item (found in the primary hand,
  since vanilla equips it there); the drop action, `forceDropHeavyItems`
  (taking a second generator while carrying one) and dragging the item to
  the floor all carry it to the converted object, with vanilla fuel equal.
  The second generator taken in the same action got its own record.

Source evidence:

* BC `IsoGenerator`: `getFuel/setFuel/getMaxFuel/getFuelPercentage`,
  `isActivated/setActivated`, `failToStart()`, `getCondition`,
  `getGeneratorItemType()`, `getItemsPowered()`, `getTotalPowerUsing()`.
  `update()` reads `SandboxOptions.generatorFuelConsumption` and writes `fuel`.
* SRC `ISAddFuel.lua:54-58`: litres from the can map 1:1 to generator fuel up
  to `getMaxFuel()`; the can is reduced with `adjustAmount`.
* SRC `ISTakeGenerator.lua:41-53`: pickup creates the item, copies condition
  and `modData.fuel`, then `generator:remove()`. Other generator modData is
  **not** carried.
* BC `IsoGenerator.setInfoFromItem`: placement copies item condition and
  `modData.fuel`, and sets object `modData.generatorFullType`.
* SRC placement: `IsoGenerator.new(item, cell, square)` in
  `ISMoveableSpriteProps.lua:2173-2194` and `MOGenerator.lua:18`.
* BC `IsoGridSquare.AddWorldInventoryItem` constructs `IsoGenerator(item, …)`
  itself when a generator item is dropped, bypassing Lua's `IsoGenerator.new`.
* Implemented (D-013): the adapter carries the TLG sidecar, device identity
  and conversion project by wrapping `ISTakeGenerator.complete` (object →
  item), every Lua drop path (`ISDropWorldItemAction.complete`,
  `forceDropHeavyItems`, `ISTransferAction:transferItem` to the floor) and
  `IsoGenerator.new` (wrapping verified RT-SP). Drops done by Java alone are
  not seen.

## G06 Stations — PASS (SP)

RT-SP (runs 3–5, Muldraugh Gas2Go, 8 pump objects, contamination on):

* With the TLG station adapter installed, pump → can took 10 L and the pump
  lost exactly 10 units; pump → vehicle (run 5) put 59 L in the tank and the
  pump lost exactly 59 units, so both vanilla conventions (1 L and 1.25 L per
  unit) are corrected to 1 L per unit and the remaining fraction is kept in
  the record (|frac| < 1e-11 after whole-litre draws).
* The reservoir record (pre-aged, with water and sediment) is created on
  first contact; the delivered parcel carries its composition and
  degradation; record and unit count survive save and reload.
* Not verified at runtime: the vanilla defects themselves (the adapter
  overrides the pump amount after both actions, so the uncorrected values
  were not observed), infinite-fuel sandbox, the TLG "pour into the station
  reservoir" command.

* BC `IsoObject.getPipedFuelAmount()/setPipedFuelAmount(int)`: an integer per
  pump object, **stored in the object's modData** under
  `IsoPropertyType.FUEL_AMOUNT` and initialised from sandbox
  (`FuelStationGasMin/Max/EmptyChance/Infinite`) when absent; the setter calls
  `transmitModData()`. TLG's station sidecar can therefore live in the same
  modData table.
* SRC `media/scripts/entities/entity_fuelpump.txt`: B42.21 also defines an
  entity `FuelPump` with a FluidContainer (capacity 22000, 5–15 % Petrol).
  Whether map pumps use this entity, the piped amount, or both is NOT RUN
  (the SP harness logs both).
* SRC `ISRefuelFromGasPump.lua:96-102`: comment "Pumps start with 100 units";
  1 unit = `Vehicles.JerryCanLitres / 8` = 10/8 = **1.25 L** (SRC
  `server/Vehicles/Vehicles.lua:18`).
* SRC `ISTakeFuel.lua:24-29,106`: pump → can treats **1 unit = 1 L**.
  The two vanilla paths disagree.
* SRC `ISTakeFuel.lua:64-70`: `complete()` adds the remaining litres to the can
  and **adds** the same number to the pump (`pumpCurrent + (itemTarget -
  itemCurrent)`), so the final increment is duplicated. Runtime confirmation
  NOT RUN.
* BC `SandboxOptions` has `FuelStationGasMin`/`FuelStationGasMax` (initial pump
  fuel); infinite-fuel behaviour NOT RUN.
* Design consequence: the station adapter owns dispensing for TLG-managed
  pumps (one unit convention, conservation enforced) and must replace both
  vanilla paths for managed pumps.

## G07 Action authority — SRC-ONLY

B42 timed actions run `update()` on the client in SP; on MP the server drives
`serverStart`/`animEvent` via `emulateAnimEvent(netAction, ...)` and executes
`complete()`; `isClient()` guards prevent client mutation in most fuel actions
(`ISAddGasolineToVehicle.lua:33`, `ISTakeFuel.lua:17`, `ISFluidTransferAction.lua:24`).
`ISRefuelFromGasPump:update()` has **no** `isClient()` guard
(`ISRefuelFromGasPump.lua:14-46`). Two-client experiments: NOT RUN.

## G08 Persistence — PASS (DS + SP, single player)

* RT-DS: `ModData.getOrCreate("TLGHarness")` counter incremented across a hard
  restart after `saveGame()` (boot 1 → 2). Clean `quit` via console saves and
  exits ("Shutdown handling finished").
* World time does not advance on an empty server with `PauseEmpty=true`
  (`getWorldAgeHours()` stayed 2.0 across boots).
* RT-SP (runs 4–5; `saveGame()`, exit to menu, continue): global ModData,
  inventory item fluids + modData, the TLG record of a can in the inventory
  and of a can on the ground, a mod item (`TLG.FermenterVessel`) lying on the
  ground with its modData, vehicle tank records (vehicle 1 in run 4, the E25
  blend of vehicle 2 in run 5), generator object records (both generators
  across runs 4–5), the pump record and unit count, and the TLG world record
  all came back unchanged. Run 5's vehicle and generator checks failed only
  because the harness looked up a neighbouring object (both records it found
  were intact); the lookup now matches by record id.
* Debug-scenario worlds: the scenario launcher does not give the new world
  any mods, so its `mods.txt` was empty and continuing it loaded none; the
  harness copies the active mods into `currentGame` before `createWorld`,
  as the Solo path does (SRC `MainScreen.lua:1400`).
* A mod added to an existing save (runs 39–40). The load screen's Choose
  Mods... rewrites the save's `mods.txt` (SRC `ModSelectorModel.lua`:
  `manipulateSavefile(folder, "WriteModsDotTxt")`), and continuing a save
  loads the mods its `mods.txt` lists (SRC
  `MainScreen.continueLatestSaveAux`). The load screen offers no sandbox
  settings. On the first load with the mod, `OnInitGlobalModData` reports
  `isNewGame = false` and `SandboxVars.TheLastGallon` holds the options'
  defaults (ExistingSavePolicy 1, TransitionDays 30, the rest default).
  `getActivatedMods()` and the `TLG` global confirmed the mod absent in the
  world played before.
* An item lying on the ground keeps its fluid on the world object:
  `item:getFluidContainer()` is nil there and
  `getFluidContainerFromSelfOrWorldItem()` returns it (run 39), as the
  container adapter reads it.
* A transition baseline takes the world-age supply's quantities, which can
  include water breathed in over the world's age that the native fluid
  does not hold. Run 41's look recorded 9.999969 L petrol and 0.0000307 L
  water for a can holding 10 L of petrol; run 40's pour-written records
  had the same shape. By the code, a difference under
  `C.FLOAT_TOLERANCE` (1e-4 L) is adopted from the native composition at
  the next read; larger ones (older worlds, bigger containers) go through
  reconciliation. Not observed beyond that.
* NOT RUN: chunk unload/reload, MP reconnect.

## Production machines and conversions (RT-SP runs 7–8)

* Machines are mod items lying on the ground (D-015). A placed
  `TLG.FermenterVessel`, `TLG.RefluxStill` and `TLG.DryingColumn` each ran a
  batch through the authority commands with real inventory items: Sugar,
  Yeast and bucket water in; Logs into the firebox; quicklime taken by the
  dryer; outputs written into jerry cans as native fluids plus a TLG record.
  Quantities matched the domain model (6 kg sugar → 3.30 L ethanol in the
  wash → 3.036 L at 94 % → dried to 0.5 % water).
* Time fixture: the harness advanced the mod clock (`TLG.World.now`), not the
  game clock; nothing in runs 7–8 shows how the machines behave while the
  game clock runs or while their chunk is unloaded (runs 13–14 did, G12).
* The three machine records survived save and reload (phase B).
* Conversions (run 8): a `Base.Generator` (`flex_generator`) and a
  `Base.CarNormal` (`flex_car_normal`) went through begin, parts delivery
  and work reports to `Commissioned`, took exactly the listed parts from the
  inventory, and then resolved to the flex profiles. Both accepted the dried
  ethanol without confirmation; the generator activated
  (`ISActivateGenerator`) and the car started (`ISStartVehicleEngine`) on it.
  The projects (generator object modData, Engine part modData) survived
  save and reload.
* Work as a timed action (run 9, D-018): `ISTLGConversionWork` has no fixed
  duration (`maxTime = -1`), reports every 15 minutes of world time and
  ends itself with `forceComplete()` when the project is commissioned. When
  the character was moved out of reach, the game polled `isValid()` and
  called the action's `stop()`; nothing was credited for the time away.
* Player path (run 12): the four machines crafted through the inventory
  craft menu, placed with `ISDropWorldItemAction`, the batch run from the
  machine context menu, both conversions done from the workshop menu (the
  car's "Work on it" walked into the engine area first).
* Game clock (run 13, request `sp-rt`): the same loop with the game's own
  time running and no mod-clock offset, 136 game hours in all: fermentation
  97.2 h, distillation 3.78 h, drying 12.09 h, the generator conversion
  7.71 h from the click and the car 13.11 h at vanilla's x40. Game time can
  be sped up from Lua with `getGameTime():setMultiplier(x)` (the debug
  panel's Game Speed slider, SRC `ISGameDebugPanel.lua:42`): about 135
  frames per game hour at x100. The waits in runs 3–12 used
  `UIManager.getSpeedControls():SetCurrentGameSpeed(4)` and took about
  13 400 frames per game hour, so that call gave little or no speed-up.
* Run 7 found an adapter defect the domain tests could not: the actor for
  `conversion.begin` was built from the device's existing project, so with
  no project yet no tool was counted and every first conversion failed with
  `missing_tool`. Fixed in `ConversionDevices.actor`; regression cases in
  `tests/integration/test_conversion_devices.lua`.

## Crafting, menus and timed actions (RT-SP runs 10–12)

* Recipe listing: the crafting window queries
  `"InHandCraft;AnySurfaceCraft"` (SRC `ISHandcraftWindow.lua:53`) and the
  inventory "craft" menu takes only recipes with one of those tags (BC
  `CraftRecipeManager.getUniqueRecipeItems`); untagged recipes load but are
  offered nowhere. `AnySurfaceCraft` needs an object with
  `isGenericCraftingSurface()` reachable within two tiles
  (BC `HandcraftLogic.findCraftSurface`).
* `canPerformCurrentRecipe` (BC `BaseCraftingLogic`) checks the recipe for
  the character (skills, `NeedToBeLearn`), whether inputs can be consumed
  and outputs created, and the workbench range. Consuming the inputs also
  needs light unless the recipe `canBeDoneInDark()` (BC
  `CraftRecipeData.consumeInputsInternal`): `IsoPlayer.tooDarkToRead()` is
  true when no lit light is in hand or on the belt and (L / m + L) / 2 <
  0.43, L the light level of the character's square and m the worn items'
  vision modifier (so L < 0.43 without such items); in a vehicle only with
  a flat battery. In runs 36–37 every machine craft was refused at the
  workbench run 12 used; in run 38 its light level was 0.15 at 10:37, and
  a torch switched on in hand, the player's way out, let all four crafts
  through.
* Container inputs (pots, jars) are kept unless the input says
  `mode:destroy` (vanilla pasta/rice recipes); outputs go through
  `Actions.addOrDropItem` and land on the floor when the inventory is full.
* `FluidContainer.CanTransfer` refuses item-to-item transfers while the
  player's inventory is full (BC), so a Lua `FluidContainer.Transfer` moves
  nothing then.
* Timed actions: `BaseAction.setJobDelta(d)` sets `currentTime = maxTime × d`
  (BC); on an open-ended action (`maxTime = -1`) that is negative,
  `hasStalled()` becomes true and `ISTimedActionQueue:tick()` removes the
  action from the Lua queue without stopping it in Java. The game then
  treats the character as idle while the action runs. Open-ended actions
  must not set a job delta. `isValid()` is polled; a `false` calls the
  action's `stop()` (run 9, run 12).
* Context menus can be driven from Lua the way `ISContextMenu` does it:
  `option.onSelect(option.target, option.param1, …)`
  (SRC `ISContextMenu.lua:70`).

## Climate (RT-SP runs 15–19)

* `ClimateManager.getDayMeanTemperature()` is the season curve: it returns
  `currentDay.season.getDayMeanTemperature()` (BC). In run 15 eleven
  January days all read 0.5–0.6 °C. `getTemperature()` is the air
  temperature with the weather: −7.2 to 3.0 °C over the days of run 16.
  TLG now records each day as the running mean of the hourly
  `getTemperature()` readings (`World.recordClimate`, D-020); the recorded
  mean matched the harness's own hourly readings within 0.01 °C on two full
  days.
* Request `sp-rtw` (`-Mode winter`): the real-clock scenario from 15
  January, one fermentation compared hour by hour with the stage rules fed
  the recorded day mean. Run 15 (season curve): 0.4 rate all through, done
  after 241.7 game h (97 h at full rate), 229 hours exact. Run 16 (weather):
  day means −0.8, −2.7, −2.4 and −4.7 °C, paused "too cold" after the 1 h
  preparation, 68 hours exact, faulted `batch_spoiled` 73.2 game h after
  loading at `pausedFor` 72.00.
* Air at a tile (BC 42.21): `ClimateManager.getAirTemperatureForSquare(sq)`
  calls the three-argument form with no vehicle and no wind chill.
  Outdoors it is `getTemperature()`. In a room (`IsoGridSquare.isInARoom()`:
  a map room, or `IWorldRegion.isPlayerRoom()` for a player-built one) it is
  22 °C while `IsoWorld.isHydroPowerOn()`; otherwise the air moves a share
  k = 0.4 + 0.2 × lagged daylight of the way to 22 °C on the ground floor
  and 0.85 k above it (above 22 °C: 0.85 k on the ground floor, k + 0.2 ×
  the lagged night upstairs; 42.21 fills the night value from
  `getDayLightLagged()` as well). Then
  `IsoCell.getHeatSourceHighestTemperature` raises it to the hottest
  `IsoHeatSource` on the same floor within its radius R and in clear line
  of sight (`LosUtil.lineClear`; an open door counts):
  T + (1 − d/R) × (T_source + clamp(T − 30, −7, 7) − T), clamped to −15..5
  instead when the source stands outdoors (`ClimateManager.lerp(t, a, b)` =
  a + t (b − a)). The game's heat sources are `IsoFire` (35 °C, its light
  radius), `IsoFireplace` (35 °C; radius `calcLightRadius()` =
  `GameTime.Lerp(1, 8, min(fuel, 60) / 60)`, fuel in minutes, so 8 tiles
  with an hour of fuel) and `IsoBarbecue` (25 °C, radius 3);
  `IsoHeatSource` is exposed to Lua, and `IsoCell.updateHeatSources` drops
  sources that are out of bounds. The lagged daylight is readable from Lua
  as `getClimateValuesCopy():getDayLightLagged()`; vanilla formats
  temperatures in the player's units with
  `Temperature.getTemperatureString` (SRC `server/radio/ISWeatherChannel.lua:209`).
  With the grid on, the four room-tile readings run 26 compared were
  22.0000 °C, and Status gave 71.6 °F (22 °C) as the day temperature at
  all three of its tiles.
* Moving a ground item (SRC 42.21), the paths run 26 used on running
  fermenters, each keeping the item's mod data: the world menu's Grab
  (`ISWorldObjectContextMenu.onGrabWItem`) queues `ISGrabItemAction`, whose
  single-player `transferItem` removes the world object and moves the same
  item into the inventory; the loot window's Grab
  (`ISInventoryPaneContextMenu.onGrabItems`, the item listed in the floor
  container by `ISInventoryPage:refreshBackpacks`) and the inventory menu's
  Drop (`onDropItems`) queue `ISInventoryTransferAction`, which calls
  `ISTransferAction:transferItem` (floor branches: remove the world object,
  or `AddWorldInventoryItem` on the character's tile, a neighbour if that
  one is full); the
  place cursor queues `ISDropWorldItemAction`, whose `complete()` calls
  `AddWorldInventoryItem`. In multiplayer the client asks the server for an
  item transaction instead (`createItemTransaction`); the server's Lua
  `TransactionProcessor` handles only moveables and `dropOnFloor`, so no
  Lua sees a grab there (not run in MP). TLG wraps
  `ISGrabItemAction.transferItem`, `ISTransferAction.transferItem` and
  `ISDropWorldItemAction.complete` (D-015); in run 27 the four
  single-player paths reached the wraps, and an item lifted with
  `ISGrabItemAction`'s own calls outside it reached none, as a multiplayer
  grab would. Run 45 also used the place action in the form the place cursor
  queues (`isPlaceItem = true`, under which `isValid` also requires a tile
  next to the character; it refuses more than 50 weight on the tile either
  way, SRC `shared/TimedActions/ISDropWorldItemAction.lua`). It worked onto a
  tile already holding a machine and reached the wrap, as did the same
  paths with stills and a drying column. Machine items in the player's
  inventory keep their mod data through a save, exit to the menu and
  continue, exactly (run 48: every field and number as saved). In that
  run the harness's first step after the continue read world hour
  103.8495, 0.0232 h after the hour the save was taken at (103.8263).
* A save continued without the mod (runs 54 and 55, alike): the game skips items whose
  type no longer exists when it loads them ("InventoryItemFactory.CreateItem()
  cannot create item … TLG.FermenterVessel", "InventoryItem.loadItem() item
  == null, skipped bytes"), and they are gone when the mod comes back. A
  container's fluid of a type no longer registered (TLG_Ethanol) was empty
  after the load, with nothing in the console. The mod data on vanilla
  items (`tlg`) came back unchanged through a launch without the mod
  (every field compared to three levels), and the global mod data kept the
  world record (`TLG_World`: seed, start, policy, epoch and next id
  compared).
* Fireplaces (BC 42.21 `IsoFireplace`): the map loader makes one from a
  tile whose `container` property is `fireplace`, `campfire`, `brazier` or
  `woodstove` (`CellLoader`); the only one vanilla Lua builds itself is the
  barrel oven (SRC `server/BuildRecipeCode/buildRecipeCode.lua:603-608`).
  Fuel is whole minutes: a lit fire burns one per game minute in
  `update()` and goes out at 0 (put out with fuel left, it smoulders for
  10 minutes). `fuelAmountMinutes`, `lit` and `lastUpdateTime` are saved
  with the object and `update()` burns every minute since `lastUpdateTime`
  in one step, so after a chunk reload a fire has used its fuel as if it
  had burned while nobody was near; its heat source exists only while it
  is loaded and lit. `addFuel` has no cap; the cap is in Lua: the menu
  offers no fuel past `getCampingFuelMax()` = sandbox
  `MaximumFireFuelHours` × 60 (8 h in the Apocalypse preset), and an item
  gives `ISCampingMenu.getFuelDurationForItem` minutes (the smaller of its
  table value and its weight × 2/3 hours: a log 6 h). Vanilla's actions add
  fuel with `addFuel` and `sendObjectChange(STATE)` and light with
  `turnOn()` (SRC `shared/TimedActions/ISBBQAddFuel.lua:72-87`,
  `ISBBQLightFromLiterature.lua:60-75`). `IsoBarbecue` keeps its fuel the
  same way (minutes, `lastUpdateTime` saved and caught up on reload,
  `MaxFuelAmount` 1200) with a fixed heat source of 25 °C, radius 3; both
  classes are exposed to Lua (vanilla tests them with `instanceof`). Item
  mod data is saved with the item (`InventoryItem.save` calls
  `KahluaTable.save`), which keeps string and number keys and string,
  number, boolean and table values (BC `KahluaTableImpl.save`/`load`), so
  a `false` in a record survives a save (seen in run 25: save, exit to
  menu and continue). In `newtiledefinitions.tiles`
  only `fixtures_fireplaces_01_0`–`_5` carry `container=fireplace` (the
  other 74 tiles of that set are chimney and wall pieces); woodstoves are
  `appliances_cooking_01_16`–`_19` and `crafted_05_4`–`_7`, campfires
  `camping_01_4`–`_6` and `camping_03_16`–`_21`, braziers
  `crafted_02_42`–`_44`. A map cell's `.lotheader` lists the tiles it uses:
  none of the start's cell 41_41 and its eight neighbours lists a working
  fireplace except 41_40 (to the north); 41_39, 42_39, 41_38, 42_38 and
  41_37 do. Run 20 (RT-SP 2026-11-01) scanned 49 windows of 97 × 97 tiles
  up to 288 tiles around the Muldraugh Gas2Go: two campfires and two
  braziers (fire objects of the map), no fireplace.
* Runs 17–19 (request `sp-rtw` since D-021, grid off): the room formula
  above matched the game's own value at a room tile to 0.00000 °C over
  94–96 hours per run; the outdoor tile equalled `getTemperature()`; a
  tile with a 35 °C, radius 1 `IsoHeatSource` added from Lua read 28.0 °C
  every hour (35 + clamp(T − 30, −7, 7) in a cold room). In run 19 the
  readings the mod filed, the day temperatures it reported and every
  machine's hourly work matched the harness exactly; nothing was filed
  while the tiles were unloaded and the readings resumed on return (runs
  17–18 found two defects, see test results).
* Run 21 (request `sp-rtf`, a map fireplace, `fixtures_fireplaces_01_5`
  at 10677,10296, grid off, January): the heat formula above matched the
  game's air on every floor tile within 9 of the fire at four fuel levels
  (no tile off; 34 tiles warmed at 360 min, 19 at 40, 11 at 20, none at
  5: the radius follows `calcLightRadius`), and unlit all 360 tiles had
  the unwarmed value. Tiles in range but out of its line of sight stayed
  unwarmed. At the fermenter 2.24 tiles away the formula matched every
  hour of a 114 hour batch (worst 0.00000 °C). Left with 365 minutes of
  fuel for a 12 hour trip that unloaded its chunk, the fire was out with
  0 on the return: the reload burns the absence away, as the bytecode
  says. A log is 360 minutes and the cap 480 (sandbox default).
* Campfires come in two kinds (SRC/BC 42.21). The map's campfire tiles
  `camping_03_16`–`_21` carry `container=campfire` and load as
  `IsoFireplace`. The campfire a player builds is a Lua global object of
  `SCampfireSystem`. The build menu's Campfire entity
  (`BuildRecipeCode.campfire.OnCreate`) and `campingCampfire:create`
  (`SCampfireSystem.instance:addCampfire`) both make one. So do the map's
  `camping_01_4`–`_6`, which `MOCampfire` replaces on load. Its parts:
  * A plain `IsoObject` named "Campfire" with a container.
  * Its fuel in minutes (`fuelAmt`), `isLit` and `exterior` (=
    `square:isOutside()`), held in the global object and copied into the
    object's mod data at every change (`saveData`).
  * While lit, a permanent `IsoFire` on its tile. Its heat source is 35 °C
    with the fire's light radius (`IsoFire.update`).
  * `SCampfireGlobalObject:fireRadius()` = max(2, R × min(fuel, 360) /
    360), with R = 10 outdoors and 18 inside, handed to
    `setLightRadius(int)`, which truncates it (run 34: 46 of 46 readings).

  Every `EveryOneMinute` event takes one minute off every lit campfire,
  loaded or not (`SCampfireSystem:lowerFuelAmount`). `GameTime` fires that
  event at most once per tick, so a tick that spans several game minutes
  burns only one. Run 34 counted 721 events in 721 game minutes at ×100
  (DayLength 4), run 35 720 in 721. Vanilla's campfire menu (`ISCampingMenu.doCampingMenu`)
  works from the client's copy (`CCampfireSystem`); in single player the
  copy was there 60 ticks after `addCampfire`. Add fuel offers a log as
  one entry while two would not fit under the cap. `IsoFire` has no fuel
  of its own; the campfire's fuel is only in that Lua object and its mod
  data.
* Run 34 (request `sp-rtof`, January, grid off, outdoors at the Muldraugh
  Gas2Go): a campfire made with `addCampfire` and a charcoal barbecue
  (`IsoBarbecue.new` with `appliances_cooking_01_35` and `AddTileObject`,
  as SRC `client/Tests/TimedActionsTests.lua` does) were fed and lit from
  their own menus. The heat formula above matched the game's air on every
  floor tile around them:
  * the campfire at four fuel levels: 528 tiles each, 282 warmed at radius
    10 (22 out of line of sight), radius 5 at 199 minutes and 2 at 100 and
    30;
  * the barbecue: 24 tiles warmed at radius 3.

  At a fermenter one tile from each, the formula matched all 42 hours
  read. Both fires burned out during a 12 hour trip that unloaded them:
  the campfire one minute per event, the barbecue by game time
  (`lastUpdateTime` is saved, BC `IsoBarbecue.save`).
* Heat sources on a dedicated server (BC 42.21, not run in multiplayer):
  `IsoBarbecue.update` returns before `updateHeatSource` when
  `GameServer.server` is set, so there a barbecue warms no tile.
  `IsoFireplace.update` calls `updateHeatSource` on the server too, and an
  `IsoFire` adds its permanent heat source with no server check.
* Grid power: `IsoWorld.hydroPowerOn` starts from
  `SandboxOptions.doesPowerGridExist()`, true while the world's age in days
  is at most `ElecShutModifier` (so −1: never);
  `randomElectricityShut(ElecShut)` picks that day for presets 2–9 (14–30
  days for 2).

## G10–G14

* G10: no per-appliance enable/priority API found on `IsoGenerator`; electrical
  priorities will be offered only for mod-owned consumers (decision D-011).
* G12: TLG machines keep their process in item modData and advance lazily
  on access (`Process.advance` from the record's time to now). Runs 13–14 moved
  the character 400 tiles away for 24 game hours: the machines' square was
  no longer loaded (`getGridSquare` nil), and the first status read after
  return credited the full 24 h at the rate the climate allowed. That was
  July at full rate. Since D-020 today's climate record moves until
  midnight, so in weather that changes the rate, a catch-up and a machine
  read through the day can differ slightly; not measured.
  `IsoGenerator.chunkLoaded(IsoChunk)` (BC) indicates load-time catch-up for
  vanilla generators; not instrumented.
* G14: anything that moves fluid in Java, or Lua code that writes fluid
  containers without `FluidContainer.Transfer`, bypasses the container
  adapter; reconciliation handles the result (D-006).

## Client harness status

`tools/run-sp-harness.ps1` starts the client with
`-debug -nosteam -nosound -cachedir=<devcache>`. Unattended runs needed four
fixes, each found by a failed launch:

1. 2026-10-30 21:33: no output after the intro videos. The Windows session
   was locked, and (found 2026-10-31) **no mod was active**: on its first
   launch the client empties `mods/default.txt` because
   `mods/reset-mods-42_00.txt` did not exist yet, and the main menu saves the
   empty list back. `setup-devenv.ps1` now writes the marker and the list
   before every launch.
2. 2026-10-31 09:45: **"Click to Start"**. After every world load
   `GameLoadingState.update()` returns `Remain` until
   `Mouse.isButtonDown(0)` or a joypad A press (BC, offsets 290–361); no
   option or Lua call skips it. The launcher posts a left click to the game
   window (`WM_LBUTTONDOWN/UP`) while a load has finished
   (`game loading took`) and the state has not exited.
3. Same run: the **Survival Guide** window (Core option `showSurvivalGuide`)
   and the tutorial prompt (`tutorialDone`, SRC `MainScreen.lua:943-979`) are
   switched off in the dev cache options and by the harness.
4. Same run: a Lua error in a TLG event handler **halted the game in the Lua
   debugger** because "Break On Error" was ticked (debug mode; toggle calls
   `UIManager.setShowLuaDebuggerOnError`, SRC
   `DebugUIs/DebugToolstrip.lua:28-29`). The harness switches it off so
   errors are logged and the run continues. The error itself was a TLG bug:
   on 42.21 `IsoCell.getVehicles()` returns a `java.util.HashSet` (BC), so
   `getVehicles():get(i)` raises "tried to call nil". Fixed in the vehicle
   adapter, the fuel menu and the workshop menu by iterating
   `ipairs(set:toArray())`, the pattern vanilla uses for Sets (SRC
   `server/Vehicles/Vehicles.lua:1037`).
5. Run 3: the debug-scenario world was saved with an empty `mods.txt`, so
   the continued save loaded no mod and phase B never ran (see G08).
6. Runs 3–4: `teleportTo(x, y, 0)` resolves to `teleportTo(int, int, int)`
   (BC overloads), so the player landed on the tile corner, outside the
   vehicle's fuel-cap area, and `ISRefuelFromGasPump` (valid only in that
   area) never started. `setPosition(float, float, float)` fixed it (run 5).

Since run 3 a launch needs no input: the full run (both phases) takes about
12 minutes. Results: run 3 phase A 41/5, run 4 phase A 42/1 and phase B 9/1,
run 5 phase A 47/0 and phase B 9/2, run 6 (adds start gates, stall and TLG
pours into a vehicle) phase A 63/0 and phase B 11/0, run 7 (adds the
renewable loop) phase A 74/8 and phase B 12/2, run 8 phase A 82/0 and
phase B 14/0, run 9 (conversion work as a timed action) phase A 83/0 and
phase B 14/0, runs 10–11 (the player's path) 76/15 and 80/11 with phase B
12/2 each, run 12 phase A **94/0** and phase B **14/0**, run 13 (the loop on
the game clock, no reload) 10/1, the one failure a check bound that missed
120 settling ticks, its rerun, run 14, **11/0**, two January runs, run 15
**5/0** and run 16 **8/0**, three January runs by site, run 17
**24/0**, run 18 24/1 and run 19 **25/0**, and two beside a map
fireplace, run 20 1/0 (the search found none near the start) and run 21
**17/0**, then the winter mode again with its helpers shared, run 22
**25/0**, the fire credit of D-022 beside the same fireplace, run 23
**21/0**, the winter mode with the fire notes running, run 24
**25/0**, the fireplace batch across a save, run 25 **8/0** before and
**20/0** after it, and running fermenters picked up and put down, run 26
25/3 and, after the fix, run 27 **34/0**, and a batch through the pot still,
run 28 **25/0**, again with the finished machines' Status wording, run 29
**28/0**, and Pause, Resume and Abort batch, run 30 19/5 (a harness setup
error), run 31 20/4 and, after the fix, run 32 29/3 (presses the menu no
longer offers) and run 33 **32/0**, and fermenters beside a campfire and
a barbecue, run 34 35/4 and, after the fix, run 35 **39/0**, then the
full mode on the release zip installed clean, run 36 90/4 with phase B
14/0, on the repository's mod, run 37 90/4 and 14/0, and on the zip again,
run 38 **94/0** and **14/0**, then an existing save gaining the zip's mod,
run 39 3/0, 7/1 and 3/0 (a harness error) and run 40 **3/0**, 9/1 and
**3/0**, and after the fix run 41 **3/0**, **11/0** and **3/0**, then the full
mode on the final zip installed clean, run 42 **94/0** and **14/0**, and
the client in Italian, run 43 4/1 (an expectation: the stored `%1$s`
placeholder form) and run 44 **5/0**, then two stills and a drying
column picked up mid-batch, run 45 **41/0**, and again with every command
but Status refused on a carried machine, run 46 **46/0**, then the full
mode on the rebuilt zip installed clean, run 47 **94/0** and **14/0**, and
the stills and column carried across a save, run 48 **29/0** and **24/0**,
and Pause, Resume and Abort batch on running stills, run 49 27/1 and, after
the fix, run 50 **28/0**, with run 33's controls again, run 51 **32/0**,
then the full mode on the zip with that fix installed clean, run 52
**94/0** and **14/0**, and fuel first found late in a new world, run 53
**7/0**, then the mod removed from a save and added back, run 54 1/0, 2/0
and 4/1 and, after the fix, run 55 **1/0**, **2/0** and **5/0**, then the
full mode on the zip with that fix installed clean, run 56 **94/0** and
**14/0**, then the water a can takes up, run 57 5/2, run 58 3/4 and,
after the second fix, run 59 **8/0**. Most failures were
traced to the harness itself (placement, a nearly full target generator, a
lookup that matched the neighbouring object, an overloaded test character)
and some found mod defects: run 4's ground-can result (container
ownership, G02), run 7's conversion refusals (tool counting), runs 10–11's
crafting and work-action results (recipe tags, `mode:destroy`, the job
delta on an open-ended action). Run 15 passed and still showed a defect:
every January day had the same temperature (the season curve, D-020).
Runs 17–18 found two in the site readings: a warmed machine paused after
midnight until the day's first reading, and the status then still showed
the unheated value (a pruned reading). Run 26's three failures were one
mod defect: the work around a machine pickup did not follow D-015 (fixed,
run 27). Run 31's four were three: Abort batch discarded the partial
result unlisted (4 L of ethanol in the drying column), and a spoiled batch
could not be cleared from the menu (fixed, run 33). Run 34's four are
one: a campfire the player builds was never noted, so its warmth was not
credited while away (D-022; fixed, run 35). Runs 36–37's four were the
harness's, in both installs alike: crafting needs light, and the
workbench measured 0.15 in run 38, where a torch in hand let every craft
through. Run 40's one failure was a mod defect: Look and smell wrote no
record onto fuel the mod had not recorded, so What I know about it stayed
unknown (fixed by D-024, run 41). Run 49's one failure was a mod defect:
Abort batch on a still kept spirit for its heating-up hour, when nothing
distils (fixed, runs 50–51). Run 54's one failure was a mod defect: fuel
that came in while the mod was away was aged a second time over the time
away (fixed, D-006 amendment, run 55). Runs 57–58's look failures were a
mod defect: the fluids were written without regard for the game's full
container, which refused the look's water after the can's petrol had been
lowered (fixed, D-007 amendment, run 59). Run 58's two pour failures were
the harness's expected figure.

## Tooling pitfalls found

* Kahlua rejects Lua files that start with a UTF-8 BOM (compile error
  "Index 65022 out of bounds"); `tests/support/compile_check.lua` flags BOMs.
  Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a BOM.
* The Windows `java` launcher glob-expands a `*` argument.
* `Compress-Archive` in Windows PowerShell 5.1 (Archive module 1.0.1.0)
  writes zip entry names with backslashes (`Contents\mods\...`; 91 of 92 in
  the 0.1.0-dev zip of 2026-10-31); the ZIP format wants forward slashes.
  `tools/package.ps1` writes the zip with `System.IO.Compression` instead.
* .NET writes a UTF-8 BOM into a redirected process stdin; the server
  console then rejects the first command.

## Next experiments

1. RT-SP, not yet covered: driving consumption, the station-reservoir pour,
   a winter with mild days between cold spells
   (the code adds paused hours up across spells), flex-engine starts in the
   cold, a campfire built indoors (radius up to 18), a propane barbecue,
   upstairs or in a
   player-built room (with the grid on: runs 26–27), pouring from a can
   lying on the ground, Italian text in game, the crafting window itself, UI rendering
   checks beyond menu contents.
2. RT-MP: dedicated server + two clients for G07/G08 reconnect. Requires a
   second client session; NOT RUN.

## Scripts verified on the dedicated server (boot 4)

Evidence: `docs/evidence/2026-10-30_rt-ds_harness_boot4.txt`. All TLG items
instantiate (`FuelStabilizer`, `FuelFilter`, `ManualFuelSystems`,
`YeastStarter`, `FermenterVessel`, `PotStill`, `RefluxStill`,
`DryingColumn`); `getScriptManager():getCraftRecipe("TLG_Make…")` returns all
seven recipes with the expected input/output counts and categories; custom
sandbox options from `media/sandbox-options.txt` appear as
`SandboxVars.TheLastGallon.*` with their defaults on an existing world; the
vehicle, generator and station adapters install their wrappers without
errors on the server. Crafting through the UI, icons/models rendering:
NOT RUN (client).
