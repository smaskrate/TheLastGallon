# Performance

Release gate 11 (spec section 18, "Performance acceptance"): the cost the
mod adds to the game, measured on a reference machine and world, and the
budgets set from that measurement. The figures come from
`tools/run-sp-harness.ps1 -Mode performance`, unless a section names
other runs:
- RT-SP runs 181–183 and 185 (2026-11-04, game 42.21.0), with the
  ethanol machines;
- runs 340–341 (2026-11-12, game 42.22.2), which add what 0.2.0 to 0.4.1
  brought: the biodiesel machines, diesel engines, wrong fuel and the
  square-load hook;
- runs 398–401, 404 and 405 (2026-11-13, game 42.22.2, the gas branch),
  which add the gas generators and gasifiers (D-040): run 398 with the
  gas stages' first version, runs 399, 401 and 404 the gas stages alone
  (`-Mode performance-gas`), runs 400 and 405 the whole mode with them.
  Runs 404 and 405 came after the gas pass's early return for a propane
  generator with less than a use of room.

Run 405, the latest run of the whole mode, passed all 53 budgets: the 40
that runs 398 and 400 passed, the first runs to check the 18 set from
run 341, and the gas stages' 13, set from run 400, one of them reset
from run 404 after the early return. Runs 401 and 404, the gas stages
alone, passed the 13 before it, run 404 against that one's budget before
the reset (see "Budgets").
Run 341 passed 21 of the 22 budgets set
before it. The fuel menu's budget had most likely been set from a menu
that never opened (see "The fuel menu"); it is now set from run 341, with
the budgets of the new workloads. Runs 181–182 measured the code before
D-032, which made the machines' notes, readings and catch-up cheaper with
the same results; the tables keep their figures for comparison. Evidence,
in `docs/evidence/`:
[run 181](evidence/2026-11-04_rt-sp_harness_run181_performance.txt),
[run 182](evidence/2026-11-04_rt-sp_harness_run182_performance.txt),
[run 183](evidence/2026-11-04_rt-sp_harness_run183_performance.txt),
[run 185](evidence/2026-11-04_rt-sp_harness_run185_performance.txt),
[run 340](evidence/2026-11-12_rt-sp_harness_run340_performance.txt),
[run 341](evidence/2026-11-12_rt-sp_harness_run341_performance.txt),
[run 398](evidence/2026-11-13_rt-sp_harness_run398_performance_gas_42.22.2.txt),
[run 399](evidence/2026-11-13_rt-sp_harness_run399_performance_gas_stages_42.22.2.txt),
[run 400](evidence/2026-11-13_rt-sp_harness_run400_performance_gas_states_42.22.2.txt),
[run 401](evidence/2026-11-13_rt-sp_harness_run401_performance_gas_clean_frames_42.22.2.txt),
[run 404](evidence/2026-11-13_rt-sp_harness_run404_performance_gas_early_return_42.22.2.txt),
[run 405](evidence/2026-11-13_rt-sp_harness_run405_performance_whole_early_return_42.22.2.txt) and
run 184's fireplace test
([run 184](evidence/2026-11-04_rt-sp_harness_run184_fireplace.txt)).

## What the mod runs on its own

- **Nothing every frame in steady play.** The mod keeps no per-frame
  handler: no `OnPlayerUpdate`, no render event, and `OnTick` only while
  the landing watch below runs.
- **The landing watch** (`Machines.watchLanding`, D-015 amendment). When a
  machine leaves a character's hands, the authority looks at it once a
  tick until it lies on the ground: one engine call a tick per machine,
  then the put-down if it landed where no hook saw it. A drop lands within
  the tick, so the watch usually ends on the first tick. It lasts at most
  300 ticks: about 5 seconds at 60 frames a second, and up to about 80
  seconds on a dedicated server, which ticked about 4 times a second at
  its start (RT-MP run 210).
- **Once for every square the game loads** (0.3.2): the square-load
  event (`LoadGridsquare`) calls `Generators.onLoadSquare`, which asks the
  square for a generator and gives a Diesel Generator that lost its
  sprite its sprite back. In the harness the event costs 0.34–0.35 µs a
  square more with the mod's handler than without it (runs 340–341),
  1.2 ms for 3,600 squares. Outside the debug scenarios, vanilla 42.22.2's
  Lua has no other handler of this event, so there the game's call into
  Lua for each square is the mod's cost too and the mod adds at least that
  much; the call was not timed apart (see "The square-load hook").
- **Once per player action:** the vanilla functions the mod wraps (a
  refuel, a transfer, an equip, the start of a timed action) and the two
  equip events it listens to (`OnEquipPrimary`, `OnEquipSecondary`). The
  events' handler, `Machines.onHands`, looks at whether the item is a
  machine with a record and, while one is held, at the holder's hands: a
  few engine calls, not timed.
- **Three timers**, run by the authority (the game in single player, the
  server in multiplayer):
  - every game minute, the engine effects of every vehicle in the loaded
    cell (`Vehicles.lua`). A parked car costs a few engine calls. A running
    one has its tank read, reconciled and judged, and its power and wear
    applied;
  - every ten game minutes, a note of the fire warming each running machine
    in the hourly list (`Machines.observeFires`). The list holds at most 256
    machines (`MAX_INDEXED`). Then a look at the hands of the characters in
    the game, two engine calls each (`Machines.censusHands`, added on
    2026-11-06): 0.0037 ms a pass with one character (run 341);
  - every game hour, the day's climate record and an air reading at each
    running machine (`Machines.sampleSites`).
