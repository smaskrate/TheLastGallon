<#
.SYNOPSIS
  Builds the release package (Workshop item layout) under dist/. Never uploads.
.DESCRIPTION
  1. Runs the gates that do not need the game: domain tests, Kahlua compile
     check (syntax + BOM), translation parity.
  2. Copies only the runtime package (Contents/mods/TheLastGallon/{42,common})
     plus player-facing docs into dist/TheLastGallon/Contents/mods/TheLastGallon,
     writes workshop.txt (visibility=private) and a SHA-256 manifest, and zips it.
  3. Rejects files outside the allowed runtime extensions and any test/harness
     content. Publication is a separate, manual step (docs/release-checklist.md).
.PARAMETER SkipTests
  Skip the domain test run (compile and translation checks still run).
#>
param([switch]$SkipTests)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$tools = $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "Contents\mods\TheLastGallon\42\mod.info") -Pattern '^modversion=(.+)$').Matches[0].Groups[1].Value

if (-not $SkipTests) {
    & (Join-Path $tools "run-tests.ps1")
    if ($LASTEXITCODE -ne 0) { throw "domain tests failed" }
}
& (Join-Path $tools "run-tests.ps1") -Entry "tests/support/compile_check.lua"
if ($LASTEXITCODE -ne 0) { throw "compile check failed" }
& (Join-Path $tools "check-translations.ps1")
if ($LASTEXITCODE -ne 0) { throw "translation check failed" }

$dist = Join-Path $repo "dist"
$item = Join-Path $dist "TheLastGallon"
if (Test-Path $item) { Remove-Item -Recurse -Force $item }
$modOut = Join-Path $item "Contents\mods\TheLastGallon"
New-Item -ItemType Directory -Force $modOut | Out-Null
foreach ($part in "42", "common") {
    robocopy (Join-Path $repo "Contents\mods\TheLastGallon\$part") (Join-Path $modOut $part) /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $part" }
}
# Player-facing documents ("docs" is not a version folder, so the game ignores it).
$docsOut = Join-Path $modOut "docs"
New-Item -ItemType Directory -Force $docsOut | Out-Null
foreach ($doc in "player-guide.md", "support-matrix.md", "migrations.md") {
    Copy-Item (Join-Path $repo "docs\$doc") $docsOut
}
foreach ($doc in "CHANGELOG.md", "NOTICE.md", "README.md") {
    if (Test-Path (Join-Path $repo $doc)) { Copy-Item (Join-Path $repo $doc) $docsOut }
}

# Content rules.
$allowed = @(".lua", ".txt", ".json", ".info", ".png", ".md", ".ogg", ".x", ".fbx", ".xml")
$bad = Get-ChildItem -Recurse -File $modOut | Where-Object {
    ($allowed -notcontains $_.Extension.ToLower()) -or ($_.FullName -match 'TLGHarness|\\tests\\|\\tools\\')
}
if ($bad) { $bad | ForEach-Object { Write-Host "REJECTED $($_.FullName)" }; throw "package contains disallowed files" }

@"
version=1
title=The Last Gallon (development build $version)
description=Fuel deterioration, alternative fuels, engine conversions and energy infrastructure.
description=Tested only on Project Zomboid 42.21.0 (4a0e9546ec). See docs/support-matrix.md inside the mod.
description=Development build: several features are untested in game (docs/release-checklist.md).
tags=Build 42;Realistic;Vehicles
visibility=private
"@ | Set-Content -Encoding ascii (Join-Path $item "workshop.txt")
if (-not (Test-Path (Join-Path $repo "art-src\preview.png"))) {
    Write-Host "WARNING: no preview.png (release art not produced); the Workshop uploader requires one."
} else {
    Copy-Item (Join-Path $repo "art-src\preview.png") $item
}

$manifest = Join-Path $dist "TheLastGallon-$version.sha256"
Get-ChildItem -Recurse -File $item | Sort-Object FullName | ForEach-Object {
    $h = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
    "$h  $($_.FullName.Substring($item.Length + 1).Replace('\', '/'))"
} | Set-Content -Encoding ascii $manifest
$zip = Join-Path $dist "TheLastGallon-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $item "*") -DestinationPath $zip
$count = (Get-ChildItem -Recurse -File $item).Count
Write-Host "package: $zip ($count files), manifest $manifest. Not uploaded."
# robocopy reports success codes 1-7; do not leak them as the script's exit code.
exit 0
