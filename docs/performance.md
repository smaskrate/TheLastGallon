# Performance

Release gate 11 (spec section 18, "Performance acceptance"): the cost the
mod adds to the game, measured on a reference machine and world, and the
budgets set from that measurement. Measured with
`tools/run-sp-harness.ps1 -Mode performance` in RT-SP runs 181–185
(2026-11-04). Runs 181–182 were the baseline. They found three pauses,
which D-032 removed; runs 183 and 185 measured the fix. Evidence:
`docs/evidence/2026-11-04_rt-sp_harness_run181_performance.txt` to
`…_run185_performance.txt`, and run 184's fireplace test
(`…_run184_fireplace.txt`).

## What the mod runs on its own

- **Nothing every frame.** The mod registers no per-frame handler: no
  `OnTick`, no `OnPlayerUpdate`, no render event. The vanilla functions it
  wraps run once per player action: a refuel, a transfer, an equip, the
  start of a timed action.
- **Three timers**, run by the authority (the game in single player, the
  server in multiplayer):
  - every game minute, the engine effects of every vehicle in the loaded
    cell (`Vehicles.lua`). A parked car costs a few engine calls. A running
    one has its tank read, reconciled and judged, and its power and wear
    applied;
  - every ten game minutes, a note of the fire warming each running machine
    in the hourly list (`Machines.observeFires`). The list holds at most 256
    machines (`MAX_INDEXED`);
  - every game hour, the day's climate record and an air reading at each
    running machine (`Machines.sampleSites`).
- **On demand:** the fuel and machine menus, the requests they send, and
  transfers. The machine menu brings the batch to now on every right-click,
  without saving it. Status saves the caught-up batch.
- **Records** live in the modData of the item, tank or object they
  describe. The mod keeps no list of them, so a record is read only when its
  object is used. Dormant supplies are never visited.

In the measured world (day length 1 hour 30 minutes) a game minute lasts
3.75 real seconds. The ten-minute note comes every 37.5 seconds and the
hourly reading every 3.75 minutes. On a 1-hour day they come every 2.5
seconds, 25 seconds and 2.5 minutes.

## Reference

| | |
| --- | --- |
| Machine | AMD Ryzen 9 7950X3D (16 cores, 32 threads), 31 GB RAM, NVIDIA GeForce RTX 5080; Windows 11 Enterprise build 26300 |
| Game | 42.21.0 (`4a0e9546ec`) as the harness launches it: windowed 1280×720, debug mode, no sound, ZGC, 3 GB heap; vsync off, frame rate capped at 60, lighting at 15 updates a second |
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
  5. 8, then 32 fermenters loaded through the machine menu, as a player
     loads them;
  6. the 32 as if a fire warmed each. The air reads 5 °C above the
     unheated value, so each ten-minute note scans the tiles around the
     machines. No fire is found, so each scan runs to the end, as it does
     when a fire is there;
  7. the 32 with 20 days of hourly readings and fire notes (480 each,
     `MAX_READINGS`). A machine keeps that many when it runs in a loaded
     area and nobody uses it for 20 days. The world is only hours old, so
     the readings are dated ahead; the cost depends on how many a record
     holds.
- Catch-up: a can's fuel, a tank's fuel and a fermenter's batch are brought
  forward 1, 30 and 365 days (`Aging.advance`, `Machines.advance`). That is
  the arithmetic of catching up after that long away. The fermenter with 20
  days of readings is also brought through them, and its menu opened with
  the mod's clock 20 days on.
- Frames: 20 seconds at normal speed after each stage. For each frame, the
  game's own main-thread time (`getCPUTime`: the frame step from logic
  through render preparation and Lua events, in whole milliseconds) and the
  time between frames.
- Offline, `tools/run-tests.ps1 -Entry tests/support/bench_machine_records.lua`
  times the pieces of one record's notes, readings and catch-up on the
  game's Lua VM (the figures below are the game's).

## Results

Milliseconds per call: the median of five batches.

### Timers before D-032 (run 181 / run 182)

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

