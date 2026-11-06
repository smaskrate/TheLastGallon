<#
.SYNOPSIS
  Runs the automated single-player harness (phase A + reload + phase B).
.DESCRIPTION
  Deploys into the isolated dev cache, writes the harness request "sp-a" and
  starts the client in debug mode (-debug -nosteam -nosound -cachedir=...).
  The harness mod force-launches its debug scenario, runs the experiments,
  exits to the menu, continues the save, verifies persistence and quits.
  A watchdog kills the client if it has not finished in time.
  A game window opens for several minutes; do not interact with it.
.PARAMETER TimeoutMinutes
  Watchdog limit (default 30; phase A alone took 10 minutes on 2026-10-31).
.PARAMETER Mode
  full (default): phase A, save, reload, phase B. realtime: only the ethanol
  loop with time passing on the game clock (no reload); took 7 minutes on
  2026-10-31 (pass -TimeoutMinutes 60 for headroom). winter: three
  fermenters on the game clock from 15 January with the grid off,
  outdoors, in a room and on a tile warmed by a heat source (D-021).
  fireplace: the same January world; finds a fireplace of the map, checks
  the air around it against the heat formula and runs one fermentation
  beside it while tending the fire with logs. fireplace-reload: the same
  batch saved mid-way (the fire left to burn out first), exited to the
  menu and continued: the records must survive, then the batch runs on.
  pickup: summer with the grid on; three of four running fermenters are
  picked up (world menu Grab, loot window Grab, and the grab's own calls
  where no Lua sees them, as in multiplayer), carried, put down again
  (place action, inventory Drop) and read against the fourth. The fourth
  is then taken into both hands as a double-click in the loot window takes
  a heavy item (the vessel is one), carried an hour and dropped by
  forceDropHeavyItems; taken again, carried half an hour and put down by
  taking a meteorite the same way (the menus unequip the hands first).
  pot-still: summer with the grid on; a 66.6 L wash through the 60 L pot
  still in two runs (the firebox left to run out once), collected into one
  can, dried with quicklime and evaluated against the engine profiles.
  controls: summer with the grid on; Pause, Resume and Abort batch from the
  machine menu on three fermenters and a drying column, one left paused
  until it spoils.
  still-pickup: summer with the grid on; a pot still and a reflux still
  distilling real wash and a drying column drying are picked up mid-batch
  (world menu Grab, loot window Grab, and the grab's own calls where no Lua
  sees them), carried two game hours and put down again (place action,
  inventory Drop); each must finish with the definitions' hours, fuel and
  spirit, nothing counted while carried.
  still-save: the same, saved and exited to the menu an hour after the
  pickups with the three machines carried; the save is continued, their
  records must come back exactly as saved, and the run goes on to the
  put-downs.
  still-controls: summer with the grid on; a pot still paused from the
  menu while heating up, held three game hours and resumed, and a reflux
  still aborted an hour into distilling, what it kept collected.
  late-find: a new world; a can of petrol recorded at the start, another
  and the nearest pump left alone for 7 game days, then found: both must
  hold the world-age condition, and the early can must have aged alike.
  can-water: a new world; an opened can of the mod's ethanol poured from
  60 days on (the mod's clock), and a petrol can looked at then: the water
  aging gave each must be in its fluids, kept by the next read, and carried
  by a further pour in proportion.
  chassis: phase A's vehicle steps on Base.PickUpTruck instead of the
  standard car: pump, can and siphon hops, pump to tank, a blend idled,
  the mod's own pours, the start gate and the stall.
  driving: fuel burned on the move, on a world with no zombies, parked
  cars or vehicle stories. A standard car takes E10 from a can and drives
  itself down the cleared main road south of Muldraugh on the game's cruise
  control (25 km/h, up to 350 tiles), braking before anything in its lane;
  the tank's drop must be vanilla's burn alone and the mod's record must
  follow it in proportion, with no part damaged. A second car on a blend no
  stock engine takes must stall on the move and coast to a stop.
  engine-effects: the same road and guards (D-031). A car on petrol whose
  record is aged in place must run at its power times the fuel's power
  factor while it runs, quality and loudness kept, and get its power back
  when it stops; its engine must lose the condition its litres burned owe
  (at 100 times the rate, a fixture). With "Bad fuel can stall engines" off,
  a car on a blend no stock engine takes must run at half power without
  stalling. A generator on aged petrol run 6 game hours must be charged its
  wear by the next refuel, once.
  performance: release gate 11, on the same road (docs/performance.md). The
  mod's three timers (each game minute, ten minutes and hour) are timed as
  they run while workloads are added: 400 petrol cans with records, 10 and
  20 parked cars, 8 of them idling on stale petrol, 8 and 32 running
  fermenters loaded from the menu, the 32 as if a fire warmed each, and
  with 20 days of hourly readings. Also timed: fuel and a batch brought
  forward 1, 30 and 365 days, and the fuel and machine menus; frames are
  sampled for 20 seconds at each stage. Budgets set in RT.PF.budgets are
  checked.
  model-import: the original test model of tools/make-test-model.ps1 wired
  to the fermenter (harness mod only): vanilla's water bottle and then a
  vessel equipped and photographed; four vessels turned 0-270 degrees and
  a copy with undoCoreScale photographed, the placeholders the machines
  use photographed; saved, exited to the menu and continued, then both
  groups photographed again. The screenshots taken are listed at the end,
  with the console lines naming the model.
  fermenter-model: the same placing with the fermenter's shipped model
  (TLG_models.txt), the test barrel at true size beside it, photographed,
  a vessel equipped and photographed with the interface (its icon in the
  equipped-item button), saved, continued and photographed again; the
  machines' inventory categories must have a text.
  held: a baseball bat, a small water bottle and the fermentation vessel
  (in one hand, then both) equipped in turn and photographed close up,
  then the hand bones drawn; no save.
  heavy: vanilla's meteorite and anvil, then the vessel (a heavy item),
  carried in both hands and photographed; then vanilla's meteorite taken
  off the floor the loot window's double-click way; no save.
  generator-unequip: two generators with records taken from the world
  menu, the second take putting the first down (the menus unequip the
  hands first), then a bat equipped from the inventory menu putting the
  second down; each record must reach its new object; no save.
  pose: the vessel taken into both hands with each hand model the trial
  lists (vanilla's WaterTank, then placements of the barrel), photographed
  from the front and from behind on its right; the held-bag pose needs
  primaryAnimMask in TLG_machines.txt; no save.
  pose-hold: both arms through the harness's own pose files
  (AnimSets/player/maskingright/tlg*.xml): the game's shrug, its unused
  holding clip and its box-packing clip, photographed and with the
  animator's own log (TLG_animlog_*.txt); no save.
  pose-freeze: five of the game's both-hands-in-front clips held still on
  their first frame (tlgfreeze*.xml), the 0.5 m barrel in hand; no save.
  pose-carry: the carry clip retargeted from a Mixamo clip
  (tools/blender/pz_arms.py, anims_X/Bob/Bob_TLGCarry.x, tlgcarry.xml) with
  the water bottle and the barrel at 0.6 m and 0.5 m, photographed and
  with the animator's log; no save.
  pose-carry-wide: the same from the user's wider clip
  (Bob_TLGCarryWide.x, tlgcarrywide.xml), the barrel at 0.75 m and 0.6 m;
  no save.
  pose-carry-mid: the two clips blended halfway (Bob_TLGCarryMid.x,
  tlgcarrymid.xml), the barrel at 0.75 m and 0.6 m; no save.
  pose-carry-offsets: the halfway blend with the full-size barrel 0.13,
  0.17 and 0.21 file units in front of the hands (Bob_TLGCarryMid13/17/21.x,
  tlgcarrymid13/17/21.xml); no save.
  vessel-carry: the shipped vessel taken into both hands with its carry
  pose (tlgcarryvessel.xml, Bob_TLG_CarryVessel.x, TLG.FermenterHeld):
  photographed from the front, from the side, walking, and through an
  action playing vanilla's "Loot"; with the animator's log; no save.
  vessel-actions: real actions while carrying: the vessel through a loot
  from a bag on the floor (put down at the feet), a generator through the
  same loot (kept in both hands), then the vessel put down by the menus'
  unequip when a bat is equipped; photographed during each; no save.
  vessel-gaits: the vessel carried along a cleared row walking, running,
  sprinting (the game's forced-run and forced-sprint flags, as its toggle
  keys set them; "Toggle to Run" is turned on for the running legs),
  sneaking, running and sprinting crouched, then crouched and still; each
  leg timed, photographed three times (sprinting, eight times over more
  than one stride) and logged by the animator; no save.
  pose-crouch: crouched carry trials, each a harness item whose own pose
  file plays a candidate clip keyed for the game's crouch
  (Bob_TLGCrouch*.x, tlgcrouch*.xml) with the vessel's hand model:
  crouched and still, then crouched walking and running; no save.
  pose-sprint: sprint carry trials, each a harness item whose own pose
  files play a candidate clip keyed for the game's sprint while it
  sprints, and the shipped standing clip otherwise (Bob_TLGSprint*.x,
  tlgsprint*.xml), with the vessel's hand model: the row sprinted both
  ways, photographed eight times over more than one stride; no save.
  machine-models: the models supplied on 2026-11-03 (TLG_models.txt): the
  fuel filter, the drying column and the two stills put down beside the
  fermenter, and on its other side the sampling kit, the yeast starter,
  the stabilizer and the manual (their floor models built by
  tools/make-prop-models.ps1), photographed as a row and with the
  character between them, a still held through an action, then each item
  equipped and photographed with the interface shown for its icon; no
  save.
  manual, manual-italian: the fuel systems field manual: the loot lists
  that hold it, manuals rolled from them as the game fills a container,
  its page measured with its text panel shown, and a rolled manual read
  through the inventory menu's Inspect (manual-italian: the client in
  Italian); no save.
  crafting: the crafting window, opened with the button beside the
  equipped items: each of the mod's seven recipes found by name in its
  search box, picked from its list and made with its Craft button (the
  drying column by double-clicking its row), beside a workbench; the
  vessel first with its nails missing (Craft disabled); no save.
  successor: a survivor loads two fermenters, looks at a petrol can and
  carries one fermenter, then dies; the game's post-death Respawn and
  character screens make a new survivor in the same world, who finds the
  world record, the can and the carried fermenter as left, knows nothing
  of the can until looking, takes both back and the fermenters work on;
  no save.
  knowledge: What I know about a fuel, from the Fuel menu: before any
  test, after a kit sample and a look two game hours apart, after the can
  is opened, after a litre is poured out, after a new look, and from an
  entry in the shape knowledge had before; no save.
  knowledge-save: the same kit sample and look, then saved and exited to
  the menu with the can sealed; the save is continued, the character's
  knowledge and the can's record must come back as saved, and What I know
  about it must list both tests, their ages gone on, with no notes.
  removal-a, removal-b, removal-c: the three launches of the removal
  rehearsal (tools/rehearse-install.ps1 -Scenario removal): a world played
  with the mod, continued without it (the driver), then with it again.
  fires: the January world; a campfire and a charcoal barbecue lit from
  their menus, the air around each checked against the heat formula, a
  fermenter beside each, and a 12 game hour trip away while they burn.
  existing-a, existing-b: the two launches of the existing-save rehearsal
  (tools/rehearse-install.ps1 -Scenario existing): a world played without
  the mod, then that save continued with it.
  italian: the client in Italian; every Italian string the mod ships must
  come back exactly as shipped, and the Fuel and machine menus read Italian.
.PARAMETER ModSource
  Folder deployed as the mod (default: the repository's; see setup-devenv.ps1).
.PARAMETER ActiveMods
  Mods the client loads (default: the mod and the harness; see setup-devenv.ps1).
#>
param([string]$GameDir = "", [string]$DevCache = "", [int]$TimeoutMinutes = 30,
    [ValidateSet("full", "realtime", "winter", "fireplace", "fireplace-reload", "pickup", "pot-still", "controls", "still-pickup",
        "still-save", "still-controls", "late-find", "can-water", "chassis", "driving", "engine-effects", "performance", "model-import", "fermenter-model", "held", "heavy",
        "generator-unequip", "pose", "pose-hold", "pose-freeze", "pose-carry", "pose-carry-wide", "pose-carry-mid", "pose-carry-offsets", "vessel-carry", "vessel-actions",
        "vessel-gaits", "pose-crouch", "pose-sprint", "machine-models", "manual", "manual-italian", "crafting", "successor", "knowledge", "knowledge-save", "fires", "existing-a", "existing-b", "removal-a", "removal-b", "removal-c", "italian")][string]$Mode = "full",
    [string]$ModSource = "", [string[]]$ActiveMods = @("TheLastGallon", "TheLastGallonHarness"))
$ErrorActionPreference = "Stop"
if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) {
    # A locked Windows session cannot present the OpenGL window; the client
    # stalls after the intro videos (2026-10-30, docs/test-results.md).
    Write-Host "The Windows session is locked; unlock the desktop and run again."
    exit 2
}
$repo = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = $env:PZ_GAME_DIR }
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $repo "..\..")).Path }
if (-not $DevCache) { $DevCache = Join-Path $env:LOCALAPPDATA "TheLastGallon\devcache" }
& (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $DevCache -ModSource $ModSource -ActiveMods $ActiveMods | Out-Null
# The game skips a pose file it cannot parse, with only a console line, so
# its node never plays (run 109: "--" inside a comment): check the deployed
# mods' XML before launching.
$badXml = @($ActiveMods | ForEach-Object { Join-Path $DevCache "mods\$_" } | Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem -Recurse -File -Filter *.xml $_ } | Where-Object {
        try { [void]([xml](Get-Content -Raw -LiteralPath $_.FullName)); $false } catch { $true } })
