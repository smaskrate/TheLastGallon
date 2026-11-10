# Release checklist

Status legend: DONE · PARTIAL · OPEN · BLOCKED (needs something this
environment does not have). Publication to the Workshop is a separate manual
decision and is **not** authorised by any task in this repository.

Evidence: RT-SP is the single-player harness, RT-MP a dedicated server with
harness clients on this computer, RT-DS a dedicated server alone; SRC is the
game's own Lua, BC its bytecode.

## Gates that must pass before any public release

| # | Gate (spec §25) | Status | Summary |
| --- | --- | --- | --- |
| 1 | Every advertised pathway has a playable tested loop | PARTIAL | Ethanol, the only advertised pathway, verified RT-SP through the player's path, from crafting the machines to a converted generator and car running on the ethanol (runs 12, 38), and through both stills, the batch controls, winter, fires and the crafting window. Other pathways are domain-only and not advertised |
| 2 | Every supported transfer path preserves fuel state | PARTIAL | Every supported path verified RT-SP, item↔item RT-DS; a can's water stays in its fluids (run 59). Station-reservoir pour SRC-ONLY |
| 3 | Native and mod quantities reconciled | PARTIAL | Vehicle idle burn, generator burn and driving burn (run 176) reconciled RT-SP, poor fuel's engine effects included (run 179, D-031). Third-party paths NOT RUN |
| 4 | Production and energy invariants pass | PARTIAL | Domain invariants pass (142 cases, incl. energy balance, mass balance per converter); one in-game ethanol batch matched the model (runs 7–9), and a pot-still batch run in two loads matched it to 1e-6 L, kg and h, wear included (run 28); no in-game energy run |
| 5 | Multiplayer and dedicated-server tests pass | PARTIAL | Verified RT-MP on a dedicated server with two clients on this computer: the mod's requests, the fuel paths, the vessel's take, carry and death, conversions, the stills, engine effects, timers, knowledge and a restart. NOT RUN: a real network, a still or drying column picked up while working, driving on poor fuel |
| 6 | Save/load, pickup/placement, unloaded simulation pass | PARTIAL | Records survive save/reload and chunk unloads; running machines and generators keep their records through every Lua pickup and put-down path, carried hours never counting (D-015); a carrier's death handled in single player and on a server. NOT RUN: a still or drying column moved in multiplayer, a climb's drop |
| 7 | Existing and late-world bootstrap scenarios pass | PARTIAL | An existing save gaining the packaged mod (run 40), fuel first found late in a new world (run 53) and the mod removed and added back (runs 55, 61) verified RT-SP. NOT RUN: the other two policies, a server, the missing-mods prompt |
| 8 | Supported chassis and maps documented | PARTIAL | `support-matrix.md`; `Base.CarNormal`, `Base.Generator` (stock and flex-converted) and the Muldraugh Gas2Go verified RT-SP. `Base.PickUpTruck` stock verified RT-SP (run 62, 29/0, phase A's vehicle steps): refuel from a can and at a pump, siphon, idle burn, the TLG pours, start gate and stall. Its flex conversion and other chassis NOT RUN |
| 9 | Required assets verified and licensed | PARTIAL | The supplied models and carry clips drawn or played in game, their rights recorded; the mod's own floor models and release art (run 190); licence CC BY-NC-SA 4.0. Open: three commissioning decisions, the banner and screenshots (R04) |
| 10 | English/Italian text and player docs complete | PARTIAL | Every shipped key in English and Italian; all 261 Italian strings as shipped in a client set to Italian (run 205); the field manual read in both languages (runs 101–103). Docs for unfinished pathways pending |
| 11 | Performance measured against a baseline | PARTIAL | Single player measured on a reference machine, its 22 budgets all passed (run 185); a server's timers measured with one client (run 189). NOT RUN: several clients sharing storage, other machines |
| 12 | Clean install and upgrade pass with the packaged artifact | PARTIAL | The 0.1.2 package is the zip of `f674d1c` (SHA-256 `be68b619…`), installed and played on 42.22.2 in launch 228 (100/0, 14/0). The Workshop item serves 0.1.1, which was never rehearsed from its zip. NOT RUN: an install through the Steam Workshop, an upgrade from 0.1.1 |
| 13 | No core behaviour represented only by a placeholder | PARTIAL | The fermentation vessel, both stills, the drying column and the filter cartridge have their own models and icons, every other item its own icon, the four small items their own floor models, and the vessel its own carry pose |
| 14 | Optional integrations distinguished from shipped scope | DONE | No external integrations claimed |

## Gate details

What each gate has verified now, with the runs that verify it, and what is
NOT RUN or open. Gates 4, 8 and 14 are complete in the table above. How
each failure was found and fixed is in `test-results.md`, by run, and in
`decisions.md`, by decision.

### Gate 1: every advertised pathway has a playable tested loop

Ethanol is the only advertised pathway. Other pathways are domain-only and
not advertised.

- **The player's path** (RT-SP run 12, and run 38 from the release zip):
  the four machines crafted from the inventory craft menu, a whole batch
  run from the machine menu (fermentation vessel → reflux still → drying
  column → cans), and a `Base.Generator` and a `Base.CarNormal` converted
  from the workshop menu and run on the ethanol. Everything survives
  reload. Crafting needs light: these runs crafted in a dark workshop with
  a torch in hand.
- **The game clock:** the same loop ran for 136 game hours, the conversion
  work at vanilla x40 (runs 13–14).
- **Winter:** a January fermentation slowed (run 15) and, with weather,
  stopped and spoiled as specified (run 16). By site (D-021, runs 17–19,
  grid off), the January batch stopped and spoiled outdoors and in an
  unheated room, and finished on a tile warmed by a heat source; readings,
  day temperatures and work matched the game exactly.
- **Fires:** beside a map fireplace kept fed with logs, the January batch
  finished, the heat formula matching every tile and hour (run 21). That
  fire was lit and fed with the calls its actions make, not through its
  menu. A fire's noted fuel covers the hours away it lasts, and the work
  over the trip is exact (run 23, D-022). Beside a campfire and a charcoal
  barbecue lit from their menus, outdoors in January, the air around both
  fires and at their vessels follows the heat formula exactly. Both fires
  are noted with their fuel, the campfire (not an `IsoFireplace`) with its
  largest radius, and their warmth is credited over a 12 hour trip
  exactly: the campfire's 6.48 h of credit and the work over the trip
  match the rule (run 35, 39/0; D-022).
- **The pot still** from its menu (run 28): a 66.6 L wash in two loads of
  its 60 L, the firebox run out mid-batch and refed (three of four logs
  fitting), the yeast starter with the last wash. Outputs, hours and fuel
  matched the definitions exactly. By the start gates' evaluation the
  spirit was unfit for every spark engine until dried, then fit for flex
  engines.
- **Batch controls** on a fermentation vessel and the drying column
  (run 51, 32/0; D-023): **Pause** and **Resume** from the menu hold and
  continue a batch exactly. **Abort batch** keeps what the batch made: an
  aborted vessel keeps its wash, its preparing hour making no ethanol, and
  a pot still takes that wash; an aborted drying column keeps its ethanol
  for a can. What is thrown away is listed, a second **Abort batch**
  empties the machine, and a spoiled batch is emptied and the vessel
  loaded again. Refusals read as sentences, and the menu offers each
  control only where it applies.
- **Running stills** (run 50, 28/0): **Pause**, **Resume** and
  **Abort batch** from the menu work. A pot still paused while heating up
  was held three hours with no work or wood burned, then finished its
  stage hours plus exactly the paused hours. A reflux still aborted an
  hour into distilling accounted for its whole wash, kept its unburned
  wood and exactly the 1.10 L it had distilled, and gave what it kept to a
  can. **Abort batch** keeps the share done of the stages that make the
  result, which the recipes mark (`makes`; D-023).
- **The crafting window** (`-Mode crafting`, run 193, 25/0), opened with
  the button beside the equipped items, at a workbench: each of the mod's
  seven recipes is listed by its name, not its id
  (`TLG_MakeFermenterVessel`), from the mod's English and Italian
  `Recipes.json`. Each was found by typing its name, picked from the list
  and made with **Craft** (the drying column by double-clicking its row).
  The vessel picked with its nails missing was refused: **Craft**
  disabled, nothing started.
- Not looked at: the craft menu's option labels, which come from the same
  names (SRC `ISInventoryPaneContextMenu`).

### Gate 2: every supported transfer path preserves fuel state

- Verified RT-SP: pump→can, pump→vehicle, can↔vehicle, can→generator, the
  TLG pour into generators and a car (with and without confirmation),
  generator pickup and drop, the end-to-end chain, still→can and
  can→drying column→can. Item↔item RT-DS.
- The water a can's fuel takes up while it ages stays in its fluids
  through a vanilla pour, a first look, siphoning and pump fills (D-007
  amendment). Run 59 (8/0) verified the pours, the read and a look on a
  full can, and a full can takes a new fluid. Siphoning and pump-to-can
  settle through the same write: in the full harness on the zip (run 60),
  a can filled to the brim at a pump and a vehicle siphoned into a can
  each moved 10 L with its fuel state carried.
- Station-reservoir pour SRC-ONLY (`support-matrix.md`).

### Gate 3: native and mod quantities reconciled

- Vehicle idle burn, generator burn and driving burn verified RT-SP. Start
  gates and stall verified RT-SP.
- Driving (`-Mode driving`, run 176, 26/0): a `Base.CarNormal` on E10
  driven 352 tiles at 25 km/h lost 0.778136 L, exactly the sum of
  vanilla's 14 burns with no other write to the tank, and the record
  reconciled to it in proportion (worst 5.6e-16). An unsuitable blend
  stalled the engine on the move at 24.7 km/h, after which nothing burned.
  No part was damaged and no impact was seen. The same again with the
  engine effects of D-031 in place (run 178, 26/0).
- Poor fuel's effects (D-031, `-Mode engine-effects`, run 179, 36/0): a
  car's power is lowered by the fuel while it runs and given back when it
  stops; the wear its litres owe comes off the Engine part; no stall with
  the sandbox option off; a generator's wear is charged by its next
  refuel, once.
- Third-party paths NOT RUN.

### Gate 5: multiplayer and dedicated-server tests pass

A dedicated server and two clients on this computer, unattended
(`tools/run-mp-harness.ps1`, RT-MP runs 136–171; runs 150 and 164 from the
package). Verified:

- Run 147 (A 26/0, B 11/0): the mod's sample, stabilize and machine-status
  requests answered by the server; a repeated request answered from its
  ledger; a can's record the same on client and server; the field manual
  rolled from the server's loot and read; the small items' floor models
  seen by both players and after a rejoin; the vessel taken off the floor
  into both arms, its batch carried, and put down again; the vessel's
  carry pose seen on the other player's screen at every gait; two players
  taking the vessel at once, one getting it and the other's action
  refused.
- On a server the mod takes the vessel off the floor itself (D-030): there
  42.21 fails that action for every heavy item, vanilla's meteorite too,
  also without the mod (run 144).
- Run 147's checks again with both players without admin rights
  (run 154).
- Two players loading one fermentation vessel at once: one load taken, the
  other refused (`machine_busy`). A running vessel moved by the world
  menu's **Grab** (run 155).
- Refuelling at the pumps, the TLG pour with its result shown to the
  player, generators started and refused, burned, taken and put back, and
  a car started and idling (run 160).
- A server restart kept the floor and the records (run 161).
- A generator (run 162) and a car (run 169) converted to flex fuel and run
  on ethanol.
- Siphoning (run 165); the vessel taken out of a container (a bin,
  run 167); both stills and the drying column from wash to dried ethanol
  (run 171).
- Poor fuel's engine effects applied by the server and seen by both
  clients: power lowered and given back, wear, the start gate, the stall
  option, a generator's wear at a refuel (run 188, A 22/0, B 9/0; D-031).
- The machines' hourly readings and ten-minute notes on the server beside
  a campfire it lit, all as the air and the fire give them (run 189, 6/0;
  D-032).
- **What I know about it** on a server (D-034): the client's menu lists
  both tests the server answered, with their ages, and the open note once
  the can is opened (run 204, 8/0). What the server knows of a player came
  back after the player left and the server was saved, stopped and
  started again: both tests, unchanged, the can sealed (run 208, 11/0).
- A carrier's death: no death event reaches a dedicated server's Lua
  (run 209), so the mod follows the hands there (D-015 amendment). The
  vessel was put down where the player died, from the death, and worked
  on (run 210, A 5/0, B 6/0; gate 6).
- A server needs the mod's real path: started through a junction, it
  stopped, since the mod ships pose files.

NOT RUN: a real network (no second machine; set aside on 2026-11-03), a
still or drying column picked up while working in multiplayer, and driving
on poor fuel in multiplayer.

### Gate 6: save/load, pickup/placement, unloaded simulation pass

Save, reload and unloaded simulation, RT-SP:

- Item, ground item, vehicle, generator, pump and machine records and
  conversion projects survive save/reload.
- A fermentation vessel whose chunk was unloaded for 24 game hours caught
  up exactly (runs 13–14).
- Machine sites and hourly readings (D-021) survived a chunk unload, and
  the readings resumed (runs 17–19, 21).
- A vessel mid-batch beside a fireplace survived save, exit to menu and
  continue with its site, readings, fire notes ("no fire" notes included),
  batch and place in the hourly list unchanged, then finished (run 25).
- **What I know about it** across a save (run 207, 7/0 and 9/0): saved and
  exited to the menu after a kit sample and a look, the save continued.
  The character's knowledge and the can's record came back as saved, and
  the menu listed both tests, their ages gone on, with no notes.

Pickup and placement:

- Generator pickup and placement on all Lua paths. Generators put down by
  the menus' unequip (a second generator taken from the world menu, a
  weapon equipped from the inventory menu) keep their records (run 85,
  8/0).
