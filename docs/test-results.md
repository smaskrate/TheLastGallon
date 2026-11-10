# Test results

Each entry gives the date, the build, the command, the outcome and what was
not run at the time. Domain tests run with `tools/run-tests.ps1` on the
game's Kahlua VM. RT-DS is the isolated dedicated server harness; RT-SP
(single player) and RT-MP (a dedicated server with clients) are the client
runtime tests.

## Not run (standing list)

| Area | Reason |
| --- | --- |
| RT-SP: **Pour into the station reservoir**; driving another chassis, a converted car or off-road (a standard car is driven on the road: launches 174–176) | Not in the harness yet |
| RT-SP: the workshop menu's **Cancel the project** and **Remove the conversion** (**Project status**: launches 211–212); the sandbox options screen and the workshop and crafting windows in Italian (every shipped Italian string comes back from the game as shipped: launches 44, 194 and 205) | Not in the harness yet |
| RT-SP: walking away from the conversion work (the harness moves the character away: launches 9 and 12); cancelling or removing a conversion; two workers at once | Not in the harness yet |
| RT-MP: a real network | Needs a second machine, so it stays NOT RUN (decided 2026-11-03). Every other multiplayer test runs on this machine (all RT-MP launches, 136–210; two clients from launch 139) |
| RT-MP: a still or drying column picked up while working; a crate as such (launch 167 used a bin, the nearest container); driving on poor fuel (the engine effects while idling: launch 188); a successor after a death (single player: launches 199 and 202; the death itself on a server: launches 209–210); a climb's drop (the same watch as a death on a server, launch 210) | Not in the multiplayer harness yet |
| Performance with several clients sharing storage, and on other machines | The performance mode runs single player on the reference machine (launches 181–182, `performance.md`); the server's timers were timed with one client (launch 189). Electrical networks are not built in game in this build |
| Upgrade from an earlier release; install through the Steam Workshop; the Workshop uploader's own checks (preview, folders, file types) | The rehearsal has no upgrade scenario (0.1.1 to 0.1.2 changed only the version values and `mod.info`). The game scans Workshop folders only in Steam mode; the zip's manual install is rehearsed (`release-checklist.md` gate 12). Uploading is the owner's manual step: 0.1.1 was uploaded on 2026-11-08, 0.1.2 has not been |

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
* Result: the client booted, passed the terms screen and played the intro
  videos, then made no progress for 7 minutes. The Windows session was
  locked (`LogonUI.exe`), so the window could not render. The client was
  stopped by hand: **no client evidence**. All RT-SP checks remain NOT RUN.

## 2026-10-30 — Domain + authority + production suites

* Command: `tools/run-tests.ps1` → `modules=8 cases=61 passed=61 failed=0`.
* Compile check (package + harness): `compiled=54 errors=0`.
* Bugs found and fixed while writing the tests: the transition policy
  applied the pre-outbreak age at install time (fresh was expected);
  BOM-prefixed files from PowerShell broke Kahlua compilation.

## 2026-10-30 — RT-DS harness boot 3 (container adapter)

* Command: `tools/dev-server-controller.ps1` + `tools/stop-dev-server.ps1`
* Evidence: [2026-10-30_rt-ds_harness_boot3.txt](evidence/2026-10-30_rt-ds_harness_boot3.txt)
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
  gates, UI menus, crafting recipes. All of them need a client session,
  and the desktop stayed locked for the whole session.

## 2026-10-30 — RT-DS harness boot 4 (scripts)

* Evidence: [2026-10-30_rt-ds_harness_boot4.txt](evidence/2026-10-30_rt-ds_harness_boot4.txt)
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

* Evidence: [2026-10-30_rt-ds_harness_boot5.txt](evidence/2026-10-30_rt-ds_harness_boot5.txt)
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
* Launch 3 ([2026-10-31_rt-sp_harness_run3_phaseA.txt](evidence/2026-10-31_rt-sp_harness_run3_phaseA.txt)):
  phase A 41 PASS / 5 FAIL; phase B never ran (the world's `mods.txt` was
  empty, then the 20-minute watchdog stopped the client). All 5 failures were
  harness placement (pump → vehicle, second generator).
* Launch 4 ([2026-10-31_rt-sp_harness_run4.txt](evidence/2026-10-31_rt-sp_harness_run4.txt)):
  phase A 42 PASS / 1 FAIL (the TLG pour target generator was nearly full:
  0.015 L moved, conserved); phase B 9 PASS / 1 FAIL: a can on the ground
  came back without an item FluidContainer, which exposed the
  container-ownership defect (fixed, see engine-capabilities G02).
* Launch 5 ([2026-10-31_rt-sp_harness_run5.txt](evidence/2026-10-31_rt-sp_harness_run5.txt)):
  phase A **47 PASS / 0 FAIL**; phase B 9 PASS / 2 FAIL. The two failures
  are harness lookups that matched the neighbouring vehicle and generator.
  The records they found were equal to the phase A records of those
  objects, to the four decimals logged. Lookups now match by record id
  (not re-run).

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

Evidence: [2026-10-31_rt-sp_harness_run6.txt](evidence/2026-10-31_rt-sp_harness_run6.txt).
Phase A **63 PASS / 0 FAIL**, phase B **11 PASS / 0 FAIL**; launcher exit
code 0.

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

Finding (balance, not a code defect; changed by D-017 below): station water
was drawn from 0–0.4 % while the stock engine tolerates 0.2 %, so about half
of all stations dispense fuel that halves a stock car's start chance from
the first day.

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

Evidence: [2026-10-31_rt-sp_harness_run7.txt](evidence/2026-10-31_rt-sp_harness_run7.txt).
Phase A **74 PASS / 8 FAIL**, phase B **12 PASS / 2 FAIL**; launcher exit
code 0.

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

Evidence: [2026-10-31_rt-sp_harness_run8.txt](evidence/2026-10-31_rt-sp_harness_run8.txt).
Phase A **82 PASS / 0 FAIL**, phase B **14 PASS / 0 FAIL**; launcher exit
code 0. Same time fixture as launch 7; commands sent directly, not through
the menus.

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

Evidence: [2026-10-31_rt-sp_harness_run9.txt](evidence/2026-10-31_rt-sp_harness_run9.txt).
Phase A **83 PASS / 0 FAIL**, phase B **14 PASS / 0 FAIL**; launcher exit
code 0; no TLG error or TLG stack frame in the console.

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

Launch 10 ([2026-10-31_rt-sp_harness_run10.txt](evidence/2026-10-31_rt-sp_harness_run10.txt)),
phase A **76/15**, phase B 12/2: all 7 recipes listed; the mash took 30 L of
the 32 L carried; every menu dialog translated; the refused start showed "A
tool is missing: - Wrench". Failures: every craft `canPerform=false`; the
split into a second can moved nothing; both work actions went quiet after
their first report; the rest followed from these.

Launch 11 ([2026-10-31_rt-sp_harness_run11.txt](evidence/2026-10-31_rt-sp_harness_run11.txt)),
phase A **80/11**, phase B 12/2, with load and action logging. Found:

* The harness carried everything at once (57.7 kg, `hasFullInventory`
  true). Vanilla then refuses a can-to-can transfer (BC
  `FluidContainer.CanTransfer`) and drops crafted outputs on the floor
  (`Actions.addOrDropItem`), which the check did not see: the crafts did
  work. Harness changed to hand materials over per step.
* Pots and jars were not consumed by crafting: container inputs are kept
  unless the recipe says `mode:destroy` (vanilla pasta/rice recipes). Fixed.
* The work action made one good report. Vanilla's action queue then
  dropped it while it kept running in Java. Its progress call
  `setJobDelta` sets `currentTime = maxTime × delta` (BC `BaseAction`),
  which is negative for an open-ended action, and the queue's `tick()` then
  treats it as stalled (`hasStalled`). The queue looked idle while the
  character worked. Progress bar removed. Run 9 never looked at the queue,
  so it did not show there.

Launch 12 ([2026-10-31_rt-sp_harness_run12.txt](evidence/2026-10-31_rt-sp_harness_run12.txt)):
phase A **94 PASS / 0 FAIL**, phase B **14 PASS / 0 FAIL**; launcher exit
code 0; no TLG error, TLG stack frame or queue warning in the console.

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
  area before working. The character was moved away after 2 h: the action
  stopped, and 3 h away earned nothing. At 6 h the screwdriver was taken,
  and the next report ended the action with "A tool is missing: -
  Screwdriver" and no credit. The third session reached `Commissioned`
  with 13 h credited.
* Pours, generator start, car start (first attempt) and phase B as in
  launch 8.

Not run: see the standing list.

## 2026-10-31 — RT-SP client harness, launch 13 (real game clock)

Command: `tools/run-sp-harness.ps1 -Mode realtime -TimeoutMinutes 60` (request
`sp-rt`: the same scenario, only the ethanol loop, no mod-clock offset, no
reload). Evidence:
[2026-10-31_rt-sp_harness_run13_realtime.txt](evidence/2026-10-31_rt-sp_harness_run13_realtime.txt).
**10 PASS / 1 FAIL**; launcher exit code 0; no TLG error, TLG stack frame or
queue warning in the console.

Time ran on the game clock, 2.0 → 138.2 world hours. Machines waited at a
debug multiplier, `GameTime.setMultiplier(100)`, the call the debug panel's
Game Speed slider makes (measured 2.22 game hours per 300 ticks). The
conversion work ran at vanilla's fastest speed, x40 (measured true
multiplier 40.0); walking and teleports ran at x1. The character was
invulnerable, invisible and kept fed.

* Fermentation (menu, 6 kg sugar, 30 L water) finished after 97.2 game
  hours: 97 h at full rate. Outdoor temperature ranged 10.9–28.0 °C; the
  climate model uses daily means and the fermenter's "sheltered" profile, so
  July never slowed it.
* Chunk unload (G12): 12 hours in, the character was moved 400 tiles away;
  the machines' square was no longer loaded. Back after 24 game hours, the
  fermenter had done 24.02 h more work. The check compared that with the
  time to the return teleport (24.01 h, logged). The status read came 120
  settling ticks later (about 0.01 game h at x1, not logged), so the check
  failed by its own bound. The bound was changed to the time between the
  two reads, and the run repeated as launch 14.
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
Evidence: [2026-10-31_rt-sp_harness_run14_realtime.txt](evidence/2026-10-31_rt-sp_harness_run14_realtime.txt).
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
compared with the stage rules of `ethanol_ferment`: full rate 18–32 °C, 0.4
between 8 and 18 °C, paused below 8 °C, spoiled after 72 h paused. The rules
are applied to the day temperature TLG had recorded, sheltered as the
climate model does: (mean + 16) / 2.

Launch 15 ([2026-10-31_rt-sp_harness_run15_winter.txt](evidence/2026-10-31_rt-sp_harness_run15_winter.txt)),
**5 PASS / 0 FAIL**. Every day recorded 0.5–0.6 °C, so the fermenter sat at
8.3 °C and ran at 0.4 (9.63 h of work per 24 h): finished after 241.7 game
hours (97 at full rate); 229 hours compared, all exact. No day stalled.
Finding: the constant value is the season curve. `getDayMeanTemperature()`
returns `currentDay.season.getDayMeanTemperature()` (BC
`ClimateManager`); the weather is in `getTemperature()`. Machines and fuel
ageing had never seen a cold snap or a heat wave. Fixed:
`World.recordClimate` now records the running mean of the hourly air
temperature (D-020).

Launch 16 ([2026-10-31_rt-sp_harness_run16_winter.txt](evidence/2026-10-31_rt-sp_harness_run16_winter.txt)),
**8 PASS / 0 FAIL**, console clean, with the fix:

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

* outdoors (10618,10627);
* in a room (10619,10628);
* in a room on a tile with an `IsoHeatSource` of radius 1 and 35 °C added
  from Lua (10618,10628).

Every game hour the harness read the game's air at the three tiles. Before
each status read it compared the readings the mod had filed with its own.
After the read it compared the day temperature the status reported with
`siteDayMean` over the harness's readings, and the work done with the
stage rule fed by that temperature. A 12 game hour trip of 400 tiles on
day 2 unloaded the tiles. Evidence:
[2026-10-31_rt-sp_harness_run17_sites.txt](evidence/2026-10-31_rt-sp_harness_run17_sites.txt),
[2026-10-31_rt-sp_harness_run18_sites.txt](evidence/2026-10-31_rt-sp_harness_run18_sites.txt),
[2026-10-31_rt-sp_harness_run19_sites.txt](evidence/2026-10-31_rt-sp_harness_run19_sites.txt).

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
batch through these Januaries; the warmed tile did. A Status read, for
example: "Paused · Reason: too cold here · Stage: fermenting · Temperature
here today: 45.3 °F, in a room" (this dev cache shows °F; the log holds a
UTF-8 "°").

Found and fixed:

* Run 17: the warmed fermenter paused after every midnight until the new
  day's first reading was filed (7.28 paused hours in all). The hour in
  progress now takes the previous hour's reading (`Climate.siteDayMean`);
  in runs 18–19 its only pauses were the 5.26 hours of a morning spent
  unloaded, and no read was paused on a day read throughout.
* Run 18: right after midnight the status still showed the unheated value
  (3.28 °C): the access pruned yesterday's last reading before the status
  used it. `Machines.trimTemps` now keeps that hour; run 19 was exact.

Not run: upper floors, a real fire, fireplace or barbecue (the heat source
was added from Lua; the vanilla objects register the same kind, BC), the
grid on, a player-built room, a machine moved between two accesses. (A
fireplace of the map: see launches 20–21.)

## 2026-11-01 — RT-SP client harness, launches 20–21 (a fireplace of the map)

Command: `tools/run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60`
(request `sp-rtf`, new). The same January world with the grid off. The
harness:

1. looks for a working fireplace of the map;
2. lights it with a log through the calls the vanilla actions make
   (`addFuel`, `turnOn`, `sendObjectChange`; the actions and their menu
   were not used);
3. compares the air on every floor tile within 9 of it with the heat
   formula, unlit and at four fuel levels (set as vanilla's
   `fireplace.setFuel` command does);
4. runs one fermentation (6 kg of sugar, 30 L of water) on a room tile
   beside it.

Meanwhile it tends the fire as a player can: a log adds 360 minutes and
only goes in once it fits under the 480 minute cap. It also makes the
winter run's checks of readings, day temperature, work and a 12 game hour
trip. Evidence:
[2026-11-01_rt-sp_harness_run20_fireplace_search.txt](evidence/2026-11-01_rt-sp_harness_run20_fireplace_search.txt),
[2026-11-01_rt-sp_harness_run21_fireplace.txt](evidence/2026-11-01_rt-sp_harness_run21_fireplace.txt).

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
all: the day stood at 7.8 °C and the batch paused (the 5.36 h). The
harness's day line for 17 January shows 12.91 h paused: when a read finds
the batch paused, the harness counts the whole interval since the previous
read as paused. The mod's own `pausedFor` is 5.36 h. Even with the fire lit
again, the day's mean then stayed below 18 °C for about 11 hours (0.4 rate;
14.6 °C at 48 h in). This is the day-mean rule of D-020 and D-021 at work,
matched exactly by the harness.

During the absence the fire burned its 365 minutes, in one step on the
reload, and was out on the return (vanilla, BC `IsoFireplace.update`).
Status read "Working · Stage: fermenting · Temperature here today: 72.0 °F,
in a room".

Not run: a fire (`IsoFire`) or barbecue beside a machine, the fireplace's
menu and timed actions, a fireplace upstairs.

Run 22 repeated the winter mode (launches 17–19) once its status,
filed-reading and trip helpers served both scenarios. It gave **25 PASS /
0 FAIL**, as run 19: the room formula exact over 94 hours; readings, day
temperatures and work exact; outdoors and the room spoiled at 72.00 paused
hours; the warmed batch finished with 5.26 h paused. Evidence:
[2026-11-01_rt-sp_harness_run22_sites.txt](evidence/2026-11-01_rt-sp_harness_run22_sites.txt).

## 2026-11-01 — RT-SP client harness, launch 23 (a fire's fuel counts while away, D-022)

Command: `tools/run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60`,
with D-022 in the mod and the harness; the same fireplace and tile as
run 21. Every ten game minutes the harness took its own note of the fire
warming the fermenter, at the same ticks as the mod, and compared the two.
It fed the fire a quarter hour before the trip (379 minutes left, so no log
fitted) and checked the work over the trip against the stage rule fed by
the credited day temperatures. Evidence:
[2026-11-01_rt-sp_harness_run23_fire_credit.txt](evidence/2026-11-01_rt-sp_harness_run23_fire_credit.txt).

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
Evidence: [2026-11-01_rt-sp_harness_run24_sites.txt](evidence/2026-11-01_rt-sp_harness_run24_sites.txt).

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
[2026-11-01_rt-sp_harness_run25_fire_reload.txt](evidence/2026-11-01_rt-sp_harness_run25_fire_reload.txt).

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
[2026-11-01_rt-sp_harness_run26_pickup.txt](evidence/2026-11-01_rt-sp_harness_run26_pickup.txt).

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
cannot tell the hours placed from the hours carried. A Status while carried
drops every hour since the last use; without one, every hour counts.

With the grid on, the four readings compared were 22.0000 °C, and Status
gave 71.6 °F (22 °C) as the day temperature at all three tiles, as the room
formula says (its first check in game with power).

Not run: a still or drying column picked up, a move in multiplayer, a
carried machine across a save.

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
[2026-11-01_rt-sp_harness_run27_pickup_fix.txt](evidence/2026-11-01_rt-sp_harness_run27_pickup_fix.txt).

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
Both runs went into one fuel can. The can was evaluated against every
spark-ignition profile with `Consumers.evaluate`, the function the vehicle
and generator start gates call; it was then dried with quicklime and
evaluated again. Expectations come from the definitions in
`Content/Production.lua`. Evidence:
[2026-11-01_rt-sp_harness_run28_pot_still.txt](evidence/2026-11-01_rt-sp_harness_run28_pot_still.txt).

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
[2026-11-01_rt-sp_harness_run29_pot_still_status.txt](evidence/2026-11-01_rt-sp_harness_run29_pot_still_status.txt).

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
the machine menu.

* F1 was paused 5 h in, resumed 6 h later and read 4 h after; Pause,
  Resume and Abort were also pressed where they do not apply.
* F2 was aborted 5 h in and loaded again.
* The drying column, loaded from a can of 4 L ethanol and 1 L water with
  4 kg quicklime, was aborted 6 h in.
* F3 was paused 5 h in and left; once spoiled, Abort and Load mash were
  tried on it.

The four `RTC.design_` checks hold Abort to its handler's own description
("returns the partial result to the player ... discarded and listed") and
to `Process.abort`'s ("an abort never loses material"), and a spoiled batch
to a way out from the menu. The still was left out: it shares the abort
handler, and the domain tests pin its firebox and litres. Evidence:
[2026-11-01_rt-sp_harness_run31_controls.txt](evidence/2026-11-01_rt-sp_harness_run31_controls.txt).

Run 30 (19 PASS / 5 FAIL) filled the column's can with vanilla water, which
never went into the can. The fluid the mod reads as water in fuel is its
own, `TLG_FuelWater`; had the game's water been there, the menu would have
greyed the entry as a can with something else in it. The load saw only
ethanol and refused it as already dry, so the column's four checks meant
nothing. Run 31 used the mod's fuel water. Evidence:
[2026-11-01_rt-sp_harness_run30_controls_setup.txt](evidence/2026-11-01_rt-sp_harness_run30_controls_setup.txt).

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
[2026-11-01_rt-sp_harness_run33_controls_fix.txt](evidence/2026-11-01_rt-sp_harness_run33_controls_fix.txt).

Run 32 (29 PASS / 3 FAIL) still pressed Pause, Resume and Abort from the
menu where they no longer appear, and found no entry; the menu was doing
its job. Run 33 sends those presses as a menu deciding on a stale copy of
the record would. Evidence:
[2026-11-01_rt-sp_harness_run32_controls_fix.txt](evidence/2026-11-01_rt-sp_harness_run32_controls_fix.txt).

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
[2026-11-01_rt-sp_harness_run34_fires.txt](evidence/2026-11-01_rt-sp_harness_run34_fires.txt).

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
| Day temperature at the machine (outdoors −6.4, −8.5, −8.2 °C) | 14.51 and 13.32 °C before the trip, rate 0.4; 7.61 °C on 17 January (derived below the table) | 4.64, 3.54 and 0.82 °C: paused too cold 53.1 of 54.1 hours |
| Notes filed = harness's | **FAIL**: 44 hours, each "no fire" while the harness saw the campfire | 44 hours, all with the fire, 0 off |
| Hours away credited | **FAIL**: 0.00 h of 12.01 (the harness's last note, 397 min, covers 6.48 h) | 6.02 h, as the harness's (369 min) |
| Work over the trip = rule with the credit | **FAIL**: did 0.0000 h, the rule 3.0332 h: uncredited, 16 January fell below the 8 °C floor and the batch stopped | 0.0000 h, as the rule (too cold either way) |
| Day temperature after the trip | **FAIL**: 1.81 °C below the harness's at the first read back | exact |
| Burned while away | 388 → 0 min, one per minute event (721 in 721 game minutes) | 361 → 0 min, by game time |

Derived for the campfire: the rule's 3.0332 h at rate 0.4 puts midnight
7.58 h after the 29.11 h read. The noted fuel ran out about 0.2 h before
that, so 17 January began with the fire out until the return.

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
[2026-11-01_rt-sp_harness_run35_fires_fix.txt](evidence/2026-11-01_rt-sp_harness_run35_fires_fix.txt).

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
`IsoPlayer.tooDarkToRead`). Every other gate of the check had passed in
runs 36–37, so darkness is inferred for them, not measured.

The harness's craft step now switches a torch on in hand when it is too
dark. In run 38 it logged a light level of 0.15 at the workbench at 10:37
game time (the threshold is 0.43); with the torch all four machines were
crafted from the menu. Run 12 had crafted at the same bench, its light
level not logged.

Everything else in run 38 matched run 12:
* the fuel chain, pumps, vehicles, generators and start gates;
* the ethanol loop and both conversions;
* after the save and reload, every record: cans, a vehicle tank, a
  generator, a pump, three machines, two conversions and the world record.

The run needed no input: the launcher's two clicks passed the two
loading screens. Evidence:
[2026-11-01_rt-sp_harness_run36_install_rehearsal.txt](evidence/2026-11-01_rt-sp_harness_run36_install_rehearsal.txt),
[2026-11-01_rt-sp_harness_run37_full_repository.txt](evidence/2026-11-01_rt-sp_harness_run37_full_repository.txt),
[2026-11-01_rt-sp_harness_run38_install_rehearsal.txt](evidence/2026-11-01_rt-sp_harness_run38_install_rehearsal.txt).

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
[2026-11-01_rt-sp_harness_run39_existing_launch1.txt](evidence/2026-11-01_rt-sp_harness_run39_existing_launch1.txt),
[2026-11-01_rt-sp_harness_run39_existing_launch2.txt](evidence/2026-11-01_rt-sp_harness_run39_existing_launch2.txt),
[2026-11-01_rt-sp_harness_run40_existing_launch1.txt](evidence/2026-11-01_rt-sp_harness_run40_existing_launch1.txt),
[2026-11-01_rt-sp_harness_run40_existing_launch2.txt](evidence/2026-11-01_rt-sp_harness_run40_existing_launch2.txt).

Run 40: launch 1 **3/0**, phase B **9/1**, phase C **3/0**.

Run 39 hit a harness error at the can on the ground: the game keeps a
ground item's fluid on the world object, and the harness read it from the
item. So run 39 never recorded that can, and its phase C check of the can
passed vacuously ("none" before and after). The world-age figures vary by
world seed and item, since the pre-outbreak age is seeded (run 39: 0.127
for the can, 0.560 for the pump).

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
[2026-11-01_rt-sp_harness_run41_existing_launch1.txt](evidence/2026-11-01_rt-sp_harness_run41_existing_launch1.txt),
[2026-11-01_rt-sp_harness_run41_existing_launch2.txt](evidence/2026-11-01_rt-sp_harness_run41_existing_launch2.txt).

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
[2026-11-01_rt-sp_harness_run42_install_rehearsal.txt](evidence/2026-11-01_rt-sp_harness_run42_install_rehearsal.txt).

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
Evidence: [2026-11-01_rt-sp_harness_run43_italian.txt](evidence/2026-11-01_rt-sp_harness_run43_italian.txt),
[2026-11-01_rt-sp_harness_run44_italian.txt](evidence/2026-11-01_rt-sp_harness_run44_italian.txt).

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
[2026-11-01_rt-sp_harness_run45_still_pickup.txt](evidence/2026-11-01_rt-sp_harness_run45_still_pickup.txt).

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
[2026-11-01_rt-sp_harness_run46_still_pickup_refusals.txt](evidence/2026-11-01_rt-sp_harness_run46_still_pickup_refusals.txt).

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
bytes. It includes the fix that makes a carried machine answer Status
only. It differs from run 42's zip (`d1a6f5e1…`) in three files:
`MachineHandlers.lua`, the player guide and the changelog. The zip matched
its manifest (82 files), was installed into a fresh isolated cache and ran
the full harness. Evidence:
[2026-11-01_rt-sp_harness_run47_install_rehearsal.txt](evidence/2026-11-01_rt-sp_harness_run47_install_rehearsal.txt).

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
[2026-11-01_rt-sp_harness_run48_still_save.txt](evidence/2026-11-01_rt-sp_harness_run48_still_save.txt).

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
[2026-11-01_rt-sp_harness_run49_still_controls.txt](evidence/2026-11-01_rt-sp_harness_run49_still_controls.txt).

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
[2026-11-01_rt-sp_harness_run50_still_controls_fix.txt](evidence/2026-11-01_rt-sp_harness_run50_still_controls_fix.txt),
[2026-11-01_rt-sp_harness_run51_controls_fix.txt](evidence/2026-11-01_rt-sp_harness_run51_controls_fix.txt).

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
Evidence: [2026-11-01_rt-sp_harness_run52_install_rehearsal.txt](evidence/2026-11-01_rt-sp_harness_run52_install_rehearsal.txt).

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
* Each first record was compared with `Aging.advance` over the whole span
  (the world-age end of run 40's `RT.X.expected`), not with
  `WorldInit.baseline`.
* The can found at the start was read again and compared with the same
  one-span calculation.

Evidence: [2026-11-01_rt-sp_harness_run53_late_find.txt](evidence/2026-11-01_rt-sp_harness_run53_late_find.txt).

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

## 2026-11-01 — RT-SP client harness, launch 54 (the mod removed from a save and added back, gate 7)

Command: `tools/rehearse-install.ps1 -NoBuild -Scenario removal` (new
scenario) on the current zip (`75873ed3…`, matched its manifest), in a
fresh isolated cache. There were three launches, and between them the
save's `mods.txt` was rewritten as the load screen's Choose mods does:
1. The mod and the harness (`rm-a`), a new world. Cans P and Q of petrol
   and can E of the mod's ethanol were each recorded by a first pour. A
   fermenter F was placed with a batch running. The game saved and the
   client quit.
2. Only the TheLastGallonPreInstall driver (`rm-b`), the mod not loaded.
   It continued the save and noted what was left, poured 2 L out of P and
   3 L of fresh petrol into Q, let a game day pass and saved.
3. The mod and the harness again (`rm-c`), continuing the save.

Evidence: [2026-11-01_rt-sp_harness_run54_removal_launch1.txt](evidence/2026-11-01_rt-sp_harness_run54_removal_launch1.txt),
[…_launch2.txt](evidence/2026-11-01_rt-sp_harness_run54_removal_launch2.txt),
[…_launch2_console.txt](evidence/2026-11-01_rt-sp_harness_run54_removal_launch2_console.txt),
[…_launch3.txt](evidence/2026-11-01_rt-sp_harness_run54_removal_launch3.txt).

Result: launch 1 **1/0**, launch 2 **2/0**, launch 3 **4/1**.

| Run 54 | Result |
| --- | --- |
| Launch 1 | P 9 L, Q 4 L, E 4 L of ethanol, each recorded; F working since world hour 2.0142. World record: seed 151808538, `new_world`, created at hour 2, next id 8 |
| Launch 2, the mod away | the save loaded with no dialog in the way. P and Q kept their petrol, and the item records (mod data `tlg`) were kept too. **E was empty**: the game dropped the mod's ethanol without a word. **F was gone**: the console says `InventoryItemFactory.CreateItem() cannot create item … "TLG.FermenterVessel"` and `InventoryItem.loadItem() item == null, skipped bytes`. The world record was still in the global mod data. Poured: P 7 L, Q 7 L; saved at world hour 26.0417 |
| Launch 3, the mod back | the cans' records were exactly as launch 1 had left them. The world record was the same one (seed, start, policy, epoch, next id), and the console showed no second "world fuel history created". P's condition 0.083816353 was its record aged to now, exactly, with the 7 L it holds now. E's record reconciled to empty. F stayed gone |
| **Design: Q's inflow** | **FAIL**: condition 0.049706059. D-006's words (its own fuel aged to now, the 3 L mixed in at the untracked baseline 0.070983207) give 0.044564895. The code mixes the inflow in at the record's last write (world hour 2.0120) and then ages the whole can, which gives exactly 0.049706059. So the inflow was aged a second time, over the day the mod was away |

Run 54's failure was a mod defect (fixed since: D-006 amendment, run 55
below). `Containers.read` reconciled an untracked change at the record's
last write (`side.t`). The caller then aged the result to now, so fuel
that came in unseen carried the baseline condition of the moment it was
found and also the aging of the whole time since the record was written.
After a day away the can read 11.5 % more degraded than D-006's rule
gives. The added fuel itself came out at about 0.083, some 17 % above the
baseline of 0.071. The excess grew with the time since the last read; in
ordinary play, reads come often and the gap was small.

