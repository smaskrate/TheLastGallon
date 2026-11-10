<#
.SYNOPSIS
  Renders the tile sprites the mod ships (128x256 PNG) into the mod.
.DESCRIPTION
  One sprite: the diesel generator's, from the shape `diesel_generator` of
  tools/blender/pz_icon_props.py, rendered by tools/blender/pz_tile_sprite.py
  in the game's tile view and written as
  Contents/mods/TheLastGallon/common/media/textures/TLG/Tile_DieselGenerator.png.
  It also writes the tile sheet's definitions, media/tlg_generators.tiles
  (one tileset of one tile: the sprite tlg_generators_01_0, which the item
  TLG.DieselGenerator names as its WorldObjectSprite and mod.info lists as
  tiledef=tlg_generators 7341). The mod ships no texture pack: the picture
  is given to the sprite in Lua (Generators.loadSprites, D-036).
  The item's icon comes from the same shape (tools/make-model-icons.ps1).
.PARAMETER Blender
  blender.exe (default: the portable 4.5.15 LTS install).
#>
param([string]$Blender = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo "Contents\mods\TheLastGallon\common\media\textures\TLG\Tile_DieselGenerator.png"
if (-not $Blender) { $Blender = Join-Path $env:LOCALAPPDATA "Programs\Blender\blender-4.5.15-windows-x64\blender.exe" }
if (-not (Test-Path $Blender)) { throw "Blender not found: $Blender" }
& $Blender -b --factory-startup --python (Join-Path $PSScriptRoot "blender\pz_tile_sprite.py") -- DieselGenerator $out 2>&1 |
    Where-Object { "$_" -match "^PZT |Error|Traceback" } | ForEach-Object { Write-Host "$_" }
if (-not (Test-Path $out)) { throw "no sprite written" }
Write-Host "sprite written to $out"

# The tile sheet's definitions, as the game reads them (BC IsoWorld
# .LoadTileDefinitions): "tdef", version, the number of tilesets; for each,
# its name and its image's name (each ended by a line feed), columns, rows,
# the tileset's number in this file and its number of tiles; for each tile,
# its number of properties. Integers are 32 bits, low byte first. One
# tileset of one tile with no property: the sprite tlg_generators_01_0.
# mod.info names the file and its number among all mods' (tiledef=
# tlg_generators 7341; the game takes 100 to 8189).
$bytes = New-Object System.Collections.Generic.List[byte]
function Add-Int([int]$v) { $bytes.AddRange([BitConverter]::GetBytes($v)) }
function Add-Line([string]$s) { $bytes.AddRange([Text.Encoding]::ASCII.GetBytes($s + "`n")) }
$bytes.AddRange([Text.Encoding]::ASCII.GetBytes("tdef")); Add-Int 1; Add-Int 1
Add-Line "tlg_generators_01"; Add-Line "tlg_generators_01.png"; Add-Int 1; Add-Int 1; Add-Int 1; Add-Int 1; Add-Int 0
$tiles = Join-Path $repo "Contents\mods\TheLastGallon\common\media\tlg_generators.tiles"
[IO.File]::WriteAllBytes($tiles, $bytes.ToArray())
Write-Host "tile definitions written to $tiles ($($bytes.Count) bytes)"