- Running fermentation vessels picked up (world menu **Grab**, loot window
  **Grab**) and put down (place action, **Drop**) keep their records, and
  offer only **Status** while carried (run 26). Placed hours count up to
  the pickup and from the put-down; carried hours never count; the hourly
  reading follows the vessel at once (run 27, 34/0; D-015). A grab no Lua
  sees, as in multiplayer, is credited up to the last time the vessel was
  found placed: 0.10 h short in run 27.
- A pot still mid-distillation, a reflux still heating up and a drying
  column mid-batch, moved by the same three pickup paths, each finished
  its remaining stage hours after the put-down, with exactly the wood and
  spirit the definitions give. Nothing advanced while carried: no work, no
  wood burned, no paused hours. The unseen grab lost 0.15 h (run 45,
  41/0).
- A carried machine answers **Status** only. The authority refuses
  **Feed the firebox**, **Collect ethanol into a fuel can**, **Pause**,
  **Resume** and **Abort batch** for it, so a **Resume** cannot make
  carried hours count (run 46, 46/0, and domain tests).
- Carried across a save (run 48, 29/0 and 24/0): saved and exited to the
  menu with all three carried, the save continued. Their records came back
  exactly as saved, still in the inventory, and the batches finished as in
  run 45.
- A still or drying column picked up while working, in multiplayer,
  NOT RUN. The fermentation vessel's moves on a server are verified
  (runs 147, 155 and 167; gate 5).
