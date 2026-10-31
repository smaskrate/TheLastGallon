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
  standard car that then run on that ethanol, save and reload).
* Fixes found in the client runs: the per-minute vehicle effects, the
  "pour into vehicle" menu entry and the workshop menu no longer fail on
  42.21 (the cell's vehicle list is a set); generators keep their fuel record
  when dropped by taking another heavy item or by dragging them to the floor;
  a fuel can left on the ground keeps its record after reload (its fluid can
  sit on the ground object); a workshop conversion can now be started (the
  tool check counted no tools until a project existed, so every first
  conversion failed with "a tool is missing").
* Ethanol chain: fermentation vessel, pot/reflux still, drying column, yeast
  starter; EN/IT strings; sandbox options. The drying column can now be used
  ("Dry ethanol with quicklime"); before, it could be built but had no action.
* Migrations with preserved future schemas.

Tested only on Project Zomboid 42.21.0 (4a0e9546ec).
