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
never went into the can (the fluid the mod reads as water in fuel is its
own, `TLG_FuelWater`; had the game's water been there, the menu would have
greyed the entry as a can with something else in it): the load saw only
ethanol and refused it as already dry, so the column's four checks meant
nothing. Run 31 used the mod's fuel water. Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run30_controls_setup.txt`.

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
litres), Pause on a still, the Italian text. (Fixed: runs 32–33.)

## 2026-11-01 — RT-SP client harness, launches 32–33 (Abort after the fix)

Command: `tools/run-sp-harness.ps1 -Mode controls -TimeoutMinutes 30`, with
the fix of commit `3db39b7`: an aborted batch keeps what it made in the
machine and lists what it throws away, a second Abort or a spoiled batch
is emptied, refusals read as sentences, and the menu offers Pause, Resume
and Abort only where they apply. The mode now expects that and adds a pot
still beside the fermenters to take a stopped wash; F1 is aborted twice at
the end and F3 is emptied and reloaded after it spoils. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run33_controls_fix.txt`.

Run 32 (29 PASS / 3 FAIL) still pressed Pause, Resume and Abort from the
menu where they no longer appear, and found no entry; the menu was doing
its job. Run 33 sends those presses as a menu deciding on a stale copy of
the record would. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run32_controls_fix.txt`.

Result, run 33: **32 PASS / 0 FAIL**, the four design checks run 31 failed
among them.

| Run 33 | Result |
| --- | --- |
| The menu | working: Pause and Abort batch; paused by hand: Resume and Abort batch; stopped early or spoiled: Abort batch only; an idle still: none |
| Pause and Resume (F1) | 5.004412 h held through 6.002127 h paused; 9.004629 h after 4 h more, exact |
| Presses that do not apply | refused, the record unchanged: "It is not working on a batch right now.", "It is not paused.", "There is no batch to stop." |
| Abort F2, 5 h in | kept 0.170 L ethanol, 30 L water and 5.690 kg sugar as wash; "Batch stopped.", "Stopped early: the wash so far is ready for a still", the amounts, "Abort batch again to throw it away." |
| The pot still | took that wash, sugar and all (30.17 L); the vessel empty and loaded again |
| Abort the drying column, 6 h in | kept 3.999836 L ethanol and 0.509576 L water (the dry converter at 0.50 done), threw away 4.49 kg of spent lime and said so; collected into a can: 3.9998 L ethanol, 0.5096 L water |
| Abort F1 twice | the wash kept, then thrown away and listed ("Ethanol 0.31, Sugar 5.44, Water 30.00"); a new mash went in |
| F3 left paused | spoiled at 72.000000 paused hours; Load mash refused with "The batch in it has spoiled: use Abort batch to empty it."; Abort: "The spoiled batch was thrown away.", sugar 6 kg and water 30 L listed; a new mash went in |

Not run: Pause or Abort on a running still (the domain tests keep its
spirit, list the rest of the wash and account for every litre), the
Italian text.

## 2026-11-01 — RT-SP client harness, launch 34 (a campfire and a barbecue beside fermenters)

Command: `tools/run-sp-harness.ps1 -Mode fires -TimeoutMinutes 60` (new
mode, request `sp-rtof`): the January world with the grid off, outdoors
at the Muldraugh Gas2Go. Two fires 24 tiles apart, so neither reaches the
other's tiles:

* a campfire built with the call its build action makes
  (`SCampfireSystem.instance:addCampfire`);
* a charcoal barbecue created as vanilla's own tests create one
  (`IsoBarbecue.new` with `appliances_cooking_01_35`), where a player
  would set one down.

