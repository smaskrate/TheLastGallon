# Changelog

## 0.3.0 (not released)

* Wrong fuel damages engines. Diesel or biodiesel in a petrol or converted
  (flex) engine, petrol or ethanol in a diesel, and ethanol past a stock
  petrol engine's limit no longer just stop the engine from starting. The
  more of the wrong fuel is in the tank, the worse the engine starts and
  runs and the faster it wears; with enough of it some engines do not
  start at all, and each try then costs engine condition. Unburned diesel
  wears a car's exhaust, and a diesel running on mostly petrol or ethanol
  can fail outright. `docs/player-guide.md`, "Wrong fuel", has every row
  and its numbers. The order of harm follows real engines: petrol or
  ethanol in a diesel is the worst case.
* A line over the character says when a start damaged the engine, when an
  engine failed, and when an engine starts on fuel that harms it.
* **Pour into this vehicle's tank** and **Pour into the generator** refuse
  a pour that would harm the engine until confirmed. The game's own **Add
  Fuel** and pumps do not check.
* New sandbox option **Wrong fuel damages engines**, on by default. Off,
  such fuel only stops the engine from starting, as in 0.2.0.
* A save from 0.2.0 changes behaviour: an engine that refused to start on
  such a blend now starts, or tries to, and is damaged. Siphon or drain
  the tank first.
* The Field Manual's two lines on ethanol in stock engines say so.

## 0.2.0 (2026-11-11)

* Biodiesel. Five new machines turn wood and cooking oil into biodiesel:
  the Wood Retort (methanol), the Ash Barrel and the Lye Leacher (lye), the
  Biodiesel Reactor and the Biodiesel Wash Tank. Each is crafted, placed on
  the ground and loaded from its menu; a machine takes what it needs from
  the finished machine beside it, and the wash tank fills a fuel can. Their
  models were supplied for the mod. `docs/player-guide.md` has the steps
  and the amounts.
* The Diesel Generator, found in loot beside the game's generators (the
  green one). It burns diesel and biodiesel in any blend.
* In worlds started with this version, pickup vans (Dash Bulldriver),
  six-seat vans, radio vans and ambulances are diesel, and about one
  station pump in four gives diesel. **Read what this pump gives**, in a
  pump's menu, says which. Worlds started earlier keep every vehicle and
  pump on petrol.
* The diesel generator's sprite and icon are the game's red generator
  recoloured; `LICENSE.md` and `NOTICE.md` say so.
* Fixed: a generator whose fuel the mod had recorded counted as a station
  pump, so the Fuel menu near it could offer the pump's entries. Version
  0.1.2 has the same fault. Found by launch 255; no pump entry was chosen
  on a generator in game.
* A save made with 0.1.2 continues with this version: its fuel records,
  its vehicles and its pumps stay as they were, all on petrol (launch 257).
* Checked in game on 42.22.2, in single player and on a dedicated server
  (launches 229–259 in `docs/test-results.md`). Not checked: driving on
  diesel or biodiesel, and biodiesel in the cold.

## 0.1.2 (2026-11-10)

* Tested on Project Zomboid 42.22.2 (`3d39148846`), which replaced 42.21.0
  on 2026-11-09. Nothing in the mod's behaviour changed; it no longer
  warns of an untested game version on this build.

## 0.1.1 (2026-11-08)

* Fuel menus now find fluids held by placed items, including red petrol
  cans, bottles and buckets. Right-clicking their world model or floor
  inventory entry offers the same fuel menu. Nearby placed containers and
  containers inside furniture can be inspected and treated by item ID.
  Other fluid containers show the menu when they contain fuel, including
  fixed world containers. Engine pours pick up the vessel first.
* Added the machine context menu when right-clicking placed 3D machines or
  their floor tile. Machines sharing a tile have separate, named submenus.
  Verified all four machine types through the floor inventory's own menu
  builder, both as individual items and grouped entries.

## 0.1.0 (2026-11-04)

* First release. The mod is licensed under CC BY-NC-SA 4.0, except the
  five supplied machine models and the carry animations, which ship only
  as part of the mod (`LICENSE.md`).