- **The gas generators' minute pass** (D-040), run by the authority every
  game minute beside the engines' minute (`Generators.gasMinute`). For
  each square in its list (a generator holding a gas record, or converted
  to gas) it reads the generator's gas record and, when the generator has
  room, refills it: from its propane tank in whole uses, or from the lit
  gasifiers within two tiles. A gasifier has no timer of its own: its
  record is brought forward when something reads it (its menu, or a
  generator's draw).
- **On demand:** the fuel and machine menus, the requests they send, and
  transfers. The machine menu brings the batch to now on every right-click,
  without saving it. **Status** saves the caught-up batch.
- **Records** live in the modData of the item, tank or object they
  describe. The mod keeps no list of them, so a record is read only when its
  object is used. Dormant supplies are never visited.

The biodiesel machines go through the same hourly list and timers as the
ethanol machines; the diesel engines through the same minute.

In the measured world (day length 1 hour 30 minutes) a game minute lasts
3.75 real seconds, so the ten-minute note comes every 37.5 seconds and the
hourly reading every 3.75 minutes. On a 1-hour day the three timers run
every 2.5 seconds, 25 seconds and 2.5 minutes.

## Reference machine and world

| | |
| --- | --- |
| Machine | AMD Ryzen 9 7950X3D (16 cores, 32 threads), 31 GB RAM, NVIDIA GeForce RTX 5080; Windows 11 Enterprise build 26300 |
| Game | 42.21.0 (`4a0e9546ec`) in runs 181–185, 42.22.2 (`3d39148846`) in runs 340–341 and 398–401, as the harness launches it: windowed 1280×720, debug mode, no sound, ZGC, 3 GB heap; vsync off, frame rate capped at 60, lighting at 15 updates a second |
| World | The harness's debug-scenario world with no zombies, parked cars, traffic jams or stories; the main road south of Muldraugh, cleared of vehicles, at 9 in the morning, 16–18 °C |
| Baseline | The same session before each workload was added; for frames, the empty road |

## Method

- Each timer is called the way its event handler calls it: the handlers'
  bodies are copied into the harness (`RT.PF.minute`, `tenMinutes`, `hour`).
  The first call is timed alone, then five batches of at least 200 ms each.
  The figure given is the median batch's time per call. The clock is
  `getTimestampMs`, in whole milliseconds, hence the batches.
- Workloads are added one after another, so each includes those before it:
  1. the empty road;
  2. 400 petrol cans of 10 L on the road, first without records, then with
     them (dormant supplies);
  3. 10, then 20 parked cars with tank records;
  4. 8 of them idling on stale petrol: deterioration 2.6, power factor
     0.85, wear factor 1.74. Stalls are off so they keep running;
  5. 8, then 32 fermentation vessels ("fermenters" in the tables), loaded
     through the machine menu as a player loads them;
  6. the 32 as if a fire warmed each. The air reads 5 °C above the
     unheated value, so each ten-minute note scans the tiles around the
     machines. No fire is found, so each scan runs to the end, as it does
     when a fire is there;
  7. the 32 with 20 days of hourly readings and fire notes (480 each,
     `MAX_READINGS`). A machine keeps that many when it runs in a loaded
     area and nobody uses it for 20 days. The world is only hours old, so
     the readings are dated ahead; the cost depends on how many a record
     holds.
- From run 340, after the budget check, so that the stages above stay as
  in runs 181–185:
  8. the 32 fermenters' fixture readings taken off and their timers timed
     again: the base for the stages below. Runs 340–341 found it within
     0.7–4.4 % of stage 5's 32;
  9. 6 of each of the five biodiesel machines, all running, beside the 32
     fermenters. The wood retorts and the ash barrels are loaded from the
     menu with 11 logs each. A lye leacher, a reactor and a wash tank load
     from a machine beside them that finished hours earlier, so their
     batches are written by the domain's own load and start
     (`Process.load`, `Process.start`), as their handlers write them after
     the draw (a fixture). They hold what one chain gives: the ash of
     99 kg of wood with its water, 18 L of oil with the methanol and lye
     it asks, and that oil's crude with its wash water. One retort is
     loaded both ways; the two records are equal in everything a load
     decides;
  10. (run 341) the parked cars of the two middle columns taken away, for
      room, and the timers timed again; then 4 diesel vans
      (`Base.VanAmbulance`, `engine_ci_stock` in a new world) idling on
      stale diesel, aged as the petrol;
  11. (run 341) the 12 running engines on fresh fuel of their own kind;
  12. (run 341) the same 12 on blends D-037 judges harmful but lets run:
      the petrol cars a fifth diesel, the vans 30 % petrol. Every roll is
      held so none fails;
  13. (runs 398–401) after the square-load hook, the gas, on the road north
      of the parked cars (rows 10798–10807): the gas minute pass with no
      gas generator; 8 generators converted to gas with the conversion
      service's steps, a full propane tank connected to each through the
      Gas menu, each started with the game's action; then 8 more, each
      with a Wood Gasifier on the tile beside it, loaded with two logs and
      lit through its menu, warmed 1.2 game hours at speed 20 and started.
      The minute pass is timed in these states (run 400):
      - propane, a part of a use below the cap, as after the connect. A
        refill moves whole tank uses, 0.0026 L each, so what it leaves
        below the cap is the rest of the room, anywhere below one use:
        this is how most minutes find a propane generator, at any load;
      - propane within the tolerance of the cap (0.0001 L), after one step
        burned and the mod's own pass moving a use;
      - propane with two steps taken out before each call, so each call
        moves one use from each tank;
      - wood gas at the caps, the propane squares out of the pass
        meanwhile;
      - wood gas with one step taken out before each call, so each call
        draws a step's gas from the gasifiers;
      - all 16 as they stand.
      Each state is reached as the game reaches it: the fuel lowered as a
      burn lowers it, the mod's own pass bringing it up, never raised by
      the harness. Each timing checks what it did, the tanks' uses, the
      gas given and the records' times before and after. A refill uses
      something up, so the refill timings run fixed batches of 50 calls,
      every record and fuel put back between batches outside the timing;
      the steps taken out alone are timed to subtract. Also timed: a lit
      gasifier brought forward 1, 30 and 365 days, the Gasifier and Gas
      menus, the square-load handler on a gas generator's square, and 20
      seconds of frames, every reply dialog the menus opened closed first
      (from run 401). Run 398 timed a first version: its propane figures
      came from states it did not control (see "What the gas work
      adds").
- Inside a batch the tank does not drop between calls, so the minute's
  figure for a running engine is its verdict, its power and the stall
  check. The wear, the exhaust wear and the failure draw that litres
  burned bring come once a game minute and are not in it.
- Catch-up: a can's fuel, a tank's fuel and each machine's batch are
  brought forward 1, 30 and 365 days (`Aging.advance`, `Machines.advance`),
  the arithmetic of catching up after that long away. The fermenter with
  20 days of readings is also brought through them, and its menu opened
  with the mod's clock 20 days on.
- Menus: a right-click's menu built and hidden: the game's context menu
  alone, then with the mod's fuel menu on a 10 L petrol can lying on the
  road, and with the machine menu on a fermenter and on each biodiesel
  machine, and the catch-up the machine menu makes. Run 341 also times the
  fuel menu's parts apart.
- The square-load hook: the handler called on the 3,600 loaded squares of
  a 60 by 60 area around the stand, and on a square holding a Diesel
  Generator; then the game's event fired from Lua (`triggerEvent`) for the
  same squares, without the mod's handler and with it. The debug
  scenario's own handler, which does nothing in the harness's scenario, is
  registered in both.
- Frames: 20 seconds at normal speed after each stage. For each frame, the
  game's own main-thread time (`getCPUTime`: the frame step from logic
  through render preparation and Lua events, in whole milliseconds) and the
  time between frames. Every menu load opens a reply dialog, and the
  harness leaves the 32 of the fermenter loads on screen, so every frame
  stage from stage 5 on has them. From run 340 a last stage closes every
  reply dialog and samples frames again.
- Offline, `tools/run-tests.ps1 -Entry tests/support/bench_machine_records.lua`
  times the pieces of one record's notes, readings and catch-up on the
  game's Lua VM (the figures below are the game's).

