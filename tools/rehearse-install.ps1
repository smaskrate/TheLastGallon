<#
.SYNOPSIS
  Rehearses a clean installation of the release zip (release gate 12).
.DESCRIPTION
  1. Builds the package with tools/package.ps1 (unless -NoBuild).
  2. Unpacks dist/TheLastGallon-<version>.zip into a fresh folder and checks
     the unpacked files against the SHA-256 manifest, both ways.
  3. Installs the mod as the player guide says: the zip's
     Contents/mods/TheLastGallon into the mods folder of a fresh, isolated
     cache directory (%LOCALAPPDATA%\TheLastGallon\installcache, never the
     user's Zomboid folder). The dev-only harness mod goes beside it to drive
     the run; it does not touch the package's files.
  4. -Scenario clean (default, release gate 12): runs the full harness
     against it: phase A, save, exit to the menu, continue the save, phase B
     (tools/run-sp-harness.ps1 -Mode full).
     -Scenario existing (release gate 7): launch 1 plays a world without the
     mod (only the dev driver TheLastGallonPreInstall is active, request
     "ex-a") and saves it; the save's mods.txt then lists the mod and the
     harness, as the load screen's Choose mods writes it; launch 2 continues
     that save with the mod (requests "ex-b", then "ex-c").
     -Scenario removal (release gate 7): launch 1 plays a new world with the
     mod and the harness (request "rm-a") and saves it; the save's mods.txt
     then lists only the driver; launch 2 continues it without the mod
     ("rm-b") and saves; mods.txt lists the mod and the harness again;
     launch 3 continues it with the mod back ("rm-c") and saves; launch 4
     continues it once more ("rm-d"). Each launch's results
     and console are kept in the cache's Lua folder as
     TLG_removal_launch<n>.results.txt and .console.txt.
     -Scenario upgrade: launch 1 plays a new world with an EARLIER release's
     package (dist/TheLastGallon-<FromVersion>.zip, checked against its own
     manifest) and the harness (request "up-a") and saves it; this version's
     package then replaces it in the mods folder, as a player replaces the
     folder; launch 2 continues the save ("up-b"). Results and consoles are
     kept as TLG_upgrade_launch<n>.results.txt and .console.txt.
  The rehearsal folders are removed and recreated only when they carry this
  script's marker file. Nothing is uploaded.
.PARAMETER NoBuild
  Rehearse the zip already in dist/.
.PARAMETER TimeoutMinutes
  Watchdog limit for each game launch (default 40).
.PARAMETER Scenario
  clean, existing, removal or upgrade (see above).
.PARAMETER FromVersion
  The earlier release the upgrade scenario starts from (default 0.1.2).
#>
param([switch]$NoBuild, [int]$TimeoutMinutes = 40,
    [ValidateSet("clean", "existing", "removal", "upgrade")][string]$Scenario = "clean", [string]$FromVersion = "0.1.2")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "Contents\mods\TheLastGallon\42\mod.info") -Pattern '^modversion=(.+)$').Matches[0].Groups[1].Value
if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot "package.ps1")
    if ($LASTEXITCODE -ne 0) { throw "package build failed" }
}
$zip = Join-Path $repo "dist\TheLastGallon-$version.zip"
$manifest = Join-Path $repo "dist\TheLastGallon-$version.sha256"
if (-not (Test-Path $zip) -or -not (Test-Path $manifest)) { throw "no $zip or its manifest: build the package first" }

$root = Join-Path $env:LOCALAPPDATA "TheLastGallon"
$cache = Join-Path $root "installcache"
$unpacked = Join-Path $root "install-unpacked"
$marker = ".tlg-install-rehearsal"
foreach ($dir in $cache, $unpacked) {
    if (Test-Path $dir) {
        if (-not (Test-Path (Join-Path $dir $marker))) { throw "$dir exists without $marker; not removing it" }
        Remove-Item -Recurse -Force $dir
    }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -Encoding ascii (Join-Path $dir $marker) "Created by tools/rehearse-install.ps1; its next run removes this folder."
}

