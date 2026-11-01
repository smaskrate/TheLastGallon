# Release checklist

Status legend: DONE · PARTIAL · OPEN · BLOCKED (needs something this
environment does not have). Publication to the Workshop is a separate manual
decision and is **not** authorised by any task in this repository.

## Gates that must pass before any public release

| # | Gate (spec §25) | Status | Evidence / what is missing |
| --- | --- | --- | --- |
| 1 | Every advertised pathway has a playable tested loop | PARTIAL | Ethanol (the only advertised pathway) verified RT-SP through the player's path (run 12): the four machines crafted from the inventory craft menu, a whole batch run from the machine menu (fermenter → reflux still → drying column → cans), a `Base.Generator` and a `Base.CarNormal` converted from the workshop menu and run on the ethanol; everything survives reload. The same loop also ran on the game clock (runs 13–14: 136 game hours, conversion work at vanilla x40), and a January fermentation slowed (run 15) and, with weather, stopped and spoiled as specified (run 16). By site (D-021, runs 17–19, grid off): outdoors and in an unheated room the January batch stopped and spoiled, on a tile warmed by a heat source it finished; readings, day temperatures and work matched the game exactly. Beside a map fireplace kept fed with logs (run 21) the January batch finished, the heat formula matching every tile and hour; the fire was lit and fed with the calls its actions make, not through its menu. With D-022 (run 23) the fire's noted fuel covered the hours away it lasted, the work over the trip exact. Distilling in the pot still, the crafting window itself and a fire or barbecue beside a machine NOT RUN. Other pathways are domain-only and not advertised |
| 2 | Every supported transfer path preserves fuel state | PARTIAL | Verified RT-SP: pump→can, pump→vehicle, can↔vehicle, can→generator, TLG pour into generators and a car (with and without confirmation), generator pickup/drop, end-to-end chain, still→can, can→drying column→can; item↔item RT-DS. Station-reservoir pour SRC-ONLY (`support-matrix.md`) |
| 3 | Native and mod quantities reconciled | PARTIAL | Verified RT-SP for vehicle idle burn and generator burn; driving burn and third-party paths NOT RUN. Start gates and stall verified RT-SP |
| 4 | Production and energy invariants pass | PARTIAL | Domain invariants pass (142 cases, incl. energy balance, mass balance per converter); one in-game ethanol batch matched the model (runs 7–9); no in-game energy run |
| 5 | Multiplayer and dedicated-server tests pass | BLOCKED | DS loads the mod; two-client tests need a second client |
| 6 | Save/load, pickup/placement, unloaded simulation pass | PARTIAL | RT-SP: item, ground item, vehicle, generator, pump and machine records and conversion projects survive save/reload; generator pickup/placement on all Lua paths; a fermenter whose chunk was unloaded for 24 game hours caught up exactly (RT-SP runs 13–14); machine sites and hourly readings (D-021) survived a chunk unload and the readings resumed (runs 17–19, 21); a fermenter mid-batch beside a fireplace survived save, exit to menu and continue with its site, readings, fire notes ("no fire" notes included), batch and place in the hourly list unchanged, then finished (run 25). Running fermenters picked up (world menu Grab, loot window Grab) and put down (place action, Drop) kept their records, offered only Status while carried and were read hourly again after the next Status (run 26), but the work around a move FAILS D-015: a Status while carried drops the hours placed since the last use, the first Status after putting down drops the hours since, and without a Status while carried the carried hours count (3 FAIL). Stills and drying column picked up NOT RUN |
| 7 | Existing and late-world bootstrap scenarios pass | OPEN | Policies domain-tested; campaign runs NOT RUN |
| 8 | Supported chassis and maps documented | PARTIAL | `support-matrix.md`; `Base.CarNormal`, `Base.Generator` (stock and flex-converted) and the Muldraugh Gas2Go verified RT-SP; other chassis NOT RUN |
| 9 | Required assets verified and licensed | PARTIAL | Vanilla references only (`asset-audit.csv`); rendering not checked in game; release art (preview.png) missing |
| 10 | English/Italian text and player docs complete | PARTIAL | All shipped keys EN/IT (`check-translations.ps1`); EN resolves in the client (RT-SP), IT not checked in game; docs for unfinished pathways pending |
| 11 | Performance measured against a baseline | OPEN | No client baseline recorded |
| 12 | Clean install and upgrade pass with the packaged artifact | OPEN | `tools/package.ps1` builds the artifact; install rehearsal NOT RUN |
| 13 | No core behaviour represented only by a placeholder | PARTIAL | Machines use vanilla models as placeholders (functional, documented) |
| 14 | Optional integrations distinguished from shipped scope | DONE | No external integrations claimed |

## Open implementation items

* Machine pickup: count exactly the hours a moved machine stood placed
  (D-015; run 26 failed it, gate 6).
* Adapters, placeable machines and UI for biodiesel, wood gas, biogas,
  propane cylinders and electrical networks (domains merged and tested).
* Automation wiring (rules exist in the domain; no adapter yet).
* "Prepare removal" admin command (`migrations.md`).
* Wood-gas and electric vehicle conversions (no shipped definitions).

## Commands for the remaining runtime gates

```powershell
tools\run-sp-harness.ps1              # unlocked desktop, no input needed; ~15 min
tools\run-sp-harness.ps1 -Mode realtime -TimeoutMinutes 60   # ethanol loop on the game clock; ~7 min
tools\run-sp-harness.ps1 -Mode winter -TimeoutMinutes 60     # three fermenters by site from 15 January, grid off
tools\run-sp-harness.ps1 -Mode fireplace -TimeoutMinutes 60  # one beside a map fireplace fed with logs, same January
tools\run-sp-harness.ps1 -Mode fireplace-reload -TimeoutMinutes 60  # the same saved mid-batch, continued, finished
tools\run-sp-harness.ps1 -Mode pickup -TimeoutMinutes 30     # two of three running fermenters picked up and put down
tools\dev-server-controller.ps1       # then connect two clients to 127.0.0.1:16361
tools\package.ps1                     # artifact for install rehearsal
```