Each was fed a log and lit from its own menu: Add fuel → Log, then Light
→ a sheet of paper with matches (the barbecue's entry used the lighter the
character carried). The air on every tile around each fire was compared
with the heat formula, the campfire's at four fuel levels. A fermenter was
then loaded on the warmed tile one east of each fire. The run then took
hourly readings and the harness's own ten-minute notes of the fire warming
each machine. It tended the fires with the calls the add-fuel actions make
(a log once it fits under the 8 h cap) and made a 12 game hour trip that
unloaded both. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run34_fires.txt`.

Result: **35 PASS / 4 FAIL**. The four failures are one defect, read from
the sources before the run:

* A campfire a player builds is not an `IsoFireplace`. It is a Lua global
  object (`SCampfireSystem`) over a plain object named "Campfire", and its
  warmth comes from a permanent `IsoFire`.
* The mod's ten-minute notes (D-022) look for fireplaces and barbecues
  only, so they never name the campfire.
* The readings taken while you are near are right. The hours away get no
  warmth, though the campfire burns on.

| Run 34 | Campfire | Barbecue |
| --- | --- | --- |
| Lit from its menu | lit, 361.5 min, radius 10 | lit, 361.0 min |
| Air around the fire = heat formula | 528 tiles at each of 4 fuel levels, 0 off; 282 warmed at radius 10 (22 out of line of sight); radius 5 at 199 min, 2 at 100 and at 30 | 80 tiles, 0 off; 24 warmed (radius 3) |
| Radius at a fuel level | truncated, 46 of 46 readings (rounded would fit 18) | always 3 |
| Machine air = formula, readings filed | 42 h, 0.00000 °C; exact | 42 h, 0.00000 °C; exact |
| Warming one tile away | 10.9 to 29.8 °C above the outdoor air; lowest air 3.5 °C | 7.7 to 15.4 °C; lowest air 2.3 °C |
| Day temperature at the machine (outdoors −6.4, −8.5, −8.2 °C) | 14.51 and 13.32 °C before the trip, rate 0.4; 7.61 °C on 17 January. Derived: the rule's 3.0332 h at rate 0.4 puts midnight 7.58 h after the 29.11 h read, and the noted fuel ran out about 0.2 h before that, so the day began with the fire out until the return | 4.64, 3.54 and 0.82 °C: paused too cold 53.1 of 54.1 hours |
| Notes filed = harness's | **FAIL**: 44 hours, each "no fire" while the harness saw the campfire | 44 hours, all with the fire, 0 off |
| Hours away credited | **FAIL**: 0.00 h of 12.01 (the harness's last note, 397 min, covers 6.48 h) | 6.02 h, as the harness's (369 min) |
| Work over the trip = rule with the credit | **FAIL**: did 0.0000 h, the rule 3.0332 h: uncredited, 16 January fell below the 8 °C floor and the batch stopped | 0.0000 h, as the rule (too cold either way) |
| Day temperature after the trip | **FAIL**: 1.81 °C below the harness's at the first read back | exact |
| Burned while away | 388 → 0 min, one per minute event (721 in 721 game minutes) | 361 → 0 min, by game time |

Logs added by the harness besides the first: 9 on the campfire, 8 on the
barbecue. Neither fire was refed during the trip, so both were out on the
return. Not run: a campfire built indoors (radius up to 18), a propane
barbecue, a fire upstairs.

## 2026-11-01 — RT-SP client harness, launch 35 (the campfire after the fix)

Command: `tools/run-sp-harness.ps1 -Mode fires -TimeoutMinutes 60`, with
the fix of commit `7b4f31d`. The notes now recognise a lit campfire by its
permanent `IsoFire` and the "Campfire" object on its tile, whose mod data
holds the fuel. They note it with its largest radius, and the credit uses
the campfire's radius law (truncated). The mode is unchanged; same sites
and tiles as run 34, milder weather. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run35_fires_fix.txt`.

Result: **39 PASS / 0 FAIL**, run 34's four failures among them.

| Run 35 | Campfire | Barbecue |
| --- | --- | --- |
| Notes filed = harness's | 44 hours, all with the fire, 0 off | 44 hours, all with the fire, 0 off |
| Last note before leaving | 397 min, `k = "campfire"`, largest radius 10, as the harness's | 369 min, radius 3, as the harness's |
| Hours away credited | 6.48 h of 12.01, as the harness's | 6.02 h, as the harness's |
| Work over the trip = rule with the credit | 3.0312 h, exact (run 34: 0 h of 3.0332) | 0.0000 h, exact (too cold either way) |
| Day temperature before / after the trip | exact / exact | exact / exact |
| Machine air = formula, readings filed | 42 h, 0.00000 °C; exact | 42 h, 0.00000 °C; exact |
| Day temperature at the machine (outdoors 2.4, −1.5, −2.7 °C) | 16.32, 14.99 and 10.08 °C: working at rate 0.4 at the end | 7.51, 5.96 and 3.69 °C: paused too cold 53.1 of 54.1 hours |
| Burned while away | 388 → 0 min, 720 minute events in 721 game minutes | 361 → 0 min, by game time |

The air around both fires repeated run 34's figures (the campfire's 282 /
68 / 8 / 8 warmed tiles at its four fuel levels, none off). Its radius was
truncated in all 46 readings. Not run: a campfire built indoors, a
propane barbecue, a fire upstairs, multiplayer.

## 2026-11-01 — RT-SP client harness, launches 36–38 (the release zip installed clean, gate 12)

Command: `tools/rehearse-install.ps1` (new). It:

1. builds the package;
2. unpacks the zip into a fresh folder and checks every file against the
   SHA-256 manifest, both ways;
