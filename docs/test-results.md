# Test results

Every run lists date, build, command, outcome and what was **not** run.
Domain = `tools/run-tests.ps1` on the game's Kahlua VM. RT-DS = isolated
dedicated server harness. RT-SP / RT-MP = client runtime tests.

## Not run (standing list)

| Area | Reason |
| --- | --- |
| RT-SP: driving burn, station-reservoir pour, pouring from a can on the ground | Not in the harness yet |
| RT-SP: crafting the sampling kit, filter and stabilizer; picking up a running still or drying column (fermenters: runs 26–27); Pause and Abort on a still (fermenters and the drying column: run 31); workshop menu Project status/Cancel/Remove; Italian text in game | Not in the harness yet |
| RT-SP: walking away from the work (the harness moves the character); cancelling or removing a conversion; two workers; a winter run (only July was tested) | Not in the harness yet |
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

## 2026-10-31 — RT-SP client harness, launches 10–12 (the player's path)

The loop now goes through what a player uses: vanilla crafting
(`ISInventoryPaneContextMenu.OnNewCraft`, next to a counter the harness
finds), the vanilla drop action, the machine context menu and the workshop
menu (entries clicked the way `ISContextMenu` does, replies and dialog text
captured). Same mod-clock fixture as launches 7–9.

Fixed before launch 10, from reading vanilla code and bytecode:

* The crafting window (`ISHandcraftWindow.lua:53`) and the inventory "craft"
  menu (BC `CraftRecipeManager.getUniqueRecipeItems`) only list recipes
  tagged `InHandCraft` or `AnySurfaceCraft`; no TLG recipe had a tag, so
  nothing the mod adds could be crafted. Tags added (D-019).
* "Load mash" without amounts (the menu sends none) asked for 5 L of water
  per kg of the 30 kg maximum, up to 130 L; it now follows the sugar
  actually loaded.
* "Collect ethanol" took the first fuel can with room, a can holding petrol
  included; it now prefers an empty can, else one holding only ethanol and
  water, and never another fuel.
* The workshop dialog listed raw ids ("Base.Wrench"); it now shows item
  names and skills as "Mechanics 4".

Launch 10 (`docs/evidence/2026-10-31_rt-sp_harness_run10.txt`), phase A
**76/15**, phase B 12/2: all 7 recipes listed; the mash took 30 L of the
32 L carried; every menu dialog translated; the refused start showed "A tool
is missing: - Wrench". Failures: every craft `canPerform=false`; the split
into a second can moved nothing; both work actions went quiet after their
first report; the rest followed from these.

Launch 11 (`…run11.txt`), phase A **80/11**, phase B 12/2, with load and
action logging. Found:

* The harness carried everything at once (57.7 kg, `hasFullInventory`
  true). Vanilla then refuses a can-to-can transfer (BC
  `FluidContainer.CanTransfer`) and drops crafted outputs on the floor
  (`Actions.addOrDropItem`), which the check did not see: the crafts did
  work. Harness changed to hand materials over per step.
* Pots and jars were not consumed by crafting: container inputs are kept
  unless the recipe says `mode:destroy` (vanilla pasta/rice recipes). Fixed.
* The work action made one good report and was then dropped from vanilla's
  action queue while it kept running in Java: its progress call
  `setJobDelta` sets `currentTime = maxTime × delta` (BC `BaseAction`),
  negative for an open-ended action, and the queue's `tick()` then treats
  it as stalled (`hasStalled`). The queue looked idle while the character
  worked. Progress bar removed. Run 9 never looked at the queue, so it did
  not show there.

Launch 12 (`…run12.txt`): phase A **94 PASS / 0 FAIL**, phase B
**14 PASS / 0 FAIL**; launcher exit code 0; no TLG error, TLG stack frame or
queue warning in the console.

* Crafted through the inventory craft menu, next to a counter: fermentation
  vessel, pot still, reflux still (in hand, welding) and drying column; each
  output in the inventory, consumed inputs gone (pot and jars included),
  kept tools (hammer, screwdriver, blowtorch, welding mask) still there.
* Placed with the vanilla drop action; the whole batch run from the machine
  menu (load mash, feed the firebox, load wash, collect, dry, collect,
  status), with the same quantities as launches 7–9.
