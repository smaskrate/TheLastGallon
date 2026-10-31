# Release checklist

Status legend: DONE · PARTIAL · OPEN · BLOCKED (needs something this
environment does not have). Publication to the Workshop is a separate manual
decision and is **not** authorised by any task in this repository.

## Gates that must pass before any public release

| # | Gate (spec §25) | Status | Evidence / what is missing |
| --- | --- | --- | --- |
| 1 | Every advertised pathway has a playable tested loop | OPEN | Ethanol chain implemented + domain-tested; in-game production loop NOT RUN. Other pathways domain-only or in progress |
| 2 | Every supported transfer path preserves fuel state | PARTIAL | Verified RT-SP: pump→can, pump→vehicle, can↔vehicle, can→generator, TLG pour into generators and a car (with and without confirmation), generator pickup/drop, end-to-end chain; item↔item RT-DS. Machine outputs and the station-reservoir pour SRC-ONLY (`support-matrix.md`) |
| 3 | Native and mod quantities reconciled | PARTIAL | Verified RT-SP for vehicle idle burn and generator burn; driving burn and third-party paths NOT RUN. Start gates and stall verified RT-SP |
| 4 | Production and energy invariants pass | PARTIAL | Domain invariants pass (138 cases, incl. energy balance, mass balance per converter); no in-game production/energy run |
| 5 | Multiplayer and dedicated-server tests pass | BLOCKED | DS loads the mod; two-client tests need a second client |
| 6 | Save/load, pickup/placement, unloaded simulation pass | PARTIAL | RT-SP: item, ground item, vehicle, generator and pump records survive save/reload; generator pickup/placement on all Lua paths. Unloaded catch-up domain-tested only; chunk unload NOT RUN |
| 7 | Existing and late-world bootstrap scenarios pass | OPEN | Policies domain-tested; campaign runs NOT RUN |
| 8 | Supported chassis and maps documented | PARTIAL | `support-matrix.md`; `Base.CarNormal`, `Base.Generator` and the Muldraugh Gas2Go verified RT-SP; other chassis NOT RUN |
| 9 | Required assets verified and licensed | PARTIAL | Vanilla references only (`asset-audit.csv`); rendering not checked in game; release art (preview.png) missing |
| 10 | English/Italian text and player docs complete | PARTIAL | All shipped keys EN/IT (`check-translations.ps1`); EN resolves in the client (RT-SP), IT not checked in game; docs for unfinished pathways pending |
| 11 | Performance measured against a baseline | OPEN | No client baseline recorded |
| 12 | Clean install and upgrade pass with the packaged artifact | OPEN | `tools/package.ps1` builds the artifact; install rehearsal NOT RUN |
| 13 | No core behaviour represented only by a placeholder | PARTIAL | Machines use vanilla models as placeholders (functional, documented) |
| 14 | Optional integrations distinguished from shipped scope | DONE | No external integrations claimed |

## Open implementation items

* Adapters, placeable machines and UI for biodiesel, wood gas, biogas,
  propane cylinders and electrical networks (domains merged and tested).
* Automation wiring (rules exist in the domain; no adapter yet).
* "Prepare removal" admin command (`migrations.md`).
* Wood-gas and electric vehicle conversions (no shipped definitions).

## Commands for the remaining runtime gates

```powershell
tools\run-sp-harness.ps1              # unlocked desktop, no input needed; ~12 min
tools\dev-server-controller.ps1       # then connect two clients to 127.0.0.1:16361
tools\package.ps1                     # artifact for install rehearsal
```