3. installs `Contents/mods/TheLastGallon` from it into a fresh, isolated
   cache (`%LOCALAPPDATA%\TheLastGallon\installcache`), as the player
   guide says, with the dev harness mod beside it;
4. runs the full harness: phase A, save, exit to the menu, continue,
   phase B.

With Steam off the game scans only `<cachedir>/mods` (BC), so this is the
manual install; the Workshop paths need Steam.

The zip itself was fixed first. `Compress-Archive` (Windows PowerShell
5.1) had written 91 of its 92 entry names with backslashes.
`tools/package.ps1` now writes forward slashes, sorted, every entry stamped
with the commit's time, and refuses a backslash. Two builds of commit
`a54f998` gave identical zips (SHA-256 `7410a9da…`, 201,414 bytes).

| Run | Mod | Phase A | Phase B |
| --- | --- | --- | --- |
| 36 | installed from the zip of commit `f956597` | 90 / 4 | 14 / 0 |
| 37 | the repository's, in the ordinary dev cache | 90 / 4 | 14 / 0 |
| 38 | installed from the zip of commit `2591370` (82 files, SHA-256 `b83e3aa9…`) | **94 / 0** | **14 / 0** |

Runs 36 and 37 failed the same four checks. None of the four machines
could be crafted from the craft menu: the recipes were listed and the
inputs, surface and range all found, yet the game's own check refused. The
package was not the cause, since the repository's mod failed identically.
The game's check needs light (BC `CraftRecipeData.consumeInputsInternal`,
`IsoPlayer.tooDarkToRead`). The harness's craft step now switches a torch
on in hand when it is too dark. In run 38 it logged a light level of 0.15
at the workbench at 10:37 game time (the threshold is 0.43). Run 12 had
crafted at the same bench, its light level not logged. Every other gate
of the check had passed in runs 36–37, so darkness is inferred for them,
not measured. With the torch all four machines were crafted from the
menu.

Everything else in run 38 matched run 12:
* the fuel chain, pumps, vehicles, generators and start gates;
* the ethanol loop and both conversions;
* after the save and reload, every record: cans, a vehicle tank, a
  generator, a pump, three machines, two conversions and the world record.

The run needed no input: the launcher's two clicks passed the two
loading screens. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run36_install_rehearsal.txt`,
`docs/evidence/2026-11-01_rt-sp_harness_run37_full_repository.txt`,
`docs/evidence/2026-11-01_rt-sp_harness_run38_install_rehearsal.txt`.

Not run: an install through the Steam Workshop (needs Steam), an upgrade
(there is no previous supported version), the packaged mod on a dedicated
server, unpacking on Linux or macOS.

## 2026-11-01 — RT-SP client harness, launches 39–40 (an existing save gains the mod, gate 7)

Command: `tools/rehearse-install.ps1 -Scenario existing` (new). The
release zip (SHA-256 `0c73ecb5…`, the final package) goes into a fresh
cache as in run 38, then two game launches:

1. **Without the mod.** Only the new dev driver `TheLastGallonPreInstall`
   is active; it does not require the mod, which never loads. It plays a
   debug scenario at the Muldraugh Gas2Go: a 10 L can of petrol carried,
   one on the ground, then 10 game days on the clock, and saves.
2. **With the mod.** The save's `mods.txt` now lists the mod and the
   harness, as the load screen's Choose mods writes it. The harness
   continues the save (phase B), then saves, exits to the menu and
   continues once more (phase C).

Fuel counts as found on the first contact that writes a record, so the
harness finds it the way a player's pour does. The can is poured from
(`FluidContainer.Transfer`, which the mod wraps), the pump through the
mod's own transfer. The harness notes the moment and computes the
expected condition from the policy's two ends, without the mod's
`WorldInit.baseline`. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run39_existing_launch1.txt` and
`_launch2.txt`, the same for run 40.

Run 40: launch 1 **3/0**, phase B **9/1**, phase C **3/0**. Run 39 hit a
harness error at the can on the ground: the game keeps a ground item's
fluid on the world object, and the harness read it from the item. So run
39 never recorded that can, and its phase C check of the can passed
vacuously ("none" before and after). The world-age figures vary by world
seed and item, since the pre-outbreak age is seeded (run 39: 0.127 for
the can, 0.560 for the pump).