- The fermentation vessel is a heavy item, carried in both hands. Taken
  the loot window's double-click way (the mod lifts the world object 42.21
  leaves on the square, run 78), carried an hour and dropped with
  `forceDropHeavyItems`, it did not count the carried hour (run 79, 39/0,
  which first repeated run 27's moves).
- Put down by the menus' unequip, as when a meteorite is taken the
  double-click way (`ISUnequipAction` drops a heavy item at the feet, and
  the mod follows it), the vessel resumed at once, and the carried half
  hour did not count (run 81, 43/0).
- The mod puts the carried vessel down at the feet when an action that
  plays its own animation starts (D-025 amendment): in a real loot (nails
  taken from a bag on the floor) the vessel lay on the ground as "Loot"
  began (runs 99 and 100, 11/0 each). A generator stays in both hands
  through the same loot, as the game keeps it, and a bat equipped from the
  inventory menu puts the vessel down through the game's unequip (run 99).

Death:

- Death and a successor (`-Mode successor`, runs 199 and 202, 18/0 each):
  a survivor who had loaded two vessels, looked at a can and carried one
  vessel was killed, and the game's **Respawn** and character screens made
  a new survivor in the same world. The world record, the can's record (in
  the body) and the placed vessel's work were as left; the new survivor
  knew nothing of the can until a look. The carried vessel was dropped at
  the body's feet, where no Lua sees it. The death hook (D-015 amendment)
  puts it down at the death, and it worked as the placed one over the same
  time (run 202). Taken back from the floor into both arms and put down,
  both vessels worked on.
