<#
.SYNOPSIS
  Builds the floor models of the sampling kit, the yeast starter, the fuel
  stabilizer and the manual (FBX and texture) into the mod.
.DESCRIPTION
  tools/blender/pz_prop_models.py builds each from the shapes its icon is
  rendered from (tools/blender/pz_icon_props.py), as it lies on the floor,
  and writes media/models_X/TLG/<Name>.fbx and media/textures/TLG/<Name>.png:
  the kind of FBX the supplied models are, 1.0 along its largest side, and
  a palette texture of flat colours. The model scripts (TLG_models.txt)
  set each one's true size. A rebuild writes the same textures; each FBX
  differs only in the time it was written.
.PARAMETER Blender
  blender.exe (default: the portable 4.5.15 LTS install).
.PARAMETER OutRoot
  The media folder written into (default: the mod's).
#>
param([string]$Blender = "", [string]$OutRoot = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Blender) { $Blender = Join-Path $env:LOCALAPPDATA "Programs\Blender\blender-4.5.15-windows-x64\blender.exe" }
if (-not $OutRoot) { $OutRoot = Join-Path $repo "Contents\mods\TheLastGallon\common\media" }
if (-not (Test-Path $Blender)) { throw "Blender not found: $Blender" }
$models = Join-Path $OutRoot "models_X\TLG"
$textures = Join-Path $OutRoot "textures\TLG"
New-Item -ItemType Directory -Force $models, $textures | Out-Null

$start = Get-Date
# The FBX ids come from Python's string hash: a fixed seed, which Blender
# reads only with --python-use-system-env, gives the same ids each build.
$seed = $env:PYTHONHASHSEED
$env:PYTHONHASHSEED = "0"
try {
    & $Blender -b --factory-startup --python-use-system-env --python (Join-Path $PSScriptRoot "blender\pz_prop_models.py") `
        -- $models $textures 2>&1 | Where-Object { "$_" -match "^PZP |Error|Traceback" } | ForEach-Object { Write-Host "$_" }
} finally {
    $env:PYTHONHASHSEED = $seed
}
foreach ($name in "FuelSampleKit", "YeastStarter", "FuelStabilizer", "ManualFuelSystems",
        "WoodRetort", "AshBarrel", "LyeLeacher", "BiodieselReactor", "BiodieselWashTank") {
    foreach ($file in (Join-Path $models "$name.fbx"), (Join-Path $textures "$name.png")) {
        if (-not (Test-Path $file) -or (Get-Item $file).LastWriteTime -lt $start) { throw "not written: $file" }
    }
}
Write-Host "floor models written to $models and $textures"
