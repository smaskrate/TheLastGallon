# Changelog

## 0.1.0-dev (unreleased)

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
  production machines and workshop conversions, verified in a single-player
  client on 2026-10-31 (refuelling, siphoning, pumps, generator pickup/drop,
  start gates, stalls, the TLG pour, one ethanol batch through fermenter,
  reflux still and drying column, flex conversion of a generator and a
  standard car that then run on that ethanol, save and reload). The machines
  were crafted and run, and the conversions done, through the player's
  menus. A separate run let the game clock run the whole loop (136 game
  hours, the conversion work at the game's x40) and unloaded the machines'
  area for a game day: the fermenter caught up exactly on return.
* Weather: machines and stored fuel now follow the day's real temperature.
  The mod used to record the season curve, so cold snaps and heat waves
  never reached them; outdoors in a freezing January a fermenter now stops
  and, after three days stopped, spoils (checked in game).
* Placement: a machine takes the temperature of where it stands, as the
  game computes it for a character there: outdoors the air, in a room
  between the air and 22 °C (22 °C while the grid is on), warmer by a lit
  fire, fireplace or barbecue. Fires count only while you are nearby.
  Status shows the temperature at the machine. Checked in game in
  January with the grid off: outdoors and in an unheated room the batch
  stopped and spoiled; on a warmed tile it finished, and so did a batch
  two tiles from a house fireplace kept fed with logs (17 logs).
* A fire left burning keeps a machine warm while you are away, for as long
  as its fuel lasts (up to 8 hours with default settings): the game burns
  that fuel while you are gone anyway. This now includes a campfire you
  build yourself, whose reach shrinks as it burns down (it had been left
  out: the game keeps it as a different kind of fire; checked in game). Checked in game: a fire's 6 hours
  of fuel covered half of a 12 hour absence, and the work done over it
  matched the credited temperatures exactly. A batch saved mid-way kept
  all of this through saving, quitting and continuing.
* Moving a working machine: it counts the hours it stood, up to the moment
  you pick it up, and starts again the moment you put it down; carried
  hours never count. Before, a Status read while carrying it lost every
  hour since the machine was last used, and without one the carried hours
  counted (found in game). In multiplayer, where the game's grab is not
  visible to mods, up to ten minutes before a pickup can be lost. Checked
  in game with the world menu's Grab, the loot window, the place action and
  Drop, and with a grab made outside the game's Lua (multiplayer itself not
  checked). Checked on fermenters, both stills and the drying column: a
  still burns no firewood while carried. A carried machine now answers only
  Status: feeding its firebox, collecting from it, Pause, Resume and Abort
  batch say "Place it on the ground first.", as loading already did. The
  menu never offered them while carried, but the server took them, and a
  Resume could make the carried hours count. The refusals were checked in
  game; the counted hours were shown by a test against the old code.
* Crafting and menus, fixed in the client runs: nothing the mod adds could
  be crafted (the recipes lacked the tags the crafting window and the craft
  menu list by); the pot still and the jar recipes gave the pot and jars
  back; "Load mash" from the menu could take up to 130 L of water for a
  small mash (it now takes 5 L per kg of sugar loaded); "Collect ethanol"
  could fill a can that held petrol (it now uses an empty can, or one
  holding only ethanol); the workshop dialog named missing items by their
  ids; the conversion work action was dropped from the game's action queue
  while it kept running (its progress bar is gone; see "Project status");
  a finished machine's Status showed its last stage as current and, on a
  fermenter with wash left after a still was filled, "output waiting,
  nowhere to put it" (it now says the wash is ready for a still and that
  the rest goes in once the still is free; a still or drying column says
  its ethanol is ready to collect; checked in game).