* Generator from the workshop menu: Start, Hand over parts, a refused "Work
  on it" without the wrench, then "Work on it" to `Commissioned` (26
  reports, 7.5 h) and the dialog "Converted and commissioned".
* Car from the workshop menu: "Work on it" walked 3.6 tiles into the engine
  area before working; moved away after 2 h, the action stopped and 3 h
  away earned nothing; at 6 h the screwdriver was taken and the next report
  ended the action with "A tool is missing: - Screwdriver" and no credit;
  the third session reached `Commissioned` with 13 h credited.
* Pours, generator start, car start (first attempt) and phase B as in
  launch 8.

Not run: see the standing list.

## 2026-10-31 — RT-SP client harness, launch 13 (real game clock)

Command: `tools/run-sp-harness.ps1 -Mode realtime -TimeoutMinutes 60` (request
`sp-rt`: the same scenario, only the ethanol loop, no mod-clock offset, no
reload). Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run13_realtime.txt`.
**10 PASS / 1 FAIL**; launcher exit code 0; no TLG error, TLG stack frame or
queue warning in the console.

Time ran on the game clock, 2.0 → 138.2 world hours. Machines waited at a
debug multiplier (`GameTime.setMultiplier(100)`, as the debug panel's Game
Speed slider; measured 2.22 game hours per 300 ticks); the conversion work
ran at vanilla's fastest speed, x40 (measured true multiplier 40.0); walking
and teleports at x1. The character was invulnerable, invisible and kept fed.

* Fermentation (menu, 6 kg sugar, 30 L water) finished after 97.2 game
  hours: 97 h at full rate. Outdoor temperature ranged 10.9–28.0 °C; the
  climate model uses daily means and the fermenter's "sheltered" profile, so
  July never slowed it.
* Chunk unload (G12): 12 hours in, the character was moved 400 tiles away;
  the machines' square was no longer loaded. Back after 24 game hours, the
  fermenter had done 24.02 h more work. The check compared that with the
  time to the return teleport (24.01 h, logged); the status read came 120
  settling ticks later (about 0.01 game h at x1, not logged), so it failed
  by its own bound. Bound changed to the time between the two reads and
  rerun as launch 14.
* Distillation: 3.78 game hours (expected ~3.8), 3.036 L ethanol + 0.194 L
  water. Drying: 12.09 game hours, water to 0.5 %.
* Generator conversion from the menu: 7.71 game hours from the click for
  7.5 h of work (30 reports), 7.5 h credited, "Converted and commissioned".
  Car: 13.11 game hours for 13 h (52 reports), 13 h credited.

Not run: pours and engine starts (unchanged from launch 12), a reload, any
season other than summer.

## 2026-10-31 — RT-SP client harness, launch 14 (real game clock, rerun)

Same command as launch 13, with the catch-up bound measured between the two
status reads and the true multiplier read before the speed is reset.
Evidence: `docs/evidence/2026-10-31_rt-sp_harness_run14_realtime.txt`.
**11 PASS / 0 FAIL**; launcher exit code 0; console clean.

* Measured x100 (true multiplier 100.0, 2.22 game hours per 300 ticks).
* Chunk unload: the machines' square unloaded; 24.02 h more work over the
  24.02 game hours between the status read before leaving and the one after
  return (`RT.unloaded_machine_catches_up` PASS).
* Fermentation 97.2 game hours (outdoor 11.8–30.9 °C), distillation 3.78 h,
  drying 12.09 h, generator conversion 7.56 h from the click for 7.5 h of
  work, car 13.11 h for 13 h; 2.0 → 138.0 world hours in all.

## 2026-10-31 — RT-SP client harness, launches 15–16 (winter)

Command: `tools/run-sp-harness.ps1 -Mode winter -TimeoutMinutes 60` (request
`sp-rtw`: the real-clock scenario from 15 January; one fermentation followed
until it finishes, spoils or 400 game hours pass). Each hourly status read is
compared with the stage rules of `ethanol_ferment` (full rate 18–32 °C,
0.4 between 8 and 18 °C, paused below 8 °C, spoiled after 72 h paused)
applied to the day temperature TLG had recorded, sheltered as the climate
model does: (mean + 16) / 2.

Launch 15 (`docs/evidence/2026-10-31_rt-sp_harness_run15_winter.txt`),
**5 PASS / 0 FAIL**. Every day recorded 0.5–0.6 °C, so the fermenter sat at
8.3 °C and ran at 0.4 (9.63 h of work per 24 h): finished after 241.7 game
hours (97 at full rate); 229 hours compared, all exact. No day stalled.
Finding: the constant value is the season curve. `getDayMeanTemperature()`
returns `currentDay.season.getDayMeanTemperature()` (BC
`ClimateManager`); the weather is in `getTemperature()`. Machines and fuel
ageing had never seen a cold snap or a heat wave. Fixed:
`World.recordClimate` now records the running mean of the hourly air
temperature (D-020).

Launch 16 (`…run16_winter.txt`), **8 PASS / 0 FAIL**, console clean, with the
fix:

* Recorded day means −0.8, −2.7, −2.4 and −4.7 °C (air −7.2 to 3.0 °C);
  the recorded mean equalled the mean of the harness's own hourly air
  readings within 0.01 °C on both full days.
* After its 1 h preparation the batch was paused as too cold every hour
  (68 of 68 compared hours exact); the Status dialog read "Paused · Reason:
  too cold here · Stage: fermenting".
* Spoiled after 72 paused hours (72.23 h by the hourly reads, `pausedFor`
  72.00 in the record), 73.2 game hours after loading: state `Faulted`,
  "batch_spoiled".

Not run: a winter with alternating cold and mild days (whether separate
cold spells add up to the 72 h, as the code does). A heated building is no
test gap: machine temperature comes from the outdoor day mean only
(`thermal = "sheltered"`), wherever the machine stands. (No longer true
since D-021: see launches 17–19.)

## 2026-10-31 — RT-SP client harness, launches 17–19 (where the machines stand)

Command: `tools/run-sp-harness.ps1 -Mode winter -TimeoutMinutes 60` (request
`sp-rtw`, rewritten for D-021). From 15 January with the grid off
(`ElecShut` 1, `ElecShutModifier` −1; `isHydroPowerOn()` false in every run),
three fermenters within reach of one spot near the Muldraugh Gas2Go were
loaded in the same hour with 6 kg of sugar and 30 L of water each:
outdoors (10618,10627), in a room (10619,10628) and in a room on a tile
with an `IsoHeatSource` of radius 1 and 35 °C added from Lua (10618,10628).
Every game hour the harness read the game's air at the three tiles; before
each status read it compared the readings the mod had filed with its own,
after it the day temperature the status reported (against
`siteDayMean` over the harness's readings) and the work done (against the
stage rule fed by that temperature). A 12 game hour trip of 400 tiles on
day 2 unloaded the tiles. Evidence:
`docs/evidence/2026-10-31_rt-sp_harness_run17_sites.txt`, `…run18_sites.txt`,
`…run19_sites.txt`.

| | Run 17 | Run 18 | Run 19 |
| --- | --- | --- | --- |
| Result | **24 PASS / 0 FAIL** | 24 / 1 | **25 / 0** |
| Room tile = `Climate.roomAir`, worst | 96 h, 0.00000 °C | 95 h, 0.00000 °C | 94 h, 0.00000 °C |
| Outdoor tile = `getTemperature()` | exact | exact | exact |
| Tile with the heat source | 28.0 °C every hour | same | same |
| Filed = game's readings (out / room / heated) | 61 / 71 / 96 h, exact | 61 / 73 / 95, exact | 61 / 83 / 94, exact |
| Status day temperature = readings' mean | exact | heated once 3.28 vs 28.00 °C | exact |
| Hourly work = stage rule | exact | exact | exact |
| Unloaded: hours filed / filed after return | 0 of 12 / 66 | 0 of 12 / 65 | 0 of 12 / 64 |
| Outdoors | spoiled, `pausedFor` 72.00 | same | same |
| Room | spoiled, `pausedFor` 72.00 | same | same |
| Heated | finished, 7.28 h paused | finished, 5.26 h | finished, 5.26 h |

Outdoor day means were −8.1 to +1.7 °C. The room ran 9.5–13.1 °C above the
outdoor air, 4.5–11.4 °C at the room fermenter: slow on the first day, then
mostly stopped, and spoiled in every run. A room alone did not carry a
batch through these Januaries; the warmed tile did. Status read, e.g.,
"Paused · Reason: too cold here · Stage: fermenting · Temperature here
today: 45.3 °F, in a room" (this dev cache shows °F; the log holds a UTF-8
"°").

Found and fixed:

* Run 17: the warmed fermenter paused after every midnight until the new
  day's first reading was filed (7.28 paused hours in all). The hour in
  progress now takes the previous hour's reading (`Climate.siteDayMean`);
  in runs 18–19 its only pauses were the 5.26 hours of a morning spent
  unloaded, and no read was paused on a day read throughout.
* Run 18: right after midnight the status still showed the unheated value
  (3.28 °C): the access pruned yesterday's last reading before the status
  used it. `Machines.trimTemps` keeps that hour; run 19 exact.

Not run: upper floors, a real fire, fireplace or barbecue (the heat source
was added from Lua; the vanilla objects register the same kind, BC), the
grid on, a player-built room, a machine moved between two accesses. (A
fireplace of the map: see launches 20–21.)

## 2026-11-01 — RT-SP client harness, launches 20–21 (a fireplace of the map)

Command: `tools/run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60`
(request `sp-rtf`, new). The same January world with the grid off. The
harness looks for a working fireplace of the map, lights it with a log
through the calls the vanilla actions make (`addFuel`, `turnOn`,
`sendObjectChange`; the actions and their menu were not used), compares
the air on every floor tile within 9 of it with the heat formula unlit and
at four fuel levels (set as vanilla's `fireplace.setFuel` command does),
then runs one fermentation (6 kg of sugar, 30 L of water) on a room tile
beside it. Meanwhile it tends the fire as a player can (a log adds 360
minutes and only goes in once it fits under the 480 minute cap) and makes
the winter run's checks of readings, day temperature, work and a 12 game
hour trip. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run20_fireplace_search.txt`,
`…run21_fireplace.txt`.

