# Test results

Every run lists date, build, command, outcome and what was **not** run.
Domain = `tools/run-tests.ps1` on the game's Kahlua VM. RT-DS = isolated
dedicated server harness. RT-SP / RT-MP = client runtime tests.

## Not run (standing list)

| Area | Reason |
| --- | --- |
| RT-SP: vehicle/generator start gates via vanilla actions, stall on poor fuel, driving burn | Harness starts engines and generators directly |
| RT-SP: TLG pour into a vehicle, station-reservoir pour, machines running a batch, crafting | Not in the harness yet |
| RT-MP two clients (authority, reconnect, concurrency) | No second client available in this environment |
| Performance baseline | Requires a measured client session |
| Packaged-artifact install/upgrade rehearsal | Not run |

## 2026-10-30 — Kahlua runtime probe

* Command: `tools/run-tests.ps1 -Entry tests/support/runtime_probe.lua`
* Result: completed; output recorded in `engine-capabilities.md` (Lua runtime).

## 2026-10-30 — RT-DS harness, boot 1 and boot 2 (42.21.0)

* Command: `tools/dev-server-controller.ps1` (boot 1 was launched with an
  earlier fire-and-forget script and hard-stopped after `saveGame()`).
* Result file: `<devcache>/Lua/TLG_harness_server.txt`
* Checks: 10 PASS, 3 FAIL on both boots.
  * PASS: namespace loaded, script item instance, fluid lookup, Fuel category,
    Petrol/Ethanol blend, mixture add, proportional transfer, proportional
    `adjustAmount`, capacity clamp, `FluidContainer.Transfer` wrapper.
  * FAIL: three translation checks returned keys on the dedicated server
    (IG_UI, ItemName, Fluids). Classified as "unverified on client", not as a
    packaging failure.
* Observations: see `engine-capabilities.md` G02/G08 (boot count 1 → 2,
  world age frozen at 2.0 h with `PauseEmpty=true`).
* Clean shutdown: `quit` via controller → "Shutdown handling finished".
  First attempt failed because the controller's stdin writer sent a UTF-8 BOM
  ("Unknown command ï»¿quit"); fixed by an ASCII writer.

## 2026-10-30 — Domain suite

* Command: `tools/run-tests.ps1`
* Result: `modules=1 cases=6 passed=6 failed=0 assertions=7510 seed=20261030`
* Notes: an empty filter argument is dropped by PowerShell and `*` is
  glob-expanded by the Windows `java` launcher; the runner now uses `all`.

## 2026-10-30 — RT-SP client harness attempt 1 (BLOCKED)

* Command: `tools/run-sp-harness.ps1`
* Result: client booted, passed terms screen, played intro videos, then no
  progress for 7 minutes. Windows session was locked (`LogonUI.exe`), so the
  window could not render. Client stopped by hand; **no client evidence**.
  All RT-SP checks remain NOT RUN.

## 2026-10-30 — Domain + authority + production suites

* Command: `tools/run-tests.ps1` → `modules=8 cases=61 passed=61 failed=0`.
* Compile check (package + harness): `compiled=54 errors=0`.
* Bug found and fixed while writing tests: transition policy applied
  pre-outbreak age at install time (expected fresh); BOM-prefixed files from
  PowerShell broke Kahlua compilation.

## 2026-10-30 — RT-DS harness boot 3 (container adapter)

* Command: `tools/dev-server-controller.ps1` + `tools/stop-dev-server.ps1`
* Evidence: `docs/evidence/2026-10-30_rt-ds_harness_boot3.txt`
* Result: 16 PASS, 3 FAIL (the same three dedicated-server translation
  checks). New PASS: world record (policy `transition`, existing world at
  2.0 h), all mod fluids registered, native composition write, transfer hook
  carries condition, untracked inflow reconciled, 200 hooked micro-transfers
  consistent. Observations: `adjustSpecificFluidAmount` sets; native float
  drift 5e-5 L over 200 transfers; water bottle ignored.
* Shutdown: first `quit` again arrived with a BOM; root cause was .NET's
  preamble on `Process.StandardInput` (controller fixed to absorb it).

## 2026-10-30 — Suite after machines/migrations, package build

* `tools/run-tests.ps1` → `modules=9 cases=67 passed=67 failed=0 assertions=32130 seed=20261030`
* Compile check (package + harness, BOM guard): `compiled=70 errors=0`
* `tools/check-translations.ps1` → OK (151 EN keys, IT parity)
* `tools/package.ps1` → `dist/TheLastGallon-0.1.0-dev.zip` (65 files) with
  SHA-256 manifest; warning: no preview.png. Not uploaded.