## Results

Milliseconds per call: the median of five batches.

### Timers by workload (run 181 / run 182)

In the fermenter rows, the ten-minute and hourly figures are those of the
code before D-032; the next table has run 185's.

| Workload (each includes those above) | Every game minute | Every ten minutes | Every hour |
| --- | --- | --- | --- |
| Empty road | 0.0015 / 0.0015 | 0.0015 / 0.0016 | 0.010 / 0.010 |
| 400 cans with records | 0.0015 / 0.0015 | 0.0016 / 0.0016 | 0.010 / 0.010 |
| 10 parked cars | 0.018 / 0.018 | 0.0016 / 0.0016 | 0.010 / 0.010 |
| 20 parked cars | 0.033 / 0.034 | 0.0016 / 0.0015 | 0.010 / 0.010 |
| 8 of them idling on stale petrol | 1.06 / 1.04 | 0.0016 / 0.0015 | 0.010 / 0.010 |
| 8 running fermenters | 1.11 / 1.09 | 0.37 / 0.36 | 0.39 / 0.38 |
| 32 running fermenters | 1.11 / 1.11 | 1.50 / 1.50 | 1.55 / 1.55 |
| The 32 warmed by a fire | – | **92 / 90** | – |
| The 32 with 20 days of readings | 1.12 / 1.11 | **193 / 192** | **193 / 202** |

### What D-032 changed (run 182 → run 185)

Run 183 came before the notes' saving, the last change of D-032, and
run 185 after it. Runs 183 and 185 measured every other workload as runs
181–182 did, within a few percent.

| Workload | Run 182 | Run 183 | Run 185 |
| --- | --- | --- | --- |
| 8 running fermenters: note / reading | 0.36 / 0.38 | 0.15 / 0.14 | 0.14 / 0.16 |
| 32 running fermenters: note / reading | 1.50 / 1.55 | 0.59 / 0.54 | 0.59 / 0.55 |
| The 32 warmed by a fire: note | 90 | 10.3 | 10.2 |
| One machine's fire scan alone | 2.85 | 2.93 | 2.82 |
| The 32 with 20 days of readings: note / reading | 192 / 202 | 17.2 / 27.8 | 6.7 / 17.6 |
| A fermenter brought through its 20 days of readings | 60 | 4.3 | 4.3 |
| Its machine menu, opened 20 days on | 59 | 4.9 | 4.9 |

Runs 340–341, on 42.22.2 with the code of 0.2.0 to 0.4.1, measured most
of these workloads higher than run 185, by up to 20 %: the 32 fermenters
0.69–0.70 ms per note and 0.63–0.66 ms per reading, 8 engines on stale
petrol 1.17–1.21 ms a minute. The budgets table gives run 341's figure for each. The two runs
do not tell the game's share from the code's.

### What 0.2.0 to 0.4.1 added (run 340 / run 341)