* Run 20 (1 PASS / 0 FAIL, the search only): 49 windows of 97 × 97 tiles
  up to 288 tiles around the start held two campfires and two braziers
  and no fireplace, and the later steps were skipped. Only
  `fixtures_fireplaces_01_0`–`_5` are working fireplaces (the rest of that
  tileset is chimney and wall), and the map cells' headers list them only
  north of the start. The search now scans those cells, nearest first.
* Run 21 (**17 PASS / 0 FAIL**): `fixtures_fireplaces_01_5` at
  10677,10296, its tile in a room; the fermenter stood at 10679,10297,
  2.24 tiles away.

| Run 21 | Result |
| --- | --- |
| Floor tiles within 9, unlit | 360, all at the unwarmed value |
| Lit with 360 min (radius 8) | 34 warmed exactly as the formula says, 158 in range but not warmed (no line of sight), 168 out of range, 0 off |
| Lit with 40 / 20 / 5 min (radius 5 / 3 / 1) | 19 / 11 / 0 warmed, 0 off |
| Machine tile | warmed at 360, 40 and 20 min, not at 5 |
| Machine air = formula at the fire's fuel, hourly | 102 h, worst 0.00000 °C; lit at all 102, lowest fuel 82 min |
| Air at the machine | 20.7 °C or more every hour, at least 9.99 °C above the unheated room; unheated room 3.2–9.6 °C, outdoors −9.4 to −1.1 °C as day means |
| Filed = game's readings / day temperature = mean / work = rule | 102 h exact / 101 reads exact / 95 h exact |
| Trip (12.01 h, tiles unloaded) | 0 of 12 hours filed; 72 filed after the return |
| Fire on the return | left lit with 365 min, found out with 0 after 721 min; relit |
| Batch | finished after 114.3 game h; 97 stage hours of work; 5.36 h paused; 18 logs |

