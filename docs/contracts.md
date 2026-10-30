# Shared contracts (for contributors and parallel workers)

Ownership: schemas, registries, the authority layer and every game-facing
adapter are owned centrally. New domain modules plug into the contracts below
and must not edit existing shared modules; report needed changes instead.

## Runtime rules (Kahlua, verified — see engine-capabilities "Lua runtime")

- [ ] Lua 5.1 subset. No `goto`, `//`, bit ops, `table.unpack` (use `unpack`).
- [ ] `next` and `math.random` do **not** exist. Emptiness: `TLG.Tables.isEmpty`.
      Randomness: `TLG.Rng.new(seed)` (deterministic).
- [ ] `%` is Java remainder (`-7 % 3 == -1`). Use `TLG.Num.mod`.
- [ ] No deep recursion (the game overflows below 3000 frames).
- [ ] Never depend on `pairs` order for state or output: iterate
      `TLG.Tables.sortedKeys(t)`; sort with `TLG.Tables.sort` (stable, iterative).
- [ ] `error(table)` arrives as a string: return `{ ok = false, reason = "code" }`.
- [ ] `string.format("%s", nil)` raises: always `tostring`.
- [ ] Files must not start with a UTF-8 BOM (Kahlua fails to compile them).
      Create Lua files with the editor's Write tool, never PowerShell
      `Set-Content -Encoding utf8`.
- [ ] Domain modules never call game APIs (`getGameTime`, `isServer`, items…).
      Time is passed in as world hours; environment comes from
      `TLG.Domain.Climate` segments.

## Module pattern

```lua
require "TLG/Util/Tables"            -- PZ-style require paths (lua/shared root)
TLG.Domain = TLG.Domain or {}
TLG.Domain.Thing = TLG.Domain.Thing or {}
local Thing = TLG.Domain.Thing
-- ... pure functions returning new tables (never mutate inputs) ...
return Thing
```

## Units

Liquids L; gases Nm³ (propane shown as kg at 2.01 kg/Nm³); solids kg;
fuel energy MJ per unit (`FuelDefinition.energyMJ`); electricity and heat kWh;
power kW; time world hours (doubles).

## Existing contracts

- `TLG.Registry.define(kind, def)`, `get`, `need`, `ids`, `all`,
  `addValidator(kind, fn(def, problem))`, `validate()`, `fingerprint(kind, id)`.
  Kinds: fuel, storage, consumer, recipe, machine, conversion, site, asset.
- Supply record (`TLG.Domain.Supply`): `{ v, id, rev, phase, cap, q, deg, stab,
  mic, storage, sealed, cond, dirty, t, label, prov }`; helpers `new`, `copy`,
  `total`, `fuelTotal`, `free`, `fraction`, `blendDeg`, `check`, `normalize`.
  Works for `phase = "gas"` with gas storage profiles (`propane_cylinder`,
  `gas_holder`).
- `TLG.Domain.Aging.advance(s, toT, env)`, `TLG.Domain.Mixing.previewTransfer`,
  `previewBlend`, `removeProportional`, `addUntracked`.
- `TLG.Domain.Climate.new(origin, log, history)`; `env:segments(t0, t1, thermal)`
  returns contiguous day-aligned segments `{ t0, t1, dt, tempC, rh, profile }`.
- Production (`TLG.Domain.Process`): machines/recipes in the registry,
  converters in `Process.converters[name] = function(inputs, params, machine,
  eff, skill, frac) return { outputs = {}, byproducts = {}, props = {} } end`.
  Stages: `{ id, hours | hoursFrom, labor, heatKW, tempMin, tempMax, slowBelow,
  slowAbove, slowRate, maxPauseHours }`. `Process.new/plan/load/start/advance/
  collect/abort/repair/decommission`.
- Authority (`TLG.Authority.Transactions`): endpoints with `key`,
  `canAccess(actor)`, `read()`, `write(record, change)`, optional `consumer`.

## Testing

- Tests live in `tests/domain/test_<module>.lua` and use `T.case`, `T.eq`,
  `T.near`, `T.ok`, `T.raises`, `T.le`; fixtures in `tests/support/fixtures.lua`
  (`F.env()`, `F.supply{...}`); `TEST_SEED` for randomized tests.
- Run `tools/run-tests.ps1` (whole suite) or `tools/run-tests.ps1 -Filter <text>`.
- Run `tools/run-tests.ps1 -Entry tests/support/compile_check.lua` (syntax + BOM).
- Required for every time-dependent module: one large advance equals many
  small ones (randomized split), conservation of every quantity except
  explicitly recorded losses, and rejection of malformed input.

## Contributions

New definitions go in a new `TLG/Content/<Module>.lua` (`require` the domain
modules it needs). Do not commit; report the file list and test results.