| Workload (each includes those above) | Every game minute | Every ten minutes | Every hour |
| --- | --- | --- | --- |
| The 32 fermenters, fresh again (stage 8) | 1.25 / 1.27 | 0.72 / 0.73 | 0.64 / 0.66 |
| With 30 running biodiesel machines | 1.26 / 1.27 | 1.37 / 1.41 | 1.27 / 1.30 |
| The 10 parked cars of the middle columns taken away | – / 1.26 | – / 1.47 | – / 1.30 |
| With 4 vans idling on stale diesel (12 engines) | – / 1.63 | – / 1.46 | – / 1.29 |
| The 12 on fresh fuel of their own kind | – / 0.73 | – / 1.47 | – / 1.30 |
| The 12 on harmful blends | – / 1.38 | – / 1.46 | – / 1.30 |

Run 340 placed no van: each of its four slots between the parked cars was
blocked, the reasons not logged. Run 341 took the middle columns' parked
cars away first. One column then had room at once; in the other a
vehicle on two squares at the slots' edge, not identified, moved its vans
7 rows south.

### What the gas work adds (runs 399, 400, 404 and 405)

The gas minute pass (`Generators.gasMinute`), milliseconds per call; runs
404 and 405 came after the early return described below. Each state was
checked to be what its row says (stage 13); the refill rows leave out the
steps taken out before each call (0.009 ms).

| The gas generators in the pass | Run 399 | Run 400 | Run 404 | Run 405 | A generator (run 400) |
| --- | --- | --- | --- | --- | --- |
| None | 0.0017 | 0.0017 | 0.0018 | 0.0017 | – |
| 8 on propane, a part of a use below the cap (most minutes) | 0.331 | 0.337 | 0.129 | 0.133 | 0.042 |
| 8 on propane, within the tolerance of the cap | 0.087 | 0.088 | 0.085 | 0.088 | 0.011 |
| 8 on propane, each moving one use | 0.571 | 0.551 | 0.591 | 0.611 | 0.069 |
| 8 on wood gas at their caps | 0.097 | 0.098 | 0.096 | 0.098 | 0.012 |
| 8 on wood gas, each drawing a step from a gasifier | 1.571 | 1.571 | 1.611 | 1.591 | 0.196 |
| All 16 as they stood (propane a part of a use below, wood gas at the caps) | 0.444 | 0.446 | 0.236 | 0.239 | – |

A generator costs the pass its record's read even when full: 0.011–0.012
ms. Before the early return described below, a propane generator a part
of a use below its cap cost about four times that, 0.042 ms: the pass
went on past its tolerance test to a refill that cannot move a whole use
(which part of that cost the extra 0.03 ms was not timed). A refill moves whole uses (0.0026 L each), so
what it leaves below the cap is the rest of the room, anywhere below one
use, and within the tolerance (0.0001 L) about once in 26 refills, at any
load: this is a propane generator's usual minute. A refill that moves a
use cost 0.069 ms in run 400, once every hour or two. A
wood-gas generator's draw costs 0.196 ms once an hour, most of it the
gasifier's: found among the squares within two tiles, read, brought
forward, drawn from and written. In run 400 eight propane generators
added about 0.34 ms to a game minute, eight on wood gas about 0.1 ms,
where eight engines idling on stale petrol take 1.2 ms.

Since then the pass returns early for a propane generator whose room takes
less than one use (`Generators.gasRefill`, with `GasFeed.usesFor`, the
rule the refill itself goes by), before the gas checks that read the
conversion record; the owner asked for it on 2026-11-13. Runs 404 and
405 timed the usual state at 0.129 and 0.133 ms for 8, 0.016–0.017 ms a
generator, against 0.042 ms in run 400, and all 16, in the same states
as in run 400, at 0.236 and 0.239 ms against 0.446. The rest, 0.005–0.006
ms above a full generator's 0.011 ms, is that whole-use calculation, the
one step this minute takes past the tolerance test, where a full
generator's minute ends. A refill that moves a use now
makes the calculation twice, in the early return's test and in the
refill, and took 0.074–0.076 ms a generator against 0.069–0.071 in runs
399–400; the second calculation is the likely cause (inferred; the two
were not timed apart). The other figures were within 4 % of run 400's in
both runs, but the pass with no gas generator in run 404, 0.0018 ms
against 0.0017.

Most generators stood within two tiles of two gasifiers, and a generator
draws from the one with the lower id (D-040), so the draws spread as the
items' ids fell: in run 399 two gasifiers served two generators each and
two served none, in run 400 three and three. The gas given in all was
every generator's step, 50 calls over.

| Also | Run 399 | Run 400 | Run 404 | Run 405 |
| --- | --- | --- | --- | --- |
| A lit gasifier brought forward 1 / 30 / 365 days | 0.134 / 0.134 / 0.132 | 0.134 / 0.133 / 0.134 | 0.134 / 0.133 / 0.132 | 0.134 / 0.134 / 0.135 |
| The Gasifier menu, with the game's context menu | 0.350 | 0.340 | 0.346 | 0.347 |
| The Gas menu on a propane / a wood-gas generator, with it | 0.137 / 0.152 | 0.137 / 0.151 | 0.138 / 0.152 | 0.139 / 0.152 |
| The square-load handler on a gas generator's square | 0.0033 | 0.0034 | 0.0033 | 0.0034 |

A gasifier brought forward costs the same for a day as for a year,
presumably because with nothing drawing it, it goes out after its
three-hour hold and the rest of the span costs nothing (inferred from the
flat cost; the advance's steps were not counted).

Run 398 timed a first version of these stages. Its propane minute, 0.34
ms, was the first row's state, but its "refill" moved nothing (the step
it took out, 0.002 L, is less than a use), and its 16 generators, 0.19 ms,
stood in states it did not record. Those figures are not used.