- On a dedicated server the carried vessel falls on the floor where the
  player died, keeping its item id, and neither `OnPlayerDeath` nor
  `OnCharacterDeath` fires there, so the death hook does not run
  (run 209). The mod follows the hands instead (D-015 amendment: the equip
  events the server's own drop fires, then a watch until the machine
  lands). In run 210 (A 5/0, B 6/0) the vessel was put down where the
  player died, from the death (0.0533 game h after the probe before it:
  the two seconds before the kill), listed for the hourly reading at once,
  and working: 0.958 h of work by a read 1.29 game h on.
- A climb's drop, which the same watch covers, NOT RUN.

### Gate 7: existing and late-world bootstrap scenarios pass

- The transition policies are domain-tested.
- An existing save gaining the packaged mod
  (`tools/rehearse-install.ps1 -Scenario existing`, run 40): a world played
  10 game days without the mod was continued with it. The world record was
  created on that load as an existing save under the default transition
  policy (the save took the mod's sandbox defaults). Fuel first recorded at
  installation was fresh (can 0.000013, pump 0.000005, exactly the rule),
  and a can first found 6 days later partly aged (0.120482, exactly the
  rule). Everything was unchanged after save and continue. A first look at
  such fuel records it, and **What I know about it** finds the look
  (run 41: 3/0, 11/0, 3/0; D-024).
- Late exploration in a new world (run 53, 7/0): the world record is a new
  game's (`new_world`). A can and the nearest pump left alone for 7 game
  days, then found, held exactly the world-age condition, as did a can
  found at the start. Read again on day 7, that early can had aged within
  0.85 % of the one-span calculation (the documented running mean of
  day 0).
- Removing and re-adding the mod (`-Scenario removal`, run 54; the mod
  taken off with the load screen's **Choose Mods...**, the save's
  `mods.txt`): the save loads without the mod, and adding it back finds
  the same world record, never created again. The records on petrol cans
  come back unchanged, and a can poured from meanwhile keeps its
  condition. The mod's machines and its ethanol in a can are lost while it
  is away: the game skips them at load. Fuel added while the mod was away
  mixes in when it is found and is not aged a second time over the time
  away (D-006 amendment): run 55, on the zip rebuilt with it (1/0, 2/0,
  5/0), matched D-006 exactly and repeated run 54's other results, and
  run 61 repeated it all on the zip with the water fix.
- NOT RUN: the other two policies, a server, and a save that still lists
  the mod after it was uninstalled (the missing-mods prompt).

### Gate 9: required assets verified and licensed

- Vanilla references: `asset-audit.csv` (57 rows); the full list is in
  `asset-requirements.md`.
- The fermentation vessel's model (`TLG.Fermenter`, generated with Tripo
  Studio) was drawn, turned and reloaded in game (runs 68–69). Its rights
  rest on the user's statement of 2026-11-02 that they hold a commercial
  Tripo licence (`art-src/fermenter/PROVENANCE.md`); Tripo's Terms text
  itself not read.
- Four more Tripo models, supplied 2026-11-03 (the pot still, the reflux
  still, the drying column and the filter cartridge), were drawn on the
  floor in game (runs 120–122). Their rights rest on the same statement
  (`PROVENANCE.md` in `art-src/potstill`, `refluxstill`, `dryingcolumn`,
  `fuelfilter`).
- The floor models of the sampling kit, the yeast starter, the stabilizer
  and the field manual are the mod's own, built from simple shapes by
  `tools/make-prop-models.ps1`, and were drawn on the floor in game
  (runs 132–133).
- The vessel's carry animation (`Bob_TLG_CarryVessel`, the arms of two
  Mixamo "Carrying" clips retargeted onto the game's skeleton) played in
  game (runs 96 and 98). Its rights are recorded from Adobe's Mixamo FAQ:
  royalty free in video games (`art-src/carry/PROVENANCE.md`); Adobe's
  General Terms not read.
- One original test model was imported and three placeholders seen drawn
  (runs 64–67, G13); the mod's own models have replaced all three
  placeholders.
- Release art (D-033): the Workshop preview (256×256, 80,474 bytes), the
  mod list's poster (the same picture) and its icon (the vessel's
  inventory icon), made by `tools/make-preview.ps1` from the mod's own
  models. The game read the poster and the icon from the installed zip's
  `mod.info` and loaded them as textures of 256×256 and 32×32 (run 190).
