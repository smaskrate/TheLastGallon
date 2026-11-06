# Persistence, versions and migrations

## Versioned contracts

| Contract | Version | Where | Notes |
| --- | --- | --- | --- |
| Supply sidecar | 1 | item/object/part modData `tlg` | `v`, id, rev, deg, stab, mic, t, storage, sealed, cond, dirty, label, prov, q (+ `frac`, `cap` for pumps; `kind`, `profile` for generators) |
| Process (machine) | 1 | machine item modData `tlgProc` | includes recipe snapshot `{ id, version, fp, params }`; optional `site` `{ room, z }`, `temps` (hourly air readings by world hour) and `startedAt` (D-021), and `fires` (by world hour, the hour's last note of the fire warming the machine `{ t, f, x, y, r, c, rad }` or `false`; D-022; a campfire's note has `k = "campfire"` and `rmax`, its largest radius, instead of `rad`, and notes without `k` keep their meaning); `site` also keeps its tile `x`, `y`, and optional `seen` is the last world hour the authority found the machine placed with a batch running (D-015). Records without them cannot tell a move no Lua saw and credit nothing past their last access. Optional `stoppedEarly` (boolean) marks output an abort kept (D-023); collecting the last of it, or a second abort, clears it; records without it behave as before |
| Conversion project | 1 | vehicle/generator modData | see `TLG/Domain/Conversions/Project.lua` |
| World record | 1 | global ModData `TLG_World` | epoch, policy, installedAt, transitionHours, calendar, climateLog (days carry optional room means `r0`, `r1`; D-021), balanceHistory, createdAsNewGame, modVersion. Sent to clients (the server answers `ModData.request` for any key), so it holds nothing private |
| World server store | 1 | modData key `tlg` of the server-side global object system `tlgworld` (file `gos_tlgworld.bin` in the save; `server/TLG/Server/WorldStore.lua`) | `v`, seed, nextId, climateAcc (today's running climate sums, optional; D-020), machineSites (placed machines for the hourly air reading, optional; D-021). Never sent to clients (security audit 2026-11-05, V-03). Saves from before it kept these four fields in `TLG_World`: on load they move here and leave the world record (the store's values win; `nextId` takes the larger). A store lost with its world record kept gets a new seed, so new ids stay distinct. Until the store loads (it loads after `OnInitGlobalModData`), and if it cannot load, the fields stay in `TLG_World`. Going back to a version from before the store is not supported: that version reads the seed and next id from `TLG_World`, finds none, and fails at its first new record id (the world record's `v` stayed 1, as no version reads it to decide) |
| Server-kept records ("vault") | 1 | key `vault` of the world server store's table (in `gos_tlgworld.bin`; `shared/TLG/Authority/Vault.lua`) | `v`, `from` (the first id given out with the vault in use), `tag` (the seed in ids then), `foreign` (only when the store was lost), `recs` (`<kind>:<id>` → `{ r = record, h = holder }` for supply records and generator conversion projects; for machine process records `{ r = record without temps and fires, h = holder, d = { temps = digest, fires = digest } }`, a digest -1 for a record without the field; `wear:<supply id>` → `{ r }`), `holders` (holder and kind joined by a bar → id, or `false` once the record moved to another holder), `dk` (the digest keys: `w`, `temps`, `fires`, `nf` = a weight per fire note field; drawn once, never sent). Holders: `item:<item id>`, `pump:x,y,z`, `gen:x,y,z`, `obj:x,y,z`. Kept on a server only (security audit 2026-11-05, V-01): a world loaded in single player drops it, and the next server start begins a new one. Saves from before it: a record whose id was given out before `from` (same seed in the id) is adopted as found the first time the server reads it, if it is no larger than 8,192 bytes as saved and its readings and notes are as the mod writes them; one from a seed the world lost with its store likewise. Vehicle parts are not kept (no way for a client to write them was found). Records are never removed from it: a destroyed item's stays. The record held is the table the server wrote to the mod data, not a copy; saved, the two are written apart and the first read after a load finds them equal. A machine's readings and fire notes are saved only as their digests (a machine takes about 1.2 KB of the store whatever its history); one whose readings or notes no longer match loses them on the next read. A vault saved with whole process records and no `dk` (the vault's first version, never released) gets its keys and is compacted when the world loads |
| Player knowledge | 1 | player modData `tlgKnowledge` | fuel record id (as a string) → the latest observation of each test, `{ kit = obs, visual = obs }` (`lab` too); an observation is what `Inspection.sample` returns. Read only by the authority (the `known` command): in multiplayer the server keeps it in its player object, and the client copy of the player never has it (RT-MP run 203). Knowledge saved before 2026-11-06 held one observation, the last of any test, as the entry itself (it has `observedDeg`): it reads as that test's, and the next result of another test is added beside it (`Inspection.tests`, `Inspection.remember`). It belongs to the character: a new survivor starts without it |
| Recipe definitions | per recipe `version` + content fingerprint | registry | active batches keep their snapshot |
| Consumer/adapter definitions | registry fingerprints | registry | `TLG.SCHEMA.adapter` = 1 |
| Balance profile | `Balance.REVISION` = 1 | code + dated history | changes apply from the change time only |

