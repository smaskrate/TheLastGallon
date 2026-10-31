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
| G01 Packaging | What structure loads? | **PASS (DS + SP)** | `common/` + `42/` layout loads; all TLG items, 7 craft recipes, fluids and custom sandbox options load (boot 4); translations resolve on the client (RT-SP), not on the DS |
| G02 Fluids | Type, mixtures, metadata | **PASS (DS + SP)** | Mod fluids register and blend; transfers proportional; condition carried through the wrapped `FluidContainer.Transfer` (RT-DS) and every vanilla fuel action (RT-SP); a can on the ground keeps its fluid on the world object after reload |
| G03 Vehicle consumption | Where does driving/idling change quantity? | **PASS (SP)** idle; driving NOT RUN; start gate NOT RUN | Native idle burn (0.0148 L in 0.5 h) reconciled proportionally into the tank record; mod never subtracts |
| G04 Generator consumption | Extend fuel/burn? | **PASS (SP)** burn; start gate NOT RUN | Native burn (0.015 L, nothing connected) reconciled proportionally; `ISActivateGenerator` gate not exercised |
| G05 Generator lifecycle | State survives pickup? | **PASS (SP)** with adapter | Pickup, drop action, `forceDropHeavyItems` (taking a second generator) and drag to the floor all carry the record |
| G06 Stations | Per-pump or shared? | **PASS (SP)** | Per-object piped units; TLG corrects both vanilla paths to 1 L/unit (10 L = −10 units, 59 L = −59 units) |
| G07 Action authority | Which stage mutates on the server? | SRC-ONLY | B42 actions mutate in `update()`/`animEvent` (server) and `complete()`; MP NOT RUN |
| G08 Persistence | Reliable stores/IDs | **PASS (DS + SP)** single player | Global ModData (DS, SP); item, world item, vehicle part, generator object and pump object modData, fluids and TLG records survive save and reload (RT-SP runs 4–5); MP reconnect NOT RUN |
| G09 Per-instance vehicles | Modify one vehicle independently | **PASS (SP)** | Part modData and `setEngineFeature` change one of two identical `Base.CarNormal` only |
| G10 Electricity | Independent consumer control | NOT RUN | Only aggregate `getTotalPowerUsing`/`setTotalPowerUsing` and `getItemsPowered` found |
| G11 Vehicle visuals | Extra parts/model variants | NOT RUN | — |
| G12 Unloaded machines | What simulates unloaded? | NOT RUN | `IsoGenerator.chunkLoaded(IsoChunk)` suggests catch-up on load (BC) |
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
  `mods` = `getCacheDirSub("mods")` only. `getAllModFoldersAux` skips a folder
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

## G03 Vehicle fuel — PASS (SP) for refuel, siphon and idle; start gate NOT RUN

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
* The harness starts engines with `tryStartEngine`/`engineDoStartingSuccess`,
  so the TLG start gate on `ISStartVehicleEngine` is NOT RUN. The per-minute
  effect handler ran without errors on good fuel; a stall was not exercised.
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

## G04/G05 Generators — PASS (SP); start gate NOT RUN

RT-SP (runs 3–5, `Base.Generator`, max fuel 10 L):

* Can → generator (`ISAddFuel`) moves exactly the litres and carries the
  record; native burn (0.015 L, nothing connected, `GeneratorFuelConsumption`
  0.1) is reconciled proportionally on the next read. The harness activates
  the generator with `setActivated(true)`, so the `ISActivateGenerator` start
  gate is NOT RUN.
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
* NOT RUN: chunk unload/reload, MP reconnect.

## G10–G14

* G10: no per-appliance enable/priority API found on `IsoGenerator`; electrical
  priorities will be offered only for mod-owned consumers (decision D-011).
* G12: `IsoGenerator.chunkLoaded(IsoChunk)` (BC) indicates load-time catch-up
  for generators; not instrumented.
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
run 5 phase A **47/0** and phase B 9/2; every failure was traced to the
harness itself (placement, a nearly full target generator, a lookup that
matched the neighbouring object) except run 4's ground-can result, which
found the container-ownership defect described under G02.

## Tooling pitfalls found

* Kahlua rejects Lua files that start with a UTF-8 BOM (compile error
  "Index 65022 out of bounds"); `tests/support/compile_check.lua` flags BOMs.
  Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a BOM.
* The Windows `java` launcher glob-expands a `*` argument.
* .NET writes a UTF-8 BOM into a redirected process stdin; the server
  console then rejects the first command.

## Next experiments

1. RT-SP, not yet covered: vehicle and generator start gates through the
   vanilla actions, a stall on poor fuel, driving consumption, TLG pour into
   a vehicle, the station-reservoir pour, placed production machines running
   a batch, crafting the machines, UI rendering checks beyond menu contents.
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
