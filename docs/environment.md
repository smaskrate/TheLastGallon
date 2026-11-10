# Development environment

The build and tools below were recorded on 2026-10-30. Re-record every field
when the game updates: the package is claimed to work only on the build
listed here.

## Pinned game build

| Item | Value | Source |
| --- | --- | --- |
| Game version | **42.22.2** (42.21.0 until 2026-11-09) | `console.txt` (`version=42.22.2 3d39148846 demo=false`) |
| Revision | `3d39148846` (`4a0e9546ec` for 42.21.0) | same |
| Steam app / depot | 108600 / 108604, manifest `7544133343391543313` | `steamapps/appmanifest_108600.acf` |
| Steam build id | 25485521 | `appmanifest_108600.acf` (`buildid`) |
| Branch | default (no `BetaKey` in the manifest) | `appmanifest_108600.acf` |
reports `42.22.2 3d39148846` at runtime
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
therefore deployed into a separate cache directory, the dev cache:
`%LOCALAPPDATA%\TheLastGallon\devcache`
(= `C:\Users\Manuel\AppData\Local\TheLastGallon\devcache`).

`tools/setup-devenv.ps1` creates the dev cache and deploys into it. It
enforces the rules that come from the
[incident of 2026-10-30](#incident-first-run-mod-folder-copy-2026-10-30)
(D-004):

* it stops if the cache lies inside `<game>/mods`;
* it pre-creates `options.ini`, so the file exists before any launch;
* it mirror-copies (`robocopy /MIR`, never links) the runtime package, the
  harness and `TheLastGallonPreInstall` (the dev driver that plays a save
  without the mod for the existing-save and removal rehearsals) into
  `<devcache>/mods`, and stops if a target folder is a link;
* it writes `mods/default.txt` (client) and `Server/TLGDev.ini` (server).

`setup-devenv.ps1` also creates `mods/reset-mods-42_00.txt` with the game's
own text and rewrites `default.txt` before every launch. Without that
marker the client empties `mods/default.txt` (no mod active); the game
writes the marker on its first launch, and the main menu saves the active
list back on every launch. That is why the first client launch
(2026-10-30 21:33) ran without any mod and the harness never started.

The user's own `%USERPROFILE%\Zomboid` (including the `Apocalypse` saves) is
never read or written by any tool in this repository.

### Incident: first-run mod folder copy (2026-10-30)

The first dev cache lived in the repository, with junctions into the
package. On a cache dir without `options.ini`, `Core.loadOptions()` calls
`initOptionsINI()`, which calls `copyPasteFolders("mods")` and copies
`<game>/mods` into `<cachedir>/mods`. Because this repository lives in
`<game>/mods`, the server copied the repository into the cache and, through
the junction, back into `Contents/mods/TheLastGallon` until Windows path
limits stopped it. Cleanup removed only the copied directories (`.devcache`,
`.git`, `art-src`, `Contents`, `.gitignore` under the package); the original
files were verified unchanged. The rules above, enforced by
`setup-devenv.ps1`, prevent a repeat.

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
* Last run: boot 5 on 2026-10-30 (`test-results.md`), before the mod had
  pose files. The controller passes `<devcache>` as given, not its final
  path; "Client harnesses" below explains why a server needs the mod's real
  path.

## Client harnesses

A single-player client harness (debug scenario with `forceLaunch`) is
described in `engine-capabilities.md` ("Unattended client launches").

`tools/run-mp-harness.ps1` runs the TLGDev dedicated server and its clients
on this computer with no clicks, with one client (A) or two (`-Clients 2`:
A acts, B watches). The setup, as `test-results.md` records it (launches
136–145):

* a fresh world with one spawn point (the harness's open ground at
  10660,10645) and no zombies;
* two test accounts, made admin from the server console (`adduser`,
  `setaccesslevel`);
* each client joins by IP as vanilla's Join by IP popup does and passes
  character creation with the screens' own Next handlers
  (`TLGHarness/MPHarness.lua`);
* a relay on the server (`TLGHarness/MPServer.lua`) carries the harness's
  messages between the clients, and the test items come from the server,
  never from a client.

Each process has its own cache under `%LOCALAPPDATA%\TheLastGallon`
(`mpserver`, `mpclient1`, `mpclient2`), deployed by `tools/setup-devenv.ps1`.
The account passwords stay in `mpserver\dev-credentials.txt`. Results go to
each client's `<cache>\Lua\TLG_harness_mp.txt` and the server's
`mpserver\Lua\TLG_harness_mpserver.txt` (the launcher's header). A server
must reach the mod by its real path: through a junction, or through the
`%LOCALAPPDATA%` that Windows redirects for the Claude app's processes, it
stops before loading any Lua (`engine-capabilities.md`, runs 136–138). The
launcher therefore passes each cache's final path.

A real network is NOT RUN: it needs a second machine (`test-results.md`,
"Not run" list).

## Commands

```powershell
tools\run-tests.ps1                    # domain tests on the game's Kahlua VM
tools\run-tests.ps1 -Filter transfer   # subset
tools\setup-devenv.ps1                 # (re)deploy into the dev cache
tools\dev-server-controller.ps1        # dedicated server (blocks)
tools\stop-dev-server.ps1              # clean stop
tools\package.ps1                      # build dist/ release package
```

`README.md` lists the other commands: the harness launchers, the install
rehearsal, the translation check and the Workshop preview.