Found for players: removing the mod loses its machines (with their
batches) and its ethanol in containers. The game skips the unknown items
when it loads and drops the unknown fluid; the mod's other fluids would
go the same way but were not tried. Petrol and the mod's records on
vanilla items survive, and adding the mod back finds them. This is what
the open "Prepare removal" item is for. The run removed the mod the way a
player does with the load screen's Choose mods, which rewrites the save's
`mods.txt`. Not run: a save that still lists the mod after it was
uninstalled (unsubscribed on the Workshop), where the game asks about
missing mods.

Launch 2's 16 Lua error lines are the driver's own: a guarded lookup of
the empty can's fluid name. Launches 1 and 3 had none.

## 2026-11-02 — RT-SP client harness, launch 55 (the mod removed and added back after the inflow fix, gate 7)

Command: `tools/rehearse-install.ps1 -Scenario removal`. It rebuilt the
package first (183/183 tests, compile check 100/0, translations OK): the
zip of commit `49cf55a` (82 files, SHA-256 `196912cf…`, 205,134 bytes),
with the fix for run 54's failure (D-006 amendment) and the removal docs.
The zip matched its manifest and was installed into a fresh isolated
cache. The three launches were run 54's.

Evidence: [2026-11-02_rt-sp_harness_run55_removal_launch1.txt](evidence/2026-11-02_rt-sp_harness_run55_removal_launch1.txt),
[…_launch2.txt](evidence/2026-11-02_rt-sp_harness_run55_removal_launch2.txt),
[…_launch2_console.txt](evidence/2026-11-02_rt-sp_harness_run55_removal_launch2_console.txt),
[…_launch3.txt](evidence/2026-11-02_rt-sp_harness_run55_removal_launch3.txt).

Result: launch 1 **1/0**, launch 2 **2/0**, launch 3 **5/0**.

| Run 55 | Result |
| --- | --- |
| Launch 1 | P 9 L, Q 4 L, E 4 L of ethanol, each recorded; F working since world hour 2.0143. World record: seed 986530352, `new_world`, created at hour 2, next id 8 |
| Launch 2, the mod away | as in run 54: P and Q kept their petrol and their records, E was empty, F was gone (the same two console lines), the world record was still there. Poured: P 7 L, Q 7 L; saved at world hour 26.0410 |
| Launch 3, the mod back | the cans' records exactly as launch 1 left them, the same world record, no second "world fuel history created". P's condition 0.360180440, its record aged to now, exactly. E's record reconciled to empty; F stayed gone |
| **Design: Q's inflow** | **PASS**: condition 0.313571525, exactly D-006's words: its own fuel aged to now, the 3 L mixed in at the untracked baseline 0.532766158. The old order (mixed in at world hour 2.0121, then aged) would have given 0.319523279 |

The fix holds in game: fuel that came in while the mod was away joins at
the baseline of the moment it is found and is aged once. This world's
seed drew older fuel than run 54's (an untracked baseline of 0.533
against 0.071), so here the second aging would have added 1.9 % to the
can, where run 54 measured 11.5 %. The check holds the code to the rule
to 1e-6 either way.

Launch 2's two exceptions are the driver's own, as in run 54
(`Driver.lua:182`, inside `pcall`). Launches 1 and 3 had no Lua or TLG
error; the ERROR lines in their consoles are the game's own (fonts, map
zones).

Not run, as in run 54: a save that still lists the mod after it was
uninstalled, a server, the mod's other fluids and items.

## 2026-11-02 — RT-SP client harness, launch 56 (the zip with the inflow fix installed clean)

Command: `tools/rehearse-install.ps1 -NoBuild`, on the zip in `dist/` that
run 55 used. That is the package of commit `49cf55a`: 82 files, SHA-256
`196912cf…`, 205,134 bytes, with the inflow fix (D-006 amendment) and the
removal docs. It differs from run 52's zip (`75873ed3…`) in eight files:
`Transactions.lua`, `Containers.lua`, `Vehicles.lua`, `Generators.lua`,
`Stations.lua`, the player guide, `migrations.md` and the changelog. The
zip matched its manifest (82 files), was installed into a fresh isolated
cache and ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run56_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run56_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42, 47
and 52.
* The workbench was dark (light 0.15 at 10.52 game time); with the torch
  in hand all four machines were crafted from the menu.
* After the save and continue, every record came back.
* The console showed "machine move hooks installed" on both loads and no
  TLG error or warning. Its one Lua error, a stack overflow, is the
  harness's own deliberate deep recursion (`LuaProbe.lua`); no stack frame
  names the mod.

## 2026-11-02 — RT-SP client harness, launches 57–59 (the water a can takes up)

A test with a faked game found that, after a vanilla pour or a first look,
the water that aging gives a can's fuel was written to the mod's record
alone. The next read, which takes the can's fluids as they are, dropped
it. The fix (D-007 amendment, `Containers.commit`) writes the water into
the fluids too.

Command: `tools/run-sp-harness.ps1 -Mode can-water` (new; request
`sp-rtcw`), on the repository's code in the dev cache. A jerry can of the
mod's ethanol is recorded by a first pour and opened with the Fuel menu's
treatment, and the mod clock moves on. Then:
* a pour through the game's `FluidContainer.Transfer` (wrapped by the
  mod), and a read;
* a second pour;
* a **Look and smell** on a full 10 L petrol can the mod had not seen.

Evidence: [2026-11-02_rt-sp_harness_run57_can_water.txt](evidence/2026-11-02_rt-sp_harness_run57_can_water.txt),
[…_run58_can_water_probe.txt](evidence/2026-11-02_rt-sp_harness_run58_can_water_probe.txt),
[…_run59_can_water.txt](evidence/2026-11-02_rt-sp_harness_run59_can_water.txt).

| Run | Result |
| --- | --- |
| 57, 60 days | **5/2**. The pours kept the water: 0.016774 L in the opened can's fluids and record alike, kept by the next read, and 0.002097 L carried by the second pour at 0.2097 %, exactly. The look's 1.243e-4 L of water never reached the full petrol can's fluids, which held 9.9999 L afterwards, and the next read dropped it from the record |
| 58, 60 days, with observations | **3/4**. The look failed the same way. After it the can read `amount 10.0000000`, `full=true`, with 9.9998884 L of Petrol and no water; the same write gave a 5 L can its water. The game reads a container within 0.001 L of capacity as full, and `addFluid` refuses a new fluid there (engine notes). The petrol had already been lowered, so the can lost those litres. The two pour failures were the harness's: the can's fluids and record agreed to 5.8e-8 L, but the expected figure ignored the water this world's first record had already put in the fluids, part of which (0.000045 L) left with the litre poured |
| 59, 300 days, after the second fix | **8/0**. `Native.writeComposition` now holds the largest fluid low while a new one goes in, and a component too small for the game is folded into the largest. The pour left 0.080075 L of water in the fluids and the record (gap 7.9e-8 L), and the next read kept it. The second pour carried 0.010009 L at 1.0009 %, exactly. The look put 4.726e-4 L of water into the full petrol can with its 10.0000 L unchanged, and the next read kept it. A full can took 5e-4 L of a new fluid, and the petrol can is still offered to vanilla refuelling (`contains(Fluid.Petrol)`) |

Run 59's console had no TLG error and no Lua exception. Not run in game
by this mode: siphoning and pump-to-can, whose settles now go through
the same write (the full harness covers both; run 60).

## 2026-11-02 — RT-SP client harness, launch 60 (the zip with the water fix installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(191/191 tests, compile check 101/0): the zip of commit `0bac424`, 82
files, SHA-256 `3970ad6b…`, 206,632 bytes, with the water fix (D-007 and
D-024 amendments). The zip matched its manifest (82 files), was installed
into a fresh isolated cache and ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run60_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run60_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52 and 56.
* The settles the fix rewrote ran in the chain. The pump filled a 10 L
  can to the brim with station fuel (its water and sediment included),
  and the vehicle was siphoned into a can. Each moved 10.00000 L with the
  mod's total equal to the fluids, and fuel state carried to within
  1.78e-8 and 2.07e-8.
* The workbench was dark (light 0.15 at 10.54 game time); with the torch
  in hand all four machines were crafted from the menu.
* After the save and continue, every record came back.
* The console showed "machine move hooks installed" on both loads and no
  TLG error or warning. Its one Lua error, a stack overflow, is the
  harness's own deliberate deep recursion (`LuaProbe.lua`); no stack frame
  names the mod.

## 2026-11-02 — RT-SP client harness, launch 61 (the mod removed and added back, on the zip with the water fix)

Command: `tools/rehearse-install.ps1 -NoBuild -Scenario removal`, on run
60's zip (`3970ad6b…`). The fix changes what a record write puts in a
can's fluids, so run 55's scenario was run again.
Evidence: [2026-11-02_rt-sp_harness_run61_removal_launch1.txt](evidence/2026-11-02_rt-sp_harness_run61_removal_launch1.txt),
[…_launch2.txt](evidence/2026-11-02_rt-sp_harness_run61_removal_launch2.txt),
[…_launch2_console.txt](evidence/2026-11-02_rt-sp_harness_run61_removal_launch2_console.txt),
[…_launch3.txt](evidence/2026-11-02_rt-sp_harness_run61_removal_launch3.txt).

Result: launch 1 **1/0**, launch 2 **2/0**, launch 3 **5/0**, as in run 55.
World seed 956347149. Without the mod, the ethanol can was empty and the
fermenter was gone (the same two console lines); P and Q kept their
petrol and records, and were poured to 7 L each. With the mod back:
* the records were exactly as launch 1 left them, and the world record
  was the same one;
* P's condition was its record aged to now, 0.347291372, exactly;
* Q's was D-006's rule, 0.381088945, exactly (the old order gives
  0.387104564).

Launch 2's two exceptions are the driver's own guarded lookup
(`Driver.lua:182`); launches 1 and 3 had no TLG error or Lua exception.

## 2026-11-02 — RT-SP client harness, launch 62 (another chassis: Base.PickUpTruck, gate 8)

Command: `tools/run-sp-harness.ps1 -Mode chassis` (new; request
`sp-rtv`), on the repository's code in the dev cache. It runs phase A's
vehicle steps unchanged, on two `Base.PickUpTruck` instead of
`Base.CarNormal`. It first checks that the game has the script (SRC
`media/scripts/generated/vehicles/vehicle_pickuptruck.txt`).
Evidence: [2026-11-02_rt-sp_harness_run62_chassis_pickup.txt](evidence/2026-11-02_rt-sp_harness_run62_chassis_pickup.txt).

Result: **29/0**. The trucks had 75 L tanks; the run emptied them first.

| Step | Result |
| --- | --- |
| Pump → can → truck → can | each hop kept its litres, the mod's total equal to the native amount, fuel state carried to 2.04e-8 |
| Pump → truck | 17 units out, 17.00000 L in (the pump corrected to 1 L per unit), fuel state carried to 3.79e-8 |
| E25 blend, can → second truck | 8.00000 L, state carried |
| Idle on station fuel | 0.0148 L burned in 0.5 game h, reconciled proportionally (worst 3.3e-16, status `reconciled`) |
| Per-instance part data and engine power | one truck only |
| The mod's own pours | petrol 3 L in; E100 refused unconfirmed with nothing moved; confirmed, 3 L in |
| Start gate | the 36 % blend refused (`too_much_ethanol`), the engine stayed `Idle`; station fuel started at the first try |
| Stall | a truck started past the gate on the blend stalled within 0.1 game minutes |

The first hop moved 1 L, where the car runs moved 10 L: the game's pump
action ended after one unit, and the run did not record why. The mod
accounted for exactly what moved: the pump's units went down one, and the
can held 1 L with the station's water and sediment. The console had no
TLG error and no Lua exception.

Not run on this chassis: the flex conversion (`flex_pickup_truck`), save
and reload, driving.

## 2026-11-02 — RT-SP client harness, launch 63 (the zip with the truck documented, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(191/191 tests, compile check 101/0, translations OK): the zip of commit
`1e7f7f6`, 82 files, SHA-256 `aa662e45…`, 206,800 bytes. It differs from
run 60's zip (`3970ad6b…`) in two files: `Containers.lua` (the written
record normalized) and the support matrix (the truck). The zip matched
its manifest (82 files), was installed into a fresh isolated cache and
ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run63_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run63_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56 and 60. The pump filled a can to the brim and the vehicle was
siphoned into a can, each 10.00000 L with the mod's total equal to the
fluids. The workbench was dark (light 0.15); with the torch in hand all
four machines were crafted. After the save and continue every record came
back. The console showed "machine move hooks installed" on both loads and
no TLG error or warning; its one Lua error is the harness's deliberate
deep recursion (`LuaProbe.lua`), and no stack frame names the mod.

## 2026-11-02 — RT-SP client harness, launches 64–67 (one original model imported, G13)

Command: `tools/make-test-model.ps1`, then
`tools/run-sp-harness.ps1 -Mode model-import` (new; requests `sp-rtmi`,
then `sp-rtmib`), on the repository's code in the dev cache. The model is
original and lives only in the dev-only harness mod: a barrel drawn by the
script (a text `.x` mesh in metres, a 256×256 texture marked to show
orientation, texture direction and transparency, a 32×32 icon). The
harness wires it to `TLG.FermenterVessel` through the item script's own
parser (`Item.DoParam`) before any vessel exists. Each launch places the
vessels turned 0, 90, 180 and 270 degrees, takes screenshots, saves,
exits to the menu, continues the save, checks every item and takes
screenshots again.
Evidence: [2026-11-02_rt-sp_harness_run64_model_import.txt](evidence/2026-11-02_rt-sp_harness_run64_model_import.txt),
[…_run65_model_import.txt](evidence/2026-11-02_rt-sp_harness_run65_model_import.txt),
[…_run66_model_import.txt](evidence/2026-11-02_rt-sp_harness_run66_model_import.txt) and
[…_run67_model_import.txt](evidence/2026-11-02_rt-sp_harness_run67_model_import.txt), and the screenshots
[2026-11-02_run65_lid_and_window_x2.5.png](evidence/2026-11-02_run65_lid_and_window_x2.5.png),
[2026-11-02_run66_held_vanilla_bottle.jpg](evidence/2026-11-02_run66_held_vanilla_bottle.jpg),
[2026-11-02_run66_icon_and_category.jpg](evidence/2026-11-02_run66_icon_and_category.jpg),
[2026-11-02_run66_placeholders.jpg](evidence/2026-11-02_run66_placeholders.jpg),
[2026-11-02_run66_test_vessels.jpg](evidence/2026-11-02_run66_test_vessels.jpg) and
[2026-11-02_run66_test_vessels_reloaded.jpg](evidence/2026-11-02_run66_test_vessels_reloaded.jpg).
What the screenshots show was read from them by the agent; nobody else
has looked yet.

| Launch | Result | What changed |
| --- | --- | --- |
| 64 | 12/2 | the row stood two tiles in front of the character: below the frame at zoom 0.25, and out of the machine menu's reach (2.8 tiles; it allows 2.5) |
| 65 | **15/0** | the row level with the character, zoom 0.5, the interface hidden for the shots: two of the four vessels in the frame |
| 66 | 15/1 | two groups, each photographed from behind its middle; a copy with `undoCoreScale`; vanilla's water bottle held as a control. After the reload the menu was asked in the same tick as the teleport (refused) |
| 67 | **16/0** | the menu asked a step after the teleport; the hide flags logged and vanilla's hand-model reset called before the held shots |

Every launch:
- the model scripts loaded with their mesh and texture (one in launches
  64–65, three from 66);
- the vessel's world model, hand model and icon were the test model's,
  its icon texture the harness mod's file;
- every item stood on its square with its turn and came back after the
  save with it.

From launch 65 the vessel's machine record id came back too (launch 64's
menu was refused, so it had none). The square stayed free and not solid.
From 1.4 tiles the machine menu answered "Ready".

The screenshots show (G13 in `engine-capabilities.md` has the details):
- the barrel drawn textured, staves and hoops, the lid's cross and notch,
  the red stripe and tap on its +X side;
- each barrel turned as set, clockwise seen from above, with +X east and
  +Z north at 0 degrees;
- "TOP" upright, so the texture's V runs down;
- the transparent window cut out and the semi-transparent airlock
  translucent;
- no ground shadow under any item.

At scale 1.0 the barrel drew 1.5 times the size of its `undoCoreScale`
copy, which measured about true size against the character. The icon
showed in the inventory list and the equipped-item button. Neither the
vessel (launches 65–67) nor vanilla's water bottle (66–67) was drawn in
the character's hand; launch 67 logged the hide flags false and called
vanilla's hand-model reset first. The in-hand look is NOT RUN.

The placeholders were seen for the first time: the drying column reads as
a car fuel tank and the pot still as a cooking pot. The inventory showed
the vessel's category as the raw key `IGUI_ItemCat_Tools` (the machines'
`DisplayCategory = Tools`; vanilla's is `Tool`), a defect in the shipped
scripts.

The console had no error naming the model, its texture or the mod. Its
one Lua error during loading came from an `OnRenderTick` handler run on
the wrong thread; neither the mod nor the harness registers that event.

Not run: multiplayer rendering, `.fbx` and `.glb` meshes, animation, the
machine menu from other sides, a vehicle part (G11).

## 2026-11-02 — RT-SP client harness, launches 68–69 (the fermenter's own model; the machines' category)

The fermentation vessel's own model was supplied on 2026-11-02: a binary
FBX exported by Blender 5.0.1 from a Tripo Studio model, and a 512×512
JPEG texture (`art-src/fermenter/PROVENANCE.md`). It ships as the model
`TLG.Fermenter` in `TLG_models.txt`, at `scale = 0.5`: the mesh
`models_X/TLG/Fermenter.fbx` unchanged, the texture saved as
`textures/TLG/Fermenter.png`. The vessel's `WorldStaticModel` names it.
Its icon and its model in the hand stay vanilla's `WaterTank`. The same
change sets the four machines' `DisplayCategory` to vanilla's `Tool`.

Command: `tools/run-sp-harness.ps1 -Mode fermenter-model` (new; requests
`sp-rtmf`, then `sp-rtmfb`): the model-import placing with the shipped
scripts, four vessels turned 0–270 degrees beside the `undoCoreScale`
test barrel, saved, continued and photographed again.
Evidence: [2026-11-02_rt-sp_harness_run68_fermenter_model.txt](evidence/2026-11-02_rt-sp_harness_run68_fermenter_model.txt),
[..._run69_fermenter_model.txt](evidence/2026-11-02_rt-sp_harness_run69_fermenter_model.txt),
[2026-11-02_run69_fermenters.jpg](evidence/2026-11-02_run69_fermenters.jpg) and
[2026-11-02_run69_fermenters_reloaded.jpg](evidence/2026-11-02_run69_fermenters_reloaded.jpg).

| Launch | Result | Notes |
| --- | --- | --- |
| 68 | 14/2 | both failures the harness's expectation: the game reads `StaticModel = WaterTank` back as `Base.WaterTank`. Its close-up at zoom 0.25 framed only the character, and its shot with the interface shown had the inventory list collapsed; both were dropped, and the zoom's direction is now read at either end of the range |
| 69 | **16/0** | |

Both launches:
- `TLG.Fermenter` loaded with its mesh and texture, and the vessel's
  world model was it;
- every machine's category read "Tool" through the inventory's own text
  lookup;
- the eight items came back after the save with their turns and the
  vessel's machine record id;
- from 1.4 tiles the machine menu answered "Ready".

The screenshots show the wooden barrel with its hoops, planked lid,
airlock and tap, the texture the right way up and the tap going round
with each turn. Each vessel is about hip-high to the character and about
15 % wider than the 0.56 m test barrel, as its proportions give at 0.75 m
tall. Run 68 had fog; run 69's pictures are clearer. The console had no
error naming the model or its texture.

Not run: the vessel in the hand, multiplayer, the model's look up close.