The absence cost about 17 hours. The 7 unloaded hours of 16 January took
the unheated room value (7.7 °C), which brought that day's mean to just
below 18 °C (0.4). The 5 unloaded hours of 17 January had no reading at
all: the day stood at 7.8 °C and the batch paused (the 5.36 h; the
harness's day line for 17 January shows 12.91 h paused because it counts
the whole interval since the previous read as paused when a read finds the
batch paused, while the mod's own `pausedFor` is 5.36 h). Even with
the fire lit again, the day's mean then stayed below 18 °C for about 11
hours (0.4 rate; 14.6 °C at 48 h in). This is the day-mean rule of D-020
and D-021 at work, matched exactly by the harness. Meanwhile the fire
burned its 365 minutes during the absence, in one step on the reload, and
was out on the return (vanilla, BC `IsoFireplace.update`). Status read
"Working · Stage: fermenting · Temperature here today: 72.0 °F, in a
room".

Not run: a fire (`IsoFire`) or barbecue beside a machine, the fireplace's
menu and timed actions, a fireplace upstairs.

Run 22 repeated the winter mode (launches 17–19) once its status,
filed-reading and trip helpers served both scenarios: **25 PASS / 0
FAIL**, as run 19 (room formula exact over 94 hours; readings, day
temperatures and work exact; outdoors and the room spoiled at 72.00
paused hours, the warmed batch finished with 5.26 h paused). Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run22_sites.txt`.

## 2026-11-01 — RT-SP client harness, launch 23 (a fire's fuel counts while away, D-022)

Command: `tools/run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60`,
with D-022 in the mod and the harness; the same fireplace and tile as run
21. Every ten game minutes the harness took its own note of the fire
warming the fermenter, at the same ticks as the mod, and compared the two.
It fed the fire a quarter hour before the trip (379 minutes left, so no log
fitted) and checked the work over the trip against the stage rule fed by
the credited day temperatures. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run23_fire_credit.txt`.

Result: **21 PASS / 0 FAIL**.

| Run 23 | Result |
| --- | --- |
| Notes filed = harness's | 99 hours noted, all with the fire, 0 off |
| Notes in hours spent away | 0 |
| Last note before leaving | 365 min, the fire at offset −2, −1 (2.24 tiles), its tile in a room |
| Trip | 12.01 h unloaded; the noted fuel covered 6.08 h; the fire was out on the return (vanilla) |
| Work over the trip = rule with the credit | 7.5633 h, exact |
| Machine air = formula / readings filed / day temperature / hourly work | 97 h, 0.00000 °C / exact / exact / exact |
| Batch | finished after 109.2 game h (run 21, no credit, a colder January: 114.3), 5.36 h paused (the uncredited hours of 17 January), 17 logs |

The tiles around the fire repeated run 21 exactly (34 / 19 / 11 / 0 warmed,
none off). Not run: a barbecue as the noted fire (unit tests only), a
fire fed less than ten minutes before leaving, two fires within reach.

Run 24 repeated the winter mode with the fire notes running: **25 PASS /
0 FAIL**. Its warmed tile has a heat source added from Lua, not a fire the
notes know, so nothing was credited: the day temperatures matched the
harness's without notes. The outcomes were as in run 22 (outdoors and the
room spoiled at 72.00 paused hours; the warmed batch finished, its 6.26
paused hours all on the day of the trip; the weather differs per run).
Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run24_sites.txt`.

## 2026-11-01 — RT-SP client harness, launch 25 (the fireplace batch across a save)

Command: `tools/run-sp-harness.ps1 -Mode fireplace-reload -TimeoutMinutes 60`
(requests `sp-rtfs`, then `sp-rtfb`; new). Phase 1 found the same fireplace,
checked the tiles around it, and ran the batch beside it with the fire
tended for 14 game hours. It then left the fire to burn out with the
character beside it until two hours of notes said no fire warmed the
machine. It wrote the record, its own readings and notes and the fire's
state to the expectations file, saved and exited to the menu. Phase 2
continued the save from the main menu and, before any access, compared the
record with the expectations. It then relit the fire and ran the batch on
with the trip and every check of the fireplace run. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run25_fire_reload.txt`.

