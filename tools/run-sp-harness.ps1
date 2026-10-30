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
  Watchdog limit (default 20).
#>
param([string]$GameDir = "", [string]$DevCache = "", [int]$TimeoutMinutes = 20)
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
& (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $DevCache | Out-Null

# First-run prompts: copy the user's own already-answered values (read only).
$userOptions = Join-Path $env:USERPROFILE "Zomboid\options.ini"
$keys = @("termsOfServiceVersion", "tutorialDone", "doneNewSaveFolder", "showFirstTimeSearchTutorial",
    "showFirstAnimalZoneInfo", "shownWelcomeMessageVersion")
$opts = [ordered]@{ version = "1"; fullScreen = "false"; screenWidth = "1280"; screenHeight = "720"; language = "EN";
    showFirstTimeSneakTutorial = "false"; showWelcomeMessage2 = "false" }
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
Set-Content -Path (Join-Path $luaDir "TLG_harness_request.txt") -Value "sp-a" -Encoding ascii

$json = Get-Content (Join-Path $GameDir "ProjectZomboid64.json") -Raw | ConvertFrom-Json
$vm = @($json.vmArgs | Where-Object { $_ -notmatch '^-Dzomboid.steam=' }) + @("-Dzomboid.steam=0", "-XX:+UseZGC")
$clientArgs = $vm + @("-cp", ($json.classpath -join ";"), ($json.mainClass -replace "/", "."),
    "-debug", "-nosteam", "-nosound", "-cachedir=$DevCache")
$out = Join-Path $DevCache "client-stdout.txt"
$err = Join-Path $DevCache "client-stderr.txt"
$p = Start-Process -FilePath (Join-Path $GameDir "jre64\bin\java.exe") -ArgumentList $clientArgs -WorkingDirectory $GameDir `
    -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "client started, pid $($p.Id)"

$results = Join-Path $luaDir "TLG_harness_sp.txt"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$finished = $false
while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
    Start-Sleep -Seconds 5
    if ((Test-Path $results) -and ((Get-Content $results -Raw) -match "(?m)^DONE")) { $finished = $true; break }
}
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

