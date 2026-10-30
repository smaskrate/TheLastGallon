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
