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
  4. Runs the full harness against it: phase A, save, exit to the menu,
     continue the save, phase B (tools/run-sp-harness.ps1 -Mode full).
  The rehearsal folders are removed and recreated only when they carry this
  script's marker file. Nothing is uploaded.
.PARAMETER NoBuild
  Rehearse the zip already in dist/.
.PARAMETER TimeoutMinutes
  Watchdog limit for the game run (default 40).
#>
param([switch]$NoBuild, [int]$TimeoutMinutes = 40)
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

# Unpack, then compare with the manifest both ways.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = Join-Path $unpacked "zip"
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
if ($bad) { $bad | ForEach-Object { Write-Host $_ }; throw "the zip does not match its manifest" }
Write-Host "zip matches its manifest: $($got.Count) files"
$mod = Join-Path $files "Contents\mods\TheLastGallon"
if (-not (Test-Path (Join-Path $mod "42\mod.info"))) { throw "the zip has no Contents/mods/TheLastGallon/42/mod.info" }

& (Join-Path $PSScriptRoot "run-sp-harness.ps1") -DevCache $cache -ModSource $mod -Mode full -TimeoutMinutes $TimeoutMinutes