Result: phase 1 **8 PASS / 0 FAIL**, phase 2 **20 PASS / 0 FAIL**.

| Run 25 | Result |
| --- | --- |
| Saved | 19.04 h into the batch, the fire out with 0 min; the record held 7 readings and 9 notes, 2 of them without a fire (earlier hours pruned as designed) |
| Continued | world hour 23.3992 (saved at 23.3762) |
| Readings / notes after the reload | identical, both "no fire" notes kept |
| Batch | identical: Processing, stage 2, 16.833 stage h, 0 h paused, started at 4.339, site in a room on the ground floor |
| Hourly list entry / the fire | kept at 10679,10297 / out with 0 min, as left |
| Trip after the reload | last note 424 min, covering 7.07 of 12.01 h; no note while away; work over the trip = rule with the credit, 7.5415 h |
| Notes / readings / day temperature / hourly work after the reload | 84 h noted, 0 off / 83 h exact / 83 reads exact / 78 h exact |
| Batch | finished after 114.2 game h, 6.37 h paused, 18 logs |

The first status after the reload read "Temperature here today: 58.5 °F,
in a room": that day's mean still held the hours the fire was out before
the save. It ended the day at 19.6 °C, and every reported day temperature
matched the harness's.

## 2026-11-01 — RT-SP client harness, launch 26 (running fermenters picked up)