* The game's mod list shows the mod's poster, its icon (the fermentation
  vessel's) and its category.
* **What I know about it** lists each test done on the fuel, the more
  precise first: the latest kit sample and the latest look, each with how
  long ago it was done and what it found. It says if, since a test, fuel
  was poured in or out or treated, or the container was opened or closed.
  When the container is open, it also says that the actual condition may
  differ. Before, it showed only the last result, so a look replaced what
  a kit had found, and the guide's "results go stale when the fuel
  changes" was never shown. In multiplayer it always said "unknown": the
  server kept what the player had learned, but the menu read the client's
  own copy, which never had it. Checked in game, in single player and on a
  server.
* A fermentation vessel carried when the character dies now falls at the
  body's feet with its batch going on, in single player and on a server.
  Before, the batch waited until someone opened the vessel's menu, losing
  the time in between. A server tells the mod nothing about a player's
  death, so there the mod watches the vessel leave the player's hands
  instead. That also covers a vessel dropped when climbing (not checked
  in game). Checked in game, in single player and on a server.
* Fuel poured with the game's **Transfer Liquid** window keeps its water
  and sediment. Before, the window's small slices (about 0.02 L each) lost
  them when the fuel held less than about 1 % of either: the target got
  petrol in their place, so a pour cleaned the fuel without the filter or
  the drain. The mod now follows each pour once, when it ends or is
  stopped. Checked in game, in single player, with a pour stopped
  part-way too.
* The crafting window and the craft menu name the mod's recipes ("Make
  Fermentation Vessel", in Italian "Crea recipiente di fermentazione").
  Before, they showed their internal ids, such as "TLG_MakeFermenterVessel",
  so searching for a machine by its name found nothing. Checked in game:
  all seven recipes found by name in the crafting window and made with its
  **Craft** button or a double-click (in English), and the Italian names
  as the game reads them.
* Fuel identity, ageing (chemical condition) and contamination (water,
  sediment, microbial) with storage, sealing, stabilizer and climate effects.
* Inspection with method precision, hysteresis and "unknown" state; filter,
  drain water, stabilize, seal/open, clean.
* Consumer profiles separating compatibility, condition and energy.
* World fuel history with new-world and existing-save policies. Station
  tanks start mostly clean (0–0.15 % water); about one station in ten is
  contaminated (0.2–0.4 %), enough to make stock cars hard to start.
* Server-authoritative commands with idempotent retries and revisions.
* Adapters: item/object fluid containers, vehicles, generators, stations,
  production machines and workshop conversions. Verified in a single-player
  client on 2026-10-31: refuelling, siphoning, pumps, generator
  pickup/drop, start gates, stalls, the TLG pour, one ethanol batch through
  fermenter, reflux still and drying column, flex conversion of a generator
  and a standard car that then run on that ethanol, save and reload. The
  machines were crafted and run, and the conversions done, through the
  player's menus. A separate run let the game clock run the whole loop (136
  game hours, the conversion work at the game's x40) and unloaded the
  machines' area for a game day: the fermenter caught up exactly on return.
* Driving, checked in game (2026-11-04): a car burns its fuel at the
  game's own rate on the road and the mod takes nothing extra; the tank's
  record follows what was burned and keeps its blend (E10 driven 350
  tiles). On fuel the engine cannot take, it stalls while driving and the
  car rolls to a stop.
* Poor fuel now costs a car power and wears engines, as the player guide
  said it would; before, the mod worked both out and applied neither. A car
  on stale, wet or dirty fuel has less power while its engine runs (never
  below half) and picks up speed more slowly; its own power comes back once
  it stops or the fuel is good. Stale or dirty fuel wears car and generator
  engines a little for every litre burned on it; a generator's wear is
  counted when it is next refuelled, moved or switched. Turned off, the
  sandbox option **Bad fuel can stall engines** now also keeps a running
  car from stalling; before, it only stopped refused starts. Checked in
  game.
* Shorter pauses with many machines. Fermenters and stills beside a fire,
  or left running for days without being opened, made the game stop for
  a moment every ten game minutes and every hour. With 32 such fermenters
  the pause was 0.09 to 0.2 seconds; it is now 0.007 to 0.018 seconds.
  Opening the menu of a machine left alone for 20 days took 0.06 seconds;
  it now takes 0.005. The results are the same. Measured on a fast
  desktop; a slower one takes proportionally longer.
* Weather: machines and stored fuel now follow the day's real temperature.
  The mod used to record the season curve, so cold snaps and heat waves
  never reached them; outdoors in a freezing January a fermenter now stops
  and, after three days stopped, spoils (checked in game).
* Placement: a machine takes the temperature of where it stands, as the
  game computes it for a character there: outdoors the air, in a room
  between the air and 22 °C (22 °C while the grid is on), warmer by a lit
  fire, fireplace or barbecue. Fires count only while you are nearby.
  **Status** shows the temperature at the machine. Checked in game in
  January with the grid off: outdoors and in an unheated room the batch
  stopped and spoiled; on a warmed tile it finished, and so did a batch
  two tiles from a house fireplace kept fed with logs (17 logs).
* A fire left burning keeps a machine warm while you are away, for as long
  as its fuel lasts (up to 8 hours with default settings): the game burns
  that fuel while you are gone anyway. This now includes a campfire you
  build yourself, whose reach shrinks as it burns down (checked in game);
  it had been left out because the game keeps it as a different kind of
  fire. Checked in game: a fire's 6 hours of fuel covered half of a
  12-hour absence, and the work done over it matched the credited
  temperatures exactly. A batch saved mid-way kept all of this through
  saving, quitting and continuing.
* Moving a working machine: it counts the hours it stood, up to the moment
  you pick it up, and starts again the moment you put it down; carried
  hours never count. Before, a **Status** read while carrying it lost every
  hour since the machine was last used, and without one the carried hours
  counted (found in game). In multiplayer, where the game's grab is not
  visible to mods, up to ten minutes before a pickup can be lost. Checked
  in game with the world menu's **Grab**, the loot window, the place action
  and **Drop**, and with a grab made outside the game's Lua (multiplayer
  itself not checked). Checked on fermenters, both stills and the drying
  column: a still burns no firewood while carried. A carried machine now
  answers only **Status**: feeding its firebox, collecting from it,
  **Pause**, **Resume** and **Abort batch** say "Place it on the ground
  first.", as loading already did. The menu never offered them while
  carried, but the server took them, and a **Resume** could make the
  carried hours count. The refusals were checked in game; the counted
  hours were shown by a test against the old code.
