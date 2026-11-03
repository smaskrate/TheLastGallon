<#
.SYNOPSIS
  Renders the inventory icons of the items whose models were supplied
  (32x32 PNG) into the mod.
.DESCRIPTION
  Each icon is rendered by tools/blender/pz_icon.py from the item's shipped
  model and texture (media/models_X/TLG/<Name>.fbx, media/textures/TLG/
  <Name>.png) and written as
  Contents/mods/TheLastGallon/common/media/textures/Item_TLG_<Name>.png:
  an item's Icon = TLG_<Name> loads the texture Item_TLG_<Name> (BC
  Item.DoParam; docs/engine-capabilities.md G13). The view of each was
  chosen by eye at 32 pixels: the pot still and the drying column from a
  little right of the front, the reflux still from its left side (its
  column upright and its arm clear of it), the filter from above its lid.
  The fermenter's icon is drawn by tools/make-icons.ps1 instead.
.PARAMETER Blender
  blender.exe (default: the portable 4.5.15 LTS install).
.PARAMETER OutDir
  The textures folder written into (default: the mod's).
#>
param([string]$Blender = "", [string]$OutDir = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$media = Join-Path $repo "Contents\mods\TheLastGallon\common\media"
if (-not $Blender) { $Blender = Join-Path $env:LOCALAPPDATA "Programs\Blender\blender-4.5.15-windows-x64\blender.exe" }
if (-not $OutDir) { $OutDir = Join-Path $media "textures" }
if (-not (Test-Path $Blender)) { throw "Blender not found: $Blender" }

# Name, azimuth (degrees round from the model's front), elevation.
$views = @(
    @("PotStill", 15, 20),
    @("RefluxStill", -70, 15),
    @("DryingColumn", 15, 20),
    @("FuelFilter", 20, 25)
)
foreach ($v in $views) {
    $name = $v[0]
    $out = Join-Path $OutDir "Item_TLG_$name.png"
    & $Blender -b --factory-startup --python (Join-Path $PSScriptRoot "blender\pz_icon.py") -- `
        (Join-Path $media "models_X\TLG\$name.fbx") (Join-Path $media "textures\TLG\$name.png") $out $v[1] $v[2] 2>&1 |
        Where-Object { "$_" -match "^PZI |Error|Traceback" } | ForEach-Object { Write-Host "$_" }
    if (-not (Test-Path $out)) { throw "no icon written for $name" }
}
Write-Host "icons written to $OutDir"