Runs 183 and 185 measured every other workload as runs 181–182 did,
within a few percent. Run 183 came before the notes' saving (the last
change of D-032), run 185 after it.

| Workload | Run 182 | Run 183 | Run 185 |
| --- | --- | --- | --- |
| 8 running fermenters: note / reading | 0.36 / 0.38 | 0.15 / 0.14 | 0.14 / 0.16 |
| 32 running fermenters: note / reading | 1.50 / 1.55 | 0.59 / 0.54 | 0.59 / 0.55 |
| The 32 warmed by a fire: note | 90 | 10.3 | 10.2 |
| One machine's fire scan alone | 2.85 | 2.93 | 2.82 |
| The 32 with 20 days of readings: note / reading | 192 / 202 | 17.2 / 27.8 | 6.7 / 17.6 |
| A fermenter brought through its 20 days of readings | 60 | 4.3 | 4.3 |
| Its machine menu, opened 20 days on | 59 | 4.9 | 4.9 |

### Per unit (run 185)

| What | Cost |
| --- | --- |
| A parked car, every game minute | 0.0016 ms |
| A running engine on stale petrol, every game minute | 0.13 ms |
| A running fermenter, per ten-minute note or hourly reading | 0.018 ms |
| A machine warmed by a fire, per note | its own scan, 2.8 ms; 32 side by side, 10.2 ms in all |
| A running fermenter with 480 readings | 0.21 ms per note, 0.55 ms per reading |
| A record of fuel caught up | 0.025 ms a day (9 ms for a year) |
| A fermenter's batch caught up | 0.065 ms a day (24 ms for a year) |
| The same through 20 days of readings | 4.3 ms (0.21 ms a day) |
| A can's first record, written by a look or a transfer | 0.8–1.0 ms, once |
| The fuel menu, on top of the game's context menu | 0.002 ms |
| The machine menu for a fresh batch, on top | 0.24 ms, of which 0.12 ms is the catch-up |
| The same with 20 days of readings | 4.9 ms |

### Catch-up

Milliseconds per call, run 181 / run 182. Runs 183 and 185 measured the
same; D-032 changed only the catch-up through readings.

| | 1 day | 30 days | 365 days |
| --- | --- | --- | --- |
| A can's fuel | 0.091 / 0.089 | 0.82 / 0.80 | 9.3 / 9.1 |
| A tank's fuel | 0.108 / 0.105 | 0.84 / 0.81 | 9.3 / 9.0 |
| A fermenter's batch | 0.155 / 0.150 | 2.13 / 2.03 | 24.7 / 23.6 |

### Frames (run 182)

Every stage of every run held the frame-rate cap of 60: between frames,
median 17 ms, worst 20–21 ms. So the frame rate cannot show load. The
game's main-thread time per frame, in milliseconds:

| Stage | Mean | Median | 95th percentile | 99th percentile | Worst |
| --- | --- | --- | --- | --- | --- |
| Empty road | 1.81 | 2 | 3 | 4 | 7 |
| 400 cans without records | 1.69 | 1 | 3 | 4 | 5 |
| 400 cans with records | 1.76 | 2 | 3 | 4 | 8 |
| 20 parked cars | 1.84 | 2 | 3 | 4 | 5 |
| 32 fermenters, 8 engines idling | 3.58 | 3 | 5 | 6 | 8 |

Giving the cans records changed nothing measurable. The last stage's rise
of 1.7 ms is the game's own work for eight running engines and 32 fermenter
models. The mod's timers come to about 0.006 ms a frame there: 1.1 ms once
every 225 frames, and less than that every 2,250 and 13,500. Runs 183 and
185 measured the same stages within 0.2 ms (the last stage: 3.66 and 3.74
mean). Run 181's main-thread times were lost to a units error in the
harness, since fixed.

## Budgets

Each budget is about three times the median of the last run of the code it
times, on the reference machine. Every performance run checks them
(`RT.PF.budgets`). The dormant cans get the empty road's budgets: records
nobody touches must cost nothing.

