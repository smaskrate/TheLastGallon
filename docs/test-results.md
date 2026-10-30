# Test results

Every run lists date, build, command, outcome and what was **not** run.
Domain = `tools/run-tests.ps1` on the game's Kahlua VM. RT-DS = isolated
dedicated server harness. RT-SP / RT-MP = client runtime tests.

## Not run (standing list)

| Area | Reason |
| --- | --- |
| RT-SP client (translations, item save/load, vehicles, generators, pumps) | Client harness not yet executed |
| RT-MP two clients (authority, reconnect, concurrency) | No second client available in this environment |
| Performance baseline | Requires a loaded client world |
| Packaged-artifact install/upgrade rehearsal | Package not built yet |

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
