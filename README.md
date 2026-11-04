# The Last Gallon

Project Zomboid **Build 42.21.0** mod: fuel that ages and gets
contaminated, engines that feel it, home-made ethanol and flex-fuel
conversions. Specification: `The_Last_Gallon_Implementation_Plan.md`.

Version 0.1.0, the first release (`CHANGELOG.md`). The domain layer and
the authority logic are tested on the game's own Lua VM
(`tools/run-tests.ps1`). In game, automated and unattended, on this
computer: single player through the player's menus (the fuel adapters,
start gates, stalls, poor fuel's effects on engines, the ethanol loop from
crafting the machines to a converted generator and car running on the
ethanol, every recipe made through the crafting window, saves and
reloads), and a dedicated server with two players on this computer (the
same paths, carrying the vessel, the machines' timers). The zip from
`tools/package.ps1` is installed into a fresh game folder and played
(`tools/rehearse-install.ps1`). A real network and the pathways other than
ethanol are not tested; `docs/release-checklist.md` lists every gate and
what is still open. Publishing to the Workshop is a
manual step, not done by any script here.

Licence: CC BY-NC-SA 4.0, except the supplied machine models and the carry
animations (`LICENSE.md`, `NOTICE.md`).

## Layout

| Path | Contents |
| --- | --- |
| `Contents/mods/TheLastGallon/` | Runtime package (`42/mod.info`, poster and icon; `common/media/...`) |
| `tests/` | Domain tests, fixtures, the in-game harness mods (dev only) |
| `tools/` | Test runner, harness launchers, dev environment, art tools, packaging |
| `docs/` | Environment, capabilities, decisions, matrices, balance, guides, test results and evidence |
| `art-src/` | Supplied models as delivered, with their provenance; the Workshop preview |

## Quick commands (PowerShell, from this folder)

```powershell
tools\run-tests.ps1                                      # domain suite on Kahlua
tools\run-tests.ps1 -Entry tests/support/compile_check.lua
tools\check-translations.ps1
tools\setup-devenv.ps1                                   # deploy to the isolated dev cache
tools\run-sp-harness.ps1                                 # single player, unattended (unlocked desktop, no input, ~15 min); -Mode for the other cases
tools\run-mp-harness.ps1 -Clients 2                      # dedicated server and two clients on this computer, unattended; -Only for the other cases
tools\make-preview.ps1                                   # Workshop preview, mod list poster and icon (Blender)
tools\package.ps1                                        # build dist/ (never uploads)
tools\rehearse-install.ps1                               # install the zip in a fresh cache and play it (~20 min)
tools\rehearse-install.ps1 -Scenario existing            # the zip added to a save played without it (~30 min)
```

Every harness mode, with what it covers and how long it takes, is listed
in `docs/release-checklist.md`; the results are in `docs/test-results.md`.

Players install from the zip as `docs/player-guide.md` describes; this
README does not ship in the package.

The game does not load mods from `<game>/mods`; never point a fresh cache dir
at this folder (see `docs/environment.md`, incident 2026-10-30).
