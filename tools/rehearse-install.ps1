<#
.SYNOPSIS
  Rehearses a clean installation of the release zip (release gate 12).
.DESCRIPTION
  1. Builds the package with tools/package.ps1 (unless -NoBuild or
     -Scenario workshop).
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
     -Scenario workshop (release gate 12): the game loads the mod from the
     copy Steam downloaded for the user's subscription to the Workshop item,
     not from a zip; nothing is built or unpacked. The download is checked
     against the manifest in dist/ of the version its mod.info names, both
     ways (Steam stores the package's Contents folder as the item folder).
     Then the full harness runs in Steam mode with no copy of the mod in the
     cache (tools/run-sp-harness.ps1 -SteamModDir). It passes only if the
     harness finished with no failed check, the client reached Steam, the
     game read mod.info from the download's folder at the version the
     download names, the cache still holds no copy of the mod and the
     download still matches the manifest. Exit code 0 if it passes, 1 if
     not, 2 if the client was not started. Results and console are kept as
     TLG_workshop.results.txt and .console.txt. Steam must be running and
     signed in; it shows the account playing Project Zomboid meanwhile.
  The rehearsal folders are removed and recreated only when they carry this
  script's marker file. Nothing is uploaded.
.PARAMETER NoBuild
  Rehearse the zip already in dist/.
.PARAMETER TimeoutMinutes
  Watchdog limit for each game launch (default 40).
.PARAMETER Scenario
  clean, existing, removal, upgrade or workshop (see above).
.PARAMETER FromVersion
  The earlier release the upgrade scenario starts from (default 0.1.2).
.PARAMETER WorkshopDir
  The item folder of Steam's download for the workshop scenario (default
  <library>\steamapps\workshop\content\108600\3835496461, the library this
  game is installed in).
#>
param([switch]$NoBuild, [int]$TimeoutMinutes = 40,
    [ValidateSet("clean", "existing", "removal", "upgrade", "workshop")][string]$Scenario = "clean", [string]$FromVersion = "0.1.2",
    [string]$WorkshopDir = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "Contents\mods\TheLastGallon\42\mod.info") -Pattern '^modversion=(.+)$').Matches[0].Groups[1].Value
if (-not $NoBuild -and $Scenario -ne "workshop") {
    & (Join-Path $PSScriptRoot "package.ps1")
    if ($LASTEXITCODE -ne 0) { throw "package build failed" }
}
$zip = Join-Path $repo "dist\TheLastGallon-$version.zip"
$manifest = Join-Path $repo "dist\TheLastGallon-$version.sha256"
if ($Scenario -ne "workshop" -and (-not (Test-Path $zip) -or -not (Test-Path $manifest))) { throw "no $zip or its manifest: build the package first" }

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

if ($Scenario -eq "workshop") {
    if (-not $WorkshopDir) { $WorkshopDir = Join-Path $repo "..\..\..\..\workshop\content\108600\3835496461" }
    $item = (Resolve-Path $WorkshopDir).Path
    $steamMod = Join-Path $item "mods\TheLastGallon"
    # The item folder against the manifest of the version its mod.info names,
    # both ways; the manifest's paths start with the package's Contents/.
    function Test-Download {
        $info = Join-Path $steamMod "42\mod.info"
        if (-not (Test-Path $info)) { throw "no $info; is the item subscribed and downloaded?" }
        $v = (Select-String -Path $info -Pattern '^modversion=(.+)$').Matches[0].Groups[1].Value
        $man = Join-Path $repo "dist\TheLastGallon-$v.sha256"
        if (-not (Test-Path $man)) { throw "no $man for the downloaded version" }
        $want = @{}
        foreach ($line in Get-Content $man) {
            $hash, $path = $line -split "  ", 2
            if ($path -like "Contents/*") { $want[$path.Substring(9)] = $hash }
        }
        $got = @{}
        Get-ChildItem -Recurse -File -Force $item | ForEach-Object {
            $got[$_.FullName.Substring($item.Length + 1).Replace('\', '/')] = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
        }
        $bad = @()
        foreach ($p in $want.Keys) { if ($got[$p] -ne $want[$p]) { $bad += "missing from the download or different: $p" } }
        foreach ($p in $got.Keys) { if (-not $want.ContainsKey($p)) { $bad += "not in the manifest: $p" } }
        $bad | ForEach-Object { Write-Host $_ }
        Write-Host "Steam's download $item`: $($got.Count) files, mod.info $v, $(if ($bad) { 'does NOT match' } else { 'matches' }) $(Split-Path -Leaf $man) both ways"
        return [pscustomobject]@{ Ok = ($bad.Count -eq 0); Version = $v }
    }
    $before = Test-Download
    if (-not $before.Ok) { throw "Steam's download does not match its manifest; not launching" }
    & (Join-Path $PSScriptRoot "run-sp-harness.ps1") -DevCache $cache -SteamModDir $steamMod -Mode full -TimeoutMinutes $TimeoutMinutes
    $code = $LASTEXITCODE
    $lua = Join-Path $cache "Lua"
    $resultsCopy = Join-Path $lua "TLG_workshop.results.txt"
    $consoleCopy = Join-Path $lua "TLG_workshop.console.txt"
    Copy-Item (Join-Path $lua "TLG_harness_sp.txt") $resultsCopy -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $cache "console.txt") $consoleCopy -ErrorAction SilentlyContinue
    Write-Host "results and console: $resultsCopy, $consoleCopy"
    if ($code -eq 2 -or $code -eq 3) { Write-Host "workshop rehearsal: NOT LAUNCHED (run-sp-harness.ps1 exit $code)"; exit 2 }
    $res = @(if (Test-Path $resultsCopy) { Get-Content $resultsCopy })
    $con = if (Test-Path $consoleCopy) { Get-Content -Raw $consoleCopy } else { "" }
    function Get-Detail([string]$check) {
        $line = $res | Where-Object { $_.StartsWith("PASS $check :: ") } | Select-Object -First 1
        if ($line) { return $line.Substring("PASS $check :: ".Length) }
        return ""
    }
    function Get-FullPath([string]$p) { return [System.IO.Path]::GetFullPath($p).TrimEnd('\').ToLowerInvariant() }
    $dir = Get-Detail "G01c.mod_info_found"
    $ver = Get-Detail "G01c.mod_info_version"
    $sums = @($res | Where-Object { $_ -match '^SUMMARY ' })
    $after = Test-Download
    $checks = [ordered]@{
        "the harness finished (DONE)" = ($code -eq 0)
        "no check failed: $($sums -join '; ')" = ($sums.Count -gt 0 -and @($sums | Where-Object { $_ -notmatch ' fail=0$' }).Count -eq 0)
        "the client reached Steam (SteamUtils initialised successfully)" = ($con -match "SteamUtils initialised successfully")
        "the game read mod.info from Steam's download: $dir" = ($dir -ne "" -and (Get-FullPath $dir) -eq (Get-FullPath $steamMod))
        "at the version the download names: $ver" = ($ver -eq "mod.info $($before.Version), TLG.VERSION $($before.Version)")
        "the cache holds no copy of the mod" = (-not (Test-Path (Join-Path $cache "mods\TheLastGallon")))
        "Steam's download still matches the manifest" = $after.Ok
    }
    foreach ($k in $checks.Keys) { Write-Host "$(if ($checks[$k]) { 'PASS' } else { 'FAIL' }) $k" }
    if (@($checks.Values | Where-Object { -not $_ }).Count -eq 0) { Write-Host "workshop rehearsal: PASS"; exit 0 }
    Write-Host "workshop rehearsal: FAIL"
    exit 1
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