Command: `tools/run-sp-harness.ps1 -Mode pickup -TimeoutMinutes 30` (request
`sp-rtp`; new). Summer with the grid on (`ElecShutModifier` 30): three
fermenters on room tiles around the character, loaded in the same tick. A
powered room holds 22 °C, so every placed hour is a full stage hour. Three
game hours later A was picked up with the world menu's Grab and B with the
loot window's Grab; C stayed where it was, as the control. A's Status was
read while it was carried, B's was not. Three game hours later A was put
down with the place action and B with the inventory menu's Drop, each on
another room tile. All three were read two game hours later, and again
two hours after that. The three `RTP.D015_` checks hold the work to D-015:
processing advances only while the machine is placed. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run26_pickup.txt`.

Result: **25 PASS / 3 FAIL**. The three failures are the D-015 checks: the
work around a move does not follow the decision.

| Run 26 | Result |
| --- | --- |
| Pickup | world menu Grab (`ISGrabItemAction`) and loot window Grab (`ISInventoryTransferAction` from the floor): both carried, records unchanged (7 readings and notes each) |
| Menu while carried | Status only; "Place it on the ground to operate it" greyed |
| A's Status while carried | Paused, "Reason: it was picked up; place it to continue" |
| Hourly list | A left it at that Status, B at the next hourly reading, C stayed; nothing filed in the 3 h carried |
| Put down | A with the place action on its tile, B with Drop on the character's tile; records unchanged; neither read in the 2 h before a Status |
| After the Status | all three Processing and listed at their tiles; readings (filed 22 = game 22.0000 °C, 4 h) and fire notes resumed; A and B then did 2.0002 h each, like C |
| Control C | 8.0319 h of work in 8.0319 game h |
| **FAIL** A before the pickup | 0 h credited for 3.01 h placed: the Status while carried paused it from its last access, the load |
| **FAIL** A after putting down | 0 h credited for 2.00 h placed: the first Status after putting down started it again from that moment |
| **FAIL** B while carried | 8.03 h credited for 5.03 h placed: never read while carried, it counted the 3.00 h carried as if it had stood at its new tile |

The mod learns of a move only when the machine is next used, and then
cannot tell the hours placed from the hours carried: a Status while
carried drops every hour since the last use, and without one every hour
counts. With the grid on, the four readings compared were 22.0000 °C, and
Status gave 71.6 °F (22 °C) as the day temperature at all three tiles, as
the room formula says (its first check in game with power). Not run: a
still or drying column picked up, a move in multiplayer, a carried machine
across a save.

## 2026-11-01 — RT-SP client harness, launch 27 (pickup after the fix)

Command: `tools/run-sp-harness.ps1 -Mode pickup -TimeoutMinutes 30`, with
the fix of D-015 (commit `d21dd15`): the adapter wraps the game's Grab,
floor transfers and place action, and credits a move no Lua saw up to the
last time it found the machine placed (`seen`). The mode now has a fourth
fermenter, D, lifted with the calls `ISGrabItemAction`'s single-player
branch makes but not through it: a grab no Lua sees, as the server's Java
item transaction is in multiplayer. D's Status was not read while carried,
and it went down with the inventory menu's Drop. The checks that run 26
read as "not read until a Status" now expect the hourly reading to find
the machines at their new tiles at once. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run27_pickup_fix.txt`.