# Unpacks a release zip into $unpacked\<name>, compares it with its manifest
# both ways and returns the mod folder inside it.
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Expand-Release([string]$zip, [string]$manifest, [string]$name) {
    $files = Join-Path $unpacked $name
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $files)
    $want = @{}
    foreach ($line in Get-Content $manifest) {
        if (-not $line) { continue }
        $hash, $path = $line -split "  ", 2
        $want[$path] = $hash
    }
    $got = @{}
    Get-ChildItem -Recurse -File $files | ForEach-Object {
        $got[$_.FullName.Substring($files.Length + 1).Replace('\', '/')] = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
    }
    $bad = @()
    foreach ($p in $want.Keys) { if ($got[$p] -ne $want[$p]) { $bad += "missing from the zip or different: $p" } }
    foreach ($p in $got.Keys) { if (-not $want.ContainsKey($p)) { $bad += "not in the manifest: $p" } }
    if ($bad) { $bad | ForEach-Object { Write-Host $_ }; throw "$zip does not match its manifest" }
    Write-Host "$(Split-Path -Leaf $zip) matches its manifest: $($got.Count) files, SHA-256 $((Get-FileHash -Algorithm SHA256 $zip).Hash)"
    $modDir = Join-Path $files "Contents\mods\TheLastGallon"
    if (-not (Test-Path (Join-Path $modDir "42\mod.info"))) { throw "$zip has no Contents/mods/TheLastGallon/42/mod.info" }
    return $modDir
}
$mod = Expand-Release $zip $manifest "zip"

$harness = Join-Path $PSScriptRoot "run-sp-harness.ps1"
if ($Scenario -eq "clean") {
    & $harness -DevCache $cache -ModSource $mod -Mode full -TimeoutMinutes $TimeoutMinutes
    exit 0
}

# The save's mod list as the load screen's Choose mods writes it
# (SRC ModSelectorModel.lua: manipulateSavefile(folder, "WriteModsDotTxt")).
function Write-ModsTxt([string]$folder, [string[]]$mods) {
    $lines = @("VERSION = 1,", "", "mods", "{") + ($mods | ForEach-Object { "    mod = $_," }) + @("}", "", "maps", "{", "}")
    $lines | Set-Content -Encoding ascii (Join-Path $folder "mods.txt")
}

if ($Scenario -eq "upgrade") {
    $fromZip = Join-Path $repo "dist\TheLastGallon-$FromVersion.zip"
    $fromManifest = Join-Path $repo "dist\TheLastGallon-$FromVersion.sha256"
    if (-not (Test-Path $fromZip) -or -not (Test-Path $fromManifest)) { throw "no $fromZip or its manifest" }
    $fromMod = Expand-Release $fromZip $fromManifest "from"
    $lua = Join-Path $cache "Lua"
    function Save-Launch([int]$n) {
        Copy-Item (Join-Path $lua "TLG_harness_sp.txt") (Join-Path $lua "TLG_upgrade_launch$n.results.txt") -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $cache "console.txt") (Join-Path $lua "TLG_upgrade_launch$n.console.txt") -ErrorAction SilentlyContinue
    }
    # Launch 1: a new world with the earlier release; fuel recorded, saved.
    & $harness -DevCache $cache -ModSource $fromMod -Mode upgrade-a -TimeoutMinutes $TimeoutMinutes
    Save-Launch 1
    $saves = @(Get-ChildItem -Directory (Join-Path $cache "Saves\Sandbox") -ErrorAction SilentlyContinue)
    if ($saves.Count -ne 1) { throw "expected the one save of launch 1, found $($saves.Count)" }
    Write-Host "save $($saves[0].Name) made with $FromVersion; the mods folder now gets $version"
    # Launch 2: this version's package in the mods folder (the harness's setup
    # mirrors it over the earlier one), the save continued.
    & $harness -DevCache $cache -ModSource $mod -Mode upgrade-b -TimeoutMinutes $TimeoutMinutes
    Save-Launch 2
    foreach ($n in 1, 2) {
        Select-String -Path (Join-Path $lua "TLG_upgrade_launch$n.console.txt") -Pattern "world fuel history created|TLG\] .*version" -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "launch $n console: $($_.Line.Trim())" }
    }
    Write-Host "results and consoles: $lua\TLG_upgrade_launch<n>.results.txt / .console.txt"
    exit 0
}

