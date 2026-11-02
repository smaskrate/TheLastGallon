<#
.SYNOPSIS
  Draws the mod's own inventory icons (32x32 PNG) into the mod.
.DESCRIPTION
  Pixel art drawn here, pixel by pixel, so this script is the editable
  source. Each icon is written as
  Contents/mods/TheLastGallon/common/media/textures/Item_<Name>.png: an
  item's Icon = <Name> loads the texture Item_<Name> (BC Item.DoParam;
  docs/engine-capabilities.md G13). Rerunning writes the same files.

  Item_TLG_Fermenter: the fermentation vessel's own model (TLG.Fermenter,
  art-src/fermenter): a wooden barrel with blue-grey hoops, a lid with two
  battens, a white airlock on a black grommet and a brass tap. The colours
  follow that model's texture (staves about #6B543A, hoops about #636B76),
  lit from the upper left like vanilla's icons, with a dark outline.
.PARAMETER OutDir
  The textures folder written into (default: the mod's).
.PARAMETER Preview
  Also writes an 8x enlarged copy of each icon here, for looking at.
#>
param([string]$OutDir = "", [string]$Preview = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repo "Contents\mods\TheLastGallon\common\media\textures" }
Add-Type -AssemblyName System.Drawing

function Hex([string]$h) { [System.Drawing.ColorTranslator]::FromHtml($h) }

# Shading index 0 (shadow) to 4 (highlight) at a horizontal position t on a
# cylinder, -1 at its left edge and 1 at its right, lit from the upper left.
function Shade([double]$t) {
    $b = 1.0 - 0.9 * [Math]::Pow($t + 0.35, 2)
    if ($b -gt 0.85) { return 4 }
    if ($b -gt 0.6) { return 3 }
    if ($b -gt 0.3) { return 2 }
    if ($b -gt 0.0) { return 1 }
    return 0
}

function Save-Icon($cells, [string]$name) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt 32; $y++) {
        for ($x = 0; $x -lt 32; $x++) {
            $c = $cells[$x, $y]
            $bmp.SetPixel($x, $y, $(if ($c) { $c } else { [System.Drawing.Color]::FromArgb(0, 0, 0, 0) }))
        }
    }
    $bmp.Save((Join-Path $OutDir "Item_$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    if ($Preview) {
        $big = New-Object System.Drawing.Bitmap 256, 256
        $g = [System.Drawing.Graphics]::FromImage($big)
        $g.Clear((Hex "#7F7F7F"))
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.DrawImage($bmp, 0, 0, 256, 256)
        $g.Dispose()
        $big.Save((Join-Path $Preview "Item_${name}_x8.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $big.Dispose()
    }
    $bmp.Dispose()
}

# A 1-pixel outline around everything drawn (4-neighbours), as vanilla's icons have.
function Add-Outline($cells, $colour) {
    $edge = @()
    for ($y = 0; $y -lt 32; $y++) {
        for ($x = 0; $x -lt 32; $x++) {
            if ($cells[$x, $y]) { continue }
            foreach ($d in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
                $nx = $x + $d[0]; $ny = $y + $d[1]
                if ($nx -ge 0 -and $nx -lt 32 -and $ny -ge 0 -and $ny -lt 32 -and $cells[$nx, $ny]) { $edge += , @($x, $y); break }
            }
        }
    }
    foreach ($e in $edge) { $cells[$e[0], $e[1]] = $colour }
}

function Draw-Fermenter {
    $cells = New-Object 'object[,]' 32, 32
    $wood = @((Hex "#3A2A1B"), (Hex "#55402B"), (Hex "#6E5538"), (Hex "#86684A"), (Hex "#9B7C58"))
    $hoop = @((Hex "#4E5661"), (Hex "#69727E"), (Hex "#848E9A"), (Hex "#A3ACB7"), (Hex "#BCC4CD"))
    $lid = @((Hex "#4F3B27"), (Hex "#6A5136"), (Hex "#7F6243"), (Hex "#937452"))
    $batten = Hex "#3F2E1C"
    $cx = 15.5; $top = 9.5; $bottom = 27.5; $rx = 9.0; $ry = 3.2

    # Body: staves bulging 1.5 px at the middle, three hoops below the lid's
    # rim, a rounded base.
    for ($y = 0; $y -lt 32; $y++) {
        for ($x = 0; $x -lt 32; $x++) {
            $px = $x + 0.5; $py = $y + 0.5
            if ($py -lt $top) { continue }
            $t = [Math]::Min(1.0, ($py - $top) / ($bottom - $top))
            $hw = $rx + 1.5 * [Math]::Sin([Math]::PI * $t)
            $inBase = $py -gt $bottom -and ([Math]::Pow(($px - $cx) / $rx, 2) + [Math]::Pow(($py - $bottom) / $ry, 2)) -le 1.0
            if (-not ($inBase -or ($py -le $bottom -and [Math]::Abs($px - $cx) -le $hw))) { continue }
            $tx = [Math]::Max(-1.0, [Math]::Min(1.0, ($px - $cx) / $hw))
            $s = Shade $tx
            $isHoop = ($t -ge 0.20 -and $t -lt 0.30) -or ($t -ge 0.53 -and $t -lt 0.63) -or ($t -ge 0.86 -and $t -lt 0.96)
            if ($isHoop) { $cells[$x, $y] = $hoop[$s]; continue }
            # Stave joints: 12 staves, the four visible joints off the edges.
            $joint = $false
            foreach ($k in -0.707, -0.259, 0.259, 0.707) { if ([Math]::Abs($px - ($cx + $k * $hw)) -lt 0.5) { $joint = $true } }
            if ($joint) { $s = [Math]::Max(0, $s - 2) }
            if ($inBase) { $s = [Math]::Max(0, $s - 1) }
            $cells[$x, $y] = $wood[$s]
        }
    }

    # Lid: an ellipse over the body's top, lighter to the upper left and
    # darker at its front rim.
    for ($y = 0; $y -lt 32; $y++) {
        for ($x = 0; $x -lt 32; $x++) {
            $lu = ($x + 0.5 - $cx) / $rx; $lv = ($y + 0.5 - $top) / $ry
            if (($lu * $lu + $lv * $lv) -gt 1.0) { continue }
            $c = $lid[2]
            if ($lu -lt -0.25 -and $lv -lt 0.3) { $c = $lid[3] }
            if ($lv -gt 0.55) { $c = $lid[0] } elseif ($lu -gt 0.45) { $c = $lid[1] }
            $cells[$x, $y] = $c
        }
    }
    # Two cleats on the lid, running down to the right, lit along their tops.
    foreach ($cleat in @(@(@(8, 8), @(9, 8), @(10, 9), @(11, 9), @(12, 10)), @(@(21, 8), @(22, 9), @(23, 9)))) {
        # (The comma binds before the minus: the index needs its parentheses.)
        foreach ($p in $cleat) { $cells[$p[0], $p[1]] = $batten; $cells[$p[0], ($p[1] - 1)] = $lid[3] }
    }

    # Airlock: a capped white chamber on a narrow stem through a black
    # grommet, right of the lid's centre.
    $white = Hex "#EEEEEE"; $grey = Hex "#B9BDC1"; $black = Hex "#1B1B1B"
    foreach ($x in 17..20) { $cells[$x, 8] = $black }
    foreach ($y in 5..7) { $cells[18, $y] = $white; $cells[19, $y] = $grey }
    foreach ($y in 2..4) { $cells[17, $y] = $white; $cells[18, $y] = $white; $cells[19, $y] = $grey; $cells[20, $y] = $grey }
    $cells[18, 1] = $grey; $cells[19, 1] = $grey

    # Tap: a brass pipe out of the lower right staves, its spout turned down.
    $brass = Hex "#BFA26C"; $brassDark = Hex "#86703F"
    $cells[26, 21] = $brass; $cells[27, 21] = $brass; $cells[28, 21] = $brass
    $cells[26, 22] = $brassDark; $cells[27, 22] = $brassDark
    $cells[28, 22] = $brassDark; $cells[28, 23] = $brassDark

    Add-Outline $cells (Hex "#1E150C")
    Save-Icon $cells "TLG_Fermenter"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
if ($Preview) { New-Item -ItemType Directory -Force $Preview | Out-Null }
Draw-Fermenter
Write-Host "icons written to $OutDir"
