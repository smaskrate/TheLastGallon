# Persistence, versions and migrations

## Versioned contracts

| Contract | Version | Where | Notes |
| --- | --- | --- | --- |
| Supply sidecar | 1 | item/object/part modData `tlg` | `v`, id, rev, deg, stab, mic, t, storage, sealed, cond, dirty, label, prov, q (+ `frac`, `cap` for pumps; `kind`, `profile` for generators) |
| Process (machine) | 1 | machine item modData `tlgProc` | includes recipe snapshot `{ id, version, fp, params }`; optional `site` `{ room, z }`, `temps` (hourly air readings by world hour) and `startedAt` (D-021), and `fires` (by world hour, the hour's last note of the fire warming the machine `{ t, f, x, y, r, c, rad }` or `false`; D-022); `site` also keeps its tile `x`, `y`, and optional `seen` is the last world hour the authority found the machine placed with a batch running (D-015). Records without them cannot tell a move no Lua saw and credit nothing past their last access. Optional `stoppedEarly` (boolean) marks output an abort kept (D-023); collecting the last of it, or a second abort, clears it; records without it behave as before |
| Conversion project | 1 | vehicle/generator modData | see `TLG/Domain/Conversions/Project.lua` |
| World record | 1 | global ModData `TLG_World` | seed, epoch, policy, installedAt, transitionHours, nextId, calendar, climateLog (days carry optional room means `r0`, `r1`; D-021), climateAcc (today's running climate sums, optional; D-020), machineSites (placed machines for the hourly air reading, optional; D-021), balanceHistory, createdAsNewGame |
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
* The policy, seed and epoch persist in global ModData; reconnecting,
  reinstalling or changing sandbox options later never re-grants fresh
  reserves. Fuel discovered late is aged as of discovery (no fresh fuel for
  late exploration).

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

Not supported while TLG fluids exist in the world. If the mod is removed:
items holding `TLG_*` fluids reference fluid types the game no longer knows
(engine behaviour NOT RUN); vanilla Petrol keeps working; TLG sidecars in
modData are inert. Before removal, players should consume or discard
ethanol, diesel, biodiesel and contaminated fuel, and dismantle TLG machines
(empty machines carry no fluids). A guided "prepare removal" admin command is
a release-checklist item, not yet implemented.

## Crash consistency

Native quantities and TLG sidecars are saved by the game in the same object
modData/save pass where possible (items, vehicle parts, generator and pump
objects). Split persistence (e.g. a crash between a native change and the
sidecar write) is reconciled on next access: decreases leave proportionally,
unexplained increases are adopted at the pessimistic baseline. Crash
injection tests: NOT RUN.
