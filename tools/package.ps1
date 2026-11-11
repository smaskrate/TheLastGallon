<#
.SYNOPSIS
  Builds the release package (Workshop item layout) under dist/. Never uploads.
.DESCRIPTION
  1. Runs the gates that do not need the game: domain tests, Kahlua compile
     check (syntax + BOM), translation parity.
  2. Copies only the runtime package (Contents/mods/TheLastGallon/{42,common})
     plus player-facing docs into dist/TheLastGallon/Contents/mods/TheLastGallon,
     writes workshop.txt (visibility=private) and a SHA-256 manifest, and zips it
     (forward-slash entry names, sorted, stamped with the commit time).
     tools/rehearse-install.ps1 installs that zip into a fresh cache and plays it.
  3. Rejects files outside the allowed runtime extensions, any test/harness
     content and XML that does not parse. Publication is a separate, manual
     step (docs/release-checklist.md).
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
# The pictures the player guide shows. Developer documents link
# docs/evidence instead, which does not ship.
robocopy (Join-Path $repo "docs\images") (Join-Path $docsOut "images") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed for docs/images" }
# README.md is the developers' (its commands do not ship); the player guide
# says how to install.
foreach ($doc in "CHANGELOG.md", "NOTICE.md", "LICENSE.md") {
    if (Test-Path (Join-Path $repo $doc)) { Copy-Item (Join-Path $repo $doc) $docsOut }
}

# Content rules.
$allowed = @(".lua", ".txt", ".json", ".info", ".png", ".jpg", ".md", ".ogg", ".x", ".fbx", ".xml", ".tiles")
$bad = Get-ChildItem -Recurse -File $modOut | Where-Object {
    ($allowed -notcontains $_.Extension.ToLower()) -or ($_.FullName -match 'TLGHarness|\\tests\\|\\tools\\')
}
if ($bad) { $bad | ForEach-Object { Write-Host "REJECTED $($_.FullName)" }; throw "package contains disallowed files" }
# The game skips a pose file it cannot parse, with only a console line, so
# its node never plays (run 109: "--" inside a comment).
$badXml = @(Get-ChildItem -Recurse -File -Filter *.xml $modOut | Where-Object {
    try { [void]([xml](Get-Content -Raw -LiteralPath $_.FullName)); $false } catch { $true }
})
if ($badXml.Count -gt 0) { $badXml | ForEach-Object { Write-Host "XML ERROR $($_.FullName)" }; throw "package contains XML that does not parse" }