* Abort batch keeps what the batch made so far, to collect (a fermenter's
  wash for a still, a still's spirit, a drying column's ethanol), and its
  message lists what it throws away; before, all of it was lost without a
  word, 4 L of ethanol in a drying column included (found in game). A
  spoiled batch can now be emptied with Abort batch (the fermenter used to
  stay spoiled for good), Pause, Resume and Abort batch are offered only
  where they apply, and refusals read as sentences instead of codes.
  Checked in game, a pot still taking a stopped fermenter's wash included.
  What a batch made now counts only the stages that make it. A still
  aborted while it heats up keeps nothing (its wash is thrown away), and
  one aborted while distilling keeps only the spirit distilled so far. It
  used to count the heat-up hour too, and kept 1.61 L where 1.10 L had
  distilled (found in game). A fermenter's hour of preparing likewise
  makes no ethanol.
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
* Fixes found in the client runs: the per-minute vehicle effects, the
  "pour into vehicle" menu entry and the workshop menu no longer fail on
  42.21 (the cell's vehicle list is a set); generators keep their fuel record
  when dropped by taking another heavy item or by dragging them to the floor;
  a fuel can left on the ground keeps its record after reload (its fluid can
  sit on the ground object); a workshop conversion can now be started (the
  tool check counted no tools until a project existed, so every first
  conversion failed with "a tool is missing").
* Workshop conversions: "Work on it" is now a timed action at the vehicle or
  generator. The character works there until the conversion is finished or
  something is missing; walking away stops the work and time away is not
  counted (a late report credits at most 1 h). The "Report progress" and
  "Stop working" entries are gone (EN/IT). Checked in game from the menu,
  including the walk to the engine, the character moved out of reach and the
  work ending on a missing tool.
* Ethanol chain: fermentation vessel, pot/reflux still, drying column, yeast
  starter; EN/IT strings; sandbox options. The drying column can now be used
  ("Dry ethanol with quicklime"); before, it could be built but had no action.
  The pot still was checked in game with a batch larger than it holds (two
  loads of wash), its firebox running out and fed again, and the yeast
  starter coming with the last of the wash; its spirit (80 %) was unfit for
  any engine by the mod's start check until dried, then fit for flex
  engines.
* The fermentation vessel stands on the floor as its own model: a wooden
  barrel with a lid, an airlock and a tap, about 0.75 m tall, and has an
  icon to match. Checked in game: put down turned four ways, saved and
  continued; the icon shows in the equipped-item button.
* A generator you carry keeps its fuel's record and its conversion when
  the game puts it down for you, as it does when you take another
  generator or equip a weapon from the menus (the record checked in
  game, the conversion by the tests). Before, the fuel lost its history
  and a converted generator was stock again.
* The fermentation vessel is carried in both hands, like the game's
  generators, anvils and ore: one at a time, and it goes down at your
  feet when you get into a vehicle, take another heavy item or equip a
  weapon. Take it by double-clicking or dragging it in the loot window. The hours it is
  carried still don't count (checked in game). The game leaves a heavy
  item standing where it was when taken that way in single player; the
  mod lifts its own vessel properly.
* You see the fermentation vessel in your arms while you carry it: held
  in front of you in both arms, standing and walking (checked in game).
  The game draws no carried heavy item, so the mod has its own carry
  pose, made from a Mixamo animation. Starting anything that plays its
  own animation (looting, eating, dressing, reading, the mod's conversion
  work) first puts the vessel down at your feet. A generator, which is
  never seen in your hands, stays there through such actions (both
  checked in game, looting from a bag on the floor).
* The four machines' inventory category reads "Tool"; it showed the raw
  key "IGUI_ItemCat_Tools" (found and checked in game).
* Migrations with preserved future schemas.
* What I know about it remembers a first Look and smell on fuel the mod
  had not recorded yet; it used to say "unknown" right after the look.
  That first look also fixes the fuel's starting condition on a save that
  gains the mod (checked in game).
* Package: the zip now unpacks the same on every system (its folder
  names used Windows backslashes), and the player guide says how to
  install it. Installed from the zip into a fresh game folder, the mod
  was played through a save and a reload (checked in game).

Tested only on Project Zomboid 42.21.0 (4a0e9546ec).