- Licence: CC BY-NC-SA 4.0, chosen on 2026-11-04 (`LICENSE.md`; D-033),
  with the supplied models and the carry clips excluded.
- Open: three commissioning decisions (item or world object, budget,
  vehicle parts after G11); the banner and screenshots, not made (R04).

### Gate 10: English/Italian text and player docs complete

- Every shipped key exists in English and Italian
  (`check-translations.ps1`); English resolves in the client (RT-SP).
- In a client set to Italian, all 261 Italian strings came back exactly as
  shipped (run 205, 5/0): menu, interface, fluid and sandbox texts, every
  item name, the seven recipe names (read as the crafting window reads
  them, `Translator.getRecipeName`) and the 14 strings D-034 added for
  **What I know about it**; none unresolved, no accent garbled.
  Placeholders were filled, and the Fuel menu, **Look and smell**, the
  machine menu and **Status** read Italian. How the fonts draw the accents
  was not looked at.
- The field manual's page (D-026) was read in game in English and Italian
  (runs 101–103, 10/0 each). **Inspect** showed the page in the game's
  print media window, and the Italian page's accents and `°C` drew
  correctly.
- Docs for unfinished pathways pending.

### Gate 11: performance measured against a baseline

Single player was measured on a reference machine
(`tools/run-sp-harness.ps1 -Mode performance`, runs 181–185);
`docs/performance.md` gives the method, the baseline and what D-032
changed.

- The mod runs nothing every frame in steady play: a machine that leaves a
  character's hands is looked at once a tick until it lands, at most 300
  ticks (D-015 amendment).
- Its three timers cost 0.0015–0.010 ms on an empty road, the same with
  400 dormant cans with records, 0.034 ms a game minute with 20 parked
  cars and 1.04 ms with 8 of them idling on stale petrol.
- 32 running fermentation vessels, freshly loaded, cost 0.59 ms per
  ten-minute note (run 185).
- The three pauses the baseline found in the machines' records (run 182)
  cost, since D-032 (run 185): a fire's scan, 10.2 ms every ten game
  minutes for 32 vessels beside a fire; machines unused for 20 days,
  6.7–17.6 ms per note and reading for 32; catching one of them up,
  4.3 ms, also on every right-click. D-032 does the same work for less
  with the same results (equivalence tests; the fireplace mode repeated in
  run 184, 21/0).
- A year's catch-up takes 9 ms for a can and 24 ms for a vessel.
- Frames held 60 a second throughout; the main thread took 1.8 ms a frame
  on the empty road, the same with the cans' records.
- The mode checks 22 budgets of about three times the latest medians; all
  passed in run 185.
- On a dedicated server with one client (run 189), with 32 running vessels,
  four beside a campfire: the hourly readings 0.40 ms, a ten-minute note
  pass 2.5 ms, a status catch-up 0.11 ms. The vehicle pass costs 0.015 ms
  a vehicle (run 188).
- NOT RUN: several clients sharing storage, other machines. Electrical
  networks are not built in game in this build.

### Gate 12: clean install and upgrade pass with the packaged artifact

The current package is `TheLastGallon-0.1.2.zip`, the zip of commit
`f674d1c`: SHA-256 `be68b619…`, 4,478,414 bytes, 144 files. Launch 228
rehearsed its manual install (`tools/rehearse-install.ps1 -NoBuild`) on
42.22.2: the zip matched its manifest and was installed into a fresh
isolated cache. Phase A passed 100/0 and phase B, after save, exit and
continue, 14/0. The console's one exception came from the harness's own
deep-recursion probe, and the mod did not warn of an untested game version.

Launch 227 had rehearsed the zip of `965e063` and failed one check (99/1,
then 14/0): the game read no description from `mod.info`, because the
0.1.2 commit (`cfae118`) had cut the line's `description=` key. `f674d1c`
restored it. The zip of `cfae118`, built and pushed on 2026-11-10, has
that defect and two malformed lines in `workshop.txt`; it was not uploaded.

The Steam Workshop item (id 3835496461) serves 0.1.1, uploaded by the
owner on 2026-11-08 and public. The 0.1.1 zip was never rehearsed: its
menus on placed items were checked from the repository's mod
(`test-results.md`, 2026-11-08). The upload folder
(`<user>/Zomboid/Workshop/TheLastGallon`) still holds 0.1.1, with a
`workshop.txt` edited by hand (the item's id, `visibility=public`, the tag
`WIP`, two reworded lines): copying the package's `workshop.txt` over it
would lose those.

What changed in the package since the last rehearsed one (run 206, 0.1.0):
the death fix on a server (D-015 amendment, run 210: `Machines.lua`,
`Boot.lua`), the **Transfer Liquid** fix (D-035, run 215:
`Containers.lua`), the 0.1.1 menus on placed items, the player guide's
pictures (`docs/images`) and the 42.22.2 version values.