* Crafting and menus, fixed in the client runs. Nothing the mod adds could
  be crafted: the recipes lacked the tags the crafting window and the craft
  menu list by. The pot still and the jar recipes gave the pot and jars
  back. **Load mash and start fermenting** could take up to 130 L of water
  for a small mash; it now takes 5 L per kg of sugar loaded.
  **Collect ethanol into a fuel can** could fill a can that held petrol; it
  now uses an empty can, or one holding only ethanol. The workshop dialog named
  missing items by their ids. The conversion work action was dropped from
  the game's action queue while it kept running (its progress bar is gone;
  see **Project status**). A finished machine's **Status** showed its last
  stage as current and, on a fermenter with wash left after a still was
  filled, "output waiting, nowhere to put it". It now says the wash is
  ready for a still and that the rest goes in once the still is free; a
  still or drying column says its ethanol is ready to collect (checked in
  game).
* **Abort batch** keeps what the batch made so far, to collect (a
  fermenter's wash for a still, a still's spirit, a drying column's
  ethanol), and its message lists what it throws away. Before, all of it
  was lost without a word, 4 L of ethanol in a drying column included
  (found in game). A spoiled batch can now be emptied with **Abort batch**;
  the fermenter used to stay spoiled for good. **Pause**, **Resume** and
  **Abort batch** are offered only where they apply, and refusals read as
  sentences instead of codes. Checked in game, a pot still taking a
  stopped fermenter's wash included. What a batch made now counts only the
  stages that make it. A still aborted while it heats up keeps nothing
  (its wash is thrown away), and one aborted while distilling keeps only
  the spirit distilled so far. It used to count the heat-up hour too, and
  kept 1.61 L where 1.10 L had distilled (found in game). A fermenter's
  hour of preparing likewise makes no ethanol.
