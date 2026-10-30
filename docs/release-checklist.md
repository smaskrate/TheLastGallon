# Release checklist

Status legend: DONE · PARTIAL · OPEN · BLOCKED (needs something this
environment does not have). Publication to the Workshop is a separate manual
decision and is **not** authorised by any task in this repository.

## Gates that must pass before any public release

| # | Gate (spec §25) | Status | Evidence / what is missing |
| --- | --- | --- | --- |
| 1 | Every advertised pathway has a playable tested loop | OPEN | Ethanol chain implemented + domain-tested; in-game loop NOT RUN. Other pathways domain-only or in progress |
| 2 | Every supported transfer path preserves fuel state | PARTIAL | Item↔item verified RT-DS; vehicle/pump/generator paths SRC-ONLY (`support-matrix.md`) |
| 3 | Native and mod quantities reconciled | PARTIAL | Reconciliation domain-tested; RT-DS item checks pass; world objects NOT RUN |
| 4 | Production and energy invariants pass | PARTIAL | Production suite passes; energy module pending merge |
| 5 | Multiplayer and dedicated-server tests pass | BLOCKED | DS loads the mod; two-client tests need a second client |
| 6 | Save/load, pickup/placement, unloaded simulation pass | PARTIAL | Global ModData persists across DS restarts; catch-up domain-tested; object/item save/load NOT RUN (SP harness ready, blocked by locked desktop) |
| 7 | Existing and late-world bootstrap scenarios pass | OPEN | Policies domain-tested; campaign runs NOT RUN |
| 8 | Supported chassis and maps documented | PARTIAL | `support-matrix.md`; nothing runtime-verified |
| 9 | Required assets verified and licensed | PARTIAL | Vanilla references only, unverified in game (`asset-audit.csv`); release art (preview.png) missing |
| 10 | English/Italian text and player docs complete | PARTIAL | All shipped keys EN/IT (`check-translations.ps1`); docs for unfinished pathways pending |
| 11 | Performance measured against a baseline | OPEN | No client baseline recorded |
| 12 | Clean install and upgrade pass with the packaged artifact | OPEN | `tools/package.ps1` builds the artifact; install rehearsal NOT RUN |
| 13 | No core behaviour represented only by a placeholder | PARTIAL | Machines use vanilla models as placeholders (functional, documented) |
| 14 | Optional integrations distinguished from shipped scope | DONE | No external integrations claimed |

## Open implementation items

* Adapters, placeable machines and UI for biodiesel, wood gas, biogas,
  propane cylinders and electrical networks (domains merged and tested).
* Automation wiring (rules exist in the domain; no adapter yet).
* "Prepare removal" admin command (`migrations.md`).
* Vehicle start gate (only stall effect implemented).

## Commands for the remaining runtime gates

```powershell
tools\run-sp-harness.ps1              # from an unlocked desktop; ~5-10 min
tools\dev-server-controller.ps1       # then connect two clients to 127.0.0.1:16361
tools\package.ps1                     # artifact for install rehearsal
```