| Run 40 | Result |
| --- | --- |
| The save continued | same world, world hour 242.04 after 10 game days |
| The mod's world record | created on this first load: existing save, policy transition, 30 days, installed at the load hour (242.0272), `newGame=false` in the mod's own log line |
| Sandbox options | the save took the mod's defaults (ExistingSavePolicy 1, TransitionDays 30); the load screen offers mods only |
| Carried can, first recorded at installation | condition 0.000013, exactly the rule; the world-age condition would have been 0.387 |
| Station pump, first recorded at installation | condition 0.000005, exactly the rule (world-age 0.079); water 34.86 L and sediment 11.54 L in 11,687 L. At 0.30 % water this is one of the one-in-ten contaminated stations (`docs/balance.md`); run 39 drew a clean one (4.85 L in 8,478 L, 0.06 %) |
| Can on the ground, first recorded 144.02 h after installation | condition 0.120482, exactly the rule: 20 % of the way from aged since installation (0.057) to the world-age condition (0.374) |
| After save, exit and continue | world record (seed, installed hour, policy), both cans' records and ids unchanged |
| **Look and smell, then What I know about it** | **FAIL**: the look answered ("Condition: Good"), but What I know about it said "Condition unknown: not sampled yet". The observation was filed under `S326600847-1`, an id the can never received |

The failure is a mod defect, the same in runs 39 and 40. A look reads the
fuel and allocates a record id without writing the record onto the can;
only transfers write it. In a world the mod has just joined, most fuel is
in that state.

Not run: the other two policies (no single-player screen sets them for an
existing save), a server, removing and re-adding the mod, late
exploration in a new world.

## 2026-11-01 — RT-SP client harness, launch 41 (a first look records the fuel, D-024)

Command: `tools/rehearse-install.ps1 -Scenario existing`, with the fix of
commit `1cf2240`: Look and smell on fuel the mod has not recorded writes
the fuel's record (its baseline, the record alone, never the fuel), so
the observation stays filed under the id the fuel carries. The zip of
that commit (82 files, SHA-256 `c5221a32…`) matched its manifest. The
look is now can A's first contact, so the harness computes its expected
condition from the moment of the look and checks that a later pour keeps
that record. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run41_existing_launch1.txt` and
`_launch2.txt`.

Result: launch 1 **3/0**, phase B **11/0**, phase C **3/0**, run 40's
failure among them.

| Run 41 | Result |
| --- | --- |
| Look and smell, then What I know about it | the look recorded the can as `S1160167558-1`, and What I know about it found the observation under that id |
| The can, first recorded by that look | condition 0.000010, exactly the transition rule at the look (world-age condition 0.241) |
| A pour after the look | the same record and id; the condition advanced from the look to the pour (0.000009956 → 0.000010016), 10 → 9 L |
| Pump, first recorded at installation | condition 0.000007, exactly the rule (world-age 0.209) |
| Can on the ground, first recorded 144.02 h after installation | condition 0.090830, exactly the rule at share 0.2 (aged since installation 0.063, world-age 0.201) |
| After save, exit and continue | world record and both cans' records unchanged |

Not run: a look with the sample kit (the same command past the kit
check; the unit tests cover only a refused one), a look at a vehicle,
pump or generator (no menu sends one), and what runs 39–40 left
untested.

## 2026-11-01 — RT-SP client harness, launch 42 (the final zip installed clean)

Command: `tools/rehearse-install.ps1`, as in run 38, now on the final
package. That is the zip of commit `6764990`, byte for byte the one
`5e22a15` built: 82 files, SHA-256 `d1a6f5e1…`. It matched its manifest.
Run 38 had used the zip of `2591370`, before D-024 changed five runtime
files. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run42_install_rehearsal.txt`.

Result: phase A **94/0**, phase B **14/0**, the same as runs 12 and 38.
* The workbench was dark again (light 0.15 at 10:31 game time); with the
  torch all four machines were crafted from the menu.
* The fuel chain, vehicles, generators, pumps, start gates, the ethanol
  loop and both conversions passed, through the endpoints D-024 changed.
* After the save and continue, every record came back: cans, a vehicle
  tank, a generator, a pump, three machines, two conversions and the
  world record.

## 2026-11-01 — RT-SP client harness, launches 43–44 (the client in Italian, gate 10)

