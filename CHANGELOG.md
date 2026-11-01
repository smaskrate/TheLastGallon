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
  that fuel while you are gone anyway. Checked in game: a fire's 6 hours
  of fuel covered half of a 12 hour absence, and the work done over it
  matched the credited temperatures exactly. A batch saved mid-way kept
  all of this through saving, quitting and continuing.
* Crafting and menus, fixed in the client runs: nothing the mod adds could
  be crafted (the recipes lacked the tags the crafting window and the craft
  menu list by); the pot still and the jar recipes gave the pot and jars
  back; "Load mash" from the menu could take up to 130 L of water for a
  small mash (it now takes 5 L per kg of sugar loaded); "Collect ethanol"
  could fill a can that held petrol (it now uses an empty can, or one
  holding only ethanol); the workshop dialog named missing items by their
  ids; the conversion work action was dropped from the game's action queue
  while it kept running (its progress bar is gone; see "Project status").
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
* Migrations with preserved future schemas.

Tested only on Project Zomboid 42.21.0 (4a0e9546ec).
