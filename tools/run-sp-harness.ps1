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
  (place action, inventory Drop) and read against the fourth.
  pot-still: summer with the grid on; a 66.6 L wash through the 60 L pot
  still in two runs (the firebox left to run out once), collected into one
  can, dried with quicklime and evaluated against the engine profiles.
  controls: summer with the grid on; Pause, Resume and Abort batch from the
  machine menu on three fermenters and a drying column, one left paused
  until it spoils.
  fires: the January world; a campfire and a charcoal barbecue lit from
  their menus, the air around each checked against the heat formula, a
  fermenter beside each, and a 12 game hour trip away while they burn.
.PARAMETER ModSource
  Folder deployed as the mod (default: the repository's; see setup-devenv.ps1).
#>
param([string]$GameDir = "", [string]$DevCache = "", [int]$TimeoutMinutes = 30,
    [ValidateSet("full", "realtime", "winter", "fireplace", "fireplace-reload", "pickup", "pot-still", "controls", "fires")][string]$Mode = "full",
    [string]$ModSource = "")
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
& (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $DevCache -ModSource $ModSource | Out-Null

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
($opts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Encoding ascii (Join-Path $DevCache "options.ini")

$luaDir = Join-Path $DevCache "Lua"
New-Item -ItemType Directory -Force $luaDir | Out-Null
foreach ($f in "TLG_harness_sp.txt", "TLG_harness_expect.txt") { Remove-Item (Join-Path $luaDir $f) -ErrorAction SilentlyContinue }
$request = switch ($Mode) { "realtime" { "sp-rt" } "winter" { "sp-rtw" } "fireplace" { "sp-rtf" }
    "fireplace-reload" { "sp-rtfs" } "pickup" { "sp-rtp" } "pot-still" { "sp-rtpot" } "controls" { "sp-rtc" }
    "fires" { "sp-rtof" } default { "sp-a" } }
Set-Content -Path (Join-Path $luaDir "TLG_harness_request.txt") -Value $request -Encoding ascii

$json = Get-Content (Join-Path $GameDir "ProjectZomboid64.json") -Raw | ConvertFrom-Json
$vm = @($json.vmArgs | Where-Object { $_ -notmatch '^-Dzomboid.steam=' }) + @("-Dzomboid.steam=0", "-XX:+UseZGC")
$clientArgs = $vm + @("-cp", ($json.classpath -join ";"), ($json.mainClass -replace "/", "."),
    "-debug", "-nosteam", "-nosound", "-cachedir=$DevCache")
$out = Join-Path $DevCache "client-stdout.txt"
$err = Join-Path $DevCache "client-stderr.txt"
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
# Explicit status: otherwise robocopy's "files copied" code 1 from setup leaks out.
if ($finished) { exit 0 } else { exit 1 }