Command: `tools/run-sp-harness.ps1 -Mode italian -TimeoutMinutes 20` (new
mode, request `sp-it`). The launcher sets `language=IT` and writes every
Italian string the deployed mod ships to `TLG_it_expect.txt` as ASCII
(`\uXXXX` for letters past ASCII). The harness decodes them and compares
each with what the game gives: `getText` for the menu, interface, fluid
and sandbox texts, an item's display name for each item id. It then fills
two placeholders and opens the Fuel menu on a petrol can and the machine
menu on a fermenter, with their Look and smell and Status dialogs.
Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run43_italian.txt`,
`docs/evidence/2026-11-01_rt-sp_harness_run44_italian.txt`.

Run 43 (4/1) matched 220 of 237. The 17 others were exactly the strings
with placeholders: the game stores `%1` as `%1$s`, which `getText`
without arguments returns. The harness now expects that form. Run 44:
**5 PASS / 0 FAIL**.

| Run 44 | Result |
| --- | --- |
| Language | `Translator.getLanguage()` = IT |
| Strings | 237 of 237 as shipped (menu 34, interface 169, fluids 8, items 9, sandbox 17); none unresolved, none garbled |
| Placeholders | "Carburante principale: Etanolo", "Condizioni: Buono (stima 0.1, più o meno 0.3)" |
| Fuel menu | "Carburante (The Last Gallon)" with its 7 entries in Italian; Look and smell: "Ispezione del carburante … Metodo: osservazione e odore (approssimativo)" |
| Machine menu | "Macchinario (The Last Gallon)" > "Stato": "Pronto … Temperatura qui adesso: 55.0 °F, all'aperto" |

Temperatures follow the game's unit option, not the language. Not
checked: how the fonts draw the accents (no screenshot was looked at),
the sandbox options screen itself, the workshop and crafting texts in
their own windows.

## 2026-11-01 — RT-SP client harness, launch 45 (stills and the drying column picked up, gate 6)

Command: `tools/run-sp-harness.ps1 -Mode still-pickup -TimeoutMinutes 40`
(new mode, request `sp-rts`). Summer with the grid on, room tiles around
the character. Two fermenters made two 33.3 L washes at full rate (6 kg of
sugar and 30 L of water each). The pot still was fed three logs and took
one wash. The drying column took 4 L of ethanol and 1 L of water from a
can, with 4 kg of quicklime. An hour later the reflux still was fed two
logs and took the other wash. Both fireboxes held more wood than their
batches burn.

Half an hour later all three were picked up:
* the pot still, distilling, with the world menu's Grab;
* the column with the loot window's Grab;
* the reflux still, still heating up, with the grab's own calls outside its
  Lua. This is how a multiplayer grab happens (run 27's D).

They were carried for two game hours, then put down:
* the pot still with the place action as the place cursor queues it
  (`isPlaceItem`, which requires a tile next to the character), onto a spent
  fermenter's tile;
* the other two with the inventory menu's Drop.

Every time the checks use comes from the records themselves (a move hook
sets `t` to the moment of the move). Every expectation comes from the
definitions. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run45_still_pickup.txt`.

Result: **41 PASS / 0 FAIL**. The console showed "machine move hooks
installed" and no TLG error or warning. The run took about 5 minutes.

| Run 45 | Result |
| --- | --- |
| At pickup | the pot still had counted to that moment: 1.517303 h of work for 1.517303 h placed, distilling, with 22.183164 kg of wood left (what those hours burn). The column had 1.531364 h for 1.531364 h. Both were Paused, "it was picked up", and left the hourly list at once |
| The reflux still, grabbed unseen | record untouched; it stayed listed until the next hourly reading, which dropped it |
| Carried | the menu offered only Status and "Place it on the ground to operate it" (greyed). Status read "Paused, Reason: it was picked up; place it to continue, Stage: distilling, Firebox: 22.2 kg of wood". Over 2.0001 game h nothing changed on any of the three: work, wood, paused hours, readings and notes |
| Put down | the pot still and the column were Processing from the put-down, with the work and wood they had, listed at their new tiles. The reflux still was found moved and credited up to the last time the mod had found it placed, 0.1535 h before the grab: 0.377846 h of work, still heating up, 17.018582 kg of wood left. Then it was Processing |
| Pot still | done 7.178232 h after loading: its 5.1625 stage hours plus 2.015732 h carried. 10.611111 kg of wood left = 27 − 5.1625 × 3.174603. 2.904 L ethanol, 0.726 L water; paused 0 h |
| Reflux still | done 5.933020 h after loading: 3.775 stage hours plus the 2.158020 h from when it was last found to the put-down. 8.194805 kg left = 18 − 3.775 × 2.597403. 3.036 L ethanol, 0.193787 L water; paused 0 h |
| Drying column | done 14.003166 h after loading: 12 stage hours plus 2.003166 h carried. 3.999968 L ethanol, 0.020000 L water |
| Collected | each machine's output into an empty can of its own, matching to 1e-3 L; every machine then Ready |

Completion times, wood and spirit all matched to 1e-6. For the unseen
grab, the reflux still lost the 0.1535 h between the mod's last
ten-minute note and the grab. That is the shortfall D-015 accepts when no
Lua sees a grab.

Not run:
* a move in multiplayer itself;
* a carried machine across a save;
* a still picked up after its wood ran out.