### Per unit (run 185, and run 341 where marked)

| What | Cost |
| --- | --- |
| A parked car, every game minute | 0.0016 ms |
| A running engine on stale petrol, every game minute | 0.13 ms |
| A running engine, every game minute (run 341, 12 engines) | 0.061 ms on fresh fuel of its kind, 0.115 ms on a harmful blend, 0.136 ms on stale fuel |
| A running fermenter, per ten-minute note or hourly reading | 0.018 ms (run 341: 0.022 and 0.021 ms) |
| A running biodiesel machine, per ten-minute note or hourly reading (run 341) | 0.022 and 0.021 ms |
| A machine warmed by a fire, per note | its own scan, 2.8 ms; 32 side by side, 10.2 ms in all |
| A running fermenter with 480 readings | 0.21 ms per note, 0.55 ms per reading |
| A record of fuel caught up | 0.025 ms a day (9 ms for a year) |
| A fermenter's batch caught up | 0.065 ms a day (24 ms for a year) |
| A biodiesel machine's batch caught up (run 341) | 0.068 ms a day (25 ms for a year) |
| The same through 20 days of readings | 4.3 ms (0.21 ms a day) |
| A can's first record, written by a look or a transfer | 0.8–1.0 ms, once (run 341: 0.74 ms) |
| The fuel menu, on top of the game's context menu (run 341) | 0.35 ms (see "The fuel menu") |
| The machine menu for a fresh batch, on top | 0.24 ms, of which 0.12 ms is the catch-up |
| The same for a biodiesel machine (run 341) | 0.24–0.31 ms, of which 0.12–0.14 ms is the catch-up |
| The same with 20 days of readings | 4.9 ms |
| The hands census, every ten game minutes (run 341) | 0.0037 ms with one character |
| A square the game loads (runs 340–341) | at least 0.34–0.35 µs added to the event (see "The square-load hook") |
| A gas generator in the minute pass, full (run 400) | 0.011 ms on propane, 0.012 ms on wood gas, a game minute |
| A propane generator a part of a use below its cap, its usual minute | 0.016–0.017 ms a game minute since the early return (runs 404–405; 0.042 ms in run 400) |
| A propane refill moving a use | 0.074–0.076 ms since the early return (runs 404–405; 0.069 ms in run 400) |
| A wood-gas generator's draw from a gasifier (run 400) | 0.196 ms, once a game hour |
| A lit gasifier brought forward, 1 to 365 days (run 400) | 0.13 ms |
| The Gasifier menu / the Gas menu, with the game's context menu (run 400) | 0.34 ms / 0.14–0.15 ms |
| The square-load handler on a gas generator's square (run 400) | 3.4 µs |

### Catch-up

Milliseconds per call, run 181 / run 182. Runs 183 and 185 measured the
same; D-032 changed only the catch-up through readings.

| | 1 day | 30 days | 365 days |
| --- | --- | --- | --- |
| A can's fuel | 0.091 / 0.089 | 0.82 / 0.80 | 9.3 / 9.1 |
| A tank's fuel | 0.108 / 0.105 | 0.84 / 0.81 | 9.3 / 9.0 |
| A fermenter's batch | 0.155 / 0.150 | 2.13 / 2.03 | 24.7 / 23.6 |

Run 341, with the biodiesel machines (a batch just loaded; the time goes
to the climate segments over the span, so every machine costs about the
same):

| | 1 day | 30 days | 365 days |
| --- | --- | --- | --- |
| A can's fuel | 0.094 | 0.85 | 9.7 |
| A tank's fuel | 0.110 | 0.87 | 9.6 |
| A fermenter's batch | 0.159 | 2.15 | 24.9 |
| A wood retort's batch | 0.170 | 2.16 | 25.0 |
| An ash barrel's batch | 0.155 | 2.13 | 24.9 |
| A lye leacher's batch | 0.158 | 2.15 | 25.0 |
| A reactor's batch | 0.197 | 2.18 | 25.0 |
| A wash tank's batch | 0.169 | 2.17 | 24.9 |

### Frames (run 182)

Every stage of every run held the frame-rate cap of 60 (between frames:
median 17 ms, worst 20–21 ms), so the frame rate cannot show load. The
game's main-thread time per frame, in milliseconds:

| Stage | Mean | Median | 95th percentile | 99th percentile | Worst |
| --- | --- | --- | --- | --- | --- |
| Empty road | 1.81 | 2 | 3 | 4 | 7 |
| 400 cans without records | 1.69 | 1 | 3 | 4 | 5 |
| 400 cans with records | 1.76 | 2 | 3 | 4 | 8 |
| 20 parked cars | 1.84 | 2 | 3 | 4 | 5 |
| 32 fermenters, 8 engines idling | 3.58 | 3 | 5 | 6 | 8 |

Giving the cans records changed nothing measurable. The last stage's rise
of 1.7 ms is mostly the 32 reply dialogs that the fermenter loads leave on
screen, not the engines or the models (runs 340–341, below; the harness
of runs 181–185 left them open too). The mod's
timers come to about 0.006 ms a frame there, mostly the minute's 1.1 ms
once every 225 frames; the ten-minute and hourly calls come once every
2,250 and 13,500 frames. Runs 183 and 185 measured the same stages within
0.2 ms (the last stage: 3.66 and 3.74 mean). Run 181's main-thread times
were lost to a units error in the harness, fixed before run 182.

### Frames (runs 340–341)