## 2026-11-02 — RT-SP client harness, launch 70 (the zip with the fermenter's model, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(191/191 tests, compile check 101/0, translations OK): the zip of commit
`e18a7ec`, 85 files, SHA-256 `15229e13…`, 847,550 bytes. It differs from
run 63's zip (`aa662e45…`, 82 files, 206,800 bytes) in the fermenter's
own model (`models_X/TLG/Fermenter.fbx`, `textures/TLG/Fermenter.png`,
`scripts/TLG_models.txt`, together 653,646 bytes unpacked), the machines'
category, the notice and the changelog. The zip matched its manifest
(85 files), was installed into a fresh isolated cache and ran the full
harness.
Evidence: [2026-11-02_rt-sp_harness_run70_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run70_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60 and 63. The console had no error naming the mod or the
model.

## 2026-11-02 — RT-SP client harness, launch 71 (the fermenter's own icon)

The vessel's icon is now the mod's own, `Item_TLG_Fermenter.png`: 32×32
pixel art drawn by `tools/make-icons.ps1` (new) in colours picked from
the supplied model's texture, showing a hooped wooden barrel with a lid,
a white airlock and a brass tap. `TLG_machines.txt` sets
`Icon = TLG_Fermenter`.

Command: `tools/run-sp-harness.ps1 -Mode fermenter-model`, which now also
equips a vessel through vanilla's equip action and takes a screenshot
with the interface shown.
Evidence: [2026-11-02_rt-sp_harness_run71_fermenter_icon.txt](evidence/2026-11-02_rt-sp_harness_run71_fermenter_icon.txt)
and [2026-11-02_run71_icon_in_equipped_button_x4.png](evidence/2026-11-02_run71_icon_in_equipped_button_x4.png).

Result: **17/0**. The icon's texture was the mod's file, in both phases
and on the placed vessels; the equipped-item button showed it (the
inventory list was collapsed again, as in run 68). Everything run 69
checked passed again. The console had no error naming the model or the
icon.

## 2026-11-02 — RT-SP client harness, launch 72 (the zip with the fermenter's icon, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(191/191 tests, compile check 101/0, translations OK): the zip of commit
`30bc5bf`, 86 files, SHA-256 `1d150946…`, 848,368 bytes. It differs from
run 70's zip (`15229e13…`, 85 files) in the fermenter's own icon
(`textures/Item_TLG_Fermenter.png`, 475 bytes), the vessel's `Icon` line,
the notice and the changelog. The zip matched its manifest (86 files),
was installed into a fresh isolated cache and ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run72_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run72_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60, 63 and 70. The console had no error naming the mod.

## 2026-11-02 — RT-SP client harness, launches 73–74 (the fermentation vessel in the hand)

Command: `tools/run-sp-harness.ps1 -Mode held` (new; request `sp-rtmh`, no
save): items equipped in turn through vanilla's equip action and
photographed at zoom 0.25 with the interface hidden. Launch 74 adds a
do-nothing timed action that holds the vessel as vanilla's actions hold
an item (`setOverrideHandModels`), with its own hand model and then with
the supplied `TLG.Fermenter` named instead.
Evidence: [2026-11-02_rt-sp_harness_run73_held.txt](evidence/2026-11-02_rt-sp_harness_run73_held.txt),
[..._run74_held.txt](evidence/2026-11-02_rt-sp_harness_run74_held.txt) and the screenshots
[2026-11-02_run73_hand_bones.jpg](evidence/2026-11-02_run73_hand_bones.jpg),
[2026-11-02_run73_held_bat.jpg](evidence/2026-11-02_run73_held_bat.jpg),
[2026-11-02_run73_held_vessel_idle.jpg](evidence/2026-11-02_run73_held_vessel_idle.jpg),
[2026-11-02_run74_vessel_in_action_hand_model.jpg](evidence/2026-11-02_run74_vessel_in_action_hand_model.jpg) and
[2026-11-02_run74_vessel_in_action_supplied_model.jpg](evidence/2026-11-02_run74_vessel_in_action_supplied_model.jpg).

Result: **9/0** both launches (every equip landed: the primary hand, and
both hands for the two-handed one).

| Held | Drawn in the hand |
| --- | --- |
| `Base.BaseballBat`, idle | yes |
| `Base.WaterBottle`, idle | no |
| the vessel, idle, one hand or both | no |
| the vessel during an action, its own hand model (`Base.WaterTank`) | yes: vanilla's water-cooler bottle at a natural grip |
| the vessel during an action, `TLG.Fermenter` named | yes: the barrel on its side at the hand bone, in front of the legs |

The hide flags were false throughout, and the hand-bone debug view drew
both hands' axes where they belong. So the empty hands of launches 65–71
were the game's own behaviour: an idle character draws no held non-weapon
item, vanilla's included. The supplied model has no attachment block, so
as a hand model it would need its offset and rotation tuned; the shipped
vessel keeps vanilla's `WaterTank` in the hand.

## 2026-11-02 — RT-SP client harness, launches 75–79 (the fermentation vessel carried in both hands)

The user asked for the vessel to be carried in both hands. Vanilla's way
is the heavy item, as `Base.LargeMeteorite` and the anvils are scripted:
`Tags = base:heavyitem` and `RequiresEquippedBothHands = true`.
`ISEquipHeavyItem` takes a heavy item into both hands, and
`forceDropHeavyItems` drops it at the feet. `TLG_machines.txt` now
scripts the vessel so, and `Machines.install` follows both moves (D-015
amendment).
Evidence: [2026-11-02_rt-sp_harness_run75_heavy.txt](evidence/2026-11-02_rt-sp_harness_run75_heavy.txt),
[..._run76_pickup_heavy.txt](evidence/2026-11-02_rt-sp_harness_run76_pickup_heavy.txt),
[..._run77_pickup_heavy.txt](evidence/2026-11-02_rt-sp_harness_run77_pickup_heavy.txt),
[..._run78_heavy_floor.txt](evidence/2026-11-02_rt-sp_harness_run78_heavy_floor.txt) and
[..._run79_pickup_heavy.txt](evidence/2026-11-02_rt-sp_harness_run79_pickup_heavy.txt).

| Launch | Command | Result | Notes |
| --- | --- | --- | --- |
| 75 | `-Mode heavy` (new) | **8/0** | vanilla's meteorite and anvil, then the vessel scripted heavy, carried in both hands: none drawn in the idle character's hands; each heavy take dropped the previous item at the feet |
| 76 | `-Mode pickup` | 35/1 | the vessel heavy, the scenario otherwise unchanged: every D-015 check passed. Its last phase called the loot window's **Grab** button (`onGrabItems`), which vanilla does not check for heavy items: a plain transfer, not a take into both hands |
| 77 | `-Mode pickup` | 34/2 | the last phase took C as a double-click does (`equipHeavyItem`): in both hands, yet its world object stayed on the square, so the mod saw no pickup |
| 78 | `-Mode heavy` | **8/0** | vanilla's meteorite taken off the floor the same way: in both hands and the inventory, its world object still on the square. `ISEquipHeavyItem.complete` removes the item from the loot window's floor container only (`sendRemoveItemFromContainer` acts only in multiplayer, BC) |
| 79 | `-Mode pickup` | **39/0** | after the fix (the mod takes its own machine's world object off as the floor transfer does): C in both hands and off its tile, counted 10.0485 h for 10.0486 h placed, carried an hour, dropped by `forceDropHeavyItems` at the character's feet, resumed there at once; 11.0487 h done for 11.0487 h placed |

Not run: entering a vehicle itself (the harness called
`forceDropHeavyItems`, which vanilla's vehicle entry calls, SRC
`ISEnterVehicle.lua:60`), dragging in the loot window (the same
`equipHeavyItem`), multiplayer. Vanilla's own heavy items keep the 42.21
behaviour of launch 78.

## 2026-11-02 — RT-SP client harness, launch 80 (the zip with the two-handed vessel, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(192/192 tests, compile check 101/0, translations OK): the zip of commit
`8520ea2`, 86 files, SHA-256 `e5ae9136…`, 849,901 bytes. It differs from
run 72's zip (`1d150946…`, 86 files) in six files: the vessel's script
lines (a heavy item, both hands), the machine move hooks
(`Machines.lua`), the notice (the model's licence), the changelog, the
player guide and the support matrix. The zip matched its manifest (86
files), was installed into a fresh isolated cache and ran the full
harness.
Evidence: [2026-11-02_rt-sp_harness_run80_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run80_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60, 63, 70 and 72. Phase A crafted the vessel, now a heavy
item, into the inventory (crafting does not put it in the hands) and put
it down with the drop action, as before. The console had no error naming
the mod; its one exception came from the harness's own deep-recursion
probe, as in earlier launches.

## 2026-11-02 — RT-SP client harness, launch 81 (the vessel put down by the menus' unequip)

Runs 75–79 put the carried vessel down with `forceDropHeavyItems`, called
directly. Reading the menus afterwards showed another way down. Before
taking a heavy item, `ISInventoryPaneContextMenu.equipHeavyItem` (the loot
window's double-click and drag) queues an `ISUnequipAction` for whatever
is in the hands (SRC `ISInventoryPaneContextMenu.lua:4157-4173`).
`ISUnequipAction.complete` drops a heavy item at the feet itself, unless
it is unequipped to be dropped or placed (`ISUnequipAction.lua:134`). The
take's own `forceDropHeavyItems` then finds the hands empty. The world
menu's Take generator, the corpse grab and the inventory menu's weapon
equip unequip the hands the same way.

The mod did not follow that drop. A running vessel put down that way
stayed paused until its menu was next opened, however long that took: a
carried machine leaves the hourly reading's list, so no reading finds it.
`Machines.install` now wraps `ISUnequipAction.complete` too, for its
machines only (192/192 tests; the new test case fails without the wrap).

Command: `tools/run-sp-harness.ps1 -Mode pickup`. After run 79's phases
the scenario takes C again the double-click way, carries it half an hour,
then puts a `Base.LargeMeteorite` on the character's tile and takes it the
same way.
Evidence: [2026-11-02_rt-sp_harness_run81_pickup_unequip.txt](evidence/2026-11-02_rt-sp_harness_run81_pickup_unequip.txt).

Result: **43/0**. Run 79's 39 checks passed again. The menus queued
`ISUnequipAction,ISEquipHeavyItem`; C went down on the character's tile
and the meteorite into both hands. C's record, read in the first tick it
stood again, was `Processing` from 16.8134 game h, the tick of the
put-down, at its new tile and listed there. An hour later it had done
12.0656 h for 12.0656 h placed: neither its carried hour nor its carried
0.5108 h counted. The console had no exception.

The generator adapter has the same gap and is not changed here: a carried
generator put down by the menus' unequip would lose what the adapter
carries over (release checklist, open items). The harness's own second
generator is taken with `ISTakeGenerator` directly.

## 2026-11-02 — RT-SP client harness, launch 82 (the zip with the unequip fix, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(192/192 tests, compile check 101/0, translations OK): the zip of commit
`ba4886d`, 86 files, SHA-256 `2a762bad…`, 850,258 bytes. It differs from
run 80's zip (`e5ae9136…`, 86 files) in three files: the machine move
hook for the menus' unequip (`Machines.lua`), a comment in
`TLG_machines.txt` and the support matrix. The zip matched its manifest
(86 files), was installed into a fresh isolated cache and ran the full
harness.
Evidence: [2026-11-02_rt-sp_harness_run82_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run82_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60, 63, 70, 72 and 80; the vessel was crafted and put down as
in run 80. The console had no error naming the mod; its one exception
came from the harness's own deep-recursion probe.

## 2026-11-02 — RT-SP client harness, launches 83–85 (generators put down by the menus' unequip)

Launch 81 showed the menus put a carried heavy item down through
`ISUnequipAction`. The generator adapter re-attached a generator's record
on every other drop path, but not on this one (it was an open item).
`Generators.lua` now wraps `ISUnequipAction.complete` as it wraps the
other drops: for a carried generator that left the inventory, the record
goes to the object it became (`G.attachNear`). Tests 193/193. A new case
(`tests/integration/test_generator_moves.lua`) fails without the wrap,
and again without the check that the generator left the inventory: a
generator unequipped to be dropped stays in the inventory, and without
the check a record-less generator with the same fuel nearby would get its
record.

Command: `tools/run-sp-harness.ps1 -Mode generator-unequip` (new; request
`sp-rtgu`, no save): two generators with records on the ground. A is
taken from the world menu (`ISWorldObjectContextMenu.onTakeGenerator`),
then B the same way while A is carried, then a bat is equipped from the
inventory menu (`ISInventoryPaneContextMenu.equipWeapon`) while B is
carried.
Evidence: [2026-11-02_rt-sp_harness_run83_generator_unequip.txt](evidence/2026-11-02_rt-sp_harness_run83_generator_unequip.txt),
[..._run84_generator_unequip.txt](evidence/2026-11-02_rt-sp_harness_run84_generator_unequip.txt) and
[..._run85_generator_unequip.txt](evidence/2026-11-02_rt-sp_harness_run85_generator_unequip.txt).

| Launch | Result | Notes |
| --- | --- | --- |
| 83 | 5/3 | before the fix. A's take, from the tile next to it, left the queue without being performed, so B's take had nothing to unequip. The bat's equip queued `ISUnequipAction,ISEquipWeaponAction` and put B down: no generator within two tiles of the character had B's record |
| 84 | 1/1 | with the fix; the same first take failed again, and the run stopped there |
| 85 | **8/0** | each take after a walk, as B's was in launch 83. B's take queued `ISWalkToTimedAction,ISUnequipAction,ISTakeGenerator`: A went down on the character's tile with its record and its 6 L, and B came into both hands with its own. The bat's equip put B down with its record and its 4 L |

The first take of launches 83–84 never ran, and the cause was not found:
the two tiles reached each other (`canReachTo`, checked before the take),
and every take after a walk went through.

Not run: a generator put down by taking a heavy item from the loot
window, or by grabbing a corpse.

## 2026-11-02 — RT-SP client harness, launches 86–87 (the vessel held with vanilla's held-bag pose, a trial)

A standing character draws a carried non-weapon only through a hand pose
mask (BC; engine-capabilities, the in-hand row). The hurricane lanterns
use vanilla's held-bag pose (`primaryAnimMask = holdingbagright`), and
the game builds the pose when the item script loads (BC `Item.Load`).
Launch 86 therefore set it in the working copy of `TLG_machines.txt` (not
committed, reverted). Launch 87 used a harness stand-in instead,
`TLGHarness.PoseBag` (`TLGHarness_pose.txt`: the vessel's script plus the
pose). Between placements the harness switched the hand model
(`StaticModel`, read when the item is drawn; `TLGHarness_models.txt`).
It photographed each one carried in both hands (`ISEquipHeavyItem`):
from the front, from behind on the right and, in launch 87, walking.
Command: `tools/run-sp-harness.ps1 -Mode pose` (new; request `sp-rtmp`,
no save).
Evidence: [2026-11-02_rt-sp_harness_run86_pose.txt](evidence/2026-11-02_rt-sp_harness_run86_pose.txt),
[..._run87_pose.txt](evidence/2026-11-02_rt-sp_harness_run87_pose.txt) and
[2026-11-02_run87_pose_trial_sheet.jpg](evidence/2026-11-02_run87_pose_trial_sheet.jpg).

Result: **11/0** and **10/0** (every hold landed, and the right hand's
mask variable read `holdingbagright`).

| Hand model | Drawn |
| --- | --- |
| vanilla's `WaterTank` (the vessel's hand model today) | the water-cooler bottle hanging from the right hand at her side |
| the barrel with the lantern's `Bip01_Prop1` turn | upright under the hand; the offset moved it 1.5 m per unit whatever the model's scale (0.5 lowered it by its 0.75 m) |
| quarter turns about one axis (launch 86) | X upright, its base at the hand; Z on its side |
| the barrel at true size (0.75 m), its top rim at the hand | its base on the floor: she seems to stand beside it, not carry it |
| 0.6 m | just clear of the floor |
| 0.5 m | hanging clear at her side, standing and walking |

Each barrel is held in the right hand only (the pose is one-armed; the
left arm hangs free), and its tap points into her leg. The mod ships none
of this: the vessel is still drawn only during actions.

## 2026-11-02 — RT-SP client harness, launches 88–90 (both arms through a mod's own pose file, a trial)

The user asked whether Mixamo carry clips would help. A hold pose is one
anim node in `AnimSets/player/maskingright/`. Vanilla's
`holdingbagright.xml` names a clip (`Bob_Idle_Bag`), the condition
`RightHandMask == holdingbagright` and the bones it drives
(`Bip01_R_Clavicle`, `Bip01_Prop1`). The harness mod now has its own
nodes there (`tlg*.xml`), each driving both clavicles and both prop
bones. Stand-in items (`TLGHarness.PoseHold`, `PosePack`, `PoseShrug`
in `TLGHarness_pose.txt`) select them through `primaryAnimMask`. From
launch 89, the animator's own log was kept for each pose
(`AnimatorDebugMonitor`, as the debug menu's anim monitor uses it).
Commands: `tools/run-sp-harness.ps1 -Mode pose-hold` (new; request
`sp-rtmph`, launches 88–89, no save) and `-Mode pose-freeze` (new;
request `sp-rtmpf`, launch 90, no save).
Evidence: [2026-11-02_rt-sp_harness_run88_pose_hold.txt](evidence/2026-11-02_rt-sp_harness_run88_pose_hold.txt),
[..._run89_pose_hold.txt](evidence/2026-11-02_rt-sp_harness_run89_pose_hold.txt),
[..._run90_pose_freeze.txt](evidence/2026-11-02_rt-sp_harness_run90_pose_freeze.txt), the animator logs
[2026-11-02_run89_animlog_shrug.txt](evidence/2026-11-02_run89_animlog_shrug.txt) and
[2026-11-02_run90_animlog_frozen.txt](evidence/2026-11-02_run90_animlog_frozen.txt), and the sheets
[2026-11-02_run89_two_arm_pose_sheet.jpg](evidence/2026-11-02_run89_two_arm_pose_sheet.jpg) and
[2026-11-02_run90_frozen_pose_sheet.jpg](evidence/2026-11-02_run90_frozen_pose_sheet.jpg).

| Launch | Result | Notes |
| --- | --- | --- |
| 88 | **8/0** | `Bob_IdleHolding` (in `anims_X/Bob`; none of the game's pose files uses it) on both arms: both arms down and the item at the right hand, standing and walking. Not a carry |
| 89 | **9/0** | each time the animator log shows the masking layer switch to the harness's node and play its clip (`player/maskingright/tlgshrug`, track `Bob_EmoteShrug2H`): a mod's own pose file loads and plays. The shrug moved both forearms, so one right-hand pose drives both arms. `Bob_IdleHolding` again kept the arms down. `Bob_IdlePackBox` brought both hands forward around the 0.5 m barrel at one moment, but it is a packing loop: walking, the barrel swung below the waist and the left hand came off it |
| 90 | **6/0** | five of the game's both-hands-in-front clips (packing and unpacking a box, large and small, opening an ammo box), each held still on its first frame (`m_SpeedScale` 0.00, as vanilla's torch pose holds its clip) and switched in through `RightHandMask`. From the front the barrel sits at her chest in two of them. From behind on the right she holds it out at arm's length with her right hand, and her left hand does not touch it |

The game side of a two-armed carry works from a mod: its own pose file is
loaded, one pose drives both arms, a clip can be held still, and the item
is drawn at the right hand. What is missing is a clip of both arms
carrying something in front; none of the game's own clips tried is one.
The mod ships none of this.

## 2026-11-02 — RT-SP client harness, launches 91–92 (a Mixamo carry clip retargeted onto the game's skeleton, a trial)

The user supplied a Mixamo clip, `createdAssets/Carrying.fbx` (2,484,432
bytes, SHA-256 `dbfd9540…`): Mixamo's 65-bone skeleton and its "Beta"
character, a 10 s idle at 30 fps with both forearms level in front at
elbow height. It is not in the repository. Blender 4.5.15 LTS (portable)
and two scripts made a game clip of its arms:
- `tools/blender/pz_x.py` reads the game's text .x files: frames, and
  now the clips' S/R/T keys. Checked on `Bob_Idle.x` and
  `Bob_Idle_Bag.x`: all 45 bones' first rotation keys equal their stored
  frame rotations transposed.
- `tools/blender/pz_arms.py` reads each Mixamo arm segment as a direction
  in the chest's frame (left, up, forward) and lays it on the game's
  skeleton in its own chest's frame, from the first frame of
  `Bob_Idle.x`. The game's coordinates are mirrored against Blender's, so
  the mapping goes by those named axes. Elbows turn about the forearm's
  and upper arm's Y, palms face the hand's Z, and bones keep the game's
  lengths.

The scripts wrote `Bob_TLGCarry` (151 keys over 10 s, every second frame) in
`anims_X/Bob/` of the harness mod. All 45 bones are animated; the arms
and fingers come from the clip and the rest holds the first frame of
`Bob_Idle.x`. The clip also places `Bip01_Prop1`, the held item's bone
(it hangs off `Bip01`), between the hands, turned as `Bob_Idle_Bag.x`
turns it. The pose file `maskingright/tlgcarry.xml` (both clavicles and
both prop bones) plays it for `TLGHarness.PoseCarry`. The barrel hand
models are centred on the prop (`FermenterHeldC*`, the lantern's turn).
Command: `tools/run-sp-harness.ps1 -Mode pose-carry` (new; request
`sp-rtmpc`, no save).
Evidence: [2026-11-02_rt-sp_harness_run91_pose_carry.txt](evidence/2026-11-02_rt-sp_harness_run91_pose_carry.txt),
[..._run92_pose_carry.txt](evidence/2026-11-02_rt-sp_harness_run92_pose_carry.txt),
[2026-11-02_run91_carry_sheet.jpg](evidence/2026-11-02_run91_carry_sheet.jpg),
[2026-11-02_run92_carry_sheet.jpg](evidence/2026-11-02_run92_carry_sheet.jpg) and the animator log
[2026-11-02_run92_animlog_carry.txt](evidence/2026-11-02_run92_animlog_carry.txt).

| Launch | Result | Notes |
| --- | --- | --- |
| 91 | **8/0** | the animator log shows the masking layer playing `tlgcarry` with track `Bob_TLGCarry`: the game loads a clip from a mod's `anims_X/Bob`. Both forearms come forward with open hands and the item between them, standing and walking. The 0.75 m barrel is wider than the arms and the torso disappears inside it; at 0.5 m it reads as carried in both arms, but its back sinks into the belly and its tap points into the left arm |
| 92 | **8/0** | the clip rewritten with the prop 0.05 file units further forward and turned a quarter about the body's up (`PROP_FORWARD`, `PROP_TURN_LEFT_TO_FORWARD`): at 0.6 m and at 0.5 m the barrel sits in front of the body with the tap forward and the hands at its sides, standing and walking |

Not checked: the vessel during actions (placing it, pouring), where the
action draws the hand model; running and sneaking; multiplayer. The mod
ships none of this yet.

## 2026-11-02 — RT-SP client harness, launches 93–94 (a wider Mixamo clip, and the two blended)

The user supplied the same clip with wider arms,
`createdAssets/CarryingBiggerArmSpace.fbx` (2,482,848 bytes, SHA-256
`9edc2c3c…`; not in the repository): 301 frames like the first, with the
hands about 0.95 m apart in Mixamo's scale instead of 0.45 m, at chest
height. `tools/blender/pz_arms.py` now takes the held item's offsets
(forward, down) and a second clip of the same animation to blend
direction by direction. Run on the first clip alone, the reworked script
gave the same hands as before.
Commands: `-Mode pose-carry-wide` (request `sp-rtmpw`) and
`-Mode pose-carry-mid` (`sp-rtmpm`), both new, no save.
Evidence: [2026-11-02_rt-sp_harness_run93_pose_carry_wide.txt](evidence/2026-11-02_rt-sp_harness_run93_pose_carry_wide.txt),
[..._run94_pose_carry_mid.txt](evidence/2026-11-02_rt-sp_harness_run94_pose_carry_mid.txt),
[2026-11-02_run93_carry_wide_sheet.jpg](evidence/2026-11-02_run93_carry_wide_sheet.jpg),
[2026-11-02_run94_carry_mid_sheet.jpg](evidence/2026-11-02_run94_carry_mid_sheet.jpg) and the animator log
[2026-11-02_run94_animlog_carry_mid.txt](evidence/2026-11-02_run94_animlog_carry_mid.txt).

| Launch | Clip (hands apart, file units) | Result | Notes |
| --- | --- | --- | --- |
| 93 | `Bob_TLGCarryWide` (0.52), prop 0.08 forward, 0.02 down | **7/0** | the masking layer played `tlgcarrywide`. Her hands are about 1 m apart, while the 0.75 m barrel is about 0.65 m wide, so her hands hang in the air beside it, and the lid comes up to her chin |
| 94 | `Bob_TLGCarryMid`, the two blended halfway (0.40), prop 0.08 forward, 0.06 down | **7/0** | the masking layer played `tlgcarrymid`. At 0.75 m (true size) her hands rest on the barrel's sides near the top band and the lid is at chest height, standing, from behind and walking; at 0.6 m the hands float slightly outside it |

Not checked, as for launches 91–92: actions, running, sneaking and
multiplayer. The mod ships none of this yet.

## 2026-11-02 — RT-SP client harness, launch 95 (the full-size barrel moved out of the torso)

The user saw launch 94's full-size barrel go halfway through the body.
`pz_arms.py` now reports the distances in front of `Bip01_Spine1`.
Launch 94's item stood 0.18 file units in front of it, about the barrel's
own radius (0.65 m across is about 0.17 file units at about 1.9 m per
unit, from the game's shoulder joints 0.195 apart). Its back was
therefore near the spine. The halfway blend was written three more times,
with the item 0.13, 0.17 and 0.21 in front of the hands (0.23, 0.27 and
0.31 in front of `Bip01_Spine1`; the hands at 0.10, 0.06 down). The clips
are `Bob_TLGCarryMid13/17/21`, with the pose files
`tlgcarrymid13/17/21.xml` and the items `TLGHarness.PoseCarryMid13/17/21`.
Each was photographed with the full-size barrel.
Command: `tools/run-sp-harness.ps1 -Mode pose-carry-offsets` (new; request
`sp-rtmpo`, no save).
Evidence: [2026-11-02_rt-sp_harness_run95_pose_carry_offsets.txt](evidence/2026-11-02_rt-sp_harness_run95_pose_carry_offsets.txt),
[2026-11-02_run95_carry_offsets_sheet.jpg](evidence/2026-11-02_run95_carry_offsets_sheet.jpg),
[2026-11-02_run95_carry_offsets_side_zoom.jpg](evidence/2026-11-02_run95_carry_offsets_side_zoom.jpg) and the animator log
[2026-11-02_run95_animlog_carry_mid17.txt](evidence/2026-11-02_run95_animlog_carry_mid17.txt).

Result: **8/0**; the animator log shows each node playing. From the side:
- 0.13: the barrel's back still presses into the belly.
- 0.17: its back stands just in front of the chest, and the hands rest on
  its sides at the band, standing and walking.
- 0.21: a gap opens, and the hands only reach its back edge.

0.17 is the fit. Not checked, as before: actions, running, sneaking and
multiplayer. The mod ships none of this yet.

## 2026-11-02 — RT-SP client harness, launch 96 (the shipped vessel carried in both arms)

The user approved the halfway blend with the item 0.17 forward (launch
95). The mod now ships it (D-025):
- `media/anims_X/Bob/Bob_TLG_CarryVessel.x`, written by `pz_arms.py` with
  launch 95's settings; byte for byte it is `Bob_TLGCarryMid17.x` apart
  from the name.
- The pose file `media/AnimSets/player/maskingright/tlgcarryvessel.xml`.
- The hand model `TLG.FermenterHeld`: the floor model at true size,
  centred on `Bip01_Prop1`.
- The vessel's script: `StaticModel = TLG.FermenterHeld` and
  `primaryAnimMask = tlgcarryvessel`.

Before the launch: tests 193/193 and the compile check 102/0.
Command: `tools/run-sp-harness.ps1 -Mode vessel-carry` (new; request
`sp-rtmv`, no save). The shipped vessel is taken into both hands
(`ISEquipHeavyItem`) and photographed from the front, from the side and
walking. It is then held through a do-nothing action playing vanilla's
"Loot", as `ISEquipHeavyItem` plays it, with the vessel as the action's
hand model.
Evidence: [2026-11-02_rt-sp_harness_run96_vessel_carry.txt](evidence/2026-11-02_rt-sp_harness_run96_vessel_carry.txt),
[2026-11-02_run96_vessel_carry_sheet.jpg](evidence/2026-11-02_run96_vessel_carry_sheet.jpg) and the animator log
[2026-11-02_run96_animlog_vessel.txt](evidence/2026-11-02_run96_animlog_vessel.txt).

Result: **6/0**. The vessel's script read back as shipped
(`StaticModel=TLG.FermenterHeld`), the vessel was in both hands, and the
animator's log shows the masking layer play `tlgcarryvessel` with
`Bob_TLG_CarryVessel`, loaded from the mod itself. Front, side and
walking show launch 95's carry. During the "Loot" action, the action
replaces the pose on that same layer: the barrel follows the action's
`Bip01_Prop1` and tilts up beside the head until the action ends. The
console had no exception.

Not checked: running, sneaking, the vessel through real actions (placing
it plays no animation and keeps the pose), multiplayer.

## 2026-11-02 — RT-SP client harness, launch 97 (the zip with the carry pose, installed clean)

Command: `tools/rehearse-install.ps1`, which rebuilt the package first
(193/193 tests, compile check 102/0, translations OK): the zip of commit
`ef1734a`, 88 files, SHA-256 `7169c16c…`, 921,305 bytes. It differs from
run 82's zip (`2a762bad…`, 86 files) in:
- the generator move hook for the menus' unequip (`Generators.lua`);
- the vessel's carry: the pose file and its clip (two new files), and the
  held model and the vessel's lines in `TLG_models.txt` and
  `TLG_machines.txt`;
- the notice, the changelog, the player guide and the support matrix.

The zip matched its manifest (88 files), was installed into a fresh
isolated cache and ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run97_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run97_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60, 63, 70, 72, 80 and 82. The console had no error naming
the mod; its one exception came from the harness's own deep-recursion
probe. Phase A crafts the vessel into the inventory and puts it down
with the drop action, so it never takes it into the hands: the carry
pose is run in launch 98.

## 2026-11-02 — RT-SP client harness, launch 98 (the carry from the package's item tree)

After launch 97 the changelog's carry entry was corrected (`4aca0b0`: it
names only the action that was seen) and the package rebuilt: 88 files,
SHA-256 `6ed15990…`, 921,325 bytes. Its files differ from launch 97's
only in that entry; the zip's entries carry the newer commit's time.
Command:
`tools/run-sp-harness.ps1 -Mode vessel-carry -ModSource <repo>\dist\TheLastGallon\Contents\mods\TheLastGallon`:
launch 96's steps with the mod deployed from the package's item tree,
the folder the zip is made from, instead of the repository. The deployed
clip `Bob_TLG_CarryVessel.x` has the repository's SHA-256 (`ecc4c413…`).
Evidence: [2026-11-02_rt-sp_harness_run98_vessel_carry_packaged.txt](evidence/2026-11-02_rt-sp_harness_run98_vessel_carry_packaged.txt),
[2026-11-02_run98_vessel_carry_packaged_sheet.jpg](evidence/2026-11-02_run98_vessel_carry_packaged_sheet.jpg) and the animator log
[2026-11-02_run98_animlog_vessel.txt](evidence/2026-11-02_run98_animlog_vessel.txt).

Result: **6/0**, as launch 96. The vessel's script read back as shipped,
the vessel was in both hands, and the animator's log shows the masking
layer play `tlgcarryvessel` with `Bob_TLG_CarryVessel`. Front, side and
walking show launch 96's carry, and during "Loot" the barrel tilts up
beside the head as it did there. The console had no exception.

## 2026-11-02 — RT-SP client harness, launch 99 (the vessel put down before an action's animation)

Launches 96 and 98 showed the barrel on the "Loot" animation's prop bone
during a harness action that drew the vessel as its hand model. The user
asked for the vessel to be dropped on the ground instead, as they
expected of a generator. The game's code drops a carried heavy item
(the vessel and a generator alike) only for a vehicle, a weapon, another
heavy item, a corpse, animals, traps, climbing and death (engine
capabilities, G14), not when looting, eating or dressing. The mod now
wraps `ISBaseTimedAction.setActionAnim`: when an action on another item
starts its animation while a mod machine that is a heavy item is
carried, `forceDropHeavyItems` puts it down at the feet (D-025
amendment). Before the launch: tests 194/194 and the compile check 102/0.
The new test case covers the put-down, an action on the vessel itself, a
multiplayer client's command, a generator and a pot still left alone, and
a failing put-down logged.

Command: `tools/run-sp-harness.ps1 -Mode vessel-actions` (new; request
`sp-rtmva`, no save). The shipped vessel is taken into both hands. A
school bag is put on the character's tile with a box of nails in it, and
vanilla's transfer action takes the nails into the inventory, as the
loot window does. The action's time is set to 600 so the picture catches
it. Then a `Base.Generator` goes through the same loot, and then a
second vessel is put down by the menus' own unequip when a bat is
equipped from the inventory menu (`equipWeapon`; the unequip's time set
to 300).
Evidence: [2026-11-02_rt-sp_harness_run99_vessel_actions.txt](evidence/2026-11-02_rt-sp_harness_run99_vessel_actions.txt),
[2026-11-02_run99_vessel_actions_sheet.jpg](evidence/2026-11-02_run99_vessel_actions_sheet.jpg),
[2026-11-02_run99_unequip_close.png](evidence/2026-11-02_run99_unequip_close.png) and the animator log
[2026-11-02_run99_animlog_vessel_loot.txt](evidence/2026-11-02_run99_animlog_vessel_loot.txt).

Result: **11/0**.
- The vessel through the loot: 30 ticks in, "Loot" was playing, the hands
  were empty and the vessel lay on the ground. Afterwards it was on the
  character's tile and the nails were in the inventory. The animator's
  log shows `RightHandMask` go from `tlgcarryvessel` to empty, then
  `[layer][1]` change from `player/maskingright/tlgcarryvessel` to
  `player/actions/LootLow`. The pictures show her bent over the bag with
  the barrel at her feet, then standing with empty hands beside it.
- The generator through the same loot stayed in both hands, not drawn,
  and the nails were taken: the game keeps it.
- The bat: the menus queued `ISUnequipAction` and `ISEquipWeaponAction`.
  30 ticks into "UnequipItem" the vessel was still in the hands, but
  nothing was drawn in the arms (close-up). Afterwards it lay at the
  character's feet with the bat in the hand.
- The console had no exception. The camera was at zoom 0.50 for the last
  two pictures instead of 0.25 (not set by the harness).

Not checked: animations the game starts without a Lua action (doors,
shoving, emotes), the mod's conversion work and the other Lua actions
with an animation (they reach the same call), entering a vehicle,
running, sneaking, multiplayer.

## 2026-11-02 — RT-SP client harness, launch 100 (launch 99 on the guarded hook)

After launch 99 the hook's look at the hands moved inside its error
guard (`c3a1d25`; tests 194/194, compile 102/0). Command: the same,
`tools/run-sp-harness.ps1 -Mode vessel-actions`.
Evidence: [2026-11-02_rt-sp_harness_run100_vessel_actions.txt](evidence/2026-11-02_rt-sp_harness_run100_vessel_actions.txt).

Result: **11/0**, every check and observation as in launch 99: the
vessel lay at the feet as "Loot" began, the generator stayed in both
hands, and the bat put a second vessel down through the game's
unequip. The console had no exception and no error from the hook. The
camera stayed at zoom 0.25 this time.

## 2026-11-02 — RT-SP client harness, launches 101–103 (the field manual found in loot and read)

The asset review found `TLG.ManualFuelSystems` could not be obtained and
did nothing when read: nothing spawned or read it. It is now print media
(D-026). Its `OnCreate` gives each new manual the game's print media
fields, so the inventory menu offers **Inspect** and the read shows a page
on start-up, compatibility and troubleshooting in the game's print media
window (EN and IT). It is added to 11 vanilla loot lists on
`OnPreDistributionMerge`. Before the launches: tests 197/197 (three new
cases: the fields, the lists added to once, the weights), the compile
check 105/0 and the translations check (240 EN keys, IT parity).

Command: `tools/run-sp-harness.ps1 -Mode manual` (new; request
`sp-rtman`, no save), and `-Mode manual-italian` (`sp-rtmanit`, the client
in Italian). The steps:
- The 11 lists are read back after the merge.
- Each of seven of them is rolled 500 times into an empty container, as
  the game fills one (`ItemPickerJava.getItemContainer` and `doRollItem`,
  the calls vanilla's loot stress test makes).
- The page is built in the game's window, as the debug menu builds it,
  to measure each text element, and its text panel is opened.
- The first rolled manual is put in the inventory. Its menu is built as
  a right-click builds it (`createMenu`), and Inspect is chosen.
Evidence: [2026-11-02_rt-sp_harness_run101_manual.txt](evidence/2026-11-02_rt-sp_harness_run101_manual.txt),
[…_run102_manual_italian.txt](evidence/2026-11-02_rt-sp_harness_run102_manual_italian.txt),
[…_run103_manual.txt](evidence/2026-11-02_rt-sp_harness_run103_manual.txt),
[2026-11-02_runs102-103_manual_pages_sheet.jpg](evidence/2026-11-02_runs102-103_manual_pages_sheet.jpg) and
[2026-11-02_run103_manual_text_panel.png](evidence/2026-11-02_run103_manual_text_panel.png).

| Launch | Language, page | Result | Notes |
| --- | --- | --- | --- |
| 101 | EN, 1100×560, body text at 0.30 | **10/0** | every list held the manual at its weight. 137 manuals in 3500 fills (9 to 33 per list), the first already print media with its page resolving. **Inspect** offered (not **Read**); the read ended with the manual recorded read (print media and literature). The page showed with its text 168–192 px tall, ending at y 326 of 560: legible but small, half the page empty |
| 102 | IT, 1100×500, body text at 0.36 | **10/0** | as 101: 154 manuals, **Ispeziona** offered. The longest column ends at y 426 of 500. Accents and `°C` draw correctly |
| 103 | EN, the same layout | **10/0** | as 101: 147 manuals; the longest column ends at y 383 of 500 |

The console had no exception in any of them. The rolls used a density
of 1 with the harness world's loot settings, so they show that the
lists produce the manual, not how often a player meets one.

Not checked: a manual found in a real building's container, multiplayer,
and the Italian text panel (the English one shows the full text,
scrollable).

## 2026-11-02 — RT-SP client harness, launches 104–106 (the zip with the put-down and the manual)

Launch 104. Command: `tools/rehearse-install.ps1`, which rebuilt the
package first (197/197 tests, compile check 105/0, translations OK): the
zip of commit `1a341ee`, 90 files, SHA-256 `abcc355a…`, 927,534 bytes.
It differs from launch 97's zip (`7169c16c…`, 88 files) in the vessel's
put-down before an action's animation (`Machines.lua`) and the field
manual: two new files (`Manual.lua`, `Loot.lua`), its item script line
and its EN/IT page (`IG_UI.json`). The changelog, the player guide and
the support matrix changed too. The zip matched its manifest (90 files),
was installed into a fresh isolated cache and ran the full harness.
Evidence: [2026-11-02_rt-sp_harness_run104_install_rehearsal.txt](evidence/2026-11-02_rt-sp_harness_run104_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as runs 12, 38, 42,
47, 52, 56, 60, 63, 70, 72, 80, 82 and 97. The console logged the manual
joining its 11 loot lists before each of the two loot parses (the first
game and the continued one). Its one exception came from the harness's
own deep-recursion probe.

The full harness exercises none of the carry, the put-down or the
manual, so the next two launches deployed the mod from the package's
item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`),
the folder the zip is made from:
- Launch 105, `-Mode vessel-actions`: **11/0**, as launches 99–100. The
  vessel lay at the feet as "Loot" began, a generator stayed in both
  hands through the same loot, and a bat put a second vessel down
  through the game's unequip. Its archived debug log had no exception
  and no error from the hook.
- Launch 106, `-Mode manual-italian`: **10/0**, as launch 102. All 11
  lists held the manual, and 133 of 3500 fills rolled it, each already
  print media. **Ispeziona** read it and the game recorded it read; the
  page measured as in launch 102. The console had no exception.
Evidence: [2026-11-02_rt-sp_harness_run105_vessel_actions_packaged.txt](evidence/2026-11-02_rt-sp_harness_run105_vessel_actions_packaged.txt)
and […_run106_manual_italian_packaged.txt](evidence/2026-11-02_rt-sp_harness_run106_manual_italian_packaged.txt).

## 2026-11-02 — RT-SP client harness, launches 107–108 (the vessel carried running and sneaking)

The carry pose is one node, `tlgcarryvessel`, with no gait of its own;
the game's held bag has a node for each. The clip was keyed against the
standing pose. None of the game's heavy-item drops is tied to a gait
(engine capabilities, G14).

Command: `tools/run-sp-harness.ps1 -Mode vessel-gaits` (new; request
`sp-rtmvg`, no save). The shipped vessel is taken into both hands. The
character then walks the row the setup found clear, end to end, once per
gait: walking, running, sprinting, sneaking and running crouched, along a
path as `ISWalkToTimedAction` walks one. Running and sprinting are the
forced-run and forced-sprint flags the game's toggle keys set, set again
every tick. Sneaking is set as the crouch key sets it (`setSneaking`).
Each leg is timed, photographed at 35, 50 and 65 percent of the way with
the interface hidden, and logged by a fresh animator monitor. Then she
crouches and is photographed still, from the front and the side. The
harness character has god mode and unlimited carry, as in every model
run.

Launch 107: **19/2**. Both running legs walked: `isRunning` stayed false
and they took as long as the walking ones (1.94 tiles a second against
1.91, and 1.60 crouched as when sneaking). The game clears the forced-run
flag every frame while "Toggle to Run" is off, its default (BC
`CharacterInputComponent.updateToggleToRun`). "Toggle to Sprint" is on by
default, and the sprinting leg sprinted. The harness now turns "Toggle to
Run" on for a running leg and back to what it was after it.

Launch 108: **21/0**.

| Leg | Speed (tiles/s) | The body's state, `[layer][0]` | Carry pose at the three shots |
| --- | --- | --- | --- |
| walking | 1.92 | `player/movement/defaultWalk` | on |
| running | 3.00 | `player/run/defaultRun` | on |
| sprinting | 3.27 | `player/run/defaultRun`, then `player/sprint/defaultSprint` | on |
| sneaking | 1.59 | `player/movement/sneakWalk` | on |
| running crouched | 2.46 | `player/run/sneakRun` | on |

- In every leg `RightHandMask` read `tlgcarryvessel` at the three shots,
  and the leg's animator log never shows the carry node stop. During a
  180° turn the game's turn animation took `[layer][1]` and the carry
  played on `[layer][2]`. The monitor returns its newest 128 lines; each
  leg's log still begins inside the variable list printed when the
  monitor was created, so it holds the whole leg.
- The vessel stayed in both hands and off the ground through every leg
  and the crouch: no gait puts it down.
- The pictures: walking, the barrel stands upright between her hands.
  Running, it tilts with her lean and swings through the stride (corrected
  after launch 117: this entry first said it stood upright when running,
  as when walking; launch 117's pictures show the tilt plainly, and read
  again, launch 113's show it as well). Sprinting, it tilts forward with
  her lean. Crouched, still, walking or running, it tips forward, its lid
  turned out and its bottom swung back between her knees, and her hips
  and belly sink into its back. Her hands stay on its sides throughout.
- Why (corrected after launch 110): the game reparents a player's
  `Bip01_Prop1` under the right hand and the clavicles under
  `Bip01_Spine1` (BC `IsoPlayer.onAnimPlayerCreated`), so the barrel turns
  with the chest. Crouched, the chest bends far forward. This entry first
  gave the root bone's turn as the cause (10.8° walking, 15.0° running,
  20.6–28.4° crouched, at the clips' first frames). Those angles are
  right, but `Bip01_Prop1` does not hang from that bone at runtime. The
  game's held bag has a clip for each gait instead
  (`walksneakbagright.xml`, `idlesneakbagright.xml` and others).
- The console had no exception.

Evidence: [2026-11-02_rt-sp_harness_run107_vessel_gaits.txt](evidence/2026-11-02_rt-sp_harness_run107_vessel_gaits.txt),
[…_run108_vessel_gaits.txt](evidence/2026-11-02_rt-sp_harness_run108_vessel_gaits.txt),
[2026-11-02_run108_vessel_gaits_sheet.jpg](evidence/2026-11-02_run108_vessel_gaits_sheet.jpg)
and the five legs' animator logs,
[2026-11-02_run108_animlogs_gaits.txt](evidence/2026-11-02_run108_animlogs_gaits.txt).

Not checked: multiplayer; the keys pressed on a keyboard (the harness sets
the flags the keys set); what the vessel's weight does to a normal
character's speed; animations the game starts without a Lua action. The
crouched clips came next (launches 109–113).

## 2026-11-02/03 — RT-SP client harness, launches 109–113 (a crouched carry pose)

After launch 108 the user asked for a crouched version of the carry. A
state plays the nodes that match with the most conditions (BC
`AnimState.getAnimNodes`). So a node with the vessel's mask and
`sneaking` true plays instead of the standing node whenever the
character crouches. The retarget tool gained a body option
(`tools/blender/pz_arms.py --body <clip.x>`). It keys the arms for the
first frame of another game clip and keeps the held item upright, and
with `--arms world` the arms keep their standing directions. Its
default output is unchanged: the shipped standing clip rebuilds byte for
byte (SHA-256 `ECC4C413…`).

Command: `tools/run-sp-harness.ps1 -Mode pose-crouch` (new; request
`sp-rtmpk`, no save). Each candidate is a harness item whose own pose
files play it, with the shipped hand model. It is taken into both hands,
and the character crouches and is photographed still from the front and
the side. Then she walks and runs crouched along the row, as in the gait
mode. Each leg checks that the candidate's node is active at its shots,
replaying the animator's log up to each one.

| Launch | Candidates | Result | What the game did |
| --- | --- | --- | --- |
| 109 | three, keyed for `Bob_WalkSneak` | 20/12 | none played: each pose file failed to parse (`--` inside its XML comment), which the game reports only in the console |
| 110 | the same, comments fixed | **32/0** | they played, but one arm swung wide and the barrel still tipped |
| 111 | arms in their standing directions, the barrel 0.17, 0.13 or 0.10 forward and 0.06 down; beside each, a still clip keyed for `Bob_IdleSneak` | **32/0** | barrel upright, hands on its sides; the lid at her chin in all three |
| 112 | 0.17 forward and 0.12 down, 0.17 and 0.16, 0.20 and 0.12 | **32/0** | 0.17/0.12: the lid below her chin, the hands on its upper sides. 0.16 down: the hands at the rim. 0.20 forward: her face back at the lid |
| 113 | the shipped pose, 0.17 and 0.12 | **23/0** | the gait mode, below |

Launch 110's arms showed the cause. A player's animation player
reparents bones when it is made (BC `IsoPlayer.onAnimPlayerCreated`):
- both clavicles under `Bip01_Spine1`;
- `Bip01_Prop1` under the right hand and `Bip01_Prop2` under the left;
- the thighs under `Bip01`.

A reparented bone keeps the offset to its new parent that the playing
clip's own pose gives it. Launch 110's clips held the standing body in
their other bones while their arms were keyed for the crouch. The tool
now writes the body pose into those bones. This also corrects launch
108's explanation: the barrel follows the right hand, and so the chest,
not the root bone.

Shipped (D-025, second amendment):
- `Bob_TLG_CarryVesselSneak.x`, keyed for `Bob_WalkSneak`, plays through
  `tlgcarryvesselsneak.xml` (the vessel's mask and `sneaking`).
- `Bob_TLG_CarryVesselSneakIdle.x`, keyed for `Bob_IdleSneak`, plays
  through `tlgcarryvesselsneakidle.xml` (also `isMoving` false).

The two crouch clips' chests stand 17° apart. Both clips hold the arms in
their standing directions and the vessel upright, 0.17 file units in
front of the hands and 0.12 down. Provenance is in
`art-src/carry/PROVENANCE.md`. `tools/package.ps1` and
`tools/run-sp-harness.ps1` now refuse XML that does not parse.

Launch 113, `-Mode vessel-gaits` with the shipped files: **23/0**.
- Walking (1.90 tiles a second), running (3.01) and sprinting (3.24)
  played the standing node, as in launch 108.
- Sneaking (1.59) and running crouched (2.45) played
  `tlgcarryvesselsneak` at every shot. Crouching still switched to
  `tlgcarryvesselsneakidle`, and standing up switched back to
  `tlgcarryvessel`.
- The pictures: crouched, still or moving, the barrel stands upright in
  front of her, her hands on its upper sides and the lid below her chin.
  Walking, running and sprinting look as in launch 108; sprinting still
  tilts the barrel with her lean (and so does running: see launch 117).
- The vessel stayed in both hands through every leg. The console had no
  exception.

Evidence: [2026-11-02_rt-sp_harness_run109_crouch_trials.txt](evidence/2026-11-02_rt-sp_harness_run109_crouch_trials.txt),
[…_run110_crouch_trials.txt](evidence/2026-11-02_rt-sp_harness_run110_crouch_trials.txt),
[2026-11-03_rt-sp_harness_run111_crouch_trials.txt](evidence/2026-11-03_rt-sp_harness_run111_crouch_trials.txt),
[…_run112_crouch_trials.txt](evidence/2026-11-03_rt-sp_harness_run112_crouch_trials.txt),
[…_run113_vessel_gaits.txt](evidence/2026-11-03_rt-sp_harness_run113_vessel_gaits.txt); the sheets
[2026-11-02_run110_crouch_trials_sheet.jpg](evidence/2026-11-02_run110_crouch_trials_sheet.jpg),
[2026-11-03_run111_crouch_trials_sheet.jpg](evidence/2026-11-03_run111_crouch_trials_sheet.jpg),
[…_run112_crouch_trials_sheet.jpg](evidence/2026-11-03_run112_crouch_trials_sheet.jpg)
and […_run113_vessel_gaits_sheet.jpg](evidence/2026-11-03_run113_vessel_gaits_sheet.jpg); and the five legs' animator logs,
[2026-11-03_run113_animlogs_gaits.txt](evidence/2026-11-03_run113_animlogs_gaits.txt).

Not checked: multiplayer; a sprint pose of its own (not made then; see
launches 116–117); the crouch through the keyboard's own key.

## 2026-11-03 — RT-SP client harness, launches 114–115 (the zip with the crouched pose)

Launch 114. Command: `tools/rehearse-install.ps1`, which rebuilt the
package first (197/197 tests, compile check 105/0, translations OK, every
shipped XML file parsing): the zip of commit `3b3ed77`, 94 files,
SHA-256 `5ab59e10…`, 1,057,082 bytes. It is byte-identical to the build
made just before. It differs from launch 104's zip (`abcc355a…`, 90
files) in the crouched carry pose. There are four new files: two clips
and two pose files. `tlgcarryvessel.xml` gained a comment, and the
changelog and the support matrix changed. The zip matched its manifest,
was installed into a fresh isolated cache and ran the full harness.
Evidence: [2026-11-03_rt-sp_harness_run114_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run114_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 104. The
console's one exception came from the harness's own deep-recursion
probe.

Launch 115, `-Mode vessel-gaits` with the mod deployed from the package's
item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**23/0**, as launch 113. The deployed clips carried the shipped hashes.
The crouched legs played `tlgcarryvesselsneak` at every shot. Crouching
still switched to `tlgcarryvesselsneakidle`, and standing up switched
back to `tlgcarryvessel`. The console had no exception.
Evidence: [2026-11-03_rt-sp_harness_run115_vessel_gaits_packaged.txt](evidence/2026-11-03_rt-sp_harness_run115_vessel_gaits_packaged.txt).

## 2026-11-03 — RT-SP client harness, launches 116–117 (a sprint carry pose)

After launch 113 the user asked for a sprint pose made the same way as
the crouched one. That way keys the arms for one frame of the game's
clip. The crouch clips' chests move under 10° through a stride; the
sprint clip's chest does not. `Bob_Sprint.x` turns `Bip01_Spine1` up to
76° from its first frame, and its first frame stands 36° from the
stride's mean. The lean holds at 41°, while the shoulder line's yaw and
roll swing ±25° and ±18°. Two engine facts, read in the bytecode, decided
the approach (engine capabilities, animation tooling):
- A looping track in a sub-layer runs at the time fraction of the body
  layer's sync track (`AnimLayer.updateInternal` and `findSyncTrack`;
  `m_SyncTrackingEnabled` is true unless a pose file says otherwise).
- A reparented bone takes its offset from the clip's own pose at the
  track's current time (`AnimationPlayer.getTrackTransform`).

So a clip as long as the body's, keyed against each of its keys, should
hold the arms in step with the stride. The retarget tool gained `--sync`
(one key at each of the body clip's key times, its other bones carrying
the body clip's own keys) and `--body-key N` (the pose at its N-th key
time). Its default output is unchanged: the three shipped carry clips
rebuild byte for byte (`ECC4C413…`, `658AC930…`, `FCBB621A…`).

Launch 116. Command: `tools/run-sp-harness.ps1 -Mode pose-sprint` (new;
request `sp-rtmps`, no save). Each candidate is a harness item with the
shipped hand model. Its own pose files play the candidate clip while the
character sprints and moves (the conditions planned for the vessel), and
the shipped standing clip otherwise. With each candidate the character
sprints the views row both ways and is photographed eight times between
30 and 65 percent of the way: 3 to 4 tiles at about 3.2 tiles a second,
just over one stride (`defaultSprint.xml` plays the 0.67 s clip at speed
scales 0.96 and 0.80).

| Candidate | Keyed for (all from `Bob_Sprint.x`, arms in their standing directions, 0.17 forward) | Down | The pictures |
| --- | --- | --- | --- |
| first frame | its first frame, as the crouch clips were | 0.06 | the barrel tilts and swings hardest |
| mean key | its key 6, 1.6° from the stride's mean chest | 0.06 | it swings on either side of upright |
| per key | each of its 21 keys (`--sync`) | 0.06 | upright and steady in all 16 shots; the rim at the chin |
| per key | the same | 0.10 | upright and steady in all 16 shots; the lid below the chin, the hands on its upper sides |

Result: **33/0**. Every shot was taken sprinting, with the candidate's
node active, and the standing node came back at the end of each leg.
Only if the game syncs the hand clip to the body's would the per-key
clips stay steady while the others swing. Chosen: the per-key clip, 0.10
down.

Evidence: [2026-11-03_rt-sp_harness_run116_sprint_trials.txt](evidence/2026-11-03_rt-sp_harness_run116_sprint_trials.txt),
the eight legs' animator logs
[2026-11-03_run116_animlogs_sprint_trials.txt](evidence/2026-11-03_run116_animlogs_sprint_trials.txt)
and the sheet
[2026-11-03_run116_sprint_trials_sheet.jpg](evidence/2026-11-03_run116_sprint_trials_sheet.jpg).
The first file was rebuilt from the game's archived debug log (its
`[TLGH]` lines, the logger's trailing period removed), because the next
launch cleared the harness's own result file before it was copied. Its
last 60 lines match the copy the launcher printed.

Shipped (D-025, third amendment): `Bob_TLG_CarryVesselSprint.x`, keyed
against each key of `Bob_Sprint`. It plays through
`tlgcarryvesselsprint.xml` on three conditions: the vessel's mask,
`isSprinting` true and `isMoving` true. That is more than the standing
node's one condition and the crouched node's two. `isMoving` keeps it
apart from the crouched still node. Provenance is in
`art-src/carry/PROVENANCE.md`.

Launch 117, `-Mode vessel-gaits` with the shipped files, now with a leg
sprinting crouched and eight shots on each sprinting leg: **26/0**.
- Walking (1.91 tiles a second) and running (2.98) played the standing
  node; sneaking (1.60) and running crouched (2.45) the crouched node, as
  in launch 113.
- Sprinting (3.17) played `tlgcarryvesselsprint` at all eight shots, the
  body going from `player/run/defaultRun` to `player/sprint/defaultSprint`.
- Sprinting crouched (3.52): sprinting and still sneaking at all eight
  shots. The body went from `player/run/sneakRun` to the standing sprint,
  `player/sprint/defaultSprint`, and the carry from
  `tlgcarryvesselsneak` to `tlgcarryvesselsprint`.
- Crouching still switched to `tlgcarryvesselsneakidle`, and standing up
  back to `tlgcarryvessel`.
- The pictures: sprinting, standing or crouched, the barrel stands
  upright and steady in front of her at all sixteen shots, the lid below
  her chin and her hands on its sides. Walking and the crouched gaits
  look as in launch 113. Running, the barrel tilts with her lean and
  swings through the stride: launch 108's note said otherwise and is
  corrected above.
- The vessel stayed in both hands through every leg. The console had no
  exception.

Evidence: [2026-11-03_rt-sp_harness_run117_vessel_gaits.txt](evidence/2026-11-03_rt-sp_harness_run117_vessel_gaits.txt),
the six legs' animator logs [2026-11-03_run117_animlogs_gaits.txt](evidence/2026-11-03_run117_animlogs_gaits.txt) and the
sheet [2026-11-03_run117_vessel_gaits_sheet.jpg](evidence/2026-11-03_run117_vessel_gaits_sheet.jpg).

Not checked:
- multiplayer;
- the keys pressed on a keyboard (the harness sets the flags they set);
- the low crouch near walls;
- a running pose of its own (not made, so running still tilts the
  barrel);
- what the vessel's weight does to a normal character (the harness has
  god mode and unlimited carry);
- a `WalkSpeed` other than 0.8, which changes the body's blend of
  `Bob_Sprint` and `Bob_Run`;
- turning or colliding while sprinting. A turn animation takes
  `[layer][1]` and moves the carry to `[layer][2]` (launch 108). The
  carry keeps the body's timing, since each layer passes its parent's
  sync track on (`AnimLayer.findSyncTrack`), but the turn poses the chest
  instead of `Bob_Sprint`, so the barrel may not hold steady while it
  plays.

## 2026-11-03 — RT-SP client harness, launches 118–119 (the zip with the sprint pose)

Launch 118. Command: `tools/rehearse-install.ps1`, which rebuilt the
package first (197/197 tests, compile check 105/0, translations OK, every
shipped XML file parsing): the zip of commit `2e0d80d`, 96 files,
SHA-256 `e3a284a3…`, 1,103,955 bytes. It differs from launch 114's zip
(`5ab59e10…`, 94 files) in the sprint carry pose: two new files
(`Bob_TLG_CarryVesselSprint.x` and `tlgcarryvesselsprint.xml`) and new
comments in `tlgcarryvessel.xml` and `tlgcarryvesselsneak.xml`. The
changelog and the support matrix changed too. The zip matched its
manifest, was installed into a fresh isolated cache and ran the full
harness.
Evidence: [2026-11-03_rt-sp_harness_run118_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run118_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 114. The
console's one exception came from the harness's own deep-recursion
probe.

Launch 119, `-Mode vessel-gaits` with the mod deployed from the package's
item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**26/0**, as launch 117. The deployed clips and pose files carried the
shipped hashes (the sprint clip `2D36AC57…`, its pose file `a756e8f9…`,
as in the zip's manifest). Both sprinting legs played
`tlgcarryvesselsprint` at all eight shots, crouched or not, and the
other legs and the crouch played the nodes they played in launch 117.
The console had no exception.
Evidence: [2026-11-03_rt-sp_harness_run119_vessel_gaits_packaged.txt](evidence/2026-11-03_rt-sp_harness_run119_vessel_gaits_packaged.txt).

## 2026-11-03 — RT-SP client harness, launches 120–122 (the stills', drying column's and fuel filter's own models)

The user supplied four models for the mod in `<game>/createdAssets/`
(provenance in `art-src/potstill`, `refluxstill`, `dryingcolumn` and
`fuelfilter`). They ship as the fermenter's did: each FBX byte for byte
in `media/models_X/TLG`, each JPEG texture saved as PNG (the method gives
the fermenter's shipped PNG byte for byte), and a model script each in
`TLG_models.txt`. The items name them as their `WorldStaticModel`
(`TLG_machines.txt`, `TLG_items.txt`). Their scales set true sizes from
the machines' capacities:
- the pot still 0.7: 1.05 m wide, 0.68 m tall, a 0.44 m pot of 55 L;
- the reflux still 0.9: 1.35 m tall, a 0.55 m boiler of 110 L;
- the drying column 0.55: 0.82 m, a 0.35 m receiver jar of 40 L;
- the filter 0.1: 0.15 m.

Command: `tools/run-sp-harness.ps1 -Mode machine-models` (new; request
`sp-rtmm`, no save). It checks each model script's mesh and texture and
each item's wiring, then puts the four down on cleared ground beside a
fermenter, at 0 degrees, and photographs them.

| Launch | Result | What it showed |
| --- | --- | --- |
| 120 | **10/0** | Every model drew, textured, in the row beside the fermenter. The close-ups missed: the character stood behind each item and at zoom 0.25 the item fell below the frame. Held through an action, the stills' hand models (the floor mesh at true size, upright and centred on the hand bone as the fermenter's is) covered the character from feet to head |
| 121 | **10/0** | The character standing on the row between the items, at zoom 0.5. Taking her as 1.75 m, the reflux still measured 1.41 m (1.35 m planned), the drying column 0.90 m (0.82 m) and the pot still's pot about 0.35 m high (0.36 m), each base taken at the centre of its ground ellipse. The drying column, which has no hand model, held through an action: nothing drawn |
| 122 | **10/0** | The stills without hand models, as shipped: the row and the character beside the items as in launch 121; the pot still held through an action, nothing drawn |

Each launch's console had no exception.

Evidence: [2026-11-03_rt-sp_harness_run120_machine_models.txt](evidence/2026-11-03_rt-sp_harness_run120_machine_models.txt),
[…_run121_machine_models.txt](evidence/2026-11-03_rt-sp_harness_run121_machine_models.txt) and
[…_run122_machine_models.txt](evidence/2026-11-03_rt-sp_harness_run122_machine_models.txt); the sheets
[2026-11-03_run120_machine_models_sheet.jpg](evidence/2026-11-03_run120_machine_models_sheet.jpg)
(the row and the stills held at true size) and
[2026-11-03_run122_machine_models_sheet.jpg](evidence/2026-11-03_run122_machine_models_sheet.jpg)
(runs 121–122).

Not checked:
- the models turned other ways than 0 degrees (the fermenter's turns drew
  and reloaded in launches 68–69, the same code);
- the models seen after a save and reload (launch 123 reloaded two of
  them, unseen);
- multiplayer;
- the items' icons (then still vanilla's pot and respirator filter; their
  own since launches 125–126).

## 2026-11-03 — RT-SP client harness, launches 123–124 (the zip with the supplied models)

Launch 123. Command: `tools/rehearse-install.ps1`, which rebuilt the
package first (197/197 tests, compile check 105/0, translations OK, every
shipped XML file parsing): the zip of commit `8c9dd19`, 104 files,
SHA-256 `0a0a6a1e…`, 3,734,318 bytes. It differs from launch 118's zip
(`e3a284a3…`, 96 files) in the four supplied models: eight new files (four
FBX meshes and four PNG textures, each with the hash its provenance
records), the model and item scripts, and the changelog and notice. The
zip matched its manifest, was installed into a fresh isolated cache and
ran the full harness.
Evidence: [2026-11-03_rt-sp_harness_run123_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run123_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 118. Phase
B found a placed reflux still and drying column back after the save and
continue (`G08.machine_records_persist`): they loaded with their new
models, though nothing photographed them. The console's one exception
came from the harness's own deep-recursion probe, and no line named the
new models or textures.

Launch 124, `-Mode machine-models` with the mod deployed from the
package's item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**10/0**, as launch 122. The deployed meshes and textures carried the
shipped hashes, the four models drew beside the fermenter, and the pot
still held through an action drew nothing. The console had no exception.
Evidence: [2026-11-03_rt-sp_harness_run124_machine_models_packaged.txt](evidence/2026-11-03_rt-sp_harness_run124_machine_models_packaged.txt).

## 2026-11-03 — RT-SP client harness, launches 125–126 (the four items' own icons)

After the models, the user chose their icons next. `tools/make-model-icons.ps1`
renders each from the shipped model and texture with
`tools/blender/pz_icon.py`: orthographic, with Eevee in Blender 4.5.15 LTS,
lit from the upper left. The render is shrunk from 256 to 32 pixels with
hard edges, reduced to twelve colours and outlined in the fermenter icon's
#1E150C. The views were chosen by eye at 32 pixels from trial renders (the
reflux still from its left side, where its column stands clear of its
arm). The items now say `Icon = TLG_PotStill`, `TLG_RefluxStill`,
`TLG_DryingColumn` and `TLG_FuelFilter`. Two renders of one model gave the
same icon (the 256-pixel renders differed in a few pixels).

The machine-models mode now also checks that each item's icon loads the
mod's `Item_TLG_<Name>.png` (not the game's question mark), and equips
each item in turn to photograph it with the interface shown.

| Launch | Result | What it showed |
| --- | --- | --- |
| 125 | **14/0** | All four icons found. The reflux still's, the drying column's and the filter's showed in the equipped-item button. The pot still's equip was queued behind the 1200-tick do-nothing action before it; its step timed out after 900 ticks (reported, not counted as a failure), and the button was empty in its picture |
| 126 | **15/0** | The equips moved before that action: all four icons in the button, the stills now told apart at a glance |

Each console had no exception.

Evidence:
[2026-11-03_rt-sp_harness_run125_machine_icons.txt](evidence/2026-11-03_rt-sp_harness_run125_machine_icons.txt),
[2026-11-03_rt-sp_harness_run126_machine_icons.txt](evidence/2026-11-03_rt-sp_harness_run126_machine_icons.txt),
the button crops
[2026-11-03_run126_machine_icons_buttons.jpg](evidence/2026-11-03_run126_machine_icons_buttons.jpg)
and the icons enlarged beside the fermenter's,
[2026-11-03_machine_icons_8x.png](evidence/2026-11-03_machine_icons_8x.png).

Not checked: the icons in the inventory list (the list stayed collapsed
in launch 68's shots, so the button stands in for it), multiplayer.

## 2026-11-03 — RT-SP client harness, launches 127–128 (the zip with the icons)

Launch 127. Command: `tools/rehearse-install.ps1`. It rebuilt the package
first (197/197 tests, compile check 105/0, translations OK, every shipped
XML file parsing): the zip of commit `f69a74a`, 108 files, SHA-256
`f9c52565…`, 3,738,890 bytes. It differs from launch 123's zip
(`0a0a6a1e…`, 104 files) in the four icons (`Item_TLG_PotStill.png`,
`Item_TLG_RefluxStill.png`, `Item_TLG_DryingColumn.png`,
`Item_TLG_FuelFilter.png`, each with the hash its provenance records), the
item scripts' `Icon` lines and comments, and the changelog and notice.
The zip matched its manifest, was installed into a fresh isolated cache
and ran the full harness.
Evidence:
[2026-11-03_rt-sp_harness_run127_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run127_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 123; phase
B again found the placed reflux still and drying column. The console's one
exception came from the harness's own deep-recursion probe, and no line
named the models or the icons.

Launch 128, `-Mode machine-models` with the mod deployed from the
package's item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**15/0**, as launch 126. The deployed icons and models carried the
shipped hashes, and each icon showed in the equipped-item button. The
console had no exception.
Evidence:
[2026-11-03_rt-sp_harness_run128_machine_icons_packaged.txt](evidence/2026-11-03_rt-sp_harness_run128_machine_icons_packaged.txt).

## 2026-11-03 — RT-SP client harness, launch 129 (icons for the four items with no model)

The user asked, in the asset-requirements session, for icons for the
sampling kit, the yeast starter, the fuel stabilizer and the field
manual (D-028). None has a model, so `tools/blender/pz_icon_props.py`
builds simple shapes for each and renders them through the same pipeline
as the model icons: for the kit, three small jars of fuel and a red rubber
hose; for the starter, a jar of cream culture under a tied cloth; for the
stabilizer, a corked bottle of tar with a label; for the manual, an olive
field manual. The first try made the starter a squat tub, too like the
filter, and the stabilizer a tin can. The second made them a taller jar
under a cloth dome and a bottle, which read apart at 32 pixels. Two
renders gave the same files, and the four model icons rebuilt byte for
byte after the renderer was split to serve both.

The machine-models mode now checks all eight rendered icons and equips
the four new items too.

Launch 129: **19/0**. Every one of the eight items loaded its own
`Item_TLG_<Name>.png` and, when equipped, showed it in the equipped-item
button. The console had no exception.

Evidence:
[2026-11-03_rt-sp_harness_run129_item_icons.txt](evidence/2026-11-03_rt-sp_harness_run129_item_icons.txt),
the button crops
[2026-11-03_run129_item_icons_buttons.jpg](evidence/2026-11-03_run129_item_icons_buttons.jpg)
and all nine icons enlarged,
[2026-11-03_item_icons_8x.png](evidence/2026-11-03_item_icons_8x.png).

Not checked: the icons in the inventory list (the button stands in for
it), multiplayer.

## 2026-11-03 — RT-SP client harness, launches 130–131 (the zip with every icon)

Launch 130. Command: `tools/rehearse-install.ps1`. It rebuilt the package
first (197/197 tests, compile check 105/0, translations OK, every shipped
XML file parsing): the zip of commit `21feecf`, 112 files, SHA-256
`b01db3e7…`, 3,743,610 bytes. It differs from launch 127's zip
(`f9c52565…`, 108 files) in the four new icons
(`Item_TLG_FuelSampleKit.png`, `Item_TLG_YeastStarter.png`,
`Item_TLG_FuelStabilizer.png`, `Item_TLG_ManualFuelSystems.png`), the item
script's `Icon` lines, and the changelog and notice. The zip matched its
manifest, was installed into a fresh isolated cache and ran the full
harness.
Evidence:
[2026-11-03_rt-sp_harness_run130_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run130_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 127. The
console's one exception came from the harness's own deep-recursion
probe, and no line named the icons or models.

Launch 131, `-Mode machine-models` with the mod deployed from the
package's item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**19/0**, as launch 129. The nine deployed icons carried the shipped
hashes, all eight rendered ones loaded, and each item equipped showed its
icon. The console had no exception.
Evidence:
[2026-11-03_rt-sp_harness_run131_item_icons_packaged.txt](evidence/2026-11-03_rt-sp_harness_run131_item_icons_packaged.txt).

## 2026-11-03 — RT-SP client harness, launches 132–133 (floor models for the four small items)

The user asked, in the asset-requirements session, for floor models for
the sampling kit, the yeast starter, the fuel stabilizer and the field
manual ("Add floor models"; D-029). They are made from the shapes their
icons are rendered from. `tools/make-prop-models.ps1` runs
`tools/blender/pz_prop_models.py`, which builds each shape as it lies on
the floor, with half the icons' sides. The lying shapes come from
`pz_icon_props.py`'s new `floor` switch: the kit's hose coiled flat, clear
of its jars; the manual on its back. The script joins each into one mesh
with a palette texture of flat colours and exports it as the supplied
models are. Dumped, each file matched the supplied filter's: Y up,
`UnitScaleFactor` 100, the node turned −90° about X, no node scaling,
triangles, one material, 1.0 along its largest side. Re-imported in
Blender, all four stood upright in their colours. Two builds first
differed in the exporter's object ids, which come from Python's string
hash (Blender seeds it anew each run), and in the order of the starter's
triangles. The build now fixes both, and three rebuilds differed only in
the time in each file's header. The eight icons rendered again byte for
byte after the shape builder gained the switch.

The machine-models mode now puts the four left of the fermenter, two on
each side of the character, and checks their model scripts and wiring
with the others'. In this mode the kit keeps its own model; until now
the harness gave it the true-size test barrel in every model mode. The
clear-ground search now covers every square the row uses (it stopped at
square 7).

Launch 132: **19/0**. All eight model scripts named their own mesh and
texture, the items named their models, and all nine items lay on their
squares. The four drew on the floor, but a morning fog washed out every
model in the frame, the supplied ones too. At zoom 0.25 the two beside
the character stood at the foot of the frame: an item is drawn about a
row below the feet of a character standing on its row.

Launch 133, with the fog intensity's override set to 0 as vanilla's
tutorial does (`Tutorial1.lua`) and the close-ups taken from a square
nearer the camera: **19/0**. The fog read 0 before the override as well
as after, so the clear sky may be the weather's. In clear light all four
showed their colours: the kit's three jars of fuel with dark lids and the
red hose coiled in front, the starter's jar under its cloth and string,
the stabilizer's corked bottle with its label and red band, the manual on
its back with its badge and title band. Widths were measured against the
character, taken as 1.75 m from hair to soles, with the camera 30° above
the ground. At zoom 0.5 the starter, the stabilizer and the manual came
out 12–18 % wider than planned, and the supplied filter and the drying
column's jar 14 % wider, in frames from the same run. The close-ups at
0.25 gave 12–15 %. So the new models take the supplied models' scale.
The console had no exception and no line about the models.

Evidence:
[2026-11-03_rt-sp_harness_run132_floor_models.txt](evidence/2026-11-03_rt-sp_harness_run132_floor_models.txt),
[2026-11-03_rt-sp_harness_run133_floor_models.txt](evidence/2026-11-03_rt-sp_harness_run133_floor_models.txt),
and the sheet
[2026-11-03_run133_floor_models_sheet.jpg](evidence/2026-11-03_run133_floor_models_sheet.jpg).

Not checked: an item dropped by a player (turned at random), the models
after a reload, multiplayer.

## 2026-11-03 — RT-SP client harness, launches 134–135 (the zip with the floor models)

Launch 134. Command: `tools/rehearse-install.ps1`. It rebuilt the package
first (197/197 tests, compile check 105/0, translations OK, every shipped
XML file parsing): the zip of commit `8950b57`, 120 files, SHA-256
`e249719d…`, 3,813,797 bytes. It differs from launch 130's zip
(`b01db3e7…`, 112 files) in the four floor models (eight new files: for
each, an FBX in `media/models_X/TLG` and its texture in
`media/textures/TLG`), the model script's four entries and the item
script's `WorldStaticModel` lines. The sprint pose's comment, the
changelog and the notice changed too. The zip matched its manifest, was
installed into a fresh isolated cache and ran the full harness.
Evidence:
[2026-11-03_rt-sp_harness_run134_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run134_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 130. The
console's one exception came from the harness's own deep-recursion
probe, and no line named the models.

Launch 135, `-Mode machine-models` with the mod deployed from the
package's item tree (`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`):
**19/0**, as launch 133. The four deployed models and textures carried
the hashes built into the mod, and all four drew on the floor in their
colours, as in launch 133. The fog read 0 again before the override. The
console had no exception.
Evidence:
[2026-11-03_rt-sp_harness_run135_floor_models_packaged.txt](evidence/2026-11-03_rt-sp_harness_run135_floor_models_packaged.txt).

## 2026-11-03 — RT-MP harness, launches 136–138 (a server and one client, unattended)

The user asked, in the asset-requirements session, for a multiplayer test
("Yes, test multiplayer"). `tools/run-mp-harness.ps1` runs the TLGDev
dedicated server and its clients on this machine with no clicks:
- a fresh world with one spawn point (the harness's open ground at
  10660,10645) and no zombies;
- two test accounts, made admin from the server console (`adduser`,
  `setaccesslevel`);
- each client joins by IP as vanilla's Join by IP popup does and passes
  character creation with the screens' own Next handlers
  (`TLGHarness/MPHarness.lua`);
- a relay on the server (`TLGHarness/MPServer.lua`) carries the harness's
  messages between the clients.

Stage 1 is the server and one client.

Launches 136 and 137: the server stopped before loading any Lua. Its
pose-file checksum found none of the mod's `AnimSets` files ("couldn't
find …tlgcarryvessel.xml"), and world generation then failed. The game's
Java resolves `%LOCALAPPDATA%` for this session's processes to the Claude
app's package folder, and the checksum mixes that path with the one it
was given (engine capabilities, "RT-MP: a dedicated server needs the
mods' real path"). The dev server last started on 2026-10-30, before the
mod had pose files. Launch 137 failed because launch 136's server had
printed "Server Terminated" but kept running, holding the port and its
log files. The launcher now passes each cache's final path and stops any
harness server left running.

Launch 138: **2/0**.
- The server was up in 21 s, with Zombies 6 and the population
  multipliers 0. Both accounts were created and made admin (the console
  lines masked).
- Client A joined, made its character (unemployed) and spawned at
  10660,10645, as tlga with the admin role and no zombies in its cell.
- A harness message came back through the server's relay after 4 ticks.
- Client A's picture shows the character with its name tag, in the
  morning fog.

Evidence:
[2026-11-03_rt-mp_harness_run138_client_a.txt](evidence/2026-11-03_rt-mp_harness_run138_client_a.txt),
[2026-11-03_rt-mp_harness_run138_server.txt](evidence/2026-11-03_rt-mp_harness_run138_server.txt).
The server's raw log is not kept: `adduser` echoes the passwords.

## 2026-11-03 — RT-MP harness, launches 139–145 (two clients)

Client A acts and client B watches, both on the TLGDev server. Items come
from the server (`MPServer.lua`: `AddItem` with `sendAddItemToContainer`,
or `AddWorldInventoryItem` for the floor), never from a client. The two
clients wait on each other through the server's relay.

What was checked, in launch 145 (A **18/2** over its two sessions, B
**10/0**):
- **The mod's requests** from a client, through `TLG.Net` and the
  server's handlers. A fuel sample and a stabilizer treatment of a can in
  A's inventory were answered. The same treatment sent again with the same
  request id came back from the ledger (`duplicate=true`), and A still had
  one of its two stabilizers. The can's record (its mod data) read the
  same on A's client as on the server.
- **A machine's status** asked by either player within reach of a vessel
  the server put down: `Ready` for both. In launch 139 it was asked from
  about four tiles away and refused with `no_access`.
- **The manual** in the server's loot: 9 manuals in 400 containers filled
  on the server from four of its loot lists (12 in launches 139–140). The
  rolled manual reached A with its print media data, its menu offered
  **Inspect**, and reading it was recorded on the server. A's own client
  did not show it read, at once or 5 s later. Vanilla's Nolan's flier,
  given and read the same way, behaved exactly so: recorded on the server,
  not on the client.
- **The small items' floor models**, dropped by A through the inventory's
  **Drop** after walking to each square. A's and B's clients each listed
  the same items on the same squares around the spawn point as the server
  did, all five there. A then left to the main menu and joined again; A's
  and B's lists still matched the server's. In the pictures each model
  lies in its colours on both screens.
- **The carry pose on another player's screen.** With the vessel in A's
  arms, B's client held the carry pose's mask (`RightHandMask` =
  `tlgcarryvessel`) and the vessel in both hands on A's character at each
  gait. B's own screenshots show A carrying it standing, walking, running,
  sprinting, sneaking and crouched; sneaking, A is drawn faded on B's
  screen.
- **Taking a heavy item off the floor** failed for the vessel and for
  vanilla's meteorite alike: both stayed on their squares. The take was
  made as a double-click in the loot window does
  (`ISInventoryPaneContextMenu.equipHeavyItem` on the item the floor
  listing holds). On the server `ISEquipHeavyItem.complete` stopped at its
  line 63 (`DoRemoveItem` of a nil container: a world item has none
  there). Launch 144 ran the meteorite alone on a server and client
  without The Last Gallon (the harness's own requirement on it stripped):
  it failed the same way. So this is the game's own multiplayer bug, and
  it keeps players from taking the vessel into their arms from the floor.
  To watch the pose anyway, the server handed A a vessel the way that
  `complete` does on the server (`AddItem`, both hands, `sendEquip`).

How the harness got there:
- Launch 139: the drops landed a square or two off. The harness had
  teleported A, and the server dropped each item where it last saw her.
  It now walks.
- Launches 140–142: the vessel pickup was tried from the next square and
  with the interface hidden, then standing on the vessel. The listing held
  it and the action ran, and then the server error above showed. Launch
  143 meant to run without the mod, but the harness's `require` brought it
  in, so launch 144 strips that line from the deployed copies.
- Launch 142 read `running=false` while running. That leg now turns on
  Toggle to Run, as the single-player legs do, and reads `running=true` on
  both screens.

Evidence:
[2026-11-03_rt-mp_harness_run145_client_a.txt](evidence/2026-11-03_rt-mp_harness_run145_client_a.txt),
[2026-11-03_rt-mp_harness_run145_client_b.txt](evidence/2026-11-03_rt-mp_harness_run145_client_b.txt),
[2026-11-03_rt-mp_harness_run145_server.txt](evidence/2026-11-03_rt-mp_harness_run145_server.txt),
[2026-11-03_rt-mp_harness_run144_nomod_client_a.txt](evidence/2026-11-03_rt-mp_harness_run144_nomod_client_a.txt)
and
[2026-11-03_rt-mp_harness_run144_nomod_server.txt](evidence/2026-11-03_rt-mp_harness_run144_nomod_server.txt).
The sheets are
[2026-11-03_run145_mp_carry_on_other_screen_sheet.jpg](evidence/2026-11-03_run145_mp_carry_on_other_screen_sheet.jpg)
and
[2026-11-03_run145_mp_floor_sheet.jpg](evidence/2026-11-03_run145_mp_floor_sheet.jpg).
Client A's file ends with `SUMMARY pass=2 fail=0`: the report starts its
counts again after the rejoin, so that line covers the second session
only. Its lines give 18 passed and 2 failed in all. Since then the harness
counts the earlier sessions' lines into the summary.

The server's path, tried on a real server: started with its cache reached
through a junction, the server stopped on the pose-file checksum
("couldn't find …\servercache_link\…tlgcarryvessel.xml", "Server
Terminated"), as the replay predicted. A symbolic link was not tried.

Not checked:
- the world menu's **Grab** of the vessel;
- two players working one machine at once;
- the TLG pour, refuelling, conversions, generators and vehicles in
  multiplayer;
- a server restart;
- players without admin rights (both test accounts were admins);
- a real network (everything ran on this machine).

## 2026-11-03 — RT-MP harness, launches 146–147, and RT-SP launch 148 (the vessel taken off the floor on a server)

On a server the mod now takes the fermentation vessel off the floor
itself (D-030). The harness takes it as a player does: A stands on its
square, and `equipHeavyItem` gets the item the loot window's floor listing
holds, as a double-click passes it. The harness's server side gained
three things:
- `probe_vessel`: where the server holds the vessel (on the floor around
  the spawn point, or in a player's inventory, in both hands or not), how
  many vessels lie or are carried there in all, its batch, and its entry
  in the hourly reading's list;
- a log of every take the mod makes on the server, with its result
  (`Machines.takeOnServer`, wrapped by the harness);
- `try_take`: the take run on the server, as the server runs a completed
  action, for the player who does not hold the vessel.

The vessel the server puts down now has a batch running
(`ethanol_ferment`, written as loading and starting one leave the
record), so the pickup's accounting shows.

Launch 146 ran the carry part alone (`-Only carry`: A **10/0**, B
**8/0**). Launch 147 ran the whole run (A **26/0** over its two sessions,
B **11/0**). Both gave the same results:
- **Vanilla's meteorite** still stays on its square, as the game leaves
  it on a server (the control).
- **The vessel** came off the floor into A's arms: in both hands, and gone
  from its square on A's client. On the server it was in A's inventory and
  both hands, the only vessel there, its batch carried (`Paused`,
  `not_placed`) and off the hourly list. A's client got the same record
  with the item. The server's log has one take, by A: `true`.
- **Carried and put down.** B saw the carry pose at every gait, as in
  launch 145. Put down at A's feet (the server's command for it), the
  vessel lay where its record says (10658,10647), listed there, its batch
  running again (`Processing`).
- **Both players at once.** B walked next to the vessel. A sent B a
  message and took the vessel at once; B queued its take on the tick the
  message reached it (tick 5 of its waiting step in launch 146, tick 4 in
  launch 147). On the server A's take came first (`true`). Then B's action
  reached the server's `complete` and was refused (`false`). There was one
  vessel, in A's arms, its batch carried; each client saw A holding it and
  B not. Run on the server for B against the vessel A held, the take
  returned false again and A kept it.
- Everything launch 145 checked passed again in launch 147: the mod's
  requests, the ledger, the can's record, a machine's status for both
  players (now `Processing`), the manual in the server's loot and read,
  and the floor models for both players and after A's rejoin.

Launch 148 (`tools/run-sp-harness.ps1 -Mode pickup`, single player)
checked that the change leaves single player as it was: **43/0**, the
same checks as run 81. Among them, fermenter C was taken into both hands
the double-click way and off its tile, its batch paused while carried,
dropped at the feet and resumed there, then taken again and put down by
taking a meteorite.

Evidence:
[2026-11-03_rt-mp_harness_run146_client_a.txt](evidence/2026-11-03_rt-mp_harness_run146_client_a.txt),
[2026-11-03_rt-mp_harness_run146_client_b.txt](evidence/2026-11-03_rt-mp_harness_run146_client_b.txt)
and
[2026-11-03_rt-mp_harness_run146_server.txt](evidence/2026-11-03_rt-mp_harness_run146_server.txt),
[2026-11-03_rt-mp_harness_run147_client_a.txt](evidence/2026-11-03_rt-mp_harness_run147_client_a.txt),
[2026-11-03_rt-mp_harness_run147_client_b.txt](evidence/2026-11-03_rt-mp_harness_run147_client_b.txt)
and
[2026-11-03_rt-mp_harness_run147_server.txt](evidence/2026-11-03_rt-mp_harness_run147_server.txt),
and
[2026-11-03_rt-sp_harness_run148_pickup.txt](evidence/2026-11-03_rt-sp_harness_run148_pickup.txt).
The domain suite has the server's take as a case of its own in
`tests/integration/test_machine_sites.lua` (198 cases, all passed). With
the take disabled, the case fails as the game does.

Not checked:
- the refusals for a vessel out of reach (more than 2.5 tiles) or on no
  square, live: `tests/integration/test_machine_sites.lua` covers them;
- the vessel taken from a container in multiplayer (the game's own
  `complete`, which the mod leaves alone; from the player's own inventory
  since checked, launch 151);
- the world menu's **Grab** of the vessel in multiplayer;
- two players working one machine's batch at once; the TLG pour,
  refuelling, conversions, generators and vehicles in multiplayer; a
  server restart; players without admin rights; a real network.

## 2026-11-03 — RT-SP launch 149 and RT-MP launch 150 (the zip with the server's take)

Launch 149. Command: `tools/rehearse-install.ps1`. It rebuilt the package
first (198/198 tests, compile check 111/0, translations OK, every shipped
XML file parsing): the zip of commit `9824306`, 120 files, SHA-256
`0947f1e7…`, 3,815,729 bytes. It differs from launch 134's zip
(`e249719d…`, `8950b57`) in `Machines.lua` (the server's take, D-030)
and in the shipped support matrix and changelog (multiplayer). The zip
matched its manifest, was installed into a fresh isolated cache and ran
the full harness.
Evidence:
[2026-11-03_rt-sp_harness_run149_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run149_install_rehearsal.txt).

Result: phase A **94/0**, phase B **14/0**, the same as launch 134. The
console's one exception came from the harness's own deep-recursion
probe, and the mod logged no error or warning.

Launch 150: `tools/run-mp-harness.ps1 -Clients 2 -Only carry` with the
mod deployed from the package's item tree
(`-ModSource …\dist\TheLastGallon\Contents\mods\TheLastGallon`). The
server's copy held the package's own docs, and its `Machines.lua` matched
the package's. Result: A **10/0**, B **8/0**, as launch 146. The vessel
came off the floor into A's arms with its batch carried. B saw it carried
at every gait, and it ran again where it was put down. In the race B's
action reached the server and was refused, as in launches 146 and 147.
Evidence:
[2026-11-03_rt-mp_harness_run150_packaged_client_a.txt](evidence/2026-11-03_rt-mp_harness_run150_packaged_client_a.txt),
[2026-11-03_rt-mp_harness_run150_packaged_client_b.txt](evidence/2026-11-03_rt-mp_harness_run150_packaged_client_b.txt)
and
[2026-11-03_rt-mp_harness_run150_packaged_server.txt](evidence/2026-11-03_rt-mp_harness_run150_packaged_server.txt).

## 2026-11-03 — RT-MP launch 151 (a vessel equipped from the inventory on a server)

Only one of the paths the server's take changed had worked on a server
before: a vessel in the player's own inventory equipped into both hands,
as a double-click in the inventory does. Before D-030 the game's
`complete` ran for it; now the mod's take must recognise the player as
the holder and leave the item to that `complete`. After the race, the
server gave A a second vessel and A equipped it from the inventory
(`equipHeavyItem` on the inventory item). Command:
`tools/run-mp-harness.ps1 -Clients 2 -Only carry`.

Result: A **12/0**, B **8/0**. The vessel came into A's hands, and the
server held it in A's inventory and both hands. The server's log shows
the mod's take returning nothing for it (`tlga:nil`), so the game's own
`complete` did the equip. Everything launch 146 checked passed again,
the race included (B's take refused on the server).
Evidence:
[2026-11-03_rt-mp_harness_run151_client_a.txt](evidence/2026-11-03_rt-mp_harness_run151_client_a.txt),
[2026-11-03_rt-mp_harness_run151_client_b.txt](evidence/2026-11-03_rt-mp_harness_run151_client_b.txt)
and
[2026-11-03_rt-mp_harness_run151_server.txt](evidence/2026-11-03_rt-mp_harness_run151_server.txt).

Not checked: a vessel taken from a crate or another container in
multiplayer (also left to the game's `complete`).

## 2026-11-03 — RT-MP launches 152–155 (plain players; the world menu's Grab; two players on one fermenter)

The user asked for the multiplayer cases not run yet (relayed by the
asset-requirements session: "Yes, test the rest"). Everything ran on this
machine, unattended. A real network needs a second machine, and the user
chose to leave it NOT RUN ("Leave it not run").

**Plain players.** `-NonAdmin` makes both test accounts plain players.
Launches 152 and 153 left them admins and are not counted. Launch 152
only skipped the `setaccesslevel` command, but accounts keep their access
level between runs in the server's database. Launch 153 sent the level
"none", and the server refused it ("Access Level '' unknown"). From
launch 154 the launcher sets the role by name, `user`. Both clients now
walk to where they stand rather than being teleported.

Launch 154 was the full run with both players `role=user` (the server
logged "User tlga is now user"): A **28/0**, B **11/0**. Everything
launch 151 checked passed, the race and the inventory equip included. The
server logged no kick and no anti-cheat line. The launcher's scan for
those had matched two packet names in the server's start-up list
(`ViewBannedIPs`, `ViewBannedSteamIDs`); it now matches whole words.

**The world menu's Grab and two players on one fermenter**
(`-Only machines`, launch 155: A **13/0**, B **2/0**):
- **Grab.** A running vessel the server put down was taken with the world
  menu's **Grab** (`ISWorldObjectContextMenu.onGrabWItem`). On a client,
  that queues an inventory transfer (`ISInventoryTransferAction`), which
  the server carries out as an item transaction. None of the mod's Lua saw
  it, and the mod's server-side take was not called. Right after the
  grab, the server's record still said `Processing` at the old tile. The
  first status asked while it was carried paused it (`Paused`,
  `not_placed`). The batch was credited only up to the last time the
  vessel was found placed (`seen`, here its start), so about 2 game
  minutes of work were lost, within D-015's ten. A second status 15 s
  later had counted nothing more.
- **Drop.** Dropped through the inventory, the vessel was seen being put
  down. Right after the drop the record was already `Processing` at the
  new tile and listed there for the hourly reading. A later status
  counted on from there (0.0129 h, then 0.0799 h).
- **Two players loading one fermenter.** Each carried 2 kg of sugar, a
  yeast and 10 L of water in a bucket, stood next to the same empty
  vessel and loaded it as the mod's menu does (`machine.loadFerment` with
  the target alone). B sent its request on the tick A's message reached
  it. A's load was taken: the batch `Processing` with 2 kg and 10 L, and
  A's sugar, yeast and water gone. B's was refused (`machine_busy`), and
  B kept all of its own.

Evidence:
[2026-11-03_rt-mp_harness_run154_nonadmin_client_a.txt](evidence/2026-11-03_rt-mp_harness_run154_nonadmin_client_a.txt),
[2026-11-03_rt-mp_harness_run154_nonadmin_client_b.txt](evidence/2026-11-03_rt-mp_harness_run154_nonadmin_client_b.txt),
[2026-11-03_rt-mp_harness_run154_nonadmin_server.txt](evidence/2026-11-03_rt-mp_harness_run154_nonadmin_server.txt),
and the same three for launch 155,
[2026-11-03_rt-mp_harness_run155_machines_client_a.txt](evidence/2026-11-03_rt-mp_harness_run155_machines_client_a.txt),
[2026-11-03_rt-mp_harness_run155_machines_client_b.txt](evidence/2026-11-03_rt-mp_harness_run155_machines_client_b.txt)
and
[2026-11-03_rt-mp_harness_run155_machines_server.txt](evidence/2026-11-03_rt-mp_harness_run155_machines_server.txt).

## 2026-11-03 — RT-MP launches 156–160 (pours, refuelling, a generator and a car; two multiplayer bugs fixed)

`-Only fuel`, one client, at the Muldraugh Gas2Go. From launch 157 it ran
on the shortest day (DayLength 1), so a generator's and a car's burn show
within the run. The server finds a pump with stock and puts down a car
with an empty tank three squares off it, as the single-player chain parks
it, plus two empty, connected generators. A then does the single-player
chain's hops through the game's own menu functions, which walk and equip
as a click does: a pump into an empty can, the can into the car, the pump
into the car, a can into the first generator. Then come the mod's pour
(petrol, then ethanol refused, then ethanol confirmed into the second
generator), both generators started, the first one's burn, unplugging,
taking and putting it back, and the car started and left idling. After
each step the server reports the pump, the tank, both generators and A's
cans with their records.

Launch 156 (A 9/10) found two bugs in the mod:
1. **Vanilla's refuelling did nothing with the mod on a server.** Filling
   the can at the pump, pumping into the car and pouring the can into the
   generator played on the client and moved no fuel. The server's log has
   `ISTakeFuel.lua:100` "attempted index: getSquare of non-table",
   `ISAddFuel.lua:73` "attempted index: getFluidContainer of non-table" and
   "no such vehicle id= nil". A client sends a timed action's fields named
   as its constructor's parameters, read from the function itself (BC
   `NetTimedAction.set`), and the server calls the constructor with them.
   The mod had wrapped those constructors as `function(self, ...)`, which
   declares none, so the server built each action empty. Each wrapped
   constructor now declares vanilla's parameters: `ISTakeFuel`,
   `ISRefuelFromGasPump`, `ISAddGasolineToVehicle`,
   `ISTakeGasolineFromVehicle` and `ISAddFuel`. A test in
   `tests/integration/test_mp_actions.lua` fails if a constructor is
   wrapped with varargs again.
2. **The pour's result never reached the player.** The mod's pour ran on
   the server, but its callback stayed on the client and never ran: a
   function is not sent with the action (BC `PZNetKahluaTableImpl.save`).
   So an incompatible fuel was refused with no message, and no offer to
   pour it anyway. The client now keeps the callback under the request id
   it sends with the action, and the server answers under that id, as the
   mod's requests are answered. Launch 157 still showed no result. The
   server passes the fields it receives in order, so the skipped function
   let the id take the callback's place. The client now takes the callback
   off the action, and a nil keeps its place.

Launches 157–159 settled the harness:
- Launch 157: the generator had to be unplugged before it could be taken
  (`ISTakeGenerator.isValid` refuses a connected one). Its record is
  reconciled with the game's burn when it is read (a status writes
  nothing), so the burn is checked against the status's answer.
- Launch 158: the car was locked; the server now gives A its key
  (`BaseVehicle.createVehicleKey`).
- Launch 159: the car did not start. A start can fail by chance (the
  mod's gate weighs the fuel's quality), so the harness tries three
  times, as the single-player gate step does.

Launch 160 (A **19/0**):
- The pump filled the empty can with 10 L, with the station's fuel
  record, the same on the client as on the server.
- The can went into the car (10 L) and the pump took it to 59 L, the
  tank's record matching both times, also on the client.
- A can put 5 L into the generator.
- The mod's pour added 3 L of petrol. Ethanol into that petrol generator
  was refused (`incompatible`) with nothing moved. Confirmed, the ethanol
  went into the empty second generator. All three results reached the
  player's client.
- The petrol generator started and the ethanol one was refused.
- The first generator burned 0.012 L, and the status's record followed
  it. Unplugged, taken and put back, it carried that record to the item
  and back.
- The car unlocked with its key, started on the first try and idled
  0.025 L, its record following.

Evidence, client A's file and the server's for each of launches 156–160:
[2026-11-03_rt-mp_harness_run156_fuel_client_a.txt](evidence/2026-11-03_rt-mp_harness_run156_fuel_client_a.txt),
[2026-11-03_rt-mp_harness_run156_fuel_server.txt](evidence/2026-11-03_rt-mp_harness_run156_fuel_server.txt),
[2026-11-03_rt-mp_harness_run157_fuel_client_a.txt](evidence/2026-11-03_rt-mp_harness_run157_fuel_client_a.txt),
[2026-11-03_rt-mp_harness_run157_fuel_server.txt](evidence/2026-11-03_rt-mp_harness_run157_fuel_server.txt),
[2026-11-03_rt-mp_harness_run158_fuel_client_a.txt](evidence/2026-11-03_rt-mp_harness_run158_fuel_client_a.txt),
[2026-11-03_rt-mp_harness_run158_fuel_server.txt](evidence/2026-11-03_rt-mp_harness_run158_fuel_server.txt),
[2026-11-03_rt-mp_harness_run159_fuel_client_a.txt](evidence/2026-11-03_rt-mp_harness_run159_fuel_client_a.txt),
[2026-11-03_rt-mp_harness_run159_fuel_server.txt](evidence/2026-11-03_rt-mp_harness_run159_fuel_server.txt),
[2026-11-03_rt-mp_harness_run160_fuel_client_a.txt](evidence/2026-11-03_rt-mp_harness_run160_fuel_client_a.txt)
and
[2026-11-03_rt-mp_harness_run160_fuel_server.txt](evidence/2026-11-03_rt-mp_harness_run160_fuel_server.txt);
and
[2026-11-03_rt-mp_run156_server_constructor_errors.txt](evidence/2026-11-03_rt-mp_run156_server_constructor_errors.txt)
(the server's lines above).

## 2026-11-03 — RT-MP launch 161 (a server restart)

`tools/run-mp-harness.ps1 -Clients 2 -Restart`: the full run, ending with
a server restart in place of A's rejoin. A first asks the server for its
can's and its vessel's records and keeps them in a file. Then both
clients leave to the main menu. The launcher saves and quits the server,
starts it again on the same world (up in 24 s) and writes each client a
go-file, and both join again.

Result: A **30/0** over its sessions, B **12/0**. After the restart both
clients' floors matched the server's: the two vessels, the five small
items and the meteorite on their tiles. The can's record came back
unchanged. The vessel's came back with the same state, site, hourly-list
entry, inputs and stage hours (`Processing`, 10658,10647, 6 kg and 30 L,
0.5250 h).

Evidence:
[2026-11-03_rt-mp_harness_run161_restart_client_a.txt](evidence/2026-11-03_rt-mp_harness_run161_restart_client_a.txt),
[2026-11-03_rt-mp_harness_run161_restart_client_b.txt](evidence/2026-11-03_rt-mp_harness_run161_restart_client_b.txt)
and
[2026-11-03_rt-mp_harness_run161_restart_server.txt](evidence/2026-11-03_rt-mp_harness_run161_restart_server.txt).

## 2026-11-03 — RT-MP launch 162 (a generator conversion)

`-Only conversion`, one client, on the shortest day (DayLength 1: the
conversion's 7.5 work hours took about 4.7 real minutes). The server put
down an empty generator by the spawn point and gave A the tools and parts
the single-player loop hands over. It set A's skills and the Generator
recipe on its own copy of the player, where the conversion's handlers
read them, as the single-player loop sets them; A's client set the same.
A then did what the workshop menu does: **Start** (`conversion.begin`),
**Hand over parts** (`conversion.deliver`), and **Work on it**
(`WorkshopMenu.work`, `ISTLGConversionWork`).

Result: A **7/0**.
- The conversion began (`InProgress`, inspect), and handing over the
  parts used a rubber hose, 4 screws and an electric wire.
- The work action reported to the server 31 times, a quarter hour of
  world time each, and ended by itself at `Commissioned`. The project's
  status said the same, and on the server the generator's effective
  profile is `generator_si_flex`. Its fuel record keeps the base profile
  (`generator_si_stock`); the commissioned conversion gives the effective
  one (Generators.profile).
- Ethanol poured into it without a confirmation was accepted, 3 L, and
  the result reached the player's client. The generator then started on
  it.

Evidence:
[2026-11-03_rt-mp_harness_run162_conversion_client_a.txt](evidence/2026-11-03_rt-mp_harness_run162_conversion_client_a.txt)
and
[2026-11-03_rt-mp_harness_run162_conversion_server.txt](evidence/2026-11-03_rt-mp_harness_run162_conversion_server.txt).

Still not checked in multiplayer: a real network (the user chose to leave
it NOT RUN, with no second machine), siphoning (it had the same fault and
has the same fix), a vehicle conversion, the stills and the drying column,
and a vessel taken from a crate.

## 2026-11-03 — RT-SP launch 163 and RT-MP launch 164 (the zip with the multiplayer fix)

Launch 163. Command: `tools/rehearse-install.ps1`. It rebuilt the package
first (200/200 tests, compile check 114/0, translations OK, every shipped
XML file parsing): the zip of commit `142d009`, 120 files, SHA-256
`16c93e7f…`, 3,817,600 bytes. It differs from launch 149's zip
(`0947f1e7…`, `9824306`) in the multiplayer fix (the constructor hooks in
`Stations.lua`, `Vehicles.lua` and `Generators.lua`, and the pour's reply
in `ISTLGPourFuel.lua`) and in the shipped support matrix and changelog.
The zip matched its manifest, was installed into a fresh isolated cache
and ran the full harness.

Result: phase A **94/0**, phase B **14/0**, the same as launch 149. Phase
A's fuel chain went through the changed hooks in single player: pump to
can, can to car, the siphon back into a can, can to generator, pump to
car, the blend, and the mod's pours with their replies. The console's one
exception came from the harness's own deep-recursion probe.
Evidence:
[2026-11-03_rt-sp_harness_run163_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run163_install_rehearsal.txt).

Launch 164, `tools/run-mp-harness.ps1 -Clients 1 -Only fuel` with the mod
deployed from the package's item tree. The server's copy held the
package's own docs, and its `Stations.lua` matched the package's. Result:
A **19/0**, as launch 160.
Evidence:
[2026-11-03_rt-mp_harness_run164_fuel_packaged_client_a.txt](evidence/2026-11-03_rt-mp_harness_run164_fuel_packaged_client_a.txt)
and
[2026-11-03_rt-mp_harness_run164_fuel_packaged_server.txt](evidence/2026-11-03_rt-mp_harness_run164_fuel_packaged_server.txt).

## 2026-11-03 — RT-MP launches 165–171 (siphoning, a vessel from a container, a car conversion, the stills and the drying column)

The user asked for the four cases still not run in multiplayer ("Yes, run
them", relayed by the asset-requirements session). All ran on this
machine, unattended; a real network stays NOT RUN, as the user chose.

**Siphoning** (`-Only fuel`, launch 165: A **20/0**). After the pump took
the car to 59 L, A got a rubber hose (the item tagged `base:siphongas`)
and siphoned through the game's own menu (`ISVehiclePartMenu.onTakeGasoline`)
into the can still in hand. 10 L went from the car (59 → 49 L) into the
can. The tank's record followed (49 L), and the can's record holds the
tank's fuel, its traces of sediment and water included. The rest of
launch 160's checks passed again.

**A vessel taken out of a container** (`-Only machines`, launches
166–167). The server put a vessel into the container nearest the spawn
point. No crate stood within 40 squares, so it was a bin (10665,10636).
A took it out as a double-click in the loot window does
(`equipHeavyItem`), which walked A to the bin. The vessel came into A's
hands. On the server it was in A's inventory and both hands, and the
mod's take returned nothing for it (`tlga:nil`), leaving it to the
game's own `complete`. The mod treats every container that is not a
character's inventory alike, a crate as a bin (D-030). Launch 166 showed
the same results but failed its check on the take log's spacing (a
run's first take has no space before it); launch 167 passed (A **15/0**,
B **2/0**, everything launch 155 checked too).

**A car conversion** (`-Only carconv`, launches 168–169, the shortest
day). The server parked a `Base.CarNormal` with an empty tank and gave A
its key, the tools and parts of `flex_car_normal`, and Mechanics 4 with
Basic Mechanics. A did what the workshop menu does: **Start**,
**Hand over parts** (2 rubber hoses, 2 engine parts, 6 screws and 2
electric wires used), **Work on it**. The work action paths to the engine
and reported 53 times (13 hours of world time, about 8 real minutes) up
to `Commissioned`. The car's profile on the server then read
`engine_si_flex`. In launch 168 A poured ethanol from where the work had
left it, at the engine. The server refused it (`no_access_destination`):
the mod takes a pour into a car only at the filler, and its menu offers
it only there. The empty car then would not start. Launch 169 (A **7/0**)
walked to the filler first: 3 L of ethanol went in without a
confirmation, with the result shown to the player, and the car started on
it at the first try.

**The stills and the drying column** (`-Only stills`, launches 170–171,
the shortest day). A fermenter's 97 hours do not fit in a run, so the
server ran a batch (20 kg of sugar, 100 L of water) to its end through the
domain, as `tests/domain/test_production.lua` runs it (July, a day at a
step: 11 L of ethanol in 100 L of water), and kept it done. The fermenter
stood between the pot still, the reflux still and the drying column, each
a square from A. Everything after went through the mod's machine
requests, as their menu sends them:
- two logs into each still's firebox (18 kg);
- the wash into each: 60 L into the pot still, the 51 L left into the
  reflux still;
- distilling, each still's status asked every 5 s;
- collecting each run into an empty jerry can;
- the reflux run into the drying column with quicklime, 12 hours of
  drying, and the dried ethanol collected.

In launch 170 the pot still stopped for heat (`no_heat`) and was still
waiting at the end. Its 60 L need 51 kWh at its firebox's efficiency, and
two logs give 34. A player feeds it again, as single-player run 28 did.
Launch 171 (A **13/0**) gave it two more logs when it stopped, and it
finished:
- the pot still's run: 6.54 L, 80 % ethanol, its purity;
- the reflux still's run: 4.95 L, 94 %;
- the dried ethanol: 4.67 L with 0.023 L of water, under 0.5 %, the cans'
  records holding each.

Evidence:
[2026-11-03_rt-mp_harness_run165_fuel_siphon_client_a.txt](evidence/2026-11-03_rt-mp_harness_run165_fuel_siphon_client_a.txt)
and
[2026-11-03_rt-mp_harness_run165_fuel_siphon_server.txt](evidence/2026-11-03_rt-mp_harness_run165_fuel_siphon_server.txt),
[2026-11-03_rt-mp_harness_run167_machines_container_client_a.txt](evidence/2026-11-03_rt-mp_harness_run167_machines_container_client_a.txt),
[2026-11-03_rt-mp_harness_run167_machines_container_client_b.txt](evidence/2026-11-03_rt-mp_harness_run167_machines_container_client_b.txt)
and
[2026-11-03_rt-mp_harness_run167_machines_container_server.txt](evidence/2026-11-03_rt-mp_harness_run167_machines_container_server.txt),
[2026-11-03_rt-mp_harness_run169_carconv_client_a.txt](evidence/2026-11-03_rt-mp_harness_run169_carconv_client_a.txt)
and
[2026-11-03_rt-mp_harness_run169_carconv_server.txt](evidence/2026-11-03_rt-mp_harness_run169_carconv_server.txt),
and client A's and the server's files for launches 170 and 171:
[2026-11-03_rt-mp_harness_run170_stills_client_a.txt](evidence/2026-11-03_rt-mp_harness_run170_stills_client_a.txt),
[2026-11-03_rt-mp_harness_run170_stills_server.txt](evidence/2026-11-03_rt-mp_harness_run170_stills_server.txt),
[2026-11-03_rt-mp_harness_run171_stills_client_a.txt](evidence/2026-11-03_rt-mp_harness_run171_stills_client_a.txt)
and
[2026-11-03_rt-mp_harness_run171_stills_server.txt](evidence/2026-11-03_rt-mp_harness_run171_stills_server.txt).

Still not run in multiplayer: a real network (the user's choice), a still
or drying column picked up while working, and a crate as such.

## 2026-11-03 — RT-SP launches 172–173 (the zip of `be48759`)

`tools/rehearse-install.ps1` built the zip of commit `be48759`: 120 files,
SHA-256 `85b078bf…`, 3,817,924 bytes, the same bytes in both launches.
200/200 tests, compile check 114/0 and translations OK came first. The zip
differs from launch 163's (`16c93e7f…`) only in the header comments of six
adapters (multiplayer now cited) and in the shipped support matrix and
changelog. It matched its manifest and was installed into a fresh
isolated cache.

Launch 172 froze. The game's log stops at frame 2485, right after phase
A's pump-to-car step queued the refuelling, with no error. The launcher's
watchdog stopped the client after 40 minutes. The Windows session was
unlocked when this was checked afterwards, and nothing was found that
explains it. The same code had passed that step in launch 163.

Launch 173, the same zip again: phase A **94/0**, phase B **14/0**, the
pump-to-car step included (39 L, its record carried). The console's one
exception came from the harness's own deep-recursion probe.

Evidence:
[2026-11-03_rt-sp_harness_run173_install_rehearsal.txt](evidence/2026-11-03_rt-sp_harness_run173_install_rehearsal.txt),
and launch 172's partial file,
[2026-11-03_rt-sp_harness_run172_install_rehearsal_stalled.txt](evidence/2026-11-03_rt-sp_harness_run172_install_rehearsal_stalled.txt).

## 2026-11-04 — RT-SP launches 174–176 (driving)

Command: `tools/run-sp-harness.ps1 -Mode driving` (request `sp-rtd`), the
repository's mod on 42.21.0, about 3 minutes a launch. The world has no
zombies, parked cars, traffic jams or vehicle and zone stories. The harness
removes every vehicle the cell holds and drives a `Base.CarNormal` south
on the main road below Muldraugh (the map's road zone at x 10585–10598
from y 10800). The lane is chosen nearest the road's middle where it is
street and clear from 4 tiles behind the car. The car drives itself on
the game's cruise control at 25 km/h. Every tick the five tiles across
the car are checked 22 tiles ahead. The car brakes on anything solid, a
tree, a vehicle, a zombie, a square that is not street or not loaded, or
a drift of 2.5 tiles. Afterwards no impact (speed lost while not braking)
and no damaged part may be found; brakes, tires, suspension and muffler
are left out, as vanilla wears them while driving.

The burn is counted where vanilla writes it: `Vehicles.Update.GasTank`
ends in `setContainerContentAmount(amount, false, true)`, about once a
game minute. The engine caches that function, so the harness wraps the
method in VehiclePart's method table instead. A call with three
arguments is vanilla's burn; a call with one comes from anyone else.

Two legs:
1. **Drive:** E10 (9 L petrol, 1 L ethanol) poured from a can through
   vanilla's `ISAddGasolineToVehicle`, then up to 350 tiles.
2. **Stall:** a 37.5 % ethanol blend no stock engine takes, the engine
   started past the gate. The mod's per-minute effects are held back until
   the car is moving at 15 km/h and vanilla has burned once; then the
   engine must stall on the move, burn nothing more and roll to a stop.

Launch 174 (**20/3**): both cars left their lane within ten tiles; the
drift guard braked them at 25 km/h, and neither hit anything or lost
condition. The debug spawn faces a car a few degrees off its direction
(forward vectors 10 and −5 degrees off south). The burns that did happen
matched vanilla's exactly and reconciled. The drive leg still failed its
`burn_by_vanilla_only` check, on its 0.02 L minimum (12 tiles burned
0.0077 L, all vanilla's), and its `drove` check, on the distance. Since
then the harness turns the car onto the road's line (`setAngles`,
measured with `getForwardVector`) and centres the lane.

Launch 175 (**22/3**): the drive leg passed everything (352 tiles,
0.778017 L against launch 176's 0.778136 L, all of it vanilla's burn).
The stall leg's engine stalled 0.02 game minute after the effects were
let go, at 15.8 km/h, before vanilla's first burn. So the three burn
checks had nothing to measure; the stall and the coast to a stop passed.
Since then the effects also wait for one burn.

Launch 176 (**26/0**):
- **Drive:** 352.1 tiles in 14.09 game minutes, top 25.3 km/h. The tank
  went 10.000000 → 9.221864 L: 0.778136 L, exactly the 14 vanilla burns,
  all on the move, and nothing else wrote the tank. The next read was
  `reconciled`: total 9.2219 = native, the blend 0.9222 L ethanol to
  8.2996 L petrol (worst deviation 5.6e-16). The engine ran throughout
  (`startFactor=1`). Vanilla's rate there: 0.055 L per game minute, 0.22 L
  per 100 tiles at 3500 rpm.
- **Stall:** the effects were released at 25.1 km/h after one burn
  (0.007796 L, reconciled). The engine stalled 0.78 game minute later, at
  24.7 km/h (`Stalling`, reason `too_much_ethanol`). The tank stayed at
  7.992204 L from the stall to the end, and the car rolled from tile 28 to
  tile 44 and stopped in its lane.
- **No collision:** no impact in either leg; every part at 100 before and
  after (wearing parts included). The cars held within 0.04 tiles of their
  line.

Found, not fixed (code reading; neither is exercised by the harness):
- `Vehicles.applyEffects` stalls engines without consulting the sandbox
  option "Bad fuel can stall engines"; only the start gate reads it.
- The power and wear factors `Consumers.evaluate` computes reach no
  vehicle or generator, although the player guide says stale, wet or dirty
  fuel costs power and wears the engine.

Not run: other chassis, a flex-converted car on the move, off-road
driving, the heater on, towing, multiplayer driving.

Evidence:
[2026-11-04_rt-sp_harness_run174_driving.txt](evidence/2026-11-04_rt-sp_harness_run174_driving.txt),
[2026-11-04_rt-sp_harness_run175_driving.txt](evidence/2026-11-04_rt-sp_harness_run175_driving.txt)
and
[2026-11-04_rt-sp_harness_run176_driving.txt](evidence/2026-11-04_rt-sp_harness_run176_driving.txt).

## 2026-11-04 — Domain suite and RT-SP launches 177–179 (engine effects, D-031)

Domain: `tools/run-tests.ps1` 214/214 (14 new cases in
`tests/domain/test_engine_effects.lua` and
`tests/integration/test_engine_effects.lua`). They cover:
- the power to run at, and its floor;
- the power never lowered twice, and given back;
- a repair becoming the base;
- wear carried as a fraction and normalised by the sandbox consumption;
- the stall option on a running car;
- a generator charged once per litre since its record was written: a tank
  run dry, a rewritten record, unseen fuel, the item's rate, and no charge
  on a multiplayer client.

Compile check 117/0, translations OK.

Command: `tools/run-sp-harness.ps1 -Mode engine-effects` (request `sp-rte`),
on the driving mode's cleared road with its crash guards (launches
174–176), about 4 minutes. Fixtures, declared in the harness:
- The tank's and the generator's records are aged in place, to 2.6 and 3.0.
- The wear rates run at 100 times their value, so whole points show in 350
  tiles and 6 hours.
- Stalls are off for the stale-petrol leg, so a random stall (1.2 % a game
  minute on that fuel) cannot cut it short.

Launch 177 (**35/1**): everything passed but the generator's wear check,
whose expectation evaluated the fuel as it was 6 hours before (wear factor
1.75 at 3.0). The mod charged the fuel aged to the moment of the charge,
as designed: 3 points and 0.00699 carried. The harness now takes the
factor as the charge does.

Launch 178, `-Mode driving` on the same code (**26/0**): the E10 drive and
the stall on the move as in launch 176, the engine effects running every
minute.

Launch 179 (**36/0**):
- **Stale petrol** (deg 2.6: power factor 0.851429, wear factor 1.742857):
  - Power: 4000 → 3406 0.12 game minutes after the cruise began, held for
    352 tiles. Quality 100 and loudness 40 were kept through
    `setEngineFeature`. Two game minutes after the stop the power was 4000
    again, with no state left in the Engine part.
  - Wear: the 0.778050 L burned in 14 game minutes owed 8.669705 points at
    100 times the rate. 8 came off the Engine part and 0.669705 was carried.
  - The burn was vanilla's alone and reconciled, with no impact and no
    other part damaged.
- **Stall option off:** a blend no stock engine takes (factor 0) ran 5.27
  game minutes and 122 tiles at 2000, half power, without a stall, and got
  4000 back two game minutes after the stop.
- **Time to 24 km/h:** 0.55 game minutes at full power (launch 178), 0.63 at
  85 % and 0.76 at half.
- **Generator** (`Base.Generator`, `ConditionLowerChanceOneIn` 30 read from
  its script): 8 L through `ISAddFuel`, the record aged to 3.0, switched on
  for 6 game hours at x40.
  - It burned 0.012 L, and vanilla took no condition.
  - At the next `ISAddFuel` the fuel had aged to 3.0093 (factor 1.752328).
    The charge made in `ISAddFuel.new` took 3 points and carried 0.009094,
    exactly the 3.009094 due.
  - Charged again at once, it took nothing.

Not run: multiplayer (the power reaches clients through `transmitEngine`),
flex-converted engines, other chassis and generator models, a fridge on the
generator.

Evidence:
[2026-11-04_rt-sp_harness_run177_engine_effects.txt](evidence/2026-11-04_rt-sp_harness_run177_engine_effects.txt),
[2026-11-04_rt-sp_harness_run178_driving.txt](evidence/2026-11-04_rt-sp_harness_run178_driving.txt)
and
[2026-11-04_rt-sp_harness_run179_engine_effects.txt](evidence/2026-11-04_rt-sp_harness_run179_engine_effects.txt).

## 2026-11-04 — RT-SP launch 180 (the zip of `b604f6b`)

`tools/rehearse-install.ps1` built the zip of commit `b604f6b`, the engine
effects (D-031): 121 files, SHA-256 `34fbd7f7…`, 3,823,662 bytes. 214/214
tests, compile check 117/0 and translations OK came first. The zip differs
from launch 173's (`85b078bf…`, `be48759`) in the new
`TLG/Domain/EngineEffects.lua`, the changed `Vehicles.lua`, `Generators.lua`
and `Resolver.lua`, and the shipped player guide, support matrix,
migrations notes and changelog. It matched its manifest and was installed
into a fresh isolated cache.

Result: phase A **94/0**, phase B **14/0**: the same 108 checks as launch
173, none added, missing or failed. Phase A ran through the changed
adapters on good fuel: the car idled half a game hour under the mod's
per-minute effects, and the can-to-generator step went through `ISAddFuel`,
whose wrapper now starts with the wear charge. The effects on poor fuel
are not part of the full harness; launch 179 tested them. The console's
one exception came from the harness's own deep-recursion probe.

Evidence:
[2026-11-04_rt-sp_harness_run180_install_rehearsal.txt](evidence/2026-11-04_rt-sp_harness_run180_install_rehearsal.txt).

## 2026-11-04 — RT-SP launches 181–182 (performance, gate 11)

Command: `tools/run-sp-harness.ps1 -Mode performance` (request `sp-rtpf`),
the repository's mod on 42.21.0, about 8 minutes a launch. The method, the
reference machine and every figure are in `docs/performance.md`.

The mod runs nothing every frame. Its three timers (every game minute, ten
minutes and hour) are called as their handlers call them and timed while
workloads are added on the driving test's cleared road:
- 400 petrol cans, first without records, then with them;
- 10, then 20 parked cars with tank records, 8 of them then idling on
  stale petrol;
- 8, then 32 fermenters loaded through the machine menu;
- the 32 as if a fire warmed each;
- the 32 with 20 days of hourly readings.

Also timed: fuel and a batch brought forward 1, 30 and 365 days, and the
fuel and machine menus. Frames were sampled for 20 seconds at each stage.

Launch 181 (**7/0**): every workload was built as intended (400 records,
20 cars in the cell with records, 8 engines running, 32 fermenters
running and listed, 480 readings each). Frames held 60 a second at every
stage. Their main-thread times read 0: `getCPUTime` and `getGPUTime`
already return whole milliseconds (the game divides its nanosecond counters
by 1,000,000, BC), and the harness divided again. The harness was fixed
before launch 182.

Launch 182 (**23/0**: the 7 again and 16 budgets): every figure within a
few percent of launch 181.
- Timers on the empty road: 0.0015, 0.0016 and 0.010 ms. With the 400
  recorded cans, the same.
- With 20 parked cars, 0.034 ms a minute; with 8 of them idling on stale
  petrol, 1.04 ms.
- With 32 running fermenters, 1.50 ms per ten-minute note and 1.55 ms per
  hourly reading.
- A year's catch-up: 9.1 ms for a can, 23.6 ms for a fermenter.
- Main thread per frame: 1.81 ms mean on the empty road and 1.76 ms with
  the recorded cans (1.69 without records). With 32 fermenters and 8
  engines idling, 3.58 ms: the game's work for the engines and models; the
  mod's timers average about 0.006 ms a frame there.

The budgets are about three times launch 181's medians (`RT.PF.budgets`).

Found, not fixed (open findings in `performance.md`, no budgets yet):
- **The fire scan.** 32 fermenters as if beside a fire: 92 and 90 ms per
  ten-minute note. Each note scans about 1,000 squares around each
  machine (2.85 ms a scan).
- **Readings kept by machines nobody uses.** The 32 with 480 readings
  each: 192 ms per note and 193–202 ms per hourly reading.
- **Catching up through readings.** One fermenter brought through its 20
  days of readings: 58–60 ms. Its menu costs as much on every right-click.

Not run: several clients sharing storage (multiplayer), other machines.
Electrical networks are not built in game in this build.

Evidence:
[2026-11-04_rt-sp_harness_run181_performance.txt](evidence/2026-11-04_rt-sp_harness_run181_performance.txt)
and
[2026-11-04_rt-sp_harness_run182_performance.txt](evidence/2026-11-04_rt-sp_harness_run182_performance.txt).

## 2026-11-04 — Domain suite and RT-SP launches 183–185 (the three findings fixed, D-032)

The user asked for the three findings of launches 181–182 to be fixed
("Yes, fix them"). D-032 makes the same work cheaper, with the same
results:
- one fire scan per ten-minute note serves every machine a fire warms;
- a trim picks the readings and notes to drop without sorting them;
- a catch-up sorts the notes' hours once for all its days;
- the notes and readings change the stored record instead of a copy.

Domain: 218/218. The four new cases compare the new code with a copy of
the old one on random records and fires: the k-th key against the sorted
keys, every day of `segments` against `siteDayMean` alone, the trim, and
the notes with ties. They passed under four seeds, and failed when the
fire list's order was swapped. Compile check 118/0 (the offline profile,
`tests/support/bench_machine_records.lua`, added), translations OK.
Offline, a 480-reading record's trim fell from 4.6 to 0.2 ms and its
catch-up through 20 days from 40 to 3.2 ms.

Launch 183, `-Mode performance` (**23/0**). Every workload as in launches
181–182, except:
- the 32 warmed fermenters: 10.3 ms per note (90 before);
- the 32 with 480 readings: 17.2 ms per note and 27.8 ms per reading
  (192 and 202);
- the catch-up through 20 days: 4.3 ms, and its menu 4.9 ms (60 and 59);
- fresh fermenters, now that the copy is gone: 0.59 and 0.54 ms for 32
  (1.50 and 1.55).

After it, the trim leaves notes one over the limit alone: a prune there
removes nothing, and the trim test covers the case. The three findings
got budgets of about three times these medians.

Launch 184, `-Mode fireplace` (**21/0**, the same 21 checks as launch 23).
A January fermenter ran beside a map fireplace fed with logs, with a
12-hour trip away. It noted the fire in all 98 noted hours, with none off.
The fire's noted fuel covered 6.08 h of the trip, and the work over the
trip was exact (7.5397 h). The machine's air matched the formula in 96
hours (worst 0.00000 °C), and the readings and day temperatures matched
the game's exactly. The batch finished after 108.2 game hours.

Launch 185, `-Mode performance` (**29/0**: the 7 workload checks and 22
budgets). The ten-minute note on 32 records with 480 readings fell to
6.7 ms; their hourly reading is 17.6 ms. Everything else measured as in
launch 183. The budgets for the 32 fermenters' notes and readings, with
and without readings, are now about three times launch 185's medians.

Not run since D-032:
- the open fires mode (a campfire and a barbecue; the equivalence tests
  cover them with stand-ins);
- multiplayer, where the server runs these timers;
- a save and reload of records written in place (the install rehearsal's
  save and continue covers it).

Evidence:
[2026-11-04_rt-sp_harness_run183_performance.txt](evidence/2026-11-04_rt-sp_harness_run183_performance.txt),
[2026-11-04_rt-sp_harness_run184_fireplace.txt](evidence/2026-11-04_rt-sp_harness_run184_fireplace.txt)
and
[2026-11-04_rt-sp_harness_run185_performance.txt](evidence/2026-11-04_rt-sp_harness_run185_performance.txt).

## 2026-11-04 — RT-SP launches 186–187 (the zip of `b7dd527`)

`tools/rehearse-install.ps1` built the zip of commit `b7dd527` (D-032 and
the performance baseline): 121 files, SHA-256 `bac724c6…`, 3,825,684 bytes.
218/218 tests, compile check 118/0 and translations OK came first. The zip
differs from launch 180's (`34fbd7f7…`, `b604f6b`) in `Machines.lua`,
`Climate.lua` and `Tables.lua` and in the shipped changelog. It matched its
manifest and was installed into a fresh isolated cache.

Launch 186 was cut short when the computer switched off. It had reached
phase A's crafting step with 64 checks passed and none failed. Its partial
file is kept.

Launch 187, the same zip built again (the same bytes): phase A **94/0**,
phase B **14/0**, the same 108 checks as launch 180. Phase A ran the
machines on the game clock, so their hourly readings and ten-minute notes
wrote records in place (D-032). Saved, exited and continued, those
records came back (`G08.machine_records_persist`). The console's one
exception came from the harness's own deep-recursion probe.

Evidence:
[2026-11-04_rt-sp_harness_run187_install_rehearsal.txt](evidence/2026-11-04_rt-sp_harness_run187_install_rehearsal.txt),
and launch 186's partial file,
[2026-11-04_rt-sp_harness_run186_install_rehearsal_interrupted.txt](evidence/2026-11-04_rt-sp_harness_run186_install_rehearsal_interrupted.txt).

## 2026-11-04 — RT-MP launches 188–189 (engine effects and the machines' timers on a server)

The user asked to test the engine effects (D-031) and the timers (D-032)
on a dedicated server ("Yes, test multiplayer"), the not-run item both
decisions named. Two new modes of `tools/run-mp-harness.ps1`, on the
shortest day, ran unattended on this machine. The server holds the
fixtures and watches the engine every game minute, after the mod's own
pass (`MPServer.lua`). The clients act as players do (`MPHarnessCases.lua`).

**Engine effects** (`-Clients 2 -Only effects`, launch 188: A **22/0**,
B **9/0**). The server parked a `Base.CarNormal` by the spawn point and
gave A its key. A poured 10 L of petrol in from a can. The server aged the
tank's record to 2.6 (power factor 0.851, wear factor 1.743) and turned
stalls off. Idling burns about 0.00056 L a game minute, so the car wear
rate ran at 1000 times its value (a fixture). A started the engine and
idled for 100 game minutes:
- the server lowered the power from 4000 to 3406 at the first minute pass
  that saw the engine run, and held it; quality 97 and loudness 40 stayed;
- both clients showed 3406, 30 and 31 ticks after they saw the engine run;
- the 0.0503 L burned owed 5.608324 points: 5 came off the Engine part
  and 0.608324 was carried, on the server and on both clients;
- after A shut the engine off through the menu, the power was 4000 again
  at the next minute pass, on the server and both clients.

Then a blend no stock engine takes (petrol and ethanol 5 to 3, written
over the record):
- with stalls on, the server's start gate refused A's start;
- with stalls off, the engine ran 29 game minutes at 2000, the floor,
  without a stall;
- with stalls on again, it stalled at the next minute pass and had 4000
  back one pass later.

Each client showed what the server had.

Each client's loudness read 14, the server's 40 × 0.37037036. It did so
from the first engine packet, while the engine was still starting, before
the mod set any power, and it held there to the end. A client applies a
received engine through `setEngineFeature`, which stores the loudness
scaled (BC `VehicleEngine.parse`). That is vanilla's own. The server runs
the engine and emits the noise zombies hear from its own loudness
(`VehicleEngine.update` returns at once on a client).

Last, a generator by the car: 8 L poured in from a can, its record aged to
3.0, switched on by the server (a fixture) for 6 game hours. It burned
0.0348 L (single-player run 179's burned 0.012 L in 6 hours; the
difference was not traced, `engine-capabilities.md`). A's 2 L refuel
through the world menu made the server build `ISAddFuel`. Its `new`
charged 8 points at 100 times the rate (a fixture), with 0.718012
carried: exactly the 8.718012 due. Charged again at once, it took
nothing. A's client showed condition 92, as the server did. The mod's
minute pass cost 0.015 ms a vehicle on the server (4290 calls over about
22 vehicles in its cell).

**The machines' timers** (`-Clients 1 -Only timers`, launch 189: A
**6/0**). The server built a campfire 11 squares from the spawn point
(`SCampfireSystem.instance:addCampfire`) and gave it 480 minutes of fuel.
It lit it, then put a running fermenter on each of the four squares
beside it and 28 more out of its reach (13 squares or more). Over three
game hours the harness's own handlers, run right after the mod's in the
same event, compared every record with what they read themselves:
- 96 of 96 hourly readings equalled the air at their machine;
- 576 of 576 ten-minute notes were as the air and the campfire give them.
  The four machines beside the fire were warmed in each pass logged (1–3,
  6, 12 and 18; air 20.15 against 15.65 °C unwarmed at the first). They
  noted the campfire: its offset, and its fuel by the server's campfire
  object (474 at the first note, 10 less each pass). None of the 28 away
  was warmed, and they noted none.

A then asked the status of a machine by the fire and one away, standing
at each, as the menu does. Both were `Processing`. The catch-up the
server ran from those notes and readings gave the fire's machine a site
temperature of 21.75 °C against 17.32 °C away.

The timers' costs on the server, as they ran (whole-ms clock): the
hourly readings 1 ms, the ten-minute notes 3.6 ms on average (6 ms the
most). The server's own bench, as the performance mode times them: the
hour's climate record and readings 0.398 ms, a note pass 2.51 ms, a
machine's status catch-up 0.106 ms. The bench's writes stayed on the
server, so these leave out sending the records to clients; the timed
events include it.

Evidence:
[2026-11-04_rt-mp_harness_run188_effects_client_a.txt](evidence/2026-11-04_rt-mp_harness_run188_effects_client_a.txt),
[2026-11-04_rt-mp_harness_run188_effects_client_b.txt](evidence/2026-11-04_rt-mp_harness_run188_effects_client_b.txt)
and
[2026-11-04_rt-mp_harness_run188_effects_server.txt](evidence/2026-11-04_rt-mp_harness_run188_effects_server.txt),
and
[2026-11-04_rt-mp_harness_run189_timers_client_a.txt](evidence/2026-11-04_rt-mp_harness_run189_timers_client_a.txt)
and
[2026-11-04_rt-mp_harness_run189_timers_server.txt](evidence/2026-11-04_rt-mp_harness_run189_timers_server.txt).
No server stdout was kept (it holds the accounts' passwords).

Not run in multiplayer: driving on poor fuel, so the lowered power's
effect on the car's speed there; flex-converted engines; other chassis;
several clients' machines and cars at once; a real network (the user's
choice).

## 2026-11-04 — RT-SP launch 190 (the 0.1.0 zip, with its release metadata)

The user asked for the release metadata ("Yes, release metadata"). When
asked, they chose the licence and the version: CC BY-NC-SA 4.0, and 0.1.0
now (D-033). `tools/make-preview.ps1` made the preview (256×256, 80,474
bytes), which is also the poster. `tools/package.ps1` then built
`TheLastGallon-0.1.0.zip` from uncommitted changes on `6123c0e`. Before
it: 218/218 tests, compile check 118/0, translations OK. The zip has 125
files, SHA-256 `2b5e1afc…`, 3,990,078 bytes. It differs from launch 187's
zip (`bac724c6…`, `b7dd527`) in:

* the version (`mod.info`, `Core.lua`) and the rest of `mod.info`: the
  description, category, poster and icon;
* four new files: `42/poster.png`, `42/icon.png`, `docs/LICENSE.md` and
  `preview.png` beside `Contents`;
* a header comment of `Vehicles.lua`;
* the shipped changelog, notice and player guide.

`tools/rehearse-install.ps1 -NoBuild`: the zip matched its manifest (125
files) and was installed into a fresh isolated cache. Phase A **100/0**:
launch 187's 94 checks and six new ones (`g01_client_mod_info`), on what
the game read from the installed `mod.info`:

* version `0.1.0`, equal to `TLG.VERSION`;
* category `features`;
* the description whole (493 characters, licence included);
* the poster found in `42/` and loaded as a 256×256 texture;
* the icon found in `42/` and loaded as 32×32.

Phase B **14/0**, after save, exit and continue. The console's one
exception came from the harness's own deep-recursion probe.

Not run: the mod list panel itself (the checks read the values it draws
from), and the Workshop uploader's checks (nothing was uploaded).

After the commit (`1d03a03`, on the user's "Do that"): `tools/package.ps1`
built the zip of the commit, 218/218 tests, compile check 118/0 and
translations OK first. It is SHA-256
`47be8fd67966eafd8538ce84c5eb2ac36ae5dfe25aad0306a633a75f91b68522`,
3,990,078 bytes. Its manifest is identical to launch 190's: the same 125
files, byte for byte. Only the entries' time stamps differ, set from the
commit. A second build gave the same bytes. This is the 0.1.0 package.

Evidence:
[2026-11-04_rt-sp_harness_run190_install_rehearsal.txt](evidence/2026-11-04_rt-sp_harness_run190_install_rehearsal.txt).

## 2026-11-04 — RT-SP launches 191–195 (the crafting window; the recipes' names)

The user asked to test the crafting window ("Yes, test the crafting
window"), which gate 1 listed as not run: phase A crafts through the
inventory menu (`OnNewCraft`) and only checks that the window's query
lists the recipes. New mode `tools/run-sp-harness.ps1 -Mode crafting`
(request `sp-rtcr`):

* The character stands at the workbench phase A uses (`industry_01_23` at
  10619,10630), with a torch when dark. The window is opened with the
  crafting button beside the equipped items (`ISEquippedItem` "CRAFTING",
  `forceClick`).
* For each of the mod's seven recipes:
  * the name the window shows (`getTranslationName`);
  * that name typed in the search box (`onTextChange`);
  * with the search cleared, its row clicked (the row's `onmousedown`);
  * made with the **Craft** button, or for the drying column with a
    double-click on its row;
  * the output counted, inputs used, and tools kept.
* The fermentation vessel is first picked with its nails missing: the
  **Craft** button must be disabled and pressing it must start nothing.
* The sampling kit, the filter and the stabilizer were never crafted in
  game before.

Launch 191 (3/21) found the defect: every recipe's row read its id
(`TLG_MakeFermenterVessel`, …). It also found two bugs in the harness: a
step table overwrote the expected names, and
`getScriptManager():getCraftRecipe(id)` found none of the recipes. The
harness now uses the window's own recipe objects, and waits for the rows
after the search is cleared.

Launch 192 (11/14), the mod as committed in `5574606`:
* all seven crafts made through the window, six with the **Craft** button
  and the drying column by double-click;
* the vessel refused without its nails (**Craft** disabled, nothing
  queued, nothing made);
* the 14 failures are the defect alone: seven names that read as ids,
  and seven searches by name that found nothing.

The mod shipped no `Recipes.json`, and the game names a recipe by its id
when that file lacks it (BC `Translator.getRecipeName`).

Fix: `Translate/EN/Recipes.json` and `IT/Recipes.json`, in vanilla's style
("Make Fermentation Vessel", "Crea recipiente di fermentazione").
`tools/check-translations.ps1` now requires a name for every `craftRecipe`
in the mod's scripts. Without the files, it lists all seven as missing.

* Launch 193 (**25/0**): all seven names as shipped; each found by typing
  its name; the refusal; all seven crafts, with the **Craft** button
  enabled 2–30 ticks after the materials arrived. No exception in the
  console.
* Launch 194 (`-Mode italian`, **5/0**): the Italian mode now reads recipe
  names as the window does (`Translator.getRecipeName`). It found 247 of
  247 Italian strings as shipped, the 7 recipe names among them.
* Launch 195 (`tools/rehearse-install.ps1`): the package rebuilt with the
  names. 218/218 tests, compile check 118/0, translations OK (247 EN keys,
  208 referenced). `TheLastGallon-0.1.0.zip` is 127 files, SHA-256
  `1e3ab9e4…`, 3,991,312 bytes, built from uncommitted changes on
  `5574606`. Its manifest differs from launch 190's in the two
  `Recipes.json` and the shipped changelog and player guide. It matched
  its manifest and was installed into a fresh cache. Phase A **100/0**,
  phase B **14/0**. The console's one exception came from the harness's
  deep-recursion probe.

The zip of `1d03a03` (`47be8fd6…`) is no longer the 0.1.0 package;
nothing had been uploaded.

Not run:
* the craft menu's option labels, which come from the same names;
* the crafting window in Italian (the names were checked as the game
  reads them).

After the commit (`42b8d3c`, 2026-11-05, on the user's "Yes"):
`tools/package.ps1` built the zip of the commit, with 218/218 tests,
compile check 118/0 and translations OK first. It is SHA-256
`8bf6ba795a6a66f16afa616fed47d883ed848d0ef9d23c21629a09742547c551`,
3,991,312 bytes. Its manifest is identical to launch 195's: the same 127
files, byte for byte. Only the entries' time stamps differ, set from the
commit. A second build gave the same bytes. This is the 0.1.0 package.

Evidence:
[2026-11-04_rt-sp_harness_run191_crafting_window.txt](evidence/2026-11-04_rt-sp_harness_run191_crafting_window.txt),
[2026-11-04_rt-sp_harness_run192_crafting_window_before.txt](evidence/2026-11-04_rt-sp_harness_run192_crafting_window_before.txt),
[2026-11-04_rt-sp_harness_run193_crafting_window.txt](evidence/2026-11-04_rt-sp_harness_run193_crafting_window.txt),
[2026-11-04_rt-sp_harness_run194_italian.txt](evidence/2026-11-04_rt-sp_harness_run194_italian.txt),
[2026-11-04_rt-sp_harness_run195_install_rehearsal.txt](evidence/2026-11-04_rt-sp_harness_run195_install_rehearsal.txt).

## 2026-11-05 — RT-SP launches 196–199 (death and a successor)

The user asked to test what happens when the character dies and play
continues as a new survivor ("Yes, test that"). New mode
`tools/run-sp-harness.ps1 -Mode successor` (request `sp-rtsu`). The scene,
beside the station:

* survivor A loads two fermenters (F1 and F2), takes a petrol can and
  looks at it (**Look and smell**);
* an hour and a half later, A takes F2 into both arms the loot window's
  double-click way;
* A is killed (`Kill(nil)`);
* the game's own screens make survivor B: Respawn, then the occupation's
  Next, then the character's Play (`ISPostDeathUI`,
  `CoopCharacterCreation`). They are clicked with `forceClick` as a
  player would, unattended;
* B is brought to the body and takes back the can (the loot window's
  transfer) and F2 (double-click, then put down).

The problems in launches 196–198 were the harness's own:
* 196: the game fires `OnNewGame` again for the new survivor, and the
  debug scenario's `onStart` hangs on it, so the steps started a second
  time beside the first. The harness now starts once. A summary helper
  was also given the wrong argument.
* 197: F2 was two tiles away, too far for the loot window, so the take
  had no container. The records were read before they had caught up. The
  body was looked for before it existed.
* 198 (17/1): the whole scenario ran. Its one failure was the harness's
  expectation that F2 would be with the body. The game drops a carried
  heavy item at the feet when its carrier dies, and that drop is one no
  Lua sees. D-015 then holds: the batch works from when the mod next
  finds it placed.

Launch 199: **18/0**, no exception in the console. In order:
* A loaded both fermenters, knew the can after a look, and carried F2
  (paused, not placed, 1.51 h done).
* A died; the body held the can; F2 lay on the floor at A's feet.
* The screens made B (Joni) at 10819,9437, far from the body.
* The world record (seed, epoch, installation, policy) was unchanged.
* B was another character, and knew nothing of the can (0 observations).
* The can's record in the body was as A left it.
* F2 was still paused until B's **Status** found it on the floor; it then
  worked, with the 0.04 game h before that not credited.
* F1, placed, worked on through the death (1.5097 → 1.5481 h) and
  answered B's **Status**.
* B took the can out of the body (record unchanged), looked, and then
  knew it.
* B took F2 from the floor into both arms and put it down; it worked
  again.
* Over the next game hour: F1 1.0192 h of work, F2 1.0001 h.

Nothing shipped changed: the 0.1.0 package (`8bf6ba79…`) stands.

Not run:
* death in multiplayer;
* the successor after a save and reload;
* a vessel carried at death and found days later (by D-015 those days
  are not credited);
* the spawn-region screen (this world offered none).

Evidence (launch 196's file interleaves the two runs):
[2026-11-05_rt-sp_harness_run196_successor.txt](evidence/2026-11-05_rt-sp_harness_run196_successor.txt),
[2026-11-05_rt-sp_harness_run197_successor.txt](evidence/2026-11-05_rt-sp_harness_run197_successor.txt),
[2026-11-05_rt-sp_harness_run198_successor.txt](evidence/2026-11-05_rt-sp_harness_run198_successor.txt)
and
[2026-11-05_rt-sp_harness_run199_successor.txt](evidence/2026-11-05_rt-sp_harness_run199_successor.txt).

## 2026-11-06 — RT-SP launches 200–202 and 205–206, RT-MP launches 203–204 (What I know about it; death fixed)

The user reported that **What I know about it** did not show what they
knew from their looks and kit samples. They asked for it to show which
tests were done, how long ago, with their results, and a note when the
container is not sealed. They also asked to fix the vessel left unworked
after a death ("Yes, fix it"). New modes:
`tools/run-sp-harness.ps1 -Mode knowledge` (`sp-rtkn`) and
`tools/run-mp-harness.ps1 -Clients 1 -Only knowledge`. Both read
**What I know about it** from the Fuel menu, as a player opens it, and
check the dialog's text.

Launch 200 (3/7), the mod as committed in `e9f1e87` (single player),
confirmed the report:
* a kit sample, then, two game hours later, a look:
  **What I know about it** showed the look alone ("Method: look and smell
  (rough)"), and the kit's "Composition: Gasoline 100.0%" was gone;
* no test was named and no age given;
* after the can was opened from the menu, and after a litre was poured
  out, it showed the same text, with no note.

Launch 203 (RT-MP, one client, 6/2), the same mod exported to a folder
(`-ModSource`): after a kit sample and a look answered by the server,
the client's menu said "Condition unknown: not sampled yet", before and
after the can was opened. The client's own copy of the player's mod data
held no knowledge.

Fix (D-034): knowledge keeps each test's latest result; the menu asks the
authority (`known`, with the same reach as `status`). The authority
answers each test, most precise first, with its age, whether the fuel
changed since, and the seal. The menu shows each test's name and age
above its findings, a note under a test the fuel changed since, and a
note for an open container. Old entries read as their test. Death (D-015
amendment): `Machines.onDeath` puts down a machine the dying character
carried.

Domain 223/223, the five new cases included:
* knowledge per test, and the list with ages and changes;
* the menu text with a stub translator;
* the `known` handler;
* the death hook's three cases.

Audit 25/25. The new audit cases are `known` out of reach, another
player's tests, and a read on a can nobody tested, which writes no record
(it still moves the next id by one, as status does; D-034). Compile
125/0. Translations OK (261 EN keys).

* Launch 201 (**10/0**), single player: the menu shows "Sampling kit, 2
  hours ago" with its composition and "Look and smell, just now". Once
  the can is opened, both results carry the changed note ("Since this
  test, fuel was poured in or out or treated, or the container opened or
  closed") and the open note follows them. After a litre is poured out,
  the same; after a new look, the look is current again and only the kit
  keeps the note. An entry in the old shape (a kit observation alone)
  reads as the kit's.
* Launch 202 (`-Mode successor`, **18/0**): the dying survivor's
  fermenter lay at the feet with its record already working from the
  death (from 3.5331; the death was at 3.5331). Over the 0.0356 game h to
  the successor's **Status** it worked 0.0356 h, as the placed one did.
  The mod's log: "a carrier died: 0 machine(s) in the hands, 1 already at
  the feet" (the drop comes before the event in 42.21).
* Launch 204 (RT-MP, **8/0**): the client's menu lists both tests,
  answered by the server, and, once the can is opened, the changed and
  open notes. The client's own copy of the player's mod data still holds
  none.
* Launch 205 (`-Mode italian`, **5/0**): 261 of 261 Italian strings as
  shipped, IG_UI 186 of 186.
* Launch 206 (`tools/rehearse-install.ps1`): the package rebuilt, with
  218+5 tests, compile check and translations first.
  `TheLastGallon-0.1.0.zip`: 129 files, SHA-256 `8ef1dd31…`, 4,008,919
  bytes, built from uncommitted changes on `e9f1e87`. It differs from
  launch 195's in:
  * the security audit's commits: the new `Vault.lua` and
    `WorldStore.lua`, and changes to the handlers, adapters and
    `World.lua`;
  * this change;
  * the shipped changelog, player guide and migrations notes.

  It matched its manifest and was installed into a fresh cache: phase A
  **100/0**, phase B **14/0**. The console's one exception came from the
  harness's own deep-recursion probe.
* The zip of commit `d9cd9aa`, which took this change: SHA-256
  `e3c075f9b6af3e917065ddcc6218e0ace22a1376013081ff54a25eddf387928b`,
  4,008,919 bytes; two builds gave the same bytes. Its 129 files match
  launch 206's manifest byte for byte; only the entries' time stamps
  differ, set from the commit. Offline before it: 223/223, audit 25/25,
  compile 125/0, translations OK.

Not run:
* death in multiplayer;
* the new knowledge across a save and reload;
* a pump's, vehicle's or generator's knowledge through a menu.

Evidence:
[2026-11-06_rt-sp_harness_run200_knowledge_before.txt](evidence/2026-11-06_rt-sp_harness_run200_knowledge_before.txt),
[2026-11-06_rt-sp_harness_run201_knowledge.txt](evidence/2026-11-06_rt-sp_harness_run201_knowledge.txt),
[2026-11-06_rt-sp_harness_run202_successor.txt](evidence/2026-11-06_rt-sp_harness_run202_successor.txt),
[2026-11-06_rt-sp_harness_run205_italian.txt](evidence/2026-11-06_rt-sp_harness_run205_italian.txt),
[2026-11-06_rt-sp_harness_run206_install_rehearsal.txt](evidence/2026-11-06_rt-sp_harness_run206_install_rehearsal.txt);
[2026-11-06_rt-mp_harness_run203_knowledge_before_client_a.txt](evidence/2026-11-06_rt-mp_harness_run203_knowledge_before_client_a.txt)
and
[2026-11-06_rt-mp_harness_run203_knowledge_before_server.txt](evidence/2026-11-06_rt-mp_harness_run203_knowledge_before_server.txt),
[2026-11-06_rt-mp_harness_run204_knowledge_client_a.txt](evidence/2026-11-06_rt-mp_harness_run204_knowledge_client_a.txt)
and
[2026-11-06_rt-mp_harness_run204_knowledge_server.txt](evidence/2026-11-06_rt-mp_harness_run204_knowledge_server.txt).

## 2026-11-06 — RT-SP launch 207, RT-MP launches 208–209 (knowledge across a save; death on a server)

The user asked to test the two things launches 200–206 left out ("Yes,
test those"): **What I know about it** across a save and reload, and a
carrier's death in multiplayer. The mod was as committed in `d9cd9aa`;
only the harness changed. New modes:
* `tools/run-sp-harness.ps1 -Mode knowledge-save` (`sp-rtkns`, then
  `sp-rtknb`);
* `tools/run-mp-harness.ps1 -Clients 1 -Only knowledge -Restart`;
* `tools/run-mp-harness.ps1 -Clients 2 -Only death`.

The server's harness now also finds a vessel in a dead body's inventory
and by its batch record, and logs `OnPlayerDeath` and `OnCharacterDeath`
if they fire on the server.

* Launch 207 (`-Mode knowledge-save`, single player, **7/0** before the
  save, **9/0** after). A kit sample and, two game hours later, a look
  were taken of a sealed petrol can; the game was then saved, exited to
  the menu and continued. Before any read, the character's knowledge came
  back exactly as saved (both tests' times and readings), and the can's
  record at the same revision (0). The menu then listed
  "Sampling kit, 2 hours ago" with "Composition: Gasoline 100.0%" and
  "Look and smell, 1 minute ago", with no changed note and no open note.
* Launch 208 (RT-MP, one client, `-Restart`, **11/0**). The server
  answered a kit sample and a look, and the menu listed both. Then the
  player left, the server was saved, stopped and started again on the
  same world, and the player joined again ("saved player: true"). The can
  came back with the same record (`S190009910-12`). The server's `known`
  reply listed the kit, then the look, neither changed, with the can
  sealed. The menu read "Sampling kit, 1 minute ago" with its composition
  and "Look and smell, 1 minute ago", no notes. So what the server writes
  into its copy of the player is saved by the server and outlives the
  client's copy, which never had it.
* Launch 209 (RT-MP, two clients, `-Only death`, on the shortest day; A
  **4/0**, B **3/3**). A took a running vessel off the floor into both
  arms (the mod's take on the server), carried it two squares and was
  killed (`Kill`, the post-death screen up at once). B watched from three
  squares away and asked the server:
  * right before the death: in A's hands, the batch carried (paused,
    `not_placed`), at game hour 3.9803;
  * 900 ticks after: the vessel lay on the floor where A died
    (10661,10644), with the same item id, but its record still said
    carried, off the hourly list;
  * the server's harness logged no `OnPlayerDeath` and no
    `OnCharacterDeath`: neither fires in a dedicated server's Lua for a
    client's death, so the mod's death hook (D-015 amendment) never ran;
  * at 5.3076 B asked for **Status** from beside it: the batch ran again
    from then (the move no Lua saw), with no work for the 1.3 game h since
    the death.

  Of B's three failures, two are this finding: the record not put down
  at the death, and no work from it. The third is the harness's own: its
  floor check compared the square with the record's site, which only a
  put-down moves, so it failed with the vessel on the floor. That check
  now asks only for the floor (the site is the put-down check's), and the
  work check now measures from the death rather than from the pickup.

Not run:
* the fix for the death on a server (none made: the finding is reported
  to the user first);
* a successor in multiplayer;
* a pump's, vehicle's or generator's knowledge through a menu.

Evidence:
[2026-11-06_rt-sp_harness_run207_knowledge_save.txt](evidence/2026-11-06_rt-sp_harness_run207_knowledge_save.txt);
[2026-11-06_rt-mp_harness_run208_knowledge_restart_client_a.txt](evidence/2026-11-06_rt-mp_harness_run208_knowledge_restart_client_a.txt)
and
[2026-11-06_rt-mp_harness_run208_knowledge_restart_server.txt](evidence/2026-11-06_rt-mp_harness_run208_knowledge_restart_server.txt);
[2026-11-06_rt-mp_harness_run209_death_client_a.txt](evidence/2026-11-06_rt-mp_harness_run209_death_client_a.txt),
[2026-11-06_rt-mp_harness_run209_death_client_b.txt](evidence/2026-11-06_rt-mp_harness_run209_death_client_b.txt)
and
[2026-11-06_rt-mp_harness_run209_death_server.txt](evidence/2026-11-06_rt-mp_harness_run209_death_server.txt).

## 2026-11-06 — RT-MP launch 210 (a carrier's death on a server, the hands followed)

The user asked for the fix of launch 209's finding ("Fix it here"). The
game's code says why nothing on the server saw the death (BC 42.21,
engine capabilities): `IsoPlayer.OnDeath` returns at once on a server,
and the server drops a dead client player's hand items in Java
(`IsoGameCharacter.die` → `dropHeldItems`). Every drop empties the hands
through `setPrimaryHandItem` and `setSecondaryHandItem`, which fire
`OnEquipPrimary` and `OnEquipSecondary` there too. So the mod now follows
the hands on the authority (`Machines.onHands`, D-015 amendment): a
machine with a record that enters a hand is remembered, and one that has
left both is looked at every tick until it lands, then put down from that
tick. Every ten game minutes the hands of the players in the game are
looked at again (a player who joins holding a machine fires no equip
event).

Before the launch: tests 225/225 and the compile check 125/0. The two new
cases cover:
* a server's drop in 42.21's order, a machine in one hand, an unequip
  into the inventory, a hook's own drop written once, a client, a failing
  look;
* the ten-minute look: a player loaded holding the vessel, hands emptied
  with no event, a holder who left, single player.

The harness's server now logs whether `OnTick` fires there and each
put-down the mod makes, with where and when. Its vessel probe says
whether the mod holds the vessel as in someone's hands (`held`) and how
many machines it watches land; A checks that the mod knew the vessel in
its hands.

Command: `tools/run-mp-harness.ps1 -Clients 2 -Only death`, the mod and
the harness as in the working tree on `e3ca43b` (about 4 minutes).
Result: A **5/0**, B **6/0**.

* `OnTick` fires on the dedicated server: 300 ticks in 78.8 s from its
  start, before anyone joined (about 3.8 a second).
* A took the running vessel off the floor into both arms (the mod's take
  on the server). The server's probe then found it in A's hands, the
  batch carried, and the mod holding it as A's (`held=tlga`): the equip
  events reach the server's Lua.
* A carried it two squares and was killed. B asked the server right
  before (game hour 4.1151: in A's hands, carried) and 900 ticks after:
  * the vessel lay on the floor where A died (10661,10644);
  * its record was `Processing` there, from 4.1684, 0.0533 game h after
    B's probe. A died 120 ticks (two seconds, 0.053 game h on this day)
    after B's probe, so the put-down came at the death;
  * it was on the hourly list at once, at that tile;
  * the mod held nothing in hands and watched nothing any more;
  * the server's log has one put-down: "1448783971 at 10661,10644 from
    t=4.1684: pause not_placed -> none, state Processing".
* B walked to it and, 1,800 ticks later, asked for **Status**:
  `Processing`, now in the fermenting stage. The probe after it found
  0.958 h of work over the 1.293 game h from the probe before the death,
  about 1.24 h of it placed. There was no second vessel and no duplicate.

Not run:
* a climb's drop (over a wall, through a window, on a sheet rope), in
  single player or on a server, which the same watch covers;
* a player who joins holding a machine and then dies (the ten-minute
  look, unit tests only);
* single player again: `OnPlayerDeath` still comes first there, inside
  the death, so run 202's path is unchanged (unit tests);
* a successor in multiplayer.

Evidence:
[2026-11-06_rt-mp_harness_run210_death_client_a.txt](evidence/2026-11-06_rt-mp_harness_run210_death_client_a.txt),
[2026-11-06_rt-mp_harness_run210_death_client_b.txt](evidence/2026-11-06_rt-mp_harness_run210_death_client_b.txt)
and
[2026-11-06_rt-mp_harness_run210_death_server.txt](evidence/2026-11-06_rt-mp_harness_run210_death_server.txt).

## 2026-11-06 — RT-SP launches 211–212 (the player guide's screenshots)

The player guide had no picture of a menu or dialog: the harness hides
each menu as soon as it is built and closes each dialog at once. New mode
`tools/run-sp-harness.ps1 -Mode docs-shots` (`sp-rtds`), summer with the
grid on, no save. The mod was as committed in `82b948e`; only the harness
changed. The mode:
* builds each menu with the game's own right-click builder
  (`ISInventoryPaneContextMenu.createMenu` for the cans and the placed
  vessel, `ISWorldObjectContextMenu.createMenu` for the generator's
  square) and holds the mod's entry as under the mouse, which opens its
  submenu;
* chooses entries as the other modes do and leaves each dialog on screen
  until its shot;
* hides the debug console (moved off screen) for each shot, and the
  collapsed inventory and loot windows behind the menus;
* logs the rectangle of each menu, submenu, dialog and of the crafting
  window. The crops in `docs/images` were cut from these rectangles.

The scene: a Fermentation Vessel on a room tile of the Gas2Go
(10670,10630), loaded from its menu with 6 kg of sugar and 30 L of water;
carried, a petrol can holding 6 L of petrol and 0.02 L of the mod's water
(0.3 %), an empty petrol can, a sampling kit, a stabilizer and a filter
cartridge, with no pump or generator within two tiles; later a generator
beside the vessel, and for the crafting window a workbench (an orange
barrel at 10619,10630).

* Launch 211 (**17/0**, about 70 s from start to quit). All ten shots
  were taken; two showed what only a debug client shows. The generator's
  menu had the game's Tile Report, Room Report and Seed rows, which
  `ISContextMenu:addDebugOption` keeps unless the debug option
  `UI.HideDebugContextMenuOptions` is on. The crafting window showed the
  recipe's id under its name, each row's tags and a **Force Action**
  button, all behind `isDebugEnabled`, which the window reads while it is
  built and drawn. Status gave the temperature in °F, the client's
  default. The harness now turns that debug option on while it builds a
  menu, has `isDebugEnabled` answer false from before the crafting window
  opens until after its shot, and sets `temperatureDisplayCelsius` for the
  mode. The generator's menu is built further left, so its submenu opens
  on the right as the others do; at x 700 it opened on the left.
* Launch 212 (**17/0**, about 60 s); its screenshots are the guide's:
  * the full can's menu: the game's Equip Primary, Equip Secondary,
    Fluid, Drop, Place Item, Put in Container (Cupboard) and More, then
    **Fuel (The Last Gallon)** with What I know about it, Look and smell,
    Take a sample (kit), Add stabilizer, Filter, Let settle and drain
    water and Open, all available; on the empty can, Clean empty container
    too;
  * the kit sample: "Condition: Good (estimate 0.2, give or take 0.3)",
    "Free water detected (about 0.3%)", "Composition: Gasoline 100.0%";
  * two game hours later, the look: "Condition: Good (estimate 0.3, give
    or take 1.0)", "No free water detected";
  * What I know about it: "Sampling kit, 2 hours ago" with the kit's
    lines, then "Look and smell, just now" with the look's;
  * the vessel's **Machine (The Last Gallon)**: Status, Load mash and
    start fermenting, Pause and Abort batch; Status: "Working", "Stage:
    fermenting", "Temperature here today: 22.0 °C, in a room";
  * the generator's menu: Generator, Sit on ground, Walk to and
    **Workshop: convert this generator**, with Project status, Start:
    Flex-fuel generator conversion, Start: Gas generator conversion, Hand
    over parts, Work on it, Cancel the project and Remove the conversion.
    No menu had a debug entry;
  * after Start and Hand over parts (an electric wire, a rubber hose and
    4 screws taken), **Project status**: "Conversion in progress",
    "Flex-fuel generator conversion", "Stage: inspect", "Engine now: stock
    gasoline generator";
  * the crafting window searched for "Make", with the vessel's
    ingredients carried: the vessel's recipe listed first and picked, all
    seven of the mod's recipes in the list, **Craft** available, no
    **Force Action**.

Not run:
* the menus and dialogs in Italian;
* a vehicle's Workshop menu, and the Fuel menu's pour and drain entries
  (beside a vehicle, a generator or a pump).

Evidence:
[2026-11-06_rt-sp_harness_run211_docs_shots.txt](evidence/2026-11-06_rt-sp_harness_run211_docs_shots.txt)
and
[2026-11-06_rt-sp_harness_run212_docs_shots.txt](evidence/2026-11-06_rt-sp_harness_run212_docs_shots.txt).
Launch 211's screenshots (stored as JPEG):
[fuel menu](evidence/2026-11-06_run211_fuel_menu.jpg),
[empty can](evidence/2026-11-06_run211_fuel_menu_empty_can.jpg),
[kit](evidence/2026-11-06_run211_kit_result.jpg),
[look](evidence/2026-11-06_run211_look_result.jpg),
[What I know](evidence/2026-11-06_run211_what_i_know.jpg),
[machine menu](evidence/2026-11-06_run211_machine_menu.jpg),
[Status](evidence/2026-11-06_run211_vessel_status.jpg),
[workshop menu](evidence/2026-11-06_run211_workshop_menu.jpg),
[Project status](evidence/2026-11-06_run211_project_status.jpg),
[crafting window](evidence/2026-11-06_run211_crafting_window.jpg).
Launch 212's:
[fuel menu](evidence/2026-11-06_run212_fuel_menu.jpg),
[empty can](evidence/2026-11-06_run212_fuel_menu_empty_can.jpg),
[kit](evidence/2026-11-06_run212_kit_result.jpg),
[look](evidence/2026-11-06_run212_look_result.jpg),
[What I know](evidence/2026-11-06_run212_what_i_know.jpg),
[machine menu](evidence/2026-11-06_run212_machine_menu.jpg),
[Status](evidence/2026-11-06_run212_vessel_status.jpg),
[workshop menu](evidence/2026-11-06_run212_workshop_menu.jpg),
[Project status](evidence/2026-11-06_run212_project_status.jpg),
[crafting window](evidence/2026-11-06_run212_crafting_window.jpg).

## 2026-11-06 — RT-SP launch 213 (the game's Transfer Liquid window)

The user asked whether the game's **Transfer Liquid** works with the mod,
then to check it in game ("Yes, check it"). Until now only the call the
window ends in, `FluidContainer.Transfer`, had been tested, called from Lua
(RT-DS boot 3). New mode `tools/run-sp-harness.ps1 -Mode transfer-liquid`
(`sp-rttl`), no save. The mod's code was as committed in `82b948e`; only
the harness changed. The mode uses the window as a player does:
* it builds the can's inventory menu with the game's right-click builder
  (`ISInventoryPaneContextMenu.createMenu`) and chooses **Fluid** >
  **Transfer Liquid**; the window opens after the game's panel action,
  with the can as the source;
* it picks the target from the menu the target box opens when clicked,
  sets the slider and clicks **Pour** (`forceClick`, what a click runs);
* it counts every `FluidContainer.Transfer` call on its way in (a call
  into a container with no owner is the window's preview) and watches the
  mod's error log.

Can A held 6 L of petrol, 1.5 L of the mod's ethanol, 0.06 L of its water
and 0.02 L of its sediment (7.58 L). A fixture on its record set the
gasoline's degradation to 0.3, the ethanol's to 0.15 and the stabilizer
to 0.6.

* Launch 213 (**22/2**). Both failures have one cause, below.
  * Pour 1, half of A into an empty petrol can B. The target box offered
    "Empty Gas Can (0 mL)"; the window showed "Max Pour: 7.58 L" and
    "Pouring: 3.79 L". `ISFluidTransferAction` (151.6 ticks of work)
    poured in 189 ticks through 190 calls of the wrapped
    `FluidContainer.Transfer`, about 0.02 L each; 3.79 L left A and
    reached B. The window's two previews before Pour wrote no record. A kept its
    condition and proportions. B got A's degradation, its stabilizer (0.6)
    and the ethanol's share, but no water or sediment: B's record held
    3.04 L of gasoline and 0.75 L of ethanol, where A's proportions give
    3.00 L of gasoline, 0.75 L of ethanol, 0.03 L of water and 0.01 L of
    sediment.
  * Pour 2, the rest of A (3.79 L) into a can C holding 4 L of petrol the
    mod had just recorded at the world's baseline (degradation 0.1543).
    The litres were kept and A emptied. C's gasoline degradation came to
    0.2166, where the mixing rules, worked out in the harness from both
    records, give 0.2167. C again got no water or sediment: 7.04 L of
    gasoline where the rules give 7.00 L, 0.03 L of water and 0.01 L of
    sediment. Its stabilizer, 0.2897 against 0.2903, is lower because
    those 0.04 L count as fuel.
  * The mod logged no error.

Cause, read in the code after the run: a slice of 0.02 L of A carries
0.00016 L of water and 0.00005 L of sediment. The mod writes a record with
any component under 0.0002 L (`Native.MIN_FLUID`) added to the largest
one (`Native.holdable`, D-007 amendment, runs 57–59), then sets the can's
fluids to the record (`Containers.commit`). A target with no water or
sediment of its own never holds 0.0002 L of either, so each slice's water
and sediment became gasoline. The run did not log B's and C's fluids by
type; by the same code they were set to the records. At 0.02 L a slice, a
share of water or sediment under 1 % does not reach the target, and a
larger one does (the first slice already holds 0.0002 L).

Not run:
* the fix (none made: the finding is reported to the user first);
* world containers (rain barrels, the FuelPump entity) and multiplayer;
* a pour stopped part-way.

Evidence:
[2026-11-06_rt-sp_harness_run213_transfer_liquid.txt](evidence/2026-11-06_rt-sp_harness_run213_transfer_liquid.txt);
the window before Pour 1 (stored as JPEG):
[Transfer Liquid](evidence/2026-11-06_run213_transfer_liquid_window.jpg).

## 2026-11-07 — RT-SP launches 214–215 (Transfer Liquid followed once per pour)

The user asked for the lost water and sediment of run 213 to be fixed
("Yes, fix it"). The mod now follows the game's pour action once per pour,
when it completes or is stopped, and leaves its slices to the game (D-035,
`Containers.installPourAction`).

Offline, on the game's Kahlua:
* domain suite 230/230, with five new cases in
  `tests/integration/test_pour_action.lua` (a full pour, a pour stopped
  part-way, a call outside the action, a fluid the mod does not track, a
  record written during the pour). With the action wrap turned off, the
  full pour's case fails;
* audit suite 25/25; compile check 126/0.

The harness mode `-Mode transfer-liquid` gained a third pour and two
checks:
* after every pour, both cans' fluids must hold what their records say
  (`fluids_match_records`, 0.0001 L);
* pour 3: can A taken away, an empty can D given, all of C poured into it
  through the window and stopped 80 ticks after **Pour** by clearing the
  action queue (`ISTimedActionQueue.clear`, which calls the character's
  `StopAllActionQueue`). No record may change before the stop
  (`no_record_written_while_pouring`), and D must hold what left C, in C's
  condition.

* Launch 214 (**32/0**, pour 1 not checked). Pour 1 ended in a harness
  error, "`__le` not defined for operand": `stopAfter`, a parameter its
  call did not pass, held a value that was not a number (launch 215 shows
  which). The action poured on while the next step took can B away; it
  then stopped, and A's record shows the 0.044 L that had left, in A's
  proportions. Pours 2 and 3 ran on what A had left: pour 2 moved 6.00 L
  into C, up to its 10 L, by the mixing rules (worst 5.1e-6); pour 3
  stopped after 80 ticks with 1.60 L in D, in C's condition.
* Launch 215 (**40/0**), the harness checking that parameter's type:
  * Pour 1, half of A into empty can B: 3.79 L in 189 ticks through 190
    calls. B's record holds 3.00 L of gasoline, 0.75 L of ethanol,
    0.03 L of water and 0.01 L of sediment, with A's degradation (0.3
    and 0.15) and stabilizer (0.6); B's fluids are the same (worst
    1.9e-6 L). In run 213 B got 3.04 L of gasoline and no water or
    sediment.
  * Pour 2, the rest of A (3.79 L) into C, 4 L of petrol at the world's
    baseline (degradation 0.0793): C holds 7.00 L of gasoline, 0.75 L of
    ethanol, 0.03 L of water and 0.01 L of sediment, gasoline
    degradation 0.1739 and stabilizer 0.2903, as the rules give (worst
    1.4e-8).
  * Pour 3, all of C (7.79 L) into empty can D, stopped at tick 80:
    1.6031 L moved. D holds it in C's proportions (worst 2.5e-9) and
    condition; neither record had changed before the stop; C kept its
    condition.
  * The mod logged no error. The parameter not passed was the string
    `"afterPour1"` in pour 1 and nil in pour 2 (`engine-capabilities.md`).

Not run:
* the window in multiplayer: reasoned from the code, the server pours in
  one call at `complete`, so nothing changes there (D-035);
* world containers (rain barrels, the FuelPump entity).

Evidence:
[2026-11-07_rt-sp_harness_run214_transfer_liquid.txt](evidence/2026-11-07_rt-sp_harness_run214_transfer_liquid.txt);
[2026-11-07_rt-sp_harness_run215_transfer_liquid.txt](evidence/2026-11-07_rt-sp_harness_run215_transfer_liquid.txt).

## 2026-11-08 — RT-SP, two launches without a number (the 0.1.1 menus on placed items)

Written on 2026-11-10 from the two result files committed with 0.1.1
(`b46cf79`). The launches were given no number and no entry at the time,
so their command line and the order they ran in are not recorded. Both
files carry the heading of `-Mode docs-shots` and `game=42.21.0
4a0e9546ec`.

* [2026-11-08_rt-sp_context_menus.txt](evidence/2026-11-08_rt-sp_context_menus.txt):
  26/0.
* [2026-11-08_rt-sp_fuel_context_menus.txt](evidence/2026-11-08_rt-sp_fuel_context_menus.txt):
  55/0. What it checked beyond the screenshots:
  * Placed containers: a petrol can holding petrol, an empty petrol can, a
    water bottle holding petrol and a bucket holding ethanol each got
    **Fuel (The Last Gallon)** from the floor inventory's menu (as a single
    item and as a grouped entry) and from the world menu.
    **What I know about it**, **Take a sample (kit)** and a treatment were
    answered for each placed container; the bucket's treatment was refused
    with `not_sealable`.
  * Machines: the placed fermentation vessel got
    **Machine (The Last Gallon)** from the world menu, and all four machine
    types got it from the floor inventory's menu, single and grouped.
  * **Pour into the generator** from a placed can's menu: the action was
    queued, the can left the ground and the generator held 0.500 L.

Not run: these menus on 42.22.2, and in multiplayer.

## 2026-11-10 — RT-SP and RT-MP on 42.22.2, launches 216–226

The game updated from 42.21.0 to 42.22.2 (`3d39148846`) on 2026-11-09.
The repository's mod at `0c8aa7f` (0.1.1) logged "untested game version"
and nothing else. Domain tests: 233 cases, 0 failed. Nine harness modes
were run again, each reporting `game=42.22.2 3d39148846`; none failed and
no code was changed.

| Launch | Command | Result (pass/fail) |
| --- | --- | --- |
| 216 | `tools/run-sp-harness.ps1` (full: phase A, reload, phase B) | 100/0, then 14/0 |
| 217 | `tools/run-mp-harness.ps1 -Clients 2` | A 28/0, B 11/0 |
| 218 | `tools/run-mp-harness.ps1 -Only fuel` | 20/0 |
| 219 | `tools/run-mp-harness.ps1 -Only heavy` | 2/0 |
| 220 | `tools/run-mp-harness.ps1 -Only death`, one client by mistake | 5/0, two waits for client B timed out; not counted |
| 221 | `tools/run-mp-harness.ps1 -Only effects`, one client by mistake | stopped by hand while waiting for client B; not counted |
| 222 | `tools/run-mp-harness.ps1 -Clients 2 -Only death` | A 5/0, B 6/0 |
| 223 | `tools/run-mp-harness.ps1 -Clients 2 -Only effects` | A 22/0, B 9/0 |
| 224 | `tools/run-mp-harness.ps1 -Clients 2 -Only machines` | A 15/0, B 2/0 |
| 225 | `tools/run-sp-harness.ps1 -Mode pickup` | 43/0 |
| 226 | `tools/run-sp-harness.ps1 -Mode engine-effects` | 36/0 |

Not run on 42.22.2:
* every other single-player mode (realtime, winter, fireplace,
  fireplace-reload, pot-still, controls, still-pickup, still-save,
  still-controls, late-find, can-water, chassis, driving, performance,
  model-import and the later ones) and the multiplayer modes carry,
  conversion, carconv, stills, timers, audit and knowledge;
* the install rehearsal and the release checklist's gates;
* a comparison of the game's 42.22 scripts and Java against what
  `engine-capabilities.md` records for 42.21.

Evidence: only the last output of each cache was kept, the earlier ones
were overwritten by the next launch.
[2026-11-10_rt-mp_harness_run224_machines_42.22.2_client_a.txt](evidence/2026-11-10_rt-mp_harness_run224_machines_42.22.2_client_a.txt);
[2026-11-10_rt-mp_harness_run224_machines_42.22.2_client_b.txt](evidence/2026-11-10_rt-mp_harness_run224_machines_42.22.2_client_b.txt);
[2026-11-10_rt-mp_harness_run224_machines_42.22.2_server.txt](evidence/2026-11-10_rt-mp_harness_run224_machines_42.22.2_server.txt);
[2026-11-10_rt-sp_harness_run226_engine_effects_42.22.2.txt](evidence/2026-11-10_rt-sp_harness_run226_engine_effects_42.22.2.txt).

## 2026-11-10 — RT-SP launches 227–228 (the 0.1.2 zip installed on 42.22.2)

* Command: `tools/package.ps1`, then `tools/rehearse-install.ps1 -NoBuild`
  (the zip unpacked, checked against its manifest and installed into a
  fresh isolated cache; phase A, save, exit to the menu, continue,
  phase B). Domain tests at each build: 233 cases, 0 failed.

| Launch | Zip | Result (pass/fail) |
| --- | --- | --- |
| 227 | the zip of `965e063`: SHA-256 `f61a68ed…`, 4,478,122 bytes, 144 files | 99/1, then 14/0 |
| 228 | the zip of `f674d1c`: SHA-256 `be68b619…`, 4,478,414 bytes, 144 files | 100/0, then 14/0 |

* Launch 227's failure: `G01c.mod_info_description` read 0 characters. The
  0.1.2 commit (`cfae118`) had replaced the `description=` line of
  `mod.info` with its tested-on sentence alone, which the game does not
  read as a key. Launch 216 had passed that check on the 0.1.1 `mod.info`,
  before the line was cut. `f674d1c` restored the line with the 42.22.2
  values; in launch 228 the game read 493 characters.
* The same commit had cut two lines of the Workshop text in
  `tools/package.ps1` and lines of the README, the player guide and
  `environment.md`; `965e063` and `f674d1c` restored them. No harness
  check reads those.
* Launch 228's console: one exception, from the harness's own
  deep-recursion probe; no "untested game version" warning.

Not run: an install through the Steam Workshop, an upgrade from 0.1.1, the
`existing` and `removal` scenarios on 42.22.2, and the modes the entry
above lists.

Evidence:
[2026-11-10_rt-sp_harness_run227_install_rehearsal_42.22.2.txt](evidence/2026-11-10_rt-sp_harness_run227_install_rehearsal_42.22.2.txt);
[2026-11-10_rt-sp_harness_run228_install_rehearsal_42.22.2.txt](evidence/2026-11-10_rt-sp_harness_run228_install_rehearsal_42.22.2.txt).