## Rules

* `MigrationService.upgrade(kind, record)` is deterministic and idempotent;
  upgrading a current record returns it unchanged.
* Records with a **newer** schema than the running build are preserved
  untouched and treated as read-only (adapters return "future_schema" and
  never write).
* Migrations never convert custom fuel into fresh gasoline and never lower
  degradation (the v0 → v1 step maps recorded age to `deg` conservatively).
* Fixture tests: `tests/fixtures/supply_v0.lua`, `tests/domain/test_migrations.lua`.

## New worlds and existing saves

The world record is created once by the authority on `OnInitGlobalModData`:

* `isNewGame = true` → policy `new_world`: original fuel ages from the world
  epoch plus a seeded pre-outbreak age.
* Existing save → sandbox "Existing saves":
  1. **Transition period** (default, 30 days): fresh at installation,
     converging on world-age condition by the end of the period.
  2. **Age from world start**: as if the mod had always been installed.
  3. **Start ageing at installation**.
* The policy and epoch persist in global ModData, the seed in the world
  server store (above); reconnecting,
  reinstalling or changing sandbox options later never re-grants fresh
  reserves. Fuel discovered late is aged as of discovery (no fresh fuel for
  late exploration).
* "Discovered" means the first contact that writes a record: a look
  (Look and smell or the sample kit, which writes the record alone,
  D-024), a pour, a refuel or another transfer.
* A single-player save that gains the mod (the load screen's Choose
  Mods..., which rewrites the save's `mods.txt`) takes the options'
  defaults: transition, 30 days. The load screen offers no sandbox
  settings (SRC `LoadGameScreen.lua`). Verified RT-SP runs 39–40: record
  created on the first load as an existing save, fuel first recorded at
  installation fresh, a can first recorded 6 days later blended 20 %
  towards the world-age condition, all unchanged after save and continue.

## Settings changes

Changing "Fuel ageing speed" appends a dated entry to `balanceHistory`;
every advance splits at those dates, so the past keeps its old rate.

## Unloaded simulation

Supplies and machines advance lazily on access over day-aligned climate
segments; machines are event-exact (stage completion, firebox exhaustion,
spoilage). A 2-year catch-up is ~730 segments per supply (test
"catch-up"). Recorded daily climate (server, hourly sampling of the day mean)
is used when available; otherwise the seasonal model (never today's weather
applied to the past).

## Installing on an existing save

Supported through the policy above. Untracked native fuel is adopted on first
contact (baseline condition); nothing is scanned eagerly.

## Removing the mod

Not supported while the mod's items or fluids exist in the world. What
happens, from RT-SP run 54 (the mod taken off with the load screen's Choose
mods, which rewrites the save's `mods.txt`; a game day played; the mod put
back):
* The save loads without a dialog. The game skips the items it cannot
  create (console: `InventoryItemFactory.CreateItem() cannot create item`
  for `TLG.FermenterVessel`, then `InventoryItem.loadItem() item == null,
  skipped bytes`): a fermenter with a batch running was gone. The other
  `TLG.*` items are items of the same kind; not tried.
* A can of `TLG_Ethanol` was empty: the game dropped the fluid without a
  word. The other `TLG_*` fluids (diesel, biodiesel, the water and sediment
  of contaminated fuel, methanol, glycerin, plant oil) not tried. Aged fuel
  in a can also holds some `TLG_FuelWater`: the water it took up (D-007
  amendment).
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

Not run: a save that still lists the mod after it was uninstalled (the
game's missing-mods prompt), a server, converted engines and generators.
Before removal, players should use up or discard ethanol, diesel, biodiesel
and contaminated fuel; the machines cannot be kept (there is no dismantling
recipe). A guided "prepare removal" admin command is a release-checklist
item, not yet implemented.

## Crash consistency

Native quantities and TLG sidecars are saved by the game in the same object
modData/save pass where possible (items, vehicle parts, generator and pump
objects). Split persistence (e.g. a crash between a native change and the
sidecar write) is reconciled on next access: decreases leave proportionally,
unexplained increases are adopted at the pessimistic baseline. Crash
injection tests: NOT RUN.

On a server the vault (server-kept records, above) is saved with the world
server store in `gos_tlgworld.bin`, apart from the chunks and players that
hold the records. After a crash between those saves, a record saved in a
chunk or a player after the store's last save is newer than the vault's,
and the next read puts the older one back: a treatment or a collect made
in between is undone; the litres reconcile as above (D-006). The other
order does no harm. Only a clean restart was run (security audit
2026-11-05, run 21). The store is saved through the engine's shared 10 MB
save buffer (`SliceY.SliceBuffer`); a store larger than that is not saved
at all (the file is left empty, BC `SGlobalObjectSystem.save`), so a world
gets a new seed and a new vault at its next start. The vault takes about
1.2-1.3 KB per machine whatever its history (its readings and notes are
kept as digests) and about 330 bytes per supply record, so the store
reaches the buffer at about 8,000 machines or 32,000 supply records
(Kahlua measures; security audit §7, V-01 item 7 (i)). For a machine,
after such a crash, readings or notes in the chunk that no longer match
the vault's digests are dropped rather than put back.