if ($badXml.Count -gt 0) { $badXml | ForEach-Object { Write-Host "XML ERROR $($_.FullName)" }; exit 3 }

# First-run prompts: copy the user's own already-answered values (read only).
# The tutorial prompt and the Survival Guide window are switched off here
# (2026-10-31: both waited for a click).
$userOptions = Join-Path $env:USERPROFILE "Zomboid\options.ini"
$keys = @("termsOfServiceVersion", "doneNewSaveFolder", "showFirstTimeSearchTutorial",
    "showFirstAnimalZoneInfo", "shownWelcomeMessageVersion")
$opts = [ordered]@{ version = "1"; fullScreen = "false"; screenWidth = "1280"; screenHeight = "720"; language = "EN";
    showFirstTimeSneakTutorial = "false"; showWelcomeMessage2 = "false"; tutorialDone = "true";
    showSurvivalGuide = "false" }
if (Test-Path $userOptions) {
    foreach ($line in Get-Content $userOptions) {
        $k, $v = $line -split "=", 2
        if ($keys -contains $k) { $opts[$k] = $v }
    }
}
if ($Mode -eq "italian" -or $Mode -eq "manual-italian") { $opts["language"] = "IT" }
($opts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Encoding ascii (Join-Path $DevCache "options.ini")

$luaDir = Join-Path $DevCache "Lua"
New-Item -ItemType Directory -Force $luaDir | Out-Null
foreach ($f in "TLG_harness_sp.txt", "TLG_harness_expect.txt") { Remove-Item (Join-Path $luaDir $f) -ErrorAction SilentlyContinue }
if ($Mode -eq "italian") {
    # Every Italian string the deployed mod ships, as category|key=value in
    # ASCII: letters past ASCII and backslashes as \uXXXX, which the harness
    # decodes, so no file encoding stands between the file and the check.
    $src = if ($ModSource) { $ModSource } else { Join-Path $repo "Contents\mods\TheLastGallon" }
    $lines = foreach ($f in Get-ChildItem (Join-Path $src "common\media\lua\shared\Translate\IT") -Filter *.json | Sort-Object Name) {
        $obj = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) {
            $v = -join ([string]$p.Value).ToCharArray().ForEach({ if ([int]$_ -gt 126 -or $_ -eq '\') { '\u{0:x4}' -f [int]$_ } else { [string]$_ } })
            "$($f.BaseName)|$($p.Name)=$v"
        }
    }
    Set-Content -Encoding ascii -Path (Join-Path $luaDir "TLG_it_expect.txt") -Value $lines
}
$request = switch ($Mode) { "realtime" { "sp-rt" } "winter" { "sp-rtw" } "fireplace" { "sp-rtf" }
    "fireplace-reload" { "sp-rtfs" } "pickup" { "sp-rtp" } "pot-still" { "sp-rtpot" } "controls" { "sp-rtc" }
    "still-pickup" { "sp-rts" } "still-save" { "sp-rtss" } "still-controls" { "sp-rtsc" } "late-find" { "sp-rtn" } "can-water" { "sp-rtcw" } "chassis" { "sp-rtv" } "driving" { "sp-rtd" } "engine-effects" { "sp-rte" } "performance" { "sp-rtpf" } "model-import" { "sp-rtmi" } "fermenter-model" { "sp-rtmf" } "held" { "sp-rtmh" } "heavy" { "sp-rtmhh" } "generator-unequip" { "sp-rtgu" } "pose" { "sp-rtmp" } "pose-hold" { "sp-rtmph" } "pose-freeze" { "sp-rtmpf" } "pose-carry" { "sp-rtmpc" } "pose-carry-wide" { "sp-rtmpw" } "pose-carry-mid" { "sp-rtmpm" } "pose-carry-offsets" { "sp-rtmpo" } "vessel-carry" { "sp-rtmv" } "vessel-actions" { "sp-rtmva" } "vessel-gaits" { "sp-rtmvg" } "pose-crouch" { "sp-rtmpk" } "pose-sprint" { "sp-rtmps" } "machine-models" { "sp-rtmm" } "manual" { "sp-rtman" } "manual-italian" { "sp-rtmanit" } "crafting" { "sp-rtcr" } "successor" { "sp-rtsu" } "knowledge" { "sp-rtkn" } "knowledge-save" { "sp-rtkns" } "removal-a" { "rm-a" } "removal-b" { "rm-b" } "removal-c" { "rm-c" } "fires" { "sp-rtof" } "existing-a" { "ex-a" } "existing-b" { "ex-b" } "italian" { "sp-it" } default { "sp-a" } }
Set-Content -Path (Join-Path $luaDir "TLG_harness_request.txt") -Value $request -Encoding ascii

$json = Get-Content (Join-Path $GameDir "ProjectZomboid64.json") -Raw | ConvertFrom-Json
$vm = @($json.vmArgs | Where-Object { $_ -notmatch '^-Dzomboid.steam=' }) + @("-Dzomboid.steam=0", "-XX:+UseZGC")
$clientArgs = $vm + @("-cp", ($json.classpath -join ";"), ($json.mainClass -replace "/", "."),
    "-debug", "-nosteam", "-nosound", "-cachedir=$DevCache")
$out = Join-Path $DevCache "client-stdout.txt"
$err = Join-Path $DevCache "client-stderr.txt"
$started = Get-Date
$p = Start-Process -FilePath (Join-Path $GameDir "jre64\bin\java.exe") -ArgumentList $clientArgs -WorkingDirectory $GameDir `
    -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "client started, pid $($p.Id)"

# After every world load GameLoadingState waits for a left click ("Click to
# Start"; BC GameLoadingState.update polls Mouse.isButtonDown(0)). The click is
# posted to the game window only (no cursor movement, no other window can
# receive it) while a load has finished but the loading state has not exited.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class TlgWin {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
function Send-GameClick([IntPtr]$hwnd) {
    $r = New-Object TlgWin+RECT
    [TlgWin]::GetClientRect($hwnd, [ref]$r) | Out-Null
    $lp = [IntPtr]((([int](($r.B - $r.T) / 2)) -shl 16) -bor [int](($r.R - $r.L) / 2))
    [TlgWin]::PostMessage($hwnd, 0x0201, [IntPtr]1, $lp) | Out-Null  # WM_LBUTTONDOWN
    Start-Sleep -Milliseconds 300
    [TlgWin]::PostMessage($hwnd, 0x0202, [IntPtr]0, $lp) | Out-Null  # WM_LBUTTONUP
}
function Read-Shared([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    $fs = [System.IO.File]::Open($path, "Open", "Read", "ReadWrite, Delete")
    try { return (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
$console = Join-Path $DevCache "console.txt"

$results = Join-Path $luaDir "TLG_harness_sp.txt"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$finished = $false
$clicks = 0
while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
    Start-Sleep -Seconds 5
    if ((Test-Path $results) -and ((Read-Shared $results) -match "(?m)^DONE")) { $finished = $true; break }
    $log = Read-Shared $console
    $loads = ([regex]::Matches($log, "game loading took")).Count
    $exits = ([regex]::Matches($log, "STATE: exit zombie\.gameStates\.GameLoadingState")).Count
    if ($loads -gt $exits) {
        $p.Refresh()
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { Send-GameClick $p.MainWindowHandle; $clicks++ }
    }
}
Write-Host "click-to-start clicks sent: $clicks"
if ($finished) {
    $grace = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $grace -and -not $p.HasExited) { Start-Sleep -Seconds 3 }
}
if (-not $p.HasExited) {
    Write-Host "watchdog: stopping client"
    Stop-Process -Id $p.Id -Force
}
Write-Host "finished=$finished exitCode=$(if ($p.HasExited) { $p.ExitCode } else { 'killed' })"
if (Test-Path $results) { Get-Content $results } else { Write-Host "no results file"; Get-Content $out -Tail 40 }
# Screenshots the run took (Core.TakeFullScreenshot writes <cachedir>/Screenshots).
$shots = Join-Path $DevCache "Screenshots"
if (Test-Path $shots) {
    Get-ChildItem $shots -File | Where-Object { $_.LastWriteTime -ge $started } | ForEach-Object { Write-Host "screenshot: $($_.FullName)" }
}
if ($Mode -eq "model-import" -or $Mode -eq "fermenter-model") {
    Select-String -Path $console -Pattern "FermenterTest|TLGHarness/|TLG/Fermenter|Fermenter\.fbx" | ForEach-Object { Write-Host "console: $($_.Line)" }
}
# Explicit status: otherwise robocopy's "files copied" code 1 from setup leaks out.
if ($finished) { exit 0 } else { exit 1 }

