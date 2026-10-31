# Test results

Every run lists date, build, command, outcome and what was **not** run.
Domain = `tools/run-tests.ps1` on the game's Kahlua VM. RT-DS = isolated
dedicated server harness. RT-SP / RT-MP = client runtime tests.

## Not run (standing list)

| Area | Reason |
| --- | --- |
| RT-SP: driving burn, station-reservoir pour, pouring from a can on the ground | Not in the harness yet |
| RT-SP: crafting the machines, the machine and workshop menus, the pot still, picking up a running machine, Italian text in game | Not in the harness yet |
| RT-SP: machines and conversion work in real elapsed game time; cancelling or removing a conversion | The harness advances the mod clock only; cancel/remove not in the harness yet |
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

## 2026-10-31 — RT-SP client harness, launch 6 (start gates, stall, vehicle pours)

Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run6.txt`. Phase A
**63 PASS / 0 FAIL**, phase B **11 PASS / 0 FAIL**; launcher exit code 0.

New checks, all through the vanilla actions:

* Generator start gate (`ISActivateGenerator`): petrol (grade good) activates;
  3 L E100 put in an empty generator with the confirmed TLG pour is refused
  (`too_much_ethanol`) and the generator stays off.
* TLG pours into a car (8 L E25 tank): 3 L petrol accepted (11 L, 18 %
  ethanol); 3 L E100 without confirmation refused with nothing moved
  (`incompatible`); the same pour confirmed is accepted (14 L, 36 % ethanol).
  Litres conserved and records match the native amounts each time.
* Vehicle start gate (`ISStartVehicleEngine`, player as driver): refused on
  the 36 % blend (engine `Idle`); allowed on station fuel (`Running`). The
  station fuel rated `startFactor=0.5` (free water 0.23 % above the stock
  engine's 0.2 %), so this allowed start depended on the 50 % roll.
* Stall: the 36 % blend, started directly, was stalled by the per-minute
  effect handler 0.6 game minutes later.
* Phase B with id-matched lookups: vehicle tank and generator records and
  amounts identical after reload, with the ground can, pump, items and world
  record (11/11).

Finding (balance, not a code defect; changed by D-017 below): station water was drawn from 0–0.4 %
while the stock engine tolerates 0.2 %, so about half of all stations
dispense fuel that halves a stock car's start chance from the first day.

## 2026-10-31 — Station water balance (D-017)

* Change: station water drawn as 0–0.15 % at about 9 in 10 sites and
  0.2–0.4 % at about 1 in 10 (was uniform 0–0.4 %).
* New case "world init: station water is low at most sites and high at
  about one in ten": 4000 pump keys on a map-like grid, 404 contaminated;
  every clean site ≤ 0.15 %, every contaminated site in [0.2 %, 0.4 %),
  deterministic per site; passes with seeds 20261030 and 1.
* `tools/run-tests.ps1` → `modules=13 cases=139 passed=139 failed=0`.
* Not re-run in game (the change is confined to the deterministic draw that
  the domain test covers).

## 2026-10-31 — RT-SP client harness, launch 7 (renewable loop)

Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run7.txt`. Phase A
**74 PASS / 8 FAIL**, phase B **12 PASS / 2 FAIL**; launcher exit code 0.

Time fixture: fermentation (96 h), distillation, drying (12 h) and the
conversion work (7.5 h and 13 h) are too long to wait for, so the harness
advances the mod clock only (`TLG.World.now` + an offset); the game clock
does not move. Catch-up and work crediting are domain-tested; this run checks
the commands, the inventory handling and the adapters. The harness sends the
commands directly; the machine and workshop menus were not used.

Passed: ethanol made from real inventory items through the authority
commands.

* Fermenter: 6 Sugar, 30 L of water from three buckets and 1 Yeast gave a
  wash holding 3.30 L ethanol, ready after 120 h of mod time (checked every
  24 h; 97 h needed).
* Reflux still: 18 kg of firewood from 2 Logs; the 33.3 L wash loaded and a
  yeast starter came back; 3.036 L ethanol + 0.194 L water (94 %) after 4 h;
  collected into a jerry can with matching fluids and a fresh record.
* Drying column: the can's spirit plus 1 quicklime (of 2); after 12 h,
  3.036 L ethanol + 0.015 L water (0.5 %), collected into a second can. A
  fixture degradation of 0.8 put on the spirit came through unchanged.
* Splitting the dried ethanol into two cans through the wrapped transfer kept
  identical states.
* Phase B: the three machine records came back (`Ready`) after reload.
* As a side result, this run's new world drew clean station fuel (0.038 %
  water), the D-017 clean tier.

