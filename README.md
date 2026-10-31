# The Last Gallon

Project Zomboid **Build 42.21.0** mod: fuel deterioration, alternative fuels,
engine conversions and energy infrastructure. Specification:
`The_Last_Gallon_Implementation_Plan.md`.

Status: development build. Domain layer and authority logic are implemented
and tested on the game's own Lua VM. In a single-player client (2026-10-31)
the fuel adapters, start gates and the ethanol loop are verified through
the player's menus: crafting the machines, a batch of ethanol, then flex
conversions of a generator and a standard car that run on it, also with the
game clock running. Multiplayer is not tested. See
`docs/release-checklist.md` for every open gate.

## Layout

| Path | Contents |
| --- | --- |
| `Contents/mods/TheLastGallon/` | Runtime package (`42/mod.info`, `common/media/...`) |
| `tests/` | Domain tests, fixtures, dev-only in-game harness mod |
| `tools/` | Test runner, dev environment, server controller, packaging |
| `docs/` | Environment, capabilities, decisions, matrices, balance, guides |
| `art-src/` | Editable art sources (none yet) |

## Quick commands (PowerShell, from this folder)

```powershell
tools\run-tests.ps1                                      # domain suite on Kahlua
tools\run-tests.ps1 -Entry tests/support/compile_check.lua
tools\check-translations.ps1
tools\setup-devenv.ps1                                   # deploy to the isolated dev cache
tools\dev-server-controller.ps1                          # isolated dedicated server
tools\run-sp-harness.ps1                                 # automated SP experiments (unlocked desktop, no input, ~12 min)
tools\package.ps1                                        # build dist/ (never uploads)
```

The game does not load mods from `<game>/mods`; never point a fresh cache dir
at this folder (see `docs/environment.md`, incident 2026-10-30).