Found by reading the code, not run: on a carried machine the authority
refuses "Load mash and start fermenting", "Load wash from a nearby
fermenter" and "Dry ethanol with quicklime" (`not_placed`). It accepts
"Feed the firebox", "Collect ethanol into a fuel can", "Abort batch" and
"Resume", which the menu hides while the machine is carried. Fixed: they
are refused since commit `f5c7b25` (run 46).

## 2026-11-01 — RT-SP client harness, launch 46 (a carried machine answers Status only)

Command: `tools/run-sp-harness.ps1 -Mode still-pickup -TimeoutMinutes 40`,
with the fix of commit `f5c7b25`. Run 45's reading of the handlers found
that the authority took Feed the firebox, Collect, Pause, Resume and Abort
batch on a carried machine, though the menu hides them. Those five now
return `not_placed`, as the loads did. While the pot still and the column
were carried, the mode now sends each of the five as a request: Feed the
firebox, Collect and Pause to the pot still, Resume and Abort batch to the
column. A log and an empty can were carried, so nothing but the placement
could refuse them. The rest of the mode is run 45's. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run46_still_pickup_refusals.txt`.

Result: **46 PASS / 0 FAIL** (the console showed "machine move hooks
installed" and no TLG error or warning).

| Run 46 | Result |
| --- | --- |
| The five commands while carried | each refused with `not_placed`, the dialog "Place it on the ground first.", the record untouched |
| The rest (run 45's 41 checks) | all passed again with the same figures: work at pickup equal to the hours placed (1.517288 h and 1.531342 h); the unseen grab credited up to 0.1535 h before it; the pot still done its 5.1625 stage hours after the put-down with 10.611111 kg of wood left; the reflux still its 3.775 h with 8.194805 kg; the column its 12 h; the definitions' spirit to 1e-6; every can as collected |

The domain tests (`tests/authority/test_machine_commands.lua`, 3 cases)
cover the case the run does not stage. With the old handler, a Resume
sent for a carried still was taken, and once the still went back down on
its own tile the batch counted 4 h of work for 2 h placed. Two of the
three cases fail against the old handler (the third, a placed still
taking the same commands, is the control); all three pass with the fix.

## 2026-11-01 — RT-SP client harness, launch 47 (the rebuilt zip installed clean)

Command: `tools/rehearse-install.ps1 -NoBuild`, on the zip in `dist/`. That
is the package of commit `21ef95c`: 82 files, SHA-256 `b608f4c5…`, 203,050
bytes. It has the fix that has a carried machine answer Status only. It
differs from run 42's zip (`d1a6f5e1…`) in three files:
`MachineHandlers.lua`, the player guide and the changelog. The zip matched
its manifest (82 files), was installed into a fresh isolated cache and ran
the full harness. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run47_install_rehearsal.txt`.

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38 and 42.
* The workbench was dark again (light 0.15 at 10.59 game time); with the
  torch in hand all four machines were crafted from the menu.
* After the save and continue, every record came back.
* The console showed "machine move hooks installed" on both loads and no
  TLG error or warning. Its four Lua error dumps are the dev harness's own
  runtime probe, a deliberate deep recursion (`LuaProbe.lua`); no stack
  frame names the mod.

## 2026-11-01 — RT-SP client harness, launch 48 (stills and the drying column carried across a save, gate 6)

Command: `tools/run-sp-harness.ps1 -Mode still-save -TimeoutMinutes 40`
(new mode, requests `sp-rtss`, then `sp-rtsb`). Phase 1 was the still
pickup run up to one game hour after the pickups, with the same three
pickup paths. Then, with the pot still, the reflux still (grabbed unseen)
and the column all carried, it wrote their records to the expectations
file, saved and exited to the menu. Phase 2 continued the save and
checked, before any access, that:
* the three were still in the inventory;
* their records were exactly as saved (every field to three levels,
  numbers exact);
* the hourly list was as it had been.
The run then carried them another hour and went on with run 45's
put-downs and every check after them. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run48_still_save.txt`.

Result: phase 1 **29 PASS / 0 FAIL**, phase 2 **24 PASS / 0 FAIL**. The
launcher sent the two click-to-start clicks, and the console showed
"machine move hooks installed" on both loads, with no TLG error or
warning and no Lua error.

| Run 48 | Result |
| --- | --- |
| Before the save | as in run 45: the pickups counted the placed hours (1.517288 h and 1.531349 h); the five commands were refused; nothing advanced over 1.0025 game h carried. Saved at world hour 103.8263, none of the three on the hourly list |
| Continued | at world hour 103.8495, the character on the tile it was left on. All three were still in the inventory, off the ground, and their records were exactly as saved. The hourly list was as saved (none listed) |
| The pot still after the continue | the menu offered only Status and "Place it on the ground to operate it" (greyed). Status read "Paused, Reason: it was picked up; place it to continue, Stage: distilling, Firebox: 22.2 kg of wood" |
| Another hour carried | nothing advanced on any of the three over 2.0035 game h carried in all |
| Put down | the pot still and the column Processing from the put-down with the work and wood they had. The reflux still was credited up to the last time it was found placed, 0.1535 h before the grab (0.377846 h, 17.018582 kg of wood left) |
| Finished | each at its due time to 1e-6: the pot still with 10.611111 kg of wood left, the reflux still with 8.194805 kg, the column after its 12 stage hours. Spirit as the definitions give it, each collected into its own can |

The hours carried span both sides of the save. The continue step first
read world hour 103.8495, 0.0232 h after the hour of the save. The
carried time is the game hours from pickup to put-down, and none of it
counted. Not run: a move in multiplayer itself.

## 2026-11-01 — RT-SP client harness, launch 49 (Pause, Resume and Abort batch on running stills, gate 1)

Command: `tools/run-sp-harness.ps1 -Mode still-controls -TimeoutMinutes 40`
(new mode, request `sp-rtsc`). The still pickup run's sites and washes
(33.3 L each): the pot still fed three logs, the reflux still two, both
loaded in the same tick. Everything was pressed from the machine menu:
* The pot still was paused half an hour in, while heating up, held three
  game hours and resumed.
* The reflux still was aborted two hours in, an hour into distilling, and
  what it kept was collected into a can.

The player guide says Abort batch "keeps what it made so far: … a still's
spirit". The check `RTSC.design_abort_keeps_only_what_it_distilled` holds
the kept spirit to what the distilling stage has made, since nothing
distils while heating up. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run49_still_controls.txt`.

Result: **27 PASS / 1 FAIL**. The console showed "machine move hooks
installed" and no TLG or Lua error.

| Run 49 | Result |
| --- | --- |
| Menu | running: Pause and Abort batch; paused by hand: Resume and Abort batch; stopped early: Abort batch only. Pause again was refused ("It is not working on a batch right now."), and so was Resume again ("It is not paused."), each record unchanged |
| Pause, heating up | 0.502914 h done; 25.403446 kg of wood left, what those hours burn. Status read "Paused, Reason: paused by hand, Stage: heating up" |
| Held 3.007393 h | no work and no wood burned; paused hours 3.007393 |
| Resumed | done 8.169893 h after loading = 5.1625 stage hours + 3.007393 h paused, to 1e-6; 10.611111 kg of wood left = 27 − 5.1625 × 3.174603; 2.904 L ethanol and 0.726 L water as defined; collected |
| Abort, 2.006729 h in | "Batch stopped. Stopped early: what it made is ready to collect … Ethanol: 1.61, Water: 0.10, Thrown away: Ethanol 1.55, Stillage 15.98, Water 14.05". Kept and thrown away add up to the 33.3 L wash; 12.787717 kg of wood kept, what was not burned; the kept spirit went into a can and the still was empty |
| **Design: kept spirit** | **FAIL**: 1.613889 L of ethanol kept. Its 1.006729 h of distilling (of 2.775 h) had made 1.101416 L. The amount kept is the share of all stage hours done, the heating-up hour included |

Run 49's failure was a mod defect, fixed in commit `1cb67b7` (runs
50–51). `Process.abort` kept `done / total` of the batch's result,
counting every stage, so it kept spirit for the heating-up hour, when
nothing distils. Aborted mid-way through heating up, a still would have
handed out spirit it never made. The fix had two constraints:
1. The same rule credits a fermenter's 1 h prepare stage (1/97 of its
   ethanol). Run 33's `RT.C.wash(done)` expects `done / 97`, so a fix
   changes that expectation too; run 33's evidence stays as it was.
2. Recipes are snapshotted into running batches ("recipe updates never
   reinterpret an active batch"). A new stage flag in the definitions
   would not reach batches already running, so the rule may belong in
   `Process.abort` itself.

## 2026-11-01 — RT-SP client harness, launches 50–51 (Abort after the fix)

With the fix of commit `1cb67b7`, recipes mark the stages that make their
result (`makes`: fermenting, distilling, drying), and Abort keeps the
share done of those. Before, every stage counted, the heat-up and
preparing hours included. The controls mode now expects a fermenter's
wash at `(done − 1) / 96`. Evidence:
`docs/evidence/2026-11-01_rt-sp_harness_run50_still_controls_fix.txt`,
`docs/evidence/2026-11-01_rt-sp_harness_run51_controls_fix.txt`.

Result: run 50 (`-Mode still-controls`) **28 PASS / 0 FAIL**; run 51
(`-Mode controls`) **32 PASS / 0 FAIL**. Both consoles showed "machine
move hooks installed" and no TLG or Lua error.

| Runs 50–51 | Result |
| --- | --- |
| Reflux still aborted 2.003639 h in | kept 1.098036 L of ethanol and 0.070087 L of water: exactly what its 1.003639 h of distilling made (the old rule would have kept 1.611404 L). Thrown away: 2.11 L of ethanol, 10.88 of stillage, 19.15 of water, the whole 33.3 L wash accounted for; the kept spirit collected |
| Pot still paused 3.000252 h while heating up | as in run 49: finished at its stage hours plus exactly the pause, 10.611111 kg of wood left, the defined spirit |
| Fermenter F2 aborted 5 h in | kept 0.137513 L of ethanol (4 of its 96 fermenting hours), 5.749976 kg of sugar and 30 L of water, the preparing hour making none; the pot still took that wash |
| The rest of run 33's checks | all passed again: Pause, Resume and Abort on F1, the drying column's ethanol kept and collected, the spoiled F3 emptied and loaded again |

## 2026-11-01 — RT-SP client harness, launch 52 (the zip with the Abort fix installed clean)

Command: `tools/rehearse-install.ps1 -NoBuild`, on the zip in `dist/`. That
is the package of commit `8b2435c`: 82 files, SHA-256 `75873ed3…`, 203,579
bytes, with the carried-machine and Abort fixes. It differs from run 47's
zip (`b608f4c5…`) in four files: `Process.lua`, `Production.lua`, the
player guide and the changelog. The zip matched its manifest (82 files),
was installed into a fresh isolated cache and ran the full harness.
Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run52_install_rehearsal.txt`.

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42 and
47.
* The workbench was dark (light 0.15 at 10.59 game time); with the torch
  in hand all four machines were crafted from the menu.
* After the save and continue, every record came back.
* The console showed "machine move hooks installed" on both loads and no
  TLG error or warning. Its four Lua error dumps are the harness's own
  deliberate deep recursion (`LuaProbe.lua`); no stack frame names the
  mod.

## 2026-11-01 — RT-SP client harness, launch 53 (fuel first found late in a new world, gate 7)

Command: `tools/run-sp-harness.ps1 -Mode late-find -TimeoutMinutes 40`
(new mode, request `sp-rtn`). This is a new world with the mod from the
start. Under its world record's policy, fuel the mod has no record of is
aged from world hour 0, plus a pre-outbreak age drawn per container (up
to 30 days for cans, 75 for station tanks).
* At the start, two 10 L cans of petrol were set on the ground. One was
  recorded at once by a pour; the other, and the pump nearest the start,
  were left alone.
* 7 game days later the second can (a pour) and the pump (the mod's own
  transfer) were found.
* Each first record was compared with Aging.advance over the whole span
  (the world-age end of run 40's `RT.X.expected`), not with
  WorldInit.baseline.
* The can found at the start was read again and compared with the same
  one-span calculation.

Evidence: `docs/evidence/2026-11-01_rt-sp_harness_run53_late_find.txt`.

Result: **7 PASS / 0 FAIL**. The console showed "world fuel history
created: policy=new_world … newGame=true" and no TLG or Lua error.

| Run 53 | Result |
| --- | --- |
| World record | a new game's: policy `new_world`, epoch 0, created at world hour 2 |
| At the start | neither can nor the pump had a record. The can found then: condition 0.065620276, the world-age rule exactly (without its pre-outbreak age it would be 0.000976) |
| Second can, found at world hour 170.0168 | no record until then. Condition 0.289550901, the world-age rule exactly (0.071608 from hour 0 alone) |
| Pump, found at world hour 170.0173 | untouched until then. Condition 0.061899812, the world-age rule exactly for a station tank (0.046694 from hour 0 alone), with its station water 29.8073 L and sediment 6.4290 L |
| Can found at the start, read again | 0.138107973; the one-span calculation gives 0.136948851, 0.85 % less (bound 1 %) |

Found late or found early, fuel carries the age of the whole world, so
waiting to find it gains nothing. The 0.85 % is the climate model's
documented day rule (`Climate.lua`). The model's day 0 runs from the
calendar midnight before world start. A record taken at hour 2 aged that
day's hours, the pre-outbreak ones included, at the mean of the readings
taken so far. The record is not redone after midnight, while the
one-span calculation uses the day's final mean. The size depends on how
far the early readings sat from the day's mean, which was not measured.
Not run: the other two existing-save policies, a server, removing and
re-adding the mod.