Result: **34 PASS / 0 FAIL** (the console showed "machine move hooks
installed" and no move error).

| Run 27 | Result |
| --- | --- |
| At pickup (A Grab, B loot window) | counted to the moment, then paused: A 3.0192 h for 3.0192 h placed, B 3.0332 h for 3.0333 h; off the hourly list at once; readings and notes kept |
| A's Status while carried | Paused, "it was picked up"; no work added |
| D, grabbed unseen | record untouched; still listed until the next hourly reading, then dropped |
| Carried 3 h | nothing filed for A, B or D |
| Put down (A place action, B and D Drop) | A and B Processing from the put-down with the work they had, site and hourly list at the new tile at once; D found moved: credited up to the last time it was found placed, 0.1017 h before the grab (2.9317 h), then Processing from the put-down |
| No Status for 2 h after | readings filed at the new tiles (6 h, filed 22 = game 22.0000 °C) and fire notes (3 h each) |
| Read 8.04 h after loading | C 8.0383 h; A 5.0225 h (3.0192 before the pickup + 2.0033 since the put-down); B 5.0351 h = its 5.0351 h placed; D 4.9321 h (2.9317 + 2.0003) |
| Two hours on | A, B, C and D 2.0071 h each |

The three checks run 26 failed (`RTP.D015_`) passed, as did a fourth for
B at the pickup. Not run: a still or drying column picked up, a move in
multiplayer itself (D only stands in for its grab), a carried machine
across a save.

## 2026-11-01 — RT-SP client harness, launch 28 (the pot still)

Command: `tools/run-sp-harness.ps1 -Mode pot-still -TimeoutMinutes 40`
(request `sp-rtpot`; new). Summer with the grid on: a fermenter, a pot
still and a drying column on room tiles around the character, everything
done from the machine menu. 12 kg of sugar and 60 L of water fermented at
full rate into 66.6 L of wash, more than the pot still's 60 L, so the wash
went in two loads. The firebox got one log before the first run and was
left to run out; an hour after Status showed it, four logs were offered.
Both runs went into one fuel can, which was evaluated with
`Consumers.evaluate`, the function the vehicle and generator start gates
call, against every spark-ignition profile; it was then dried with
quicklime and evaluated again. Expectations come from the definitions in
`Content/Production.lua`. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run28_pot_still.txt`.

Result: **25 PASS / 0 FAIL** (no TLG error or warning in the console).

| Run 28 | Result |
| --- | --- |
| Fermentation | done 97.0000 h after loading; 6.6 L ethanol, 60 L water |
| First "Load wash" | 60 L taken, the fermenter left OutputReady with 0.654 L ethanol and 5.946 L water; no yeast starter yet |
| Firebox, one log (9 kg) | ran out mid-distillation (fuel for 2.835 h; Status at 2.904 h: "Reason: the firebox is out of fuel") |
| Four logs offered an hour later | 27 kg taken, one log left (the firebox holds 30 kg) |
| Run 1 | 9.605819 h = 8.5 h of stages + 1.105819 h without fuel, exactly the time it had none; firebox left 9.015873 kg; 5.232432 L ethanol and 1.308108 L water (recovery 0.88, purity 0.80); condition 0.98 |
| Second "Load wash" | the remaining 6.6 L; the fermenter Ready; the yeast starter came with it |
| Run 2 | 2 h (6.6 L at 8 L/h is under the 1 h minimum), no pause; the firebox's 9.015873 kg carried over, 2.666667 kg left; 0.572114 L ethanol and 0.143029 L water, the efficiency of condition 0.98; condition 0.96 |
| One can | 5.8045 L ethanol, 1.4511 L water: unfit for all four spark profiles (free water; stock ones also too much ethanol) |
| Dried with 5 kg quicklime | 12.000 h; 5.8045 L ethanol, 0.0290 L water: fit for the flex engine and the flex generator, still too much ethanol for stock ones |

With wash left in it, the fermenter's Status read "Finished: output
waiting", "Reason: output waiting, nowhere to put it", "Stage: fermenting":
the batch is done and waits for the still, which those words do not say
(fixed, run 29).
The engines' verdicts are the start gates' evaluation, not engine starts;
the engines ran on dried reflux ethanol in runs 13–14. Not run: the pot
still built from the crafting window in this run (spawned; building it was
run 12), the reflux still with this wash, a pot-still batch aborted.

## 2026-11-01 — RT-SP client harness, launch 29 (Status of finished machines)

Command: `tools/run-sp-harness.ps1 -Mode pot-still -TimeoutMinutes 40`,
with the fix of commit `958b958`: `Process.status` names a stage only while
the batch runs, and the machine menu words a finished machine by its kind.
Run 28's note on the fermenter's Status became a check, with one for the
still after its first run and one for the drying column. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run29_pot_still_status.txt`.

Result: **28 PASS / 0 FAIL**: run 28's 25 checks again (the same
quantities; the hour without fuel was 1.105826 h, the refeed a few ticks
later) and the three new ones.