if ($Scenario -eq "removal") {
    $lua = Join-Path $cache "Lua"
    # The game starts console.txt afresh on every launch: keep each one.
    function Save-Launch([int]$n) {
        Copy-Item (Join-Path $lua "TLG_harness_sp.txt") (Join-Path $lua "TLG_removal_launch$n.results.txt") -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $cache "console.txt") (Join-Path $lua "TLG_removal_launch$n.console.txt") -ErrorAction SilentlyContinue
    }
    # Launch 1: a new world with the mod; cans and a fermenter recorded, saved.
    & $harness -DevCache $cache -ModSource $mod -Mode removal-a -TimeoutMinutes $TimeoutMinutes
    Save-Launch 1
    $saves = @(Get-ChildItem -Directory (Join-Path $cache "Saves\Sandbox") -ErrorAction SilentlyContinue)
    if ($saves.Count -ne 1) { throw "expected the one save of launch 1, found $($saves.Count)" }
    # The mod taken off the save; the driver plays it.
    Write-ModsTxt $saves[0].FullName @("TheLastGallonPreInstall")
    Write-Host "save $($saves[0].Name): mods.txt now lists only TheLastGallonPreInstall"
    # Launch 2: the save continued without the mod.
    & $harness -DevCache $cache -ModSource $mod -Mode removal-b -ActiveMods @("TheLastGallonPreInstall") -TimeoutMinutes $TimeoutMinutes
    Save-Launch 2
    # The mod back on the save.
    Write-ModsTxt $saves[0].FullName @("TheLastGallon", "TheLastGallonHarness")
    Write-Host "save $($saves[0].Name): mods.txt lists TheLastGallon and TheLastGallonHarness again"
    # Launch 3: the save continued with the mod.
    & $harness -DevCache $cache -ModSource $mod -Mode removal-c -TimeoutMinutes $TimeoutMinutes
    Save-Launch 3
    # Launch 4: the save of launch 3 continued, the mod still on it.
    & $harness -DevCache $cache -ModSource $mod -Mode removal-d -TimeoutMinutes $TimeoutMinutes
    Save-Launch 4
    foreach ($n in 1, 2, 3, 4) {
        Select-String -Path (Join-Path $lua "TLG_removal_launch$n.console.txt") -Pattern "world fuel history created" -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "launch $n console: $($_.Line.Trim())" }
    }
    Write-Host "results and consoles: $lua\TLG_removal_launch<n>.results.txt / .console.txt"
    exit 0
}

# Launch 1: a world played without the mod, saved.
& $harness -DevCache $cache -ModSource $mod -Mode existing-a -ActiveMods @("TheLastGallonPreInstall") -TimeoutMinutes $TimeoutMinutes
$lua = Join-Path $cache "Lua"
$launch1 = Join-Path $lua "TLG_existing_launch1.txt"
Copy-Item (Join-Path $lua "TLG_harness_sp.txt") $launch1 -ErrorAction SilentlyContinue
$saves = @(Get-ChildItem -Directory (Join-Path $cache "Saves\Sandbox") -ErrorAction SilentlyContinue)
if ($saves.Count -ne 1) { throw "expected the one save of launch 1, found $($saves.Count)" }
# The mod added to that save as the load screen's Choose mods does
# (SRC ModSelectorModel.lua: manipulateSavefile(folder, "WriteModsDotTxt")),
# in default.txt's order, the driver left out.
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
"@ | Set-Content -Encoding ascii (Join-Path $saves[0].FullName "mods.txt")
Write-Host "save $($saves[0].Name): mods.txt now lists TheLastGallon and TheLastGallonHarness"

# Launch 2: that save continued with the mod, saved and continued again.
& $harness -DevCache $cache -ModSource $mod -Mode existing-b -TimeoutMinutes $TimeoutMinutes
Select-String -Path (Join-Path $cache "console.txt") -Pattern "world fuel history created" |
    ForEach-Object { Write-Host "console: $($_.Line.Trim())" }
Write-Host "launch 1 results: $launch1"
exit 0