# The Workshop page's text (Steam's BBCode), offered by the game's uploader
# for review. Tags from the game's media/WorkshopTags.txt. Visibility stays
# private: publishing is the user's step, never this script's.
@"
version=1
title=The Last Gallon
description=Fuel that ages, takes up water and gathers dirt, and engines that feel it. Version $version for Project Zomboid Build 42.22.
description=
description=[h2]Fuel that goes bad[/h2]
description=[list]
description=[*]Fuel left behind by the old world slowly goes stale. How fast depends on what it is, how it is stored, how warm it gets and whether the container is sealed. Water and sediment get in too, and diesel can grow sludge.
description=[*]Look and smell, or take a sample with a sampling kit, to judge what you found. Filter it, drain the water, add stabilizer, seal it, clean old containers.
description=[*]Poor fuel makes engines hard to start and stalls them, costs a car power and wears car and generator engines. A sandbox option turns the stalls off.
description=[*]The wrong fuel damages an engine: diesel in a petrol engine, petrol or ethanol in a diesel, too much ethanol in an engine that is not converted. A sandbox option turns that damage off.
description=[*]About one gas station in ten holds water-contaminated fuel: sample before you fill up.
description=[/list]
description=
description=[h2]Make your own: ethanol[/h2]
description=[list]
description=[*]Ferment sugar, corn, potatoes or fruit in a fermentation vessel, distil the wash in a pot or reflux still, and dry it with quicklime in a drying column.
description=[*]Convert a generator or a car to flex fuel at the workshop, and run it on your ethanol.
description=[*]The machines follow the weather and the warmth where they stand: in winter, keep a fire fed near the fermenter.
description=[*]The Field Manual: Fuel Systems turns up in garages, gas stations, farms and bookstores.
description=[/list]
description=
description=[h2]Make your own: biodiesel[/h2]
description=[list]
description=[*]Distil wood into methanol in a wood retort, burn wood to ash and leach it into lye, react cooking oil with both, then wash and dry the biodiesel: five machines, each feeding the next.
description=[*]Building them takes Welding (2 to 5) or Carpentry 2, and the recipes are learned from the Biodiesel Handbook, found in loot, or by skill.
description=[*]Burn it in the Diesel Generator, found in loot beside the game's generators, or in a diesel vehicle.
description=[*]In new worlds, pickup vans, six-seat vans, radio vans and ambulances are diesel, and about one station pump in four gives diesel: read what a pump gives from its menu.
description=[/list]
description=
description=[h2]Good to know[/h2]
description=[list]
description=[*]Tested only on Project Zomboid 42.22.2, in single player and on a dedicated server (two players on one computer). Other builds are not supported.
description=[*]English and Italian.
description=[*]New and existing saves. Read the player guide before removing the mod: without it the game drops its machines and the ethanol in your containers (docs/player-guide.md in the mod folder).
description=[*]Diesel vehicles and diesel pumps appear only in worlds started with version 0.2.0 or later.
description=[*]Not in this version: wood gas, biogas, propane and electrical networks.
description=[/list]
description=
description=Created by smaskrate.
description=Licence: CC BY-NC-SA 4.0, except the supplied machine models, the carry animations and the diesel generator's pictures, which ship only as part of the mod (docs/LICENSE.md in the mod folder).
tags=Build 42;Realistic;Vehicles;Items
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
# The zip: entry names with forward slashes (ZIP APPNOTE 4.4.17; Compress-
# Archive in Windows PowerShell 5.1 writes backslashes, which unzip tools on
# other systems mishandle), in sorted order, every entry stamped with the
# time of the last commit that changed what ships, so a clean checkout
# builds the same bytes for the same content. Uncommitted changes are
# packaged too, and then the zip belongs to no commit: say so.
$zip = Join-Path $dist "TheLastGallon-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
$shipped = @("Contents", "docs/player-guide.md", "docs/support-matrix.md", "docs/migrations.md", "docs/images",
    "CHANGELOG.md", "NOTICE.md", "LICENSE.md", "art-src/preview.png", "tools/package.ps1")
$stamp = [DateTimeOffset]::Parse((& git -C $repo log -1 --format=%cI -- $shipped))
$commit = (& git -C $repo rev-parse --short HEAD)
$dirty = @(& git -C $repo status --porcelain -- $shipped).Count -gt 0
if ($dirty) { Write-Host "WARNING: uncommitted changes to shipped files: this zip is not the one commit $commit builds." }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$files = Get-ChildItem -Recurse -File $item | Sort-Object FullName
$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
try {
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $entry = $archive.CreateEntry($f.FullName.Substring($item.Length + 1).Replace('\', '/'),
                [System.IO.Compression.CompressionLevel]::Optimal)
            # Set before the entry is written: it is frozen afterwards.
            $entry.LastWriteTime = $stamp
            $out = $entry.Open()
            $in = [System.IO.File]::OpenRead($f.FullName)
            try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
        }
    } finally { $archive.Dispose() }
} finally { $fs.Dispose() }
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try { $backslashed = @($check.Entries | Where-Object { $_.FullName.Contains('\') }).Count } finally { $check.Dispose() }
if ($backslashed -gt 0) { throw "zip has $backslashed entry names with backslashes" }
$count = $files.Count
$from = if ($dirty) { "commit $commit plus uncommitted changes" } else { "commit $commit" }
Write-Host "package: $zip ($count files, $from), manifest $manifest. Not uploaded."
# robocopy reports success codes 1-7; do not leak them as the script's exit code.
exit 0