| Status read (EN) | Text |
| --- | --- |
| Fermenter with wash left | "Finished: the wash is ready for a still", "Wash is left: load it again when the still is free", the temperature, ethanol 0.65 and water 5.95; no stage |
| Pot still after run 1 | "Finished: ethanol ready to collect", the temperature, "Firebox: 9.0 kg of wood", ethanol 5.23 and water 1.31; no stage |
| Drying column, done | "Finished: dried ethanol ready to collect", the temperature, ethanol 5.80 and water 0.03; no stage |

A paused batch still shows its stage ("Stage: distilling" with the firebox
out), as it should. The Italian text is not checked in game.

## 2026-11-01 — RT-SP client harness, launches 30–31 (Pause, Resume, Abort batch)

Command: `tools/run-sp-harness.ps1 -Mode controls -TimeoutMinutes 30`
(request `sp-rtc`; new). Summer with the grid on, room tiles: three
fermenters and a drying column loaded in the same tick, every press from
the machine menu. F1 was paused 5 h in, resumed 6 h later and read 4 h
after; Pause, Resume and Abort were also pressed where they do not apply.
F2 was aborted 5 h in and loaded again. The drying column, loaded from a
can of 4 L ethanol and 1 L water with 4 kg quicklime, was aborted 6 h in.
F3 was paused 5 h in and left; once spoiled, Abort and Load mash were tried
on it. The four `RTC.design_` checks hold Abort to its handler's own
description ("returns the partial result to the player ... discarded and
listed") and to `Process.abort`'s ("an abort never loses material"), and a
spoiled batch to a way out from the menu. The still was left out: it shares
the abort handler, and the domain tests pin its firebox and litres.
Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run31_controls.txt`.

Run 30 (19 PASS / 5 FAIL) filled the column's can with vanilla water, which
the mod does not track as water in fuel (that is its own fluid,
`TLG_FuelWater`): the load saw only ethanol and refused it as already dry,
so the column's four checks meant nothing. Run 31 used the mod's fuel
water. Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run30_controls_setup.txt`.

Result, run 31: **20 PASS / 4 FAIL**. The four failures are the design
checks: three defects.

| Run 31 | Result |
| --- | --- |
| Pause (F1) | "Paused", "Reason: paused by hand"; Status keeps "Stage: fermenting" |
| Six hours paused | no work (5.004478 h before and after); the hours count as paused (6.003233 h) |
| Resume | working again; 4 h later 9.004705 h done, exactly the hours it ran |
| Pause, Resume, Abort where they do not apply | refused, the record unchanged; the dialogs read "Not possible right now (not_processing).", "(not_paused)." and "(nothing_to_abort)." |
| The menu | Status, Load mash, Pause, Resume and Abort batch in every state (working, paused, spoiled), none greyed |
| Abort (F2, 5 h in) | the reply holds the partial batch exactly as `Process.abort` gives it (ethanol 0.170255 L, water 30 L, sugar 5.690445 kg); the fermenter is empty and Ready and takes a new mash; no sugar comes back |
| **FAIL** what F2's abort lost | the dialog says only "Ready" |
| Abort (drying column, 6 h in) | the reply holds ethanol 3.999929 L and water 0.509433 L, the dry converter's result at 0.5006 done; the column is empty and Ready |
| **FAIL** what the column's abort lost | the dialog says only "Ready" |
| **FAIL** the column's ethanol | 4 L of ethanol, taken from the can at loading, is in no can and not in the column: gone |
| Hand pause left (F3) | spoiled at exactly 72 paused hours: "Faulted", "Reason: the batch spoiled while stalled" (the guide's "stopped for 3 days in all" includes Pause) |
| **FAIL** clearing the spoiled batch | Abort refused (nothing_to_abort), Load mash refused (busy): the fermenter stays spoiled; nothing in the menu reaches `Process.repair` |

Not run: Abort on a still (shared handler; the domain pins its firebox and
litres), Pause on a still, the Italian text.
