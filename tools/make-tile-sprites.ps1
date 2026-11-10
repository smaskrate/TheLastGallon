<#
.SYNOPSIS
  Makes the diesel generator's tile sprite, its icon and the mod's tile
  definitions.
.DESCRIPTION
  The diesel generator looks like vanilla's red generator in another
  colour (the owner's choice of 2026-11-10, D-036). This reads vanilla's
  sprite appliances_misc_01_0 (Tiles2x.pack) and its icon Item_Generator
  (UI2.pack) out of the game's own texture packs (tools/pack-sprites.ps1)
  and turns their red to a dark green: a pixel whose hue is within 30
  degrees of red and whose saturation is over 0.2 gets hue 110, 0.6 of
  its saturation and 0.75 of its lightness; every other pixel is kept. It
  writes
    media/textures/TLG/Tile_DieselGenerator.png   (128x256, the tile's frame)
    media/textures/Item_TLG_DieselGenerator.png   (32x32)
  and the tile sheet's definitions, media/tlg_generators.tiles (one
  tileset of one tile: the sprite tlg_generators_01_0, which the item
  TLG.DieselGenerator names as its WorldObjectSprite and mod.info lists as
  tiledef=tlg_generators 7341). The mod ships no texture pack: the picture
  is given to the sprite in Lua (Generators.loadSprites).
  Both pictures are derived from the game's art and are for use with the
  game only (LICENSE.md).
.PARAMETER GameDir
  Project Zomboid install directory. Defaults to $env:PZ_GAME_DIR, then to
  the directory two levels above this repository.
#>
param([string]$GameDir = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = $env:PZ_GAME_DIR }
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $repo "..\..")).Path }
$packs = Join-Path $GameDir "media\texturepacks"
$media = Join-Path $repo "Contents\mods\TheLastGallon\common\media"
. (Join-Path $PSScriptRoot "pack-sprites.ps1")

function Convert-HslToColor([int]$a, [double]$h, [double]$s, [double]$l) {
    $c = (1 - [math]::Abs(2 * $l - 1)) * $s
    $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1))
    $m = $l - $c / 2
    $r, $g, $b = switch ([int][math]::Floor($h / 60) % 6) {
        0 { $c, $x, 0 } 1 { $x, $c, 0 } 2 { 0, $c, $x } 3 { 0, $x, $c } 4 { $x, 0, $c } default { $c, 0, $x }
    }
    return [System.Drawing.Color]::FromArgb($a, [int][math]::Round(255 * ($r + $m)), [int][math]::Round(255 * ($g + $m)),
        [int][math]::Round(255 * ($b + $m)))
}

# Red to dark green, in place; returns the number of pixels changed.
function Set-DieselColours([System.Drawing.Bitmap]$bmp) {
    $changed = 0
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $p = $bmp.GetPixel($x, $y)
            if ($p.A -eq 0) { continue }
            $h, $s, $l = $p.GetHue(), $p.GetSaturation(), $p.GetBrightness()
            if (($h -le 30 -or $h -ge 330) -and $s -gt 0.2) {
                $bmp.SetPixel($x, $y, (Convert-HslToColor $p.A 110 ($s * 0.6) ($l * 0.75)))
                $changed++
            }
        }
    }
    return $changed
}

$jobs = @(
    @{ Pack = "Tiles2x.pack"; Name = "appliances_misc_01_0"; Out = (Join-Path $media "textures\TLG\Tile_DieselGenerator.png") },
    @{ Pack = "UI2.pack"; Name = "Item_Generator"; Out = (Join-Path $media "textures\Item_TLG_DieselGenerator.png") }
)
foreach ($j in $jobs) {
    $got = Get-PackSprite -Pack (Join-Path $packs $j.Pack) -Names $j.Name
    $bmp = $got[$j.Name]
    if (-not $bmp) { throw "$($j.Name) not found in $($j.Pack)" }
    $n = Set-DieselColours $bmp
    $bmp.Save($j.Out, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "$($j.Name) -> $($j.Out): $($bmp.Width)x$($bmp.Height), $n pixels recoloured"
    $bmp.Dispose()
}

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
$tiles = Join-Path $media "tlg_generators.tiles"
[IO.File]::WriteAllBytes($tiles, $bytes.ToArray())
Write-Host "tile definitions written to $tiles ($($bytes.Count) bytes)"