Mean main-thread time per frame, in milliseconds, run 340 / run 341. Every
stage held 60 frames a second (between frames: median 17 ms, worst
19–27 ms).

| Stage | Mean |
| --- | --- |
| Empty road | 1.57 / 1.38 |
| 400 cans with records | 1.32 / 1.27 |
| 20 parked cars | 1.31 / 1.30 |
| 32 fermenters, 8 engines idling, 32 reply dialogs on screen | 3.13 / 3.21 |
| Also 30 biodiesel machines; run 341 also 4 vans (12 engines); the dialogs still on screen | 2.83 / 3.09 |
| The same with the dialogs closed | 1.35 / 1.69 |

With the dialogs closed, 62 running machines, 8–12 idling engines and 400
recorded cans took about what the empty road took. Each figure is one
20-second sample.

### Frames with the gas (runs 398–401, 404 and 405)

Mean main-thread time per frame; each figure is one 20-second sample, and
every stage held 60 frames a second. The Gas and Gasifier menus show a
reply dialog after each action. Runs 401 and 404, the gas stages alone
on the bare road, closed every reply dialog before sampling (24 each):

| Stage | Run 401 | Run 404 |
| --- | --- | --- |
| The bare road, before the gas | 1.66 ms | 1.33 ms |
| 16 gas generators and 8 lit gasifiers running | 1.40 ms | 1.24 ms |

On the bare road the gas adds no measurable time to a frame. Run 399
sampled the same stage without closing the replies: 2.61 ms, which fits
what reply dialogs cost (32 of them add 1.3–1.6 ms in the whole mode,
runs 398, 400 and 405).

In the whole mode, with every other workload still running, the frames
rose with the gas in each run:

| Stage | Run 398 | Run 400 | Run 405 |
| --- | --- | --- | --- |
| Every other workload running, the dialogs closed | 1.70 ms | 1.45 ms | 1.52 ms |
| The gas added | 2.05 ms | 1.78 ms | 1.91 ms |

Run 405 closed the replies before its gas sample and found none left on
screen, yet rose as much as runs 398 and 400, which did not close them:
the rise is there without the dialogs. It is spread over every frame: in
each run the median frame went from 1 to 2 ms with the gas while the
longest stayed at 7–9 ms, where a cost once a game minute would need a
spike of some 75–90 ms to lift the mean as much. What raises it is not
established. Between the two samples the mode also times the square-load
hook (about 3.3 million square-load events, and a Diesel Generator put
down) and places the gas among the other workloads; no frames were
sampled in between. The mod's gas pass runs once a game minute (0.24 ms
for the 16 since the early return, about 0.001 ms a frame; 0.45 ms
before it), and the mod registers no per-frame event handler but the
landing watch, which follows a machine for at most 300 ticks after it
leaves a character's hands. The
same stage also differs between runs by as much as the rise: the bare
road read 1.66 ms in run 401 and 1.33 ms in run 404.

### The fuel menu (run 341)

The fuel menu of a can costs 0.375 ms with the game's context menu, of
which the game's menu is 0.025 ms. Its parts, each timed alone:

| Part | ms |
| --- | --- |
| A bare submenu, with the game's context menu | 0.070 |
| The pour entries, on a bare submenu | 0.19 |
| The drain entries, on a bare submenu | 0.11 |
| The search of the 25 squares around the player for a pump | 0.066 |
| The same search for a generator (the pour and the drain entries each make it) | 0.040 |
| The search of the cell's vehicles for one whose tank is in reach | 0.018 |
| The can's fluid container, its reference and the three inventory searches | under 0.003 each |

The three searches come to 0.16 ms, the submenu to 0.045 ms and the
entries to most of the rest. The searches walk every object on those
squares, so they cost more where more objects stand.

Runs 181–185 timed 0.027 ms, 0.002 ms above the game's own menu, most
likely because the menu did not open. On the ground the game keeps a
can's fluid on its world item, so `item:getFluidContainer()` is nil there
(run 341, in the session the can was put down in; run 39, after a
reload), and the 0.1.0 menu asked only that. 0.1.1 asks the world item as
well (`Containers.fluidOf`). Both conclusions are inferred: nobody saw the
menu of runs 181–185, and that runs 340–341 time a built menu rests on
its cost, which its parts add up to; its entries were not counted.

### The square-load hook (runs 340–341)

| Per square | Run 340 | Run 341 |
| --- | --- | --- |
| The handler alone, over 3,600 loaded squares | 0.41 µs | 0.47 µs |
| The handler on a square holding a Diesel Generator | 1.6 µs | 1.7 µs |
| The event fired from Lua, without the mod's handler | 0.48 µs | 0.49 µs |
| The same with it | 0.82 µs | 0.84 µs |

In the harness the mod's handler adds 0.34–0.35 µs a square to the event.
There the debug scenario's handler keeps the game calling into Lua in
both cases. In a game started normally the mod's handler is the only one
in vanilla 42.22.2's Lua, so that call is the mod's cost as well and the
mod adds at least 0.34–0.35 µs a square; the comparison does not give the
call apart.

## Budgets

Each budget is about three times the median of the last run of the code it
times, on the reference machine. Every performance run checks them
(`RT.PF.budgets`; the workloads after the budget check against
`RT.PF.budgetsAdded`, at the end of the mode). The dormant cans get the
empty road's budgets: records nobody touches must cost nothing.