| Measured | Budget, ms per call | Set from | Run 185 |
| --- | --- | --- | --- |
| Empty road: minute / ten minutes / hour | 0.005 / 0.005 / 0.03 | run 181 | 0.0015 / 0.0016 / 0.010 |
| 400 dormant cans: minute / ten minutes / hour | 0.005 / 0.005 / 0.03 | run 181 | 0.0015 / 0.0016 / 0.010 |
| 20 parked cars: minute | 0.1 | run 181 | 0.033 |
| 8 engines idling on stale petrol: minute | 3.2 | run 181 | 1.05 |
| 32 running fermenters: minute | 3.3 | run 181 | 1.11 |
| 32 running fermenters: ten minutes / hour | 1.8 / 1.7 | run 185 | 0.59 / 0.55 |
| The 32 warmed by a fire: ten minutes / one machine's scan | 31 / 9 | run 183 | 10.2 / 2.8 |
| The 32 with 20 days of readings: ten minutes / hour | 20 / 53 | run 185 | 6.7 / 17.6 |
| A year's catch-up: can / tank / fermenter | 28 / 28 / 75 | run 181 | 9.1 / 9.1 / 23.7 |
| Through 20 days of readings / its machine menu | 13 / 15 | run 183 | 4.3 / 4.9 |
| Fuel menu / machine menu for a fresh batch, each with the game's own context menu (0.024 ms) | 0.08 / 0.8 | run 181 | 0.027 / 0.27 |

Run 182 passed the 16 budgets of run 181. Run 185 passed all 22, four of
them at their earlier values: 4.5 and 4.7 from run 181, 52 and 83 from
run 183. Those four are now set from run 185 itself. Run 185's figures
are within the new values, and the next performance run checks them.

## The three findings and D-032

Runs 181–182 found three pauses, all in the machines' records. D-032 made
the work cheaper with the same results.

1. **The fire scan.** Each ten-minute note looked for the fire warming its
   machine by scanning every square within 18 tiles, about 1,000 of them,
   and every object on them. Floor items count: they are in a square's
   objects. With 32 fermenters beside a fire that was 90 ms every 37.5
   seconds. Now one scan serves all the warmed machines, each square
   visited once: 10.2 ms.
2. **Readings kept by machines nobody uses.** Each hourly reading and
   ten-minute note copied the whole record and sorted the hours of its
   readings and notes. Readings pile up from the last time the batch was
   brought forward, up to 480, until a Status or an action brings it
   forward again. 32 fermenters left unused for 20 days in a loaded area
   cost 190–200 ms at every note and reading. Now the notes and readings
   change the stored record in place, and a trim finds what to drop
   without sorting: 6.7 ms per note, 17.6 ms per reading.
3. **Catching up through readings.** `Climate:siteDayMean` sorted the
   notes' hours again for every day it averaged. Bringing a fermenter
   through 20 days of readings took 60 ms, and its menu took as long on
   every right-click. Now they are sorted once: 4.3 and 4.9 ms.

The equivalence tests compare the new code with the old on random records
and fires, ties included. The fireplace mode repeated its run in game
(run 184, 21/0): every fire note and reading as the game gives them, the
trip away credited exactly.

What remains is linear in what a base holds. Extrapolated to the hourly
list's limit of 256 machines (not measured): 4.6 ms per note or reading
for running fermenters. With 480 readings each it would be about 54 ms
per note and 140 ms per hourly reading. The fire scan grows with the area
the warmed machines cover rather than with their number.

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
gave 0.55 ms per reading and 0.59 ms per note for 32 fresh fermenters
(run 185). The server's note pass costs more here because four machines
stand by a fire: each pass scans the squares within reach of them.

## Not measured

- **Multiple electrical networks:** no network is built in game in this
  build. The energy model is domain-only (gate 4).
- **Several clients using shared storage:** the server's timers were
  timed with one player's car or machines (above). Several players'
  cars and machines at once were not measured, nor frames on a client in
  multiplayer.
- **Other machines:** every figure is this machine's. A slower CPU makes
  each call proportionally slower.