Run 206 rehearsed the 0.1.0 package's manual install from the zip
(`tools/rehearse-install.ps1`) on `TheLastGallon-0.1.0.zip` built from
uncommitted changes on `e9f1e87`: SHA-256 `8ef1dd31…`, 4,008,919 bytes,
129 files. The zip matched its manifest and was installed into a fresh
isolated cache. Phase A, whose 100 checks are the 94 of the earlier
packages (the fuel chain among them: pump to can, can to car, the siphon,
can to generator, pump to car, the TLG pours) and six on what the game
read from `mod.info`, passed 100/0. Phase B, which checks the records
after save, exit and continue (among them a placed reflux still and drying
column found back), passed 14/0. The console's one exception came from the
harness's own deep-recursion probe. The zip's files differ from run 195's
in:

- the security audit's commits (`fe50875`, `e9f1e87`): the new `Vault.lua`
  and `WorldStore.lua`, and changes to the handlers, adapters and
  `World.lua`, none installed from a zip before;
- D-034 and the death hook: `Inspection.lua`, `Handlers.lua`, `Format.lua`,
  `FuelContextMenu.lua`, `Machines.lua`, the English and Italian
  `IG_UI.json`;
- the shipped changelog, player guide and migrations notes.

The zip's entry names use forward slashes, and two builds of one commit
are byte-identical.

Earlier 0.1.0 packages, all superseded and none uploaded, are listed below with
the runs made from each package's item tree, which the zip is made from.
The full harness runs single player, so the multiplayer cases ran from
the item tree (runs 150 and 164); run 61 used run 60's zip itself. The
packages' sizes, file counts and contents are in `test-results.md`.

| Install run | Zip SHA-256 | Runs from its item tree |
| --- | --- | --- |
| run 195, built from uncommitted changes on `5574606` | `1e3ab9e4…`; the zip of commit `42b8d3c`, the same files: `8bf6ba79…` | |
| run 190, built from uncommitted changes on `6123c0e` | `2b5e1afc…`; the zip of commit `1d03a03`, the same files: `47be8fd6…` | |
| run 187, the zip of `b7dd527` | `bac724c6…` | |
| run 180, the zip of `b604f6b` | `34fbd7f7…` | |
| run 173, the zip of `be48759` | `85b078bf…` | |
| run 163, the zip of `142d009` | `16c93e7f…` | run 164 (19/0): the multiplayer fuel case |
| run 149, the zip of `9824306` | `0947f1e7…` | run 150 (A 10/0, B 8/0): the multiplayer carry |
| run 134 | `e249719d…` | run 135 (19/0): the floor models |
| run 130 | `b01db3e7…` | run 131 (19/0): every icon |
| run 127 | `f9c52565…` | run 128 (15/0): the icons |
| run 123 | `0a0a6a1e…` | run 124 (10/0): the models |
| run 118 | `e3a284a3…` | run 119 (26/0): the gaits |
| run 114 | `5ab59e10…` | run 115 (23/0): the gaits |
| run 104 | `abcc355a…` | runs 105 and 106: the put-down and the manual |
| run 97 | `7169c16c…` | run 98 (6/0): the carry, from the item tree of `4aca0b0`, one changelog entry later |
| run 82 | `2a762bad…` | |
| run 80 | `e5ae9136…` | |
| run 72 | `1d150946…` | |
| run 70 | `15229e13…` | |
| run 63 | `aa662e45…` | |
| run 60 | `3970ad6b…` | run 61: the removal scenario |
| run 56 | `196912cf…` | |
| run 52 | `75873ed3…` | |
| run 47 | `b608f4c5…` | |
| run 42 | `d1a6f5e1…` | |
| run 38 | — | |

- Install through the Steam Workshop (staged or subscribed) NOT RUN: the
  game scans those folders only in Steam mode (BC), and the harness does
  not run in it. A subscribed copy of 0.1.1 is on this computer.
- Upgrade NOT RUN: a save played with 0.1.1 has not been continued with
  0.1.2, and `tools/rehearse-install.ps1` has no scenario for it. Between
  the two versions only the version values and `mod.info` changed.

### Gate 13: no core behaviour represented only by a placeholder

- The fermentation vessel has its own model on the floor (runs 68–69) and
  its own icon (run 71), and is carried in both arms as that model, with
  its own carry pose (runs 96 and 98).
- The two stills, the drying column and the filter cartridge have their
  own models on the floor (runs 120–122; D-027) and their own icons,
  rendered from those models (runs 125–126). Every other item has an icon
  of its own as well (run 129, D-028).
- The sampling kit, the yeast starter, the stabilizer and the field manual
  lie on the floor as their own models (runs 132–133, D-029).

## Open implementation items

* Adapters, placeable machines and UI for biodiesel, wood gas, biogas,
  propane cylinders and electrical networks (domains merged and tested).
* Automation wiring (rules exist in the domain; no adapter yet).
* "Prepare removal" admin command (`migrations.md`). It must cover what the
  game drops when it loads a save without the mod: the mod's machines,
  with their batches, and its ethanol in containers (runs 54 and 55; its
  other fluids not tried). Until it exists, the player guide and
  `migrations.md` say what is lost and what to use up first.
* Wood-gas and electric vehicle conversions (no shipped definitions).
* Mark the making stages (`makes`) of the biodiesel, biogas, wood retort
  and ash pit recipes with their machines; until then **Abort batch**
  counts every stage of them (D-023).