| Measured | Budget, ms per call | Set from | Run 341 |
| --- | --- | --- | --- |
| Empty road: minute / ten minutes / hour | 0.005 / 0.005 / 0.03 | run 181 | 0.0016 / 0.0018 / 0.011 |
| 400 dormant cans: minute / ten minutes / hour | 0.005 / 0.005 / 0.03 | run 181 | 0.0016 / 0.0018 / 0.011 |
| 20 parked cars: minute | 0.1 | run 181 | 0.034 |
| 8 engines idling on stale petrol: minute | 3.2 | run 181 | 1.21 |
| 32 running fermenters: minute | 3.3 | run 181 | 1.25 |
| 32 running fermenters: ten minutes / hour | 1.8 / 1.7 | run 185 | 0.70 / 0.66 |
| The 32 warmed by a fire: ten minutes / one machine's scan | 31 / 9 | run 183 | 10.6 / 2.9 |
| The 32 with 20 days of readings: ten minutes / hour | 20 / 53 | run 185 | 7.1 / 17.9 |
| A year's catch-up: can / tank / fermenter | 28 / 28 / 75 | run 181 | 9.7 / 9.6 / 24.9 |
| Through 20 days of readings / its machine menu | 13 / 15 | run 183 | 4.4 / 5.0 |
| Fuel menu, with the game's own context menu (0.025 ms) | 1.1 | run 341 | 0.38 |
| Machine menu for a fresh batch, with the game's own context menu | 0.8 | run 181 | 0.27 |
| The hands census: ten minutes | 0.011 | run 341 | 0.0037 |
| The 32 fermenters with 30 biodiesel machines: ten minutes / hour | 4.2 / 3.9 | run 341 | 1.41 / 1.30 |
| 8 petrol and 4 diesel engines idling on stale fuel: minute | 4.9 | run 341 | 1.63 |
| The 12 on fresh fuel / on harmful blends: minute | 2.2 / 4.1 | run 341 | 0.73 / 1.38 |
| A year's catch-up: retort / ash barrel / leacher / reactor / wash tank | 75 each | run 341 | 25.0 / 24.9 / 25.0 / 25.0 / 24.9 |
| Machine menu: retort / ash barrel / leacher / reactor / wash tank | 0.9 / 0.8 / 0.9 / 0.9 / 1.0 | run 341 | 0.29 / 0.27 / 0.29 / 0.31 / 0.33 |
| The square-load handler: 3,600 squares / a square with a generator | 5.1 / 0.005 | run 341 | 1.69 / 0.0017 |

Run 182 passed the 16 budgets set from run 181, and run 185 passed all 22.
Four of them had earlier values when run 185 checked them: 4.5 and 4.7
from run 181, 52 and 83 from run 183. Those four are set from run 185
itself (the two rows marked run 185).

Runs 340 and 341 passed 21 of the 22. The fuel menu failed its 0.08 ms,
set from run 181's 0.027 ms, which most likely timed a menu that did not
open (see "The fuel menu"). It is now 1.1 ms, set from run 341, as are
the 18 budgets of the workloads after the budget check. Runs 398 and 400
were the first to check those 18, and passed all 40, as did run 405.

