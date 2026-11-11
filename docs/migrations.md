# Persistence, versions and migrations

## Versioned contracts

| Contract | Version | Where | Notes |
| --- | --- | --- | --- |
| Supply sidecar | 1 | item/object/part modData `tlg` | `v`, id, rev, deg, stab, mic, t, storage, sealed, cond, dirty, label, prov, q (+ `frac`, `cap`, `product` for pumps; `kind`, `profile` for generators) |
| Process (machine) | 1 | machine item modData `tlgProc` | recipe snapshot `{ id, version, fp, params }`; optional fields below |
| Conversion project | 1 | vehicle/generator modData | see `TLG/Domain/Conversions/Project.lua` |
| World record | 1 | global ModData `TLG_World` | epoch, policy, installedAt, transitionHours, calendar, climateLog (days carry optional room means `r0`, `r1`; D-021), balanceHistory, createdAsNewGame, dieselVehicles, modVersion. Sent to clients (the server answers `ModData.request` for any key), so it holds nothing private |
| World server store | 1 | modData key `tlg` of the server-side global object system `tlgworld` (file `gos_tlgworld.bin` in the save; `server/TLG/Server/WorldStore.lua`) | `v`, seed, nextId, climateAcc (today's running climate sums, optional; D-020), machineSites (placed machines for the hourly air reading, optional; D-021). Never sent to clients (security audit 2026-11-05, V-03). Rules below |
| Server-kept records ("vault") | 1 | key `vault` of the world server store's table (in `gos_tlgworld.bin`; `shared/TLG/Authority/Vault.lua`) | `v`, `from`, `tag`, `foreign`, `recs`, `holders`, `dk`; fields and rules below |
| Player knowledge | 1 | player modData `tlgKnowledge` | fuel record id (as a string) → the latest observation of each test, `{ kit = obs, visual = obs }` (`lab` too); rules below |
| Recipe definitions | per recipe `version` + content fingerprint | registry | active batches keep their snapshot |
| Consumer/adapter definitions | registry fingerprints | registry | `TLG.SCHEMA.adapter` = 1 |
| Balance profile | `Balance.REVISION` = 1 | code + dated history | changes apply from the change time only |

### Process records (machines)

A process record includes the recipe snapshot `{ id, version, fp, params }`.
Its optional fields:

* `site` `{ room, z }`, `temps` (hourly air readings by world hour) and
  `startedAt` (D-021).
* `fires`, by world hour: the hour's last note of the fire warming the
  machine, `{ t, f, x, y, r, c, rad }`, or `false` (D-022). A campfire's
  note has `k = "campfire"` and `rmax`, its largest radius, instead of
  `rad`; notes without `k` keep their meaning.
* `site` also keeps its tile `x`, `y`, and `seen` is the last world hour
  the authority found the machine placed with a batch running (D-015).
  Records without them cannot tell a move no Lua saw and credit nothing
  past their last access.
* `stoppedEarly` (boolean) marks output an abort kept (D-023). Collecting
  the last of it, or a second abort, clears it. Records without it behave
  as before.

### World server store

* Saves from before the store kept its four fields (seed, nextId,
  climateAcc, machineSites) in `TLG_World`. On load they move here and
  leave the world record; the store's values win, and `nextId` takes the
  larger.
* Until the store loads (it loads after `OnInitGlobalModData`), and if it
  cannot load, the fields stay in `TLG_World`.
* A store lost with its world record kept gets a new seed, so new ids stay
  distinct.
* Going back to a version from before the store is not supported. That
  version reads the seed and next id from `TLG_World`, finds none, and
  fails at its first new record id. The world record's `v` stayed 1, as no
  version reads it to decide.

### Server-kept records (the vault)

Kept on a server only (security audit 2026-11-05, V-01): a world loaded in
single player drops it, and the next server start begins a new one.

Fields:

* `v`: the schema version;
* `from`: the first id given out with the vault in use;
* `tag`: the seed in ids then;
* `foreign`: only when the store was lost;
* `recs`: `<kind>:<id>` → `{ r = record, h = holder }` for supply records
  and generator conversion projects. For machine process records,
  `{ r = record without temps and fires, h = holder, d = { temps = digest, fires = digest } }`,
  a digest -1 for a record without the field. `wear:<supply id>` → `{ r }`;
* `holders`: holder and kind joined by a bar → id, or `false` once the
  record moved to another holder. Holders: `item:<item id>`, `pump:x,y,z`,
  `gen:x,y,z`, `obj:x,y,z`;
* `dk`: the digest keys, `w`, `temps`, `fires` and `nf` (a weight per fire
  note field), drawn once and never sent.

Rules:

* Saves from before the vault: a record whose id was given out before
  `from` (same seed in the id) is adopted as found the first time the
  server reads it, if it is no larger than 8,192 bytes as saved and its
  readings and notes are as the mod writes them. One from a seed the world
  lost with its store is adopted likewise.
* Vehicle parts are not kept: no way for a client to write them was found.
* Records are never removed from the vault: a destroyed item's stays.
* The record held is the table the server wrote to the mod data, not a
  copy. Saved, the two are written apart, and the first read after a load
  finds them equal.
* A machine's readings and fire notes are saved only as their digests, so
  a machine takes about 1.2 KB of the store whatever its history. One
  whose readings or notes no longer match loses them on the next read.
* A vault saved with whole process records and no `dk` (the vault's first
  version, never released) gets its keys and is compacted when the world
  loads.

### Player knowledge

* An observation is what `Inspection.sample` returns.
* Only the authority reads it (the `known` command). In multiplayer the
  server keeps it in its player object, and the client copy of the player
  never has it (RT-MP run 203).
* Knowledge saved before 2026-11-06 held one observation, the last of any
  test, as the entry itself (it has `observedDeg`). It reads as that
  test's, and the next result of another test is added beside it
  (`Inspection.tests`, `Inspection.remember`).
* It belongs to the character: a new survivor starts without it.

## Migration rules

* `MigrationService.upgrade(kind, record)` is deterministic and idempotent;
  upgrading a current record returns it unchanged.
* Records with a **newer** schema than the running build are preserved
  untouched and treated as read-only (adapters return "future_schema" and
  never write).
* Migrations never convert custom fuel into fresh gasoline and never lower
  degradation (the v0 → v1 step maps recorded age to `deg` conservatively).
* Fixture tests: `tests/fixtures/supply_v0.lua`, `tests/domain/test_migrations.lua`.

## New worlds and existing saves

The authority creates the world record once, on `OnInitGlobalModData`:

* `isNewGame = true` → policy `new_world`: original fuel ages from the world
  epoch plus a seeded pre-outbreak age.
* Existing save → sandbox option **Existing saves**:
  1. **Transition period** (default, 30 days): fresh at installation,
     converging on world-age condition by the end of the period.
  2. **Age from world start**: as if the mod had always been installed.
  3. **Start ageing at installation**.
* The policy and epoch persist in global ModData, the seed in the world
  server store (above). Reconnecting, reinstalling or changing sandbox
  options later never re-grants fresh reserves. Fuel discovered late is
  aged as of discovery (no fresh fuel for late exploration).
* "Discovered" means the first contact that writes a record: a pour, a
  refuel, another transfer, or a look (**Look and smell**, or a sample
  with the sampling kit), which writes only the record (D-024).
* A single-player save that gains the mod (the load screen's
  **Choose Mods...**, which rewrites the save's `mods.txt`) takes the
  options' defaults: transition, 30 days. The load screen offers no sandbox
  settings (SRC `LoadGameScreen.lua`). Verified in RT-SP runs 39–40: the
  record was created on the first load as an existing save, fuel first
  recorded at installation was fresh, a can first recorded 6 days later
  was blended 20 % towards the world-age condition, and all of it was
  unchanged after save and continue.

### Diesel in new worlds (0.2.0, D-036)

Two optional fields carry it; neither changes a schema version:

* The world record's `dieselVehicles` is set once, when the record is
  created: `true` for a new game, `false` for an existing save. A record
  made by an earlier version has no such field, which reads as `false`.
  Where it is `true`, the chassis of `Vehicles.DIESEL_FAMILIES` have the
  profile `engine_ci_stock` and an unrecorded tank is read as diesel;
  elsewhere every vehicle keeps `engine_si_stock` and petrol.
* A pump's sidecar keeps `product`, `"diesel"` or `"gasoline"`, from its
  first record on. In a world with `dieselVehicles` it is drawn from the
  world's seed and the pump's key; elsewhere it is `"gasoline"`. A sidecar
  from an earlier version has no such field and reads as `"gasoline"`.

So a save from 0.1.x keeps its vehicles and pumps on petrol under 0.2.0.
Launch 257 played a new world with the 0.1.2 zip and continued it with the
0.2.0 zip (`tools/rehearse-install.ps1 -Scenario upgrade`):

* The records 0.1.2 wrote (three cans, a pump, an ambulance, a car and a
  generator) were unchanged before any read. A petrol can, the ethanol
  can, both vehicles, the generator and the pump then read as their
  records. A fermenter's batch was still running.
* The world record was the same one. It has no `dieselVehicles`, and its
  `modVersion` stays `0.1.2`: that field is the version that created the
  record, and nothing updates it.
* The pump 0.1.2 recorded had no `product`; it read as petrol, delivered
  2 L of it, and its record then named `"gasoline"`. All eight pumps of
  the station gave petrol.
* The recorded ambulance kept `engine_si_stock` and its petrol and
  started; an ambulance met for the first time read as petrol too.
* 0.2.0's items and fluids exist in that save, and a Diesel Generator put
  down there has its sprite and picture: the tile sheet works in a save
  made without it.

Not run: an upgrade from 0.1.0 or 0.1.1, an upgrade on a server, and a
second save and reload after the upgrade.

The diesel generator and the biodiesel
machines are new items and need no migration. A placed diesel generator
is saved by the game with its tile sprite, `tlg_generators_01_0`, whose
number comes from `tiledef=tlg_generators 7341` in `mod.info`: changing
that number would orphan placed generators.

### Wrong fuel (0.3.0, D-037)

No record changes. The sandbox option `TheLastGallon.WrongFuelDamage` is
new; a save without it reads it as on. A save from 0.2.0 therefore
behaves differently from its first load with 0.3.0: a tank holding a fuel
its engine is not built for, which refused the start and did no harm,
now lets the engine start, or try to, and damages it. Not run in game.

## Settings changes
Changing **Fuel ageing speed** appends a dated entry to `balanceHistory`;
every advance splits at those dates, so the past keeps its old rate.

## Unloaded simulation

Supplies and machines advance lazily on access over day-aligned climate
segments; machines are event-exact (stage completion, firebox exhaustion,
spoilage). A 2-year catch-up is ~730 segments per supply (test
"catch-up"). Recorded daily climate (server, hourly sampling of the day
mean) is used when available, otherwise the seasonal model; today's
weather is never applied to the past.

## Installing on an existing save

Supported through the policy above. Untracked native fuel is adopted on first
contact (baseline condition); nothing is scanned eagerly.

## Removing the mod

Not supported while the mod's items or fluids exist in the world. Before
removal, players should use up or discard ethanol, diesel, biodiesel and
contaminated fuel; the machines cannot be kept (there is no dismantling
recipe). A guided "prepare removal" admin command is a release-checklist
item, not yet implemented.

RT-SP run 54 took the mod off with the load screen's **Choose Mods...**
(which rewrites the save's `mods.txt`), played a game day and put the mod
back. What happened:

* The save loads without a dialog. The game skips the items it cannot
  create (console: `InventoryItemFactory.CreateItem() cannot create item`
  for `TLG.FermenterVessel`, then
  `InventoryItem.loadItem() item == null, skipped bytes`): a fermentation
  vessel with a batch running was gone. The other `TLG.*` items are items
  of the same kind; not tried.
* A can of `TLG_Ethanol` was empty: the game dropped the fluid without a
  word. The other `TLG_*` fluids (diesel, biodiesel, the water and
  sediment of contaminated fuel, methanol, glycerin, plant oil) were not
  tried. Aged fuel in a can also holds some `TLG_FuelWater`: the water it
  took up (D-007 amendment).
* Vanilla Petrol keeps working. TLG sidecars in item modData and the world
  record in global ModData persist and are inert.
* A car saved with its engine running on poor fuel is saved with the power
  the mod lowered (D-031; the game saves the engine's power, BC
  `BaseVehicle.save`). With the mod, the power comes back once the engine
  stops. Without it nothing restores it until a repair or an engine swap
  (BC `VehiclePart.repair`). Engine wear the mod applied is permanent by
  design, as damage is. Not run.
* With the mod back, the world record is the same one, never created again
  (re-adding grants no fresh fuel), and the sidecars read as they were
  saved. Changes made meanwhile are reconciled like any change TLG did not
  see (D-006): a decrease leaves proportionally, so the rest keeps its
  condition; an increase is untracked inflow at the baseline of the moment
  it is found.

Launches 255 and 256 repeated it with 0.2.0, in a world started with it:

* The world's `dieselVehicles` and what each of the station's eight pumps
  gives (from the world's seed; none had a record) were the same with the
  mod back.
* A `TLG.WoodRetort` on the ground was gone, like the fermenter.
* A placed Diesel Generator stays in the save as a generator object, with
  its fuel amount, its `generatorFullType` and the mod's record. Its
  sprite, which comes from the mod's tile sheet, is lost on the load
  without the mod (`getSprite()` is nil) and does not come back with the
  mod: the object is then saved without one. With the mod back its record
  and its profile, `generator_ci_bio`, read as before. Nothing restores
  the sprite. What a player can do with a generator without a sprite was
  not tried.

Not run: a save that still lists the mod after it was uninstalled (the
game's missing-mods prompt), a server, converted engines, a vanilla
generator, diesel in a vehicle's tank or a can.

## Crash consistency

Native quantities and TLG sidecars are saved by the game in the same object
modData/save pass where possible (items, vehicle parts, generator and pump
objects). Split persistence (e.g. a crash between a native change and the
sidecar write) is reconciled on next access: decreases leave
proportionally, unexplained increases are adopted at the pessimistic
baseline. Crash injection tests: NOT RUN.

On a server the vault (server-kept records, above) is saved with the world
server store in `gos_tlgworld.bin`, apart from the chunks and players that
hold the records. After a crash between those saves, a record saved in a
chunk or a player after the store's last save is newer than the vault's,
and the next read puts the older one back: a treatment or a collect made
in between is undone, and the litres reconcile as above (D-006). For a
machine, readings or notes in the chunk that no longer match the vault's
digests are dropped rather than put back. The other order does no harm.
Only a clean restart was run (security audit 2026-11-05, run 21).

The store is saved through the engine's shared 10 MB save buffer
(`SliceY.SliceBuffer`). A store larger than that is not saved at all (the
file is left empty, BC `SGlobalObjectSystem.save`), so a world gets a new
seed and a new vault at its next start. The vault takes about 1.2-1.3 KB
per machine whatever its history (its readings and notes are kept as
digests) and about 330 bytes per supply record, so the store reaches the
buffer at about 8,000 machines or 32,000 supply records (Kahlua measures;
security audit §7, V-01 item 7 (i)).