Failed: one defect and its consequences.

* `conversion.begin` refused both conversions with `missing_tool`
  (`Base.Screwdriver`) although the player carried every tool. The adapter
  counted only the items named by the device's existing project, and a first
  conversion has none yet, so no conversion could ever be started in game.
  The domain tests passed because they hand the service a ready-made actor.
  Fixed: `CD.actor` also counts the requested conversion (and removal tools);
  regression cases in `tests/integration/test_conversion_devices.lua`.
* Consequences: both engines stayed stock, so the TLG pours of the dried
  ethanol were refused as incompatible (correct for stock engines), the
  generator stayed empty and did not start, and phase B found no conversion.
* Harness weakness: `LOOP.flex_car_start.not_refused_by_tlg` passed with an
  empty tank (TLG never refuses an empty tank). The gate step now also
  requires fuel, and the loop's car has to actually start (up to three
  attempts).

## 2026-10-31 — RT-SP client harness, launch 8 (renewable loop after the fix)

Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run8.txt`. Phase A
**82 PASS / 0 FAIL**, phase B **14 PASS / 0 FAIL**; launcher exit code 0.
Same time fixture as launch 7; commands sent directly, not through the menus.

* Production repeated launch 7 exactly (3.30 L ethanol in the wash, 3.036 L
  at 94 %, dried to 0.5 % water, degradation kept).
* Generator conversion (`flex_generator` on `Base.Generator`): started, took
  exactly its parts (1 rubber hose, 4 screws, 1 electric wire) and was
  commissioned by one 8 h work report (7.5 h needed); profile
  `generator_si_flex`.
* Car conversion (`flex_car_normal` on `Base.CarNormal`): took 2 rubber
  hoses, 2 engine parts, 6 screws and 2 electric wires; an 8 h report left it
  at the install stage and a 6 h report commissioned it (13 h needed);
  profile `engine_si_flex`.
* The dried ethanol (1.53 L each) went into both with the TLG pour: accepted
  without confirmation, litres conserved, records equal to the native
  amounts.
* The generator activated through `ISActivateGenerator` (grade good, start
  factor 1). The car started through `ISStartVehicleEngine` on the first
  attempt (`Running`). The harness repaired the car beforehand (battery 1.00,
  engine 100) so that vanilla part condition could not decide the start.
* Phase B: both conversions came back `Commissioned` with their flex profiles
  (the generator still held its 1.5256 L), with the machine records and every
  earlier record (14/14).
* Station fuel in this world rated start factor 1 (clean tier); the
  station-fuel car started.
* Suite: `modules=14 cases=141 passed=141 failed=0` (adds
  `tests/integration/test_conversion_devices.lua`); compile check
  `compiled=91 errors=0`.

Not run: the machine and workshop menus, crafting the machines, the pot
still, machines and conversions in real elapsed game time, driving on
ethanol, cancelling or removing a conversion, multiplayer.

## 2026-10-31 — RT-SP client harness, launch 9 (conversion work as a timed action, D-018)

Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run9.txt`. Phase A
**83 PASS / 0 FAIL**, phase B **14 PASS / 0 FAIL**; launcher exit code 0; no
TLG error or TLG stack frame in the console.

The harness queues `ISTLGConversionWork` itself and moves the mod clock
0.05 h per tick while it runs (same fixture as launches 7–8).

* A bare `conversion.work` three hours after the last report, without the
  action, credited exactly 1 h and ended the assignment (`expired`,
  `released`).
* Generator: the action re-joined, reported 26 times and ended by itself at
  `Commissioned`; 7.5 h credited in total (1 h from the bare report).
* Car, first session: after 8 reports (2.003 h credited) the character was
  moved 12 tiles away. The game polled `isValid()` and called the action's
  `stop()` (no refused report, no dialog); the queue was idle. Three hours
  passed away from the car: still 2.003 h.
* Car, second session: re-joining credited nothing for the time away
  (2.003 h at re-join); the action ended by itself at `Commissioned` with
  13 h credited in total.
* Production, pours, the generator activation, the car start (first
  attempt) and phase B as in launch 8.
* Suite: `modules=14 cases=142 passed=142 failed=0` (new domain case for the
  caller's worker timeout); compile check `compiled=92 errors=0`;
  translations 213 EN keys, IT parity.

Not run: the menu entry itself (walking to the engine area or next to the
generator), walking away (the character was moved), the action ending on a
block (missing tool or parts, tank not empty) or on a refused join, the
progress bar's rendering, two workers at once, multiplayer.