The gas stages' budgets (`RT.PF.budgetsGas`), set from run 400. Run 401,
the gas stages alone, checked them first and passed all 13 (its medians
within 5 % of run 400's). The propane part-of-a-use budget is reset
from run 404, after the early return; run 404 passed it at 1.0 ms, the
budget before the reset. Run 405, the whole mode, checked all 13 with
the reset one and passed them (that one at 0.133 ms against 0.39). The
refill rows include the
steps taken out before each call. All 16 as they stood have none: that
state depends on how many hours the warm-up crossed. The part-of-a-use
timing takes the propane generators as the connect leaves them; an hour
passing between their start and the timing would change that state, and
its state check would fail.

| Measured | Budget, ms per call | Run 400 |
| --- | --- | --- |
| The gas minute pass with no gas generator | 0.005 | 0.0017 |
| 8 on propane: a part of a use below / within the tolerance / moving a use | 0.39 (from run 404: 0.129) / 0.27 / 1.7 | 0.337 / 0.088 / 0.56 |
| 8 on wood gas: at their caps / drawing a step | 0.30 / 4.8 | 0.098 / 1.58 |
| A lit gasifier brought forward 1, 30 and 365 days | 0.41 each | 0.134 / 0.133 / 0.134 |
| The Gasifier menu / the Gas menu on propane / on wood gas | 1.0 / 0.42 / 0.46 | 0.340 / 0.137 / 0.151 |
| The square-load handler on a gas generator's square | 0.011 | 0.0034 |

## Machine records: fire scan, readings and catch-up

Three conditions raise the cost of a machine's notes, readings and
catch-up: a fire warming it, readings it keeps while nobody uses it, and
catching up through those readings. Since D-032 each works as described
below. The figures before it are from runs 181–182; the decision and the
test log have the history.

1. **The fire scan.** A ten-minute note looks for the fire warming its
   machine among every square within 18 tiles, about 1,000 of them, and
   every object on them. Floor items count: they are in a square's
   objects. One scan serves all the warmed machines, each square visited
   once: 10.2 ms for 32 vessels beside a fire. With a scan for each
   machine, before D-032, the same 32 took 90 ms every 37.5 seconds.
2. **Readings kept by machines nobody uses.** Readings pile up from the
   last time the batch was brought forward, up to 480, until a **Status**
   or an action brings it forward again. The hourly reading and the
   ten-minute note change the stored record in place, and a trim finds
   what to drop without sorting: 6.7 ms per note and 17.6 ms per reading
   for 32 vessels left unused for 20 days in a loaded area. Before D-032
   each note and reading copied the whole record and sorted the hours of
   its readings and notes, and the same 32 cost 190–200 ms at every note
   and reading.
3. **Catching up through readings.** The notes' hours are sorted once for
   all the days a catch-up averages; before D-032, `Climate:siteDayMean`
   sorted them again for every day it averaged. Bringing a vessel through
   20 days of readings takes 4.3 ms, and its menu, which does so on every
   right-click, 4.9 ms. Before D-032 the catch-up took 60 ms, and the menu
   as long.

Equivalence tests compare the code with the code before D-032 on random
records and fires, ties included. In game, the fireplace mode repeated its
run (run 184, 21/0): every fire note and reading as the game gives them,
and the trip away credited exactly.

The remaining cost is linear in what a base holds. Extrapolated to the
hourly list's limit of 256 machines (not measured): 4.6 ms per note or
reading for running vessels, and with 480 readings each about 54 ms per
note and 140 ms per hourly reading. The fire scan grows with the area the
warmed machines cover rather than with their number.

## On a dedicated server (RT-MP runs 188–189)

The server runs the timers and answers the requests. Two multiplayer modes
timed them there (`tools/run-mp-harness.ps1 -Only effects` with two
clients, `-Only timers` with one). The server and its clients ran on the
reference machine, sharing its CPU, and the clock counts whole
milliseconds. These are observations, not budgets.

| What | Server |
| --- | --- |
| The minute pass, per vehicle in the server's cell (about 22, one idling on stale petrol; run 188) | 0.015 ms on average over 4290 calls, 2 ms the most |
| Hourly climate record and readings, 32 running fermenters (run 189's bench) | 0.398 ms |
| Ten-minute note pass, 32 fermenters, four beside a lit campfire (bench) | 2.51 ms |
| A fermenter's status catch-up (read, advance, site air; bench) | 0.106 ms |
| The same timers as they ran over three game hours | readings 1 ms; notes 3.6 ms on average, 6 ms the most |

The bench kept its writes on the server, so its figures leave out sending
the records to the clients; the timed events include it. Single player
gave 0.55 ms per reading and 0.59 ms per note for 32 fresh vessels
(run 185). The server's note pass costs more because four machines stand
by a fire: each pass scans the squares within reach of them.

### The vault's cost

On a server every read and write of a record also goes through the vault
(`TLG/Authority/Vault.lua`, docs/security-audit-2026-11-05.md §7.3), added
by the security audit's V-01 fix (2026-11-05). Single player does not use
the vault. The vault keeps a machine's readings and fire notes as digests
(the compact store, 2026-11-05), so every write of a machine record also
brings its digests up to date, recomputing only the entries that changed.

The timers mode (above) measured the server's passes in three of the
security audit's runs:

| Server pass | Without the vault (the audit's run 5) | Uncompacted vault (the audit's run 19) | Compact store (the audit's run 27) |
| --- | --- | --- | --- |
| Hourly pass | 0.40 ms | 0.60 ms | 0.76 ms |
| Ten-minute note pass | 4.39 ms | 2.87 ms | 2.91 ms |
| A status | 0.17 ms | 0.11 ms | 0.10 ms |

The differences between runs 5 and 19 are within what two unchanged runs
differ by here. In run 27 the 32 vessels had a few hours of history.

Measured in Kahlua on one vessel with 480 readings and 480 notes, each
call one hour (or ten minutes) after the last, so each write adds an entry
and the trim drops the oldest:

| Call | Without the vault | With the vault |
| --- | --- | --- |
| Hourly reading | 0.45 ms | 0.64-0.68 ms |
| Hourly reading, with a fireplace note every hour | 0.37 ms | 0.59-0.62 ms |
| Ten-minute note | 0.20-0.21 ms | 0.35-0.37 ms |

With 256 such machines the vault adds about 50 ms to the hourly pass and
40 ms to the ten-minute pass.

The first read of a record after the world loads compares it field by
field once: about 0.3 ms for a machine with 480 readings (Kahlua). For a
machine, the first read after a load, of the world or of the machine's
chunk, computes the digests whole, because the item's mod data comes back
as new tables: about 3.4 ms for that vessel with fireplace notes, against
about 0.3 ms for the field comparison alone before the compact store.

To recompute only what changed, the server keeps in memory (not saved),
per machine, each reading's and note's value and term: about 1,900 table
entries for a machine with 480 of each, on top of the record itself.

## Not measured

- **The gas on a server:** the minute pass there, and the gasifier
  records the server sends to every client at each write (D-041).
- **More than 16 gas generators,** or gasifiers that several generators
  draw from in one pass; and the game's own cost of running generators
  apart from the mod's (see "Frames with the gas").
- **What raises the frames with the gas in the whole mode:** no frames
  were sampled between the square-load stage and the gas, which would
  tell the gas from what runs before it (see "Frames with the gas").
- **Multiple electrical networks:** no network is built in game in this
  build. The energy model is domain-only (gate 4).
- **Several clients using shared storage:** the server's timers were
  timed with one player's car or machines (above). Several players' cars
  and machines at once were not measured, nor frames on a client in
  multiplayer.
- **On a server since 0.2.0:** the biodiesel machines, the diesel engines
  and the wrong-fuel rules.
- **The minute's work for litres burned:** the wear, the exhaust wear
  and, on wrong fuel, the failure draw. They run once a game minute, when
  the tank has dropped; inside a timed batch it never drops.
- **The square-load event as the chunk loader fires it,** and the game's
  call into Lua apart from the handler (see "The square-load hook").
- **Other computers:** every figure is the reference machine's. A slower
  CPU makes each call proportionally slower.