* Fuel that got into a can, tank, generator or pump without the mod seeing
  it (another mod, an action the mod does not follow, or while the mod was
  removed) now joins at the condition of fuel of unknown origin at the
  moment it is found. It used to be aged again over all the time since the
  container was last recorded: a can topped up while the mod was away for
  a game day read 11.5 % more degraded (found in game).
* The water stored fuel takes up while it ages (faster in an opened
  container, and in ethanol most of all) now stays in the can: it is kept
  in the can's fluids and goes with the fuel when poured. It used to be
  lost whenever the can was poured from or into with the game's own
  pouring, filled by siphoning or at a pump, or first looked at. A full
  can now takes it too: the game refuses a new fluid in a container
  within 0.001 L of full, which could also drop a clean station's last
  trace of water from a can filled to the brim.
* Fixes found in the client runs. The per-minute vehicle effects, the
  "pour into vehicle" menu entry and the workshop menu no longer fail on
  42.21 (the cell's vehicle list is a set). Generators keep their fuel
  record when dropped by taking another heavy item or by dragging them to
  the floor. A fuel can left on the ground keeps its record after reload
  (its fluid can sit on the ground object). A workshop conversion can now
  be started: the tool check counted no tools until a project existed, so
  every first conversion failed with "a tool is missing".
* Workshop conversions: **Work on it** is now a timed action at the
  vehicle or generator. The character works there until the conversion is
  finished or something is missing; walking away stops the work and time
  away is not counted (a late report credits at most 1 h). The
  **Report progress** and **Stop working** entries are gone (EN/IT).
  Checked in game from the menu, including the walk to the engine, the
  character moved out of reach and the work ending on a missing tool.
* Ethanol chain: fermentation vessel, pot/reflux still, drying column, yeast
  starter; EN/IT strings; sandbox options. The drying column can now be
  used (**Dry ethanol with quicklime**); before, it could be built but had
  no action. The pot still was checked in game with a batch larger than it
  holds (two loads of wash), its firebox running out and fed again, and
  the yeast starter coming with the last of the wash. Its spirit (80 %)
  was unfit for any engine by the mod's start check until dried, then fit
  for flex engines.
* The fermentation vessel stands on the floor as its own model: a wooden
  barrel with a lid, an airlock and a tap, about 0.75 m tall, and has an
  icon to match. Checked in game: put down turned four ways, saved and
  continued; the icon shows in the equipped-item button.
* The pot still, the reflux still, the drying column and the fuel filter
  stand on the floor as their own models too, sized to what they hold:
  the pot still a pot with a swan neck and a hose, about 1 m wide; the
  reflux still a boiler under its column, about 1.35 m tall; the drying
  column a pipe column in its receiver jar, about 0.8 m tall; the filter a
  small canister. Before, both stills were a cooking pot and the drying
  column a car's fuel tank. A still in your hand is no longer drawn as a
  cooking pot during an action; nothing is drawn there, as for a carried
  generator. Each also has its own inventory icon, rendered from its
  model, so the two stills, and the filter and the drying column, no
  longer share one. Checked in game.
* The sampling kit, the yeast starter, the fuel stabilizer and the field
  manual have their own inventory icons too, so no two of the mod's items
  share one: three small jars of fuel with a hose, a jar of culture under
  a tied cloth, a corked bottle of tar, and an olive field manual. Before,
  the kit and the starter were both a glass jar, the stabilizer a bleach
  bottle and the manual a smithing magazine. Checked in game.
* The same four now lie on the floor as their own models, made from the
  shapes of their icons at true size: the kit's three sample jars with
  the hose coiled in front (0.34 m across), the starter's jar under its
  tied cloth (0.16 m tall), the stabilizer's corked bottle (0.17 m tall)
  and the manual on its back (0.24 m long). Before, none of the four had
  a floor model, so every item of the mod now has its own. Checked in
  game.
* A generator you carry keeps its fuel's record and its conversion when
  the game puts it down for you, as it does when you take another
  generator or equip a weapon from the menus (the record checked in
  game, the conversion by the tests). Before, the fuel lost its history
  and a converted generator was stock again.
* The fermentation vessel is carried in both hands, like the game's
  generators, anvils and ore: one at a time, and it goes down at your
  feet when you get into a vehicle, take another heavy item or equip a
  weapon. Take it by double-clicking or dragging it in the loot window.
  The hours it is carried still don't count (checked in game). The game
  leaves a heavy item standing where it was when taken that way in single
  player; the mod lifts its own vessel properly.
* You see the fermentation vessel in your arms while you carry it: held
  in front of you in both arms, standing, walking and running, and
  upright in your arms when you sprint, crouched or not, and when you
  crouch, still or moving (all checked in game). The game draws no carried
  heavy item, so the mod has its own carry pose, made from a Mixamo
  animation. Starting anything that plays its own animation (looting,
  eating, dressing, reading, the mod's conversion work) first puts the
  vessel down at your feet. A generator, which is never seen in your
  hands, stays there through such actions (both checked in game, looting
  from a bag on the floor).
* The *Field Manual: Fuel Systems* can now be found and read. It turns up
  in gas station storage, garages, farms, generator crates, bookstores,
  tool stores and libraries. **Inspect** shows a page on starting the
  ethanol loop, fuel compatibility and troubleshooting, in English and
  Italian (checked in game). Before, nothing spawned it and reading it did
  nothing. It teaches no recipe.
* The four machines' inventory category reads "Tool"; it showed the raw
  key "IGUI_ItemCat_Tools" (found and checked in game).
* Multiplayer fix: with the mod on a server, the game's own refuelling
  did nothing. Filling a can at a pump, pumping into a car, pouring a can
  into a car or a generator, and siphoning played their animation but
  moved no fuel: the mod's hooks hid each action's details from the
  server. They work now, each keeping its fuel's record (checked on a
  server). The mod's own pour now tells the player its result in
  multiplayer too: a refused fuel shows its message and the offer to pour
  it anyway, as in single player.
* Multiplayer, checked on a dedicated server with two players (both on
  one computer): the fuel commands, a machine's status, the manual found
  in the server's loot, the small items on the floor for both players and
  after a rejoin, and the vessel's carry pose seen by the other player.
  Also: players without admin rights; two players loading one fermenter
  at once (one gets it, the other keeps their ingredients); a running
  fermenter taken with the world menu's **Grab** (its batch pauses the
  next time anyone looks at it); refuelling and siphoning at the pumps,
  generators started or refused by their fuel, a car started and idling;
  a generator and a car converted to flex fuel and run on ethanol; both
  stills and the drying column from wash to dried ethanol; the vessel
  taken out of a container; and a server restart, with the floor and the
  records kept. A real network was not tried. The game itself (42.21)
  cannot take a heavy item off the floor on a server. For the
  fermentation vessel the mod now does it on the server, so players lift
  it from the floor through the loot window as in single player, its
  batch paused while carried. When two players take it at once, one gets
  it and the other's action is refused. The game's own heavy items, such
  as the meteorite, still cannot be lifted there. A server must not reach
  the mod's folder through a junction. See the support matrix.
* Migrations with preserved future schemas.
* **What I know about it** remembers a first **Look and smell** on fuel the
  mod had not recorded yet; it used to say "unknown" right after the look.
  That first look also fixes the fuel's starting condition on a save that
  gains the mod (checked in game).
* Package: the zip now unpacks the same on every system (its folder
  names used Windows backslashes), and the player guide says how to
  install it. Installed from the zip into a fresh game folder, the mod
  was played through a save and a reload (checked in game).

Tested only on Project Zomboid 42.21.0 (4a0e9546ec).