* Not run: every adapter path that needs a world object (vehicles,
  generators, pumps, machines on the ground), the TLG pour action, start
  gates, UI menus, crafting recipes — all require a client session; the
  desktop stayed locked for the whole session.

## 2026-10-30 — RT-DS harness boot 4 (scripts)

* Evidence: `docs/evidence/2026-10-30_rt-ds_harness_boot4.txt`
* Result: 32 PASS, 3 FAIL (dedicated-server translation checks, unchanged).
  New PASS: 8 items, 7 craft recipes, sandbox options; machine process record
  round-trips through item modData (in memory). Adapter install log clean.

## 2026-10-30 — Merged worker modules

* Conversions (21 cases), energy (23), pathways (17) merged after review.
  Fixes made during integration: registry overwrote machine `kind`; abort
  lost unprocessed wash; plan accepted NaN; output capacity unenforced;
  wood gas ran at full power.
* `tools/run-tests.ps1` → `modules=13 cases=137 passed=137 failed=0`
  (also seeds 1 and 4242).
* Compile check `compiled=90 errors=0`; translations OK (210 EN keys).

## 2026-10-30 — RT-DS harness boot 5 (merged package)

* Evidence: `docs/evidence/2026-10-30_rt-ds_harness_boot5.txt`
* Result: 32 PASS, 3 FAIL (dedicated-server translation checks, unchanged).
  With energy, biodiesel, biogas, wood gas, propane and conversion content
  loaded at boot: no registry validation problems, no duplicate definitions,
  all four adapters installed, "ready" logged. Clean `quit`.

## 2026-10-31 — RT-SP client harness, launches 1–5 (42.21.0)

Command: `tools/run-sp-harness.ps1` from an unlocked desktop. Each launch
runs phase A (debug scenario at the Muldraugh Gas2Go), saves, exits to the
menu, continues the save and runs phase B (persistence).

* Launch 1: no result. The client had emptied `mods/default.txt` on its
  first start (no `reset-mods-42_00.txt` yet), so no mod loaded and the game
  idled at the menu. Setup now writes the marker and the list every time.
* Launch 2: no result. The user had to click "Click to Start" and close the
  Survival Guide; then the TLG vehicle adapter raised "tried to call nil"
  (`getVehicles():get(i)` on a `HashSet`) and "Break On Error" halted the
  game in the Lua debugger. Fixed: Set iteration (adapter and two menus),
  automatic click, options, debugger break off for harness runs.
* Launch 3 (`docs/evidence/2026-10-31_rt-sp_harness_run3_phaseA.txt`):
  phase A 41 PASS / 5 FAIL; phase B never ran (the world's `mods.txt` was
  empty, then the 20-minute watchdog stopped the client). All 5 failures were
  harness placement (pump → vehicle, second generator).
* Launch 4 (`docs/evidence/2026-10-31_rt-sp_harness_run4.txt`): phase A
  42 PASS / 1 FAIL (the TLG pour target generator was nearly full: 0.015 L
  moved, conserved); phase B 9 PASS / 1 FAIL: a can on the ground came back
  without an item FluidContainer, which exposed the container-ownership defect
  (fixed, see engine-capabilities G02).
* Launch 5 (`docs/evidence/2026-10-31_rt-sp_harness_run5.txt`): phase A
  **47 PASS / 0 FAIL**; phase B 9 PASS / 2 FAIL. The two failures are harness
  lookups that matched the neighbouring vehicle / generator; the records
  found equal, to the four decimals logged, the phase A records of those
  objects. Lookups now match by record id (not re-run).

Verified at runtime (RT-SP, details in `engine-capabilities.md`):

* End-to-end station → can → vehicle → can → generator with one batch:
  10.00000 L at every hop, water/sediment and degradation carried (largest
  per-hop deviation 2e-8; end-to-end 4e-5 from ageing during the run).
* Pump → can 10 L = −10 units; pump → vehicle 59 L = −59 units.
* Ethanol blend through the vanilla can → vehicle path; native idle burn of
  a car and generator burn reconciled proportionally.
* Generator record through pickup, drop action, `forceDropHeavyItems` and
  floor drag; two identical cars keep separate part modData and engine power.
* TLG pour into a generator (petrol 3 L accepted and conserved; E100 refused
  without confirmation, nothing moved); fuel context menu (10 entries);
  sample request round trip; EN translations on the client.
* Save/reload of inventory, ground and machine items, vehicle tank,
  generator and pump records, global ModData, TLG world record.

Not run: see the standing list above. Domain suite after the fixes:
`modules=13 cases=138 passed=138 failed=0`; compile check `compiled=90 errors=0`.
