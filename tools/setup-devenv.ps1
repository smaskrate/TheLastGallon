<#
.SYNOPSIS
  Creates/refreshes the isolated development cache directory used for all
  runtime tests and deploys the mod into it.
.DESCRIPTION
  Findings that shape this script (docs/engine-capabilities.md, G01):
  * The game scans <cachedir>/mods (plus Steam Workshop folders), never the
    install-dir mods folder, so the repository is not loaded in place.
  * On a cache dir without options.ini, Core.loadOptions() -> initOptionsINI()
    -> copyPasteFolders("mods") copies <gamedir>/mods into <cachedir>/mods.
    This repository lives in <gamedir>/mods, so options.ini is pre-created to
    stop that copy, the cache dir lives outside <gamedir>/mods, and mods are
    deployed by mirror copy instead of junctions (the game can never write
    into the repository).
  Nothing under the user's own %USERPROFILE%\Zomboid directory is touched.
.PARAMETER DevCache
  Cache directory (default %LOCALAPPDATA%\TheLastGallon\devcache).
.PARAMETER Force
  Rewrite generated configuration files even if they already exist.
#>
param([string]$DevCache = "", [switch]$Force)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $DevCache) { $DevCache = Join-Path $env:LOCALAPPDATA "TheLastGallon\devcache" }
$gameMods = (Resolve-Path (Join-Path $repo "..")).Path
if ($DevCache.StartsWith($gameMods, [System.StringComparison]::OrdinalIgnoreCase) -or
    $DevCache.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The dev cache must not live inside $gameMods (first-run copy would recurse)."
}
$mods = Join-Path $DevCache "mods"
New-Item -ItemType Directory -Force $mods, (Join-Path $DevCache "Server") | Out-Null

# Must exist before the first launch, see description.
$options = Join-Path $DevCache "options.ini"
if ($Force -or -not (Test-Path $options)) {
    @"
version=1
fullScreen=false
screenWidth=1280
screenHeight=720
"@ | Set-Content -Encoding ascii $options
}

function Sync-Mod([string]$source, [string]$target) {
    $item = Get-Item -Force $target -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) { throw "$target is a link; remove it (rmdir without /s) and rerun" }
    robocopy $source $target /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE) for $source" }
}
Sync-Mod (Join-Path $repo "Contents\mods\TheLastGallon") (Join-Path $mods "TheLastGallon")
Sync-Mod (Join-Path $repo "tests\ingame\TheLastGallonHarness") (Join-Path $mods "TheLastGallonHarness")

$defaultTxt = Join-Path $mods "default.txt"
if ($Force -or -not (Test-Path $defaultTxt)) {
    @"
VERSION = 1,

mods
{
    mod = TheLastGallon,
    mod = TheLastGallonHarness,
}

maps
{
}
"@ | Set-Content -Encoding ascii $defaultTxt
}

# Credentials for the loopback-only dev server; never committed.
$cred = Join-Path $DevCache "dev-credentials.txt"
if (-not (Test-Path $cred)) {
    $chars = (48..57) + (65..90) + (97..122)
    $admin = -join ($chars | Get-Random -Count 20 | ForEach-Object { [char]$_ })
    $join = -join ($chars | Get-Random -Count 20 | ForEach-Object { [char]$_ })
    "admin=$admin`nserverPassword=$join" | Set-Content -Encoding ascii $cred
}
$values = @{}
Get-Content $cred | ForEach-Object { $k, $v = $_ -split "=", 2; $values[$k] = $v }

$ini = Join-Path $DevCache "Server\TLGDev.ini"
if ($Force -or -not (Test-Path $ini)) {
    @"
Mods=TheLastGallon;TheLastGallonHarness
Map=Muldraugh, KY
Public=false
Open=true
Password=$($values.serverPassword)
DefaultPort=16361
UDPPort=16362
PauseEmpty=true
SaveWorldEveryMinutes=0
DoLuaChecksum=true
SteamVAC=false
"@ | Set-Content -Encoding ascii $ini
}
Write-Host "Dev cache ready: $DevCache"
