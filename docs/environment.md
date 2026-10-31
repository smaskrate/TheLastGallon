# Development environment

Recorded 2026-10-30. Re-record every field when the game updates; the package
is only claimed to work on the build listed here.

## Pinned game build

| Item | Value | Source |
| --- | --- | --- |
| Game version | **42.21.0** | `Zomboid/version.txt`, `console.txt` (`version=42.21.0 4a0e9546ec demo=false`) |
| Revision | `4a0e9546ec` | same |
| Steam app / depot | 108600 / 108604, manifest `7544133343391543313` | `steamapps/appmanifest_108600.acf` |
| Steam build id | 25485521 | `appmanifest_108600.acf` (`buildid`) |
| Branch | default (no `BetaKey` in the manifest) | `appmanifest_108600.acf` |
| Dedicated server | Same install (`zombie.network.GameServer` in `projectzomboid.jar`); reports `42.21.0 4a0e9546ec` at runtime | `TLG_harness_server.txt` line `game=` |
| Game JRE | Azul Zulu 25.0.1+8 (`jre64`) | `jre64/release` |
| Class file version | 69 (Java 25) | `javap -v zombie.core.GameVersion` |
| PZBullet | 1.0.0.28 | `version.txt` |
| Lua VM | Kahlua (PZ fork) + `stdlib.lua` from the install dir | `projectzomboid.jar`, `stdlib.lua` |

Install directory: `G:\SteamLibrary\steamapps\common\ProjectZomboid`.

## Tooling

| Tool | Version / path | Use |
| --- | --- | --- |
| JDK | Amazon Corretto 17.0.11 (`javac`, `javap`, `jar`) | Compiles `tools/kahlua-runner` (reflection only, `--release 17`); bytecode inspection |
| Game JRE | `jre64\bin\java.exe` (Java 25) | Runs the Kahlua test runner and the dedicated server |
| Git | `C:\Program Files\Git` | Source control (repository root = this folder) |
| Node.js | `C:\Program Files\nodejs` | Not used |
| Python | Not installed (Microsoft Store stub only) | Not used |
| Standalone Lua | Not installed | Not needed: tests run on the game's own Kahlua VM |

API annotations: no Umbrella checkout was used. The primary API evidence is
`javap` of the installed `projectzomboid.jar` plus the shipped Lua under
`media/lua`. Umbrella revision `13d01f9ee58fa48773553920db56d06f0005e7f8`
(cited by the specification) was **not** fetched; annotations never count as
runtime proof here.

## Repository layout

```text
TheLastGallon/                    git repository (this folder; inside <game>/mods)
  Contents/mods/TheLastGallon/    runtime package (the only thing that ships)
    42/mod.info                   version folder (game picks highest <= 42.21)
    common/media/...              Lua, scripts, translations
  tests/                          domain tests, fixtures, in-game harness mod
    ingame/TheLastGallonHarness/  dev-only harness mod (never packaged)
  tools/                          runner, dev environment, packaging scripts
  docs/                           this documentation set
  art-src/                        editable art sources (never packaged)
```

## Isolated development installation

**The game does not load mods from `<game>/mods`.** `ZomboidFileSystem.getAllModFolders`
scans Workshop stage folders, installed Workshop items and `<cachedir>/mods`
only (bytecode evidence in `engine-capabilities.md`, G01). The repository is
therefore deployed into a separate cache directory:

* Dev cache: `%LOCALAPPDATA%\TheLastGallon\devcache`
  (= `C:\Users\Manuel\AppData\Local\TheLastGallon\devcache`).
* `tools/setup-devenv.ps1` creates it, pre-creates `options.ini`, mirror-copies
  the runtime package and the harness into `<devcache>/mods`, writes
  `mods/default.txt` (client) and `Server/TLGDev.ini` (server).
* The client empties `mods/default.txt` (no mod active) when
  `mods/reset-mods-42_00.txt` is missing; the game writes that marker on its
  first launch and the main menu saves the active list back on every launch.
  The first client launch (2026-10-30 21:33) therefore ran without any mod,
  which is why the harness never started. The setup script now creates the
  marker with the game's own text and rewrites `default.txt` before every
  launch.
* The user's own `%USERPROFILE%\Zomboid` (including the `Apocalypse` saves) is
  never read or written by any tool in this repository.

### Incident: first-run mod folder copy (2026-10-30)

The first dev cache lived in the repository with junctions into the package.
On a cache dir without `options.ini`, `Core.loadOptions()` calls
`initOptionsINI()`, which calls `copyPasteFolders("mods")` and copies
`<game>/mods` into `<cachedir>/mods`. Because this repository lives in
`<game>/mods`, the server copied the repository into the cache and, through the
junction, back into `Contents/mods/TheLastGallon` until Windows path limits
stopped it. Cleanup removed only the copied directories (`.devcache`, `.git`,
`art-src`, `Contents`, `.gitignore` under the package); the original files were
verified unchanged. Mitigations now enforced by `setup-devenv.ps1`: the cache
must be outside `<game>/mods`, `options.ini` is created before any launch, and
deployment uses `robocopy /MIR` instead of links.

## Dedicated server

* Start: `tools/dev-server-controller.ps1` (long-running; keeps the console
  pipe). Arguments mirror `ProjectZomboidServer.bat` plus
  `-nosteam -cachedir=<devcache> -servername TLGDev -ip 127.0.0.1 -port 16361 -udpport 16362`.
* Credentials: generated into `<devcache>/dev-credentials.txt` (not committed).
* Console commands: write lines to `<devcache>/server-control.txt`.
* Stop cleanly: `tools/stop-dev-server.ps1` (sends `quit`; verified to save
  and exit, see `test-results.md`).
* Logs: `<devcache>/server-stdout.txt`, `<devcache>/Logs/`.
* Harness results: `<devcache>/Lua/TLG_harness_server.txt`.

## Client

A single-player client harness (debug scenario with `forceLaunch`) is
described in `engine-capabilities.md`. Two-client multiplayer has **not** been
set up; all MP gates remain NOT RUN until a second client is available.

## Commands

```powershell
tools\run-tests.ps1                    # domain tests on the game's Kahlua VM
tools\run-tests.ps1 -Filter transfer   # subset
tools\setup-devenv.ps1                 # (re)deploy into the dev cache
tools\dev-server-controller.ps1        # dedicated server (blocks)
tools\stop-dev-server.ps1              # clean stop
tools\package.ps1                      # build dist/ release package
```