* The fermentation vessel carried (D-025). The mod puts it down before any
  Lua action that plays its own animation, since that animation replaces
  the carry pose (run 99). Walking, running, sprinting and sneaking keep it
  in both hands with the pose on (run 108). Crouched it has a pose of its
  own that holds it upright (run 113), and so has sprinting, crouched or
  not (run 117). Open:
  - running still tilts the barrel with the runner's lean and swings it
    through the stride (the standing clip; run 117's pictures);
  - turning or colliding while sprinting is not run: the turn animation
    poses the chest instead of the sprint clip, so the barrel may not hold
    steady while it plays;
  - not covered and not run: animations the game starts without a Lua
    action (opening doors, shoving, emotes), and in multiplayer the
    put-down itself (a multiplayer client asks the server to put the
    vessel down, as the vehicle entry does);
  - the supplied model's editable sources are still missing (a `.blend`
    file or the Tripo project; `art-src/fermenter/PROVENANCE.md`).

## Harness and packaging commands

From the repository folder, in PowerShell. The comment after each command
says what it runs and, for some, about how long it takes.

```powershell
tools\run-sp-harness.ps1              # unlocked desktop, no input needed; ~15 min
tools\run-sp-harness.ps1 -Mode realtime -TimeoutMinutes 60   # ethanol loop on the game clock; ~7 min
tools\run-sp-harness.ps1 -Mode winter -TimeoutMinutes 60     # three fermenters by site from 15 January, grid off
tools\run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60  # one beside a map fireplace fed with logs, same January
tools\run-sp-harness.ps1 -Mode fireplace-reload -TimeoutMinutes 60  # the same saved mid-batch, continued, finished
tools\run-sp-harness.ps1 -Mode pickup -TimeoutMinutes 30     # three of four running fermenters picked up and put down
tools\run-sp-harness.ps1 -Mode pot-still -TimeoutMinutes 40  # a batch through the pot still in two runs, then dried
tools\run-sp-harness.ps1 -Mode controls -TimeoutMinutes 30   # Pause, Resume and Abort batch from the machine menu
tools\run-sp-harness.ps1 -Mode still-pickup -TimeoutMinutes 40  # two stills and a drying column picked up mid-batch and put down
tools\run-sp-harness.ps1 -Mode still-save -TimeoutMinutes 40    # the same, saved and continued while the three are carried
tools\run-sp-harness.ps1 -Mode still-controls -TimeoutMinutes 40  # Pause, Resume and Abort batch on running stills
tools\run-sp-harness.ps1 -Mode late-find -TimeoutMinutes 40     # a new world: fuel first found 7 days in
tools\run-sp-harness.ps1 -Mode can-water                        # an opened can's water through pours, a look on a full can
tools\run-sp-harness.ps1 -Mode chassis                          # phase A's vehicle steps on Base.PickUpTruck
tools\run-sp-harness.ps1 -Mode driving                          # a car on E10 driven 350 tiles on cruise control, then one stalling on the move; ~3 min
tools\run-sp-harness.ps1 -Mode engine-effects                   # poor fuel: a car's power and wear, no stall with the option off, a generator's wear; ~4 min
tools\run-sp-harness.ps1 -Mode performance                      # gate 11: the mod's timers, catch-up and menus timed as workloads are added, frames sampled, budgets checked (docs/performance.md); ~8 min
tools\make-test-model.ps1                                        # the original test model, into the harness mod only
tools\run-sp-harness.ps1 -Mode model-import                     # that model on the fermenter: placed, turned, held, photographed, reloaded
tools\run-sp-harness.ps1 -Mode fermenter-model                  # the fermenter's shipped model beside the true-size test barrel, reloaded
tools\run-sp-harness.ps1 -Mode held                             # held items close up: a bat, a bottle, the vessel idle and during an action
tools\run-sp-harness.ps1 -Mode heavy                            # heavy items in both hands; a meteorite taken off the floor
tools\run-sp-harness.ps1 -Mode generator-unequip                # generators put down by the menus' unequip keep their records
tools\run-sp-harness.ps1 -Mode pose                             # a vessel stand-in held with the held-bag pose, hand models compared
tools\run-sp-harness.ps1 -Mode pose-hold                        # both arms through the harness's own pose files, with the animator's log
tools\run-sp-harness.ps1 -Mode pose-freeze                      # the game's both-hands clips held still on their first frame
tools\run-sp-harness.ps1 -Mode pose-carry                       # the carry clip retargeted from a Mixamo clip, the bottle and the barrel at 0.6 m and 0.5 m; no save
tools\run-sp-harness.ps1 -Mode pose-carry-wide                  # the same from the wider clip, the barrel at 0.75 m and 0.6 m; no save
tools\run-sp-harness.ps1 -Mode pose-carry-mid                   # the two clips blended halfway, the barrel at 0.75 m and 0.6 m; no save
tools\run-sp-harness.ps1 -Mode pose-carry-offsets               # the halfway blend, the full-size barrel 0.13, 0.17 and 0.21 file units in front of the hands; no save
tools\run-sp-harness.ps1 -Mode vessel-carry                     # the shipped vessel carried in both arms: front, side, walking, an action
tools\run-sp-harness.ps1 -Mode vessel-carry -ModSource "$PWD\dist\TheLastGallon\Contents\mods\TheLastGallon"  # the same from the package's item tree (after tools\package.ps1)
tools\run-sp-harness.ps1 -Mode vessel-actions                   # the vessel and a generator through a real loot, the vessel unequipped for a bat
tools\run-sp-harness.ps1 -Mode vessel-gaits                     # the vessel carried walking, running, sprinting, sneaking, running and sprinting crouched, crouched
tools\run-sp-harness.ps1 -Mode pose-crouch                      # crouched carry candidates (harness clips Bob_TLGCrouch*), crouched still, walking, running
tools\run-sp-harness.ps1 -Mode pose-sprint                      # sprint carry candidates (harness clips Bob_TLGSprint*), sprinting the row both ways
tools\run-sp-harness.ps1 -Mode machine-models                   # every item's own floor model beside the fermenter (fog held at 0), the icons, a still held in an action
tools\make-model-icons.ps1                                       # the icons rendered in Blender: four from their models, four from shapes (pz_icon_props.py), into the mod
tools\make-prop-models.ps1                                       # the kit's, starter's, stabilizer's and manual's floor models (FBX and texture) built from the same shapes, into the mod
tools\run-sp-harness.ps1 -Mode manual                           # the field manual: its loot lists, manuals rolled from them, one read through Inspect
tools\run-sp-harness.ps1 -Mode manual-italian                   # the same in a client set to Italian
tools\run-sp-harness.ps1 -Mode crafting                         # the crafting window: the seven recipes found by name, made with Craft or a double-click, one refused; ~5 min
tools\run-sp-harness.ps1 -Mode successor                        # death and a new survivor in the same world: the records, the can, the carried and placed fermenters; ~6 min
tools\run-sp-harness.ps1 -Mode knowledge                        # What I know about it: a kit and a look two game hours apart, the can opened, a litre poured out, an old entry; ~4 min
tools\run-sp-harness.ps1 -Mode knowledge-save                   # the kit sample and the look, saved and exited with the can sealed, the save continued; both must come back as saved
tools\run-sp-harness.ps1 -Mode fires -TimeoutMinutes 60      # a campfire and a barbecue lit from their menus, a fermenter beside each, a trip away
tools\run-sp-harness.ps1 -Mode italian -TimeoutMinutes 20    # the client in Italian: every Italian string, the Fuel and machine menus
tools\run-sp-harness.ps1 -Mode docs-shots                       # the player guide's screenshots: the Fuel, Machine and Workshop menus open, their dialogs, the crafting window; no save; ~1 min
tools\dev-server-controller.ps1       # then connect two clients to 127.0.0.1:16361
tools\run-mp-harness.ps1 -Clients 2   # the TLGDev server and two harness clients on this machine, unattended
tools\run-mp-harness.ps1 -Clients 2 -Restart        # the full run; both clients leave, the server is saved, stopped and started on the same world, both join again
tools\run-mp-harness.ps1 -Clients 2 -Restart -DropVault  # the same, the server store saved without the vault first, as before the V-01 fix
tools\run-mp-harness.ps1 -Clients 2 -NonAdmin       # the same with both accounts plain players
tools\run-mp-harness.ps1 -Clients 2 -Only carry     # the vessel's pickup, its gaits, its put-down and two players taking it at once
tools\run-mp-harness.ps1 -Clients 1 -Only heavy     # vanilla's meteorite taken off the floor; add -NoMod for the same without the mod
tools\run-mp-harness.ps1 -Clients 2 -Only machines  # a running vessel moved by the world menu's Grab, two players loading one vessel, a vessel taken out of a crate
tools\run-mp-harness.ps1 -Clients 1 -Only fuel      # pours, refuelling and siphoning at the Gas2Go pumps, a generator and a car
tools\run-mp-harness.ps1 -Clients 1 -Only conversion  # a generator converted at the workshop, on the shortest day
tools\run-mp-harness.ps1 -Clients 1 -Only carconv   # a car converted, on the shortest day
tools\run-mp-harness.ps1 -Clients 1 -Only stills    # both stills and the drying column, on the shortest day
tools\run-mp-harness.ps1 -Clients 1 -Only audit -NonAdmin  # the security audit's cases (docs/security-audit-2026-11-05.md)
tools\run-mp-harness.ps1 -Clients 2 -Only effects   # poor fuel on a server: a car's power, wear, start gate and stall seen by both clients, a generator's wear; ~15 min
tools\run-mp-harness.ps1 -Clients 1 -Only timers    # the machines' readings and notes on a server beside a campfire, their cost there; ~8 min
tools\run-mp-harness.ps1 -Clients 1 -Only knowledge # What I know about it from a client's Fuel menu, answered by the server; ~5 min
tools\run-mp-harness.ps1 -Clients 1 -Only knowledge -Restart  # the same with the can sealed; the player leaves, the server restarts, the player joins and reads it again
tools\run-mp-harness.ps1 -Clients 2 -Only death     # A dies carrying a running vessel; B asks the server where it fell and whether it works from the death; ~4 min
tools\make-preview.ps1                # the Workshop preview, the mod list's poster and icon (Blender), into art-src and the mod
tools\package.ps1                     # the release zip (never uploads)
tools\rehearse-install.ps1            # that zip installed in a fresh cache and played through a save; ~20 min
tools\rehearse-install.ps1 -Scenario existing   # a save played 10 days without the mod, then with it; ~30 min
tools\rehearse-install.ps1 -Scenario removal    # a save with the mod, continued without it, then with it again
# -Mode existing-a, existing-b and removal-a, -b, -c are the launches the two rehearsals above make; they are not run by hand.
```
