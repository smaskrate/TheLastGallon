# Engine capabilities and verification gates

Build: Project Zomboid **42.21.0** (`4a0e9546ec`). Evidence types:

* **SRC** – shipped Lua/script source in `<game>/media` (path:line).
* **BC** – `javap` of `projectzomboid.jar` (method signatures/bytecode).
* **RT-DS** – runtime experiment on the isolated dedicated server
  (`tests/ingame/TheLastGallonHarness`, result file `TLG_harness_server.txt`).
* **RT-SP** – runtime experiment in a single-player client.
* **RT-MP** – runtime experiment with a server and two clients.

Status values: **PASS** (verified at runtime), **SRC-ONLY** (source evidence,
runtime NOT RUN), **PARTIAL**, **FAIL** (capability unavailable; see
alternative), **NOT RUN**.

## Gate summary

| Gate | Question | Status | Evidence / result |
| --- | --- | --- | --- |
| G01 Packaging | What structure loads? | **PASS (DS)**; client NOT RUN | `common/` + `42/` layout loads; script item instantiates; translations unresolved on DS (see below) |
| G02 Fluids | Type, mixtures, metadata | **PASS (DS) item level**; save/reload NOT RUN | Mod fluids register and blend; transfers proportional; TLG container adapter carries condition through the wrapped `FluidContainer.Transfer` (M2.* checks) |
| G03 Vehicle consumption | Where does driving/idling change quantity? | SRC-ONLY | Tank is `VehiclePart` content amount (float litres); burn is in Java; mod never subtracts |
| G04 Generator consumption | Extend fuel/burn? | SRC-ONLY | `IsoGenerator.update()` burns `fuel` using `SandboxOptions.generatorFuelConsumption`; `failToStart()` exists |
| G05 Generator lifecycle | State survives pickup? | SRC-ONLY → requires adapter | Vanilla copies only `fuel` + condition between object and item |
| G06 Stations | Per-pump or shared? | SRC-ONLY | Per-object `getPipedFuelAmount()`; inconsistent native unit conversion; vanilla defect in `ISTakeFuel:complete()` |
| G07 Action authority | Which stage mutates on the server? | SRC-ONLY | B42 actions mutate in `update()`/`animEvent` (server) and `complete()`; MP NOT RUN |
| G08 Persistence | Reliable stores/IDs | **PARTIAL (DS)** | Global ModData persists across DS restart after `saveGame()`; item/vehicle/object modData save/load NOT RUN |
| G09 Per-instance vehicles | Modify one vehicle independently | SRC-ONLY | `VehiclePart:getModData()`, `BaseVehicle:setEngineFeature(q, l, p)` are per instance |
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

## G01 Packaging — PASS on dedicated server

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
  Whether a dedicated server loads mod translations at all is unverified;
  client check pending (RT-SP).

## G02 Fluids — PARTIAL

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
* NOT RUN: save/load of item fluids and sidecars, drop/pickup, world-object
  containers (rain barrels, FuelPump entity).

## G03 Vehicle fuel — SRC-ONLY

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
  Driving/idle instrumentation: NOT RUN.

## G04/G05 Generators — SRC-ONLY

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
* Design consequence: the generator adapter carries the TLG sidecar by
  wrapping `ISTakeGenerator.complete` (object → item) and `IsoGenerator.new`
  (item → object). Wrapping a Java class function from Lua is proven for
  `FluidContainer.Transfer` only; `IsoGenerator.new` NOT RUN.

## G06 Stations — SRC-ONLY

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

## G08 Persistence — PARTIAL

* RT-DS: `ModData.getOrCreate("TLGHarness")` counter incremented across a hard
  restart after `saveGame()` (boot 1 → 2). Clean `quit` via console saves and
  exits ("Shutdown handling finished").
* World time does not advance on an empty server with `PauseEmpty=true`
  (`getWorldAgeHours()` stayed 2.0 across boots).
* NOT RUN: item modData in containers across save/load, vehicle part modData,
  generator object modData, chunk unload/reload, reconnect.

## G10–G14

* G10: no per-appliance enable/priority API found on `IsoGenerator`; electrical
  priorities will be offered only for mod-owned consumers (decision D-011).
* G12: `IsoGenerator.chunkLoaded(IsoChunk)` (BC) indicates load-time catch-up
  for generators; not instrumented.
* G14: anything that moves fluid in Java, or Lua code that writes fluid
  containers without `FluidContainer.Transfer`, bypasses the container
  adapter; reconciliation handles the result (D-006).

## Client harness status

`tools/run-sp-harness.ps1` (2026-10-30 21:33) started the client with
`-debug -nosteam -nosound -cachedir=<devcache>`; it booted, passed the terms
screen and played the intro videos, then produced no further output for
7 minutes. The Windows session was **locked** (`LogonUI.exe` running), so the
OpenGL window could not present frames. The client was stopped; no client
evidence exists yet. Rerun the harness from an unlocked desktop.

## Tooling pitfalls found

* Kahlua rejects Lua files that start with a UTF-8 BOM (compile error
  "Index 65022 out of bounds"); `tests/support/compile_check.lua` flags BOMs.
  Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a BOM.
* The Windows `java` launcher glob-expands a `*` argument.
* .NET writes a UTF-8 BOM into a redirected process stdin; the server
  console then rejects the first command.

## Next experiments

1. RT-SP harness (debug scenario, `DebugScenario.ForceLaunch`): translations,
   item fluid save/load, vehicle idle burn, generator burn + pickup/placement,
   pump unit conversions and the `ISTakeFuel` defect, two identical vehicles.
2. RT-MP: dedicated server + two clients for G07/G08 reconnect. Requires a
   second client session; NOT RUN.
