<#
.SYNOPSIS
  Makes the release art: the Workshop preview (art-src/preview.png) and the
  mod list's poster and icon (Contents/mods/TheLastGallon/42/poster.png and
  icon.png).
.DESCRIPTION
  1. tools/blender/pz_preview.py renders the mod's own fourteen models (the
     nine machines, and the fuel filter, the sampling kit, the yeast
     starter, the fuel stabilizer and the manual) at their in-game
     scales, 1024x1024 with a transparent background, into a temporary
     folder. The Diesel Generator and the Biodiesel Handbook have no model
     of their own and are not in the picture.
  2. That render is laid over a dusk gradient with a warm glow behind the
     machines, and the title is drawn above them (Bahnschrift SemiBold
     Condensed and Stencil, fonts installed with Windows and Office), at
     1024x1024.
  3. The picture is reduced to 256x256 (the Workshop uploader wants exactly
     that, no larger than 1000 KB: UI_WorkshopError_Preview* in the game's
     UI.json) and written as the preview and the poster. The icon is the
     fermenter's inventory icon (Item_TLG_Fermenter.png), copied.
  No game asset is drawn or copied. The script checks the size and bytes of
  what it wrote.
.PARAMETER Blender
  blender.exe (default: the portable 4.5.15 LTS install).
.PARAMETER Keep
  A folder to keep the 1024x1024 render and picture in (default: none).
#>
param([string]$Blender = "", [string]$Keep = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$mod = Join-Path $repo "Contents\mods\TheLastGallon"
$media = Join-Path $mod "common\media"
if (-not $Blender) { $Blender = Join-Path $env:LOCALAPPDATA "Programs\Blender\blender-4.5.15-windows-x64\blender.exe" }
if (-not (Test-Path $Blender)) { throw "Blender not found: $Blender" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("tlg_preview_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $work | Out-Null
$render = Join-Path $work "render.png"
& $Blender -b --factory-startup --python (Join-Path $PSScriptRoot "blender\pz_preview.py") -- $media $render 1024 |
    Where-Object { $_ -match '^PZP|Error|Traceback' } | ForEach-Object { Write-Host $_ }
if (-not (Test-Path $render)) { throw "the render was not written" }

Add-Type -AssemblyName System.Drawing
$S = 1024
$big = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($big)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
function C([int]$r, [int]$gr, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $gr, $b) }

# Dusk: dark at the top, an amber band low behind the machines, dark ground.
$rect = New-Object System.Drawing.Rectangle(0, 0, $S, $S)
$sky = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (C 0 0 0), (C 0 0 0), 90.0)
$blend = New-Object System.Drawing.Drawing2D.ColorBlend(5)
$blend.Colors = @((C 22 17 14), (C 40 27 19), (C 104 58 24), (C 46 31 21), (C 17 13 11))
$blend.Positions = @(0.0, 0.40, 0.62, 0.80, 1.0)
$sky.InterpolationColors = $blend
$g.FillRectangle($sky, $rect)
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse(-80, 380, $S + 160, 560)
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glow.CenterColor = C 214 120 44 120
$glow.SurroundColors = @((C 214 120 44 0))
$glow.CenterPoint = New-Object System.Drawing.PointF(($S / 2), 640)
$g.FillPath($glow, $glowPath)

$machines = [System.Drawing.Image]::FromFile($render)
$g.DrawImage($machines, 0, 0, $S, $S)
$machines.Dispose()

# Darker corners.
$vigPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$vigPath.AddEllipse(-260, -260, $S + 520, $S + 520)
$vig = New-Object System.Drawing.Drawing2D.PathGradientBrush($vigPath)
$vig.CenterColor = C 0 0 0 0
$vig.SurroundColors = @((C 0 0 0 200))
$vig.FocusScales = New-Object System.Drawing.PointF(0.55, 0.55)
$g.FillPath($vig, $vigPath)

# The title, centred, with a soft shadow.
function TitleLine([string]$text, [string]$family, [float]$px, [float]$top, [float]$track) {
    $fam = New-Object System.Drawing.FontFamily($family)
    # Winding: Bahnschrift's outlines overlap, and the default alternate
    # fill leaves holes where they do.
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Winding)
    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $x = 0.0
    foreach ($ch in $text.ToCharArray()) {
        $one = New-Object System.Drawing.Drawing2D.GraphicsPath
        $one.AddString([string]$ch, $fam, [int][System.Drawing.FontStyle]::Regular, $px, (New-Object System.Drawing.PointF(0, 0)), $fmt)
        $b = $one.GetBounds()
        $m = New-Object System.Drawing.Drawing2D.Matrix
        if ($ch -eq ' ') { $x += $px * 0.25; continue }
        $m.Translate($x - $b.X, 0)
        $one.Transform($m)
        $path.AddPath($one, $false)
        $x += $b.Width + $track
    }
    $b = $path.GetBounds()
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(($S - $b.Width) / 2 - $b.X, $top - $b.Y)
    $path.Transform($m)
    return $path
}
$line1 = TitleLine "THE LAST" "Bahnschrift SemiBold Condensed" 112 70 16
$line2 = TitleLine "GALLON" "Stencil" 236 196 10
foreach ($p in $line1, $line2) {
    foreach ($o in @(@(8, 0.25), @(5, 0.35), @(3, 0.5))) {
        $m = New-Object System.Drawing.Drawing2D.Matrix
        $m.Translate($o[0], $o[0])
        $sh = $p.Clone()
        $sh.Transform($m)
        $shade = C 0 0 0 ([int](255 * $o[1]))
        $g.FillPath((New-Object System.Drawing.SolidBrush($shade)), $sh)
    }
}
$g.FillPath((New-Object System.Drawing.SolidBrush((C 236 222 196))), $line1)
$g.FillPath((New-Object System.Drawing.SolidBrush((C 240 168 70))), $line2)
$g.Dispose()

$small = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gs = [System.Drawing.Graphics]::FromImage($small)
$gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gs.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gs.DrawImage($big, (New-Object System.Drawing.Rectangle(0, 0, 256, 256)), 0, 0, $S, $S, [System.Drawing.GraphicsUnit]::Pixel)
$gs.Dispose()

$preview = Join-Path $repo "art-src\preview.png"
$poster = Join-Path $mod "42\poster.png"
$icon = Join-Path $mod "42\icon.png"
$small.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$small.Dispose()
Copy-Item $preview $poster -Force
Copy-Item (Join-Path $media "textures\Item_TLG_Fermenter.png") $icon -Force
if ($Keep) {
    New-Item -ItemType Directory -Force $Keep | Out-Null
    Copy-Item $render (Join-Path $Keep "render-1024.png") -Force
    $big.Save((Join-Path $Keep "preview-1024.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}
$big.Dispose()
Remove-Item -Recurse -Force $work

foreach ($f in $preview, $poster, $icon) {
    $img = [System.Drawing.Image]::FromFile($f)
    $w = $img.Width; $h = $img.Height
    $img.Dispose()
    $len = (Get-Item $f).Length
    $sha = (Get-FileHash -Algorithm SHA256 $f).Hash
    Write-Host ("{0}: {1}x{2}, {3:N0} bytes, SHA-256 {4}" -f $f.Substring($repo.Length + 1), $w, $h, $len, $sha)
}
$img = [System.Drawing.Image]::FromFile($preview)
try { if ($img.Width -ne 256 -or $img.Height -ne 256) { throw "preview.png is not 256x256" } } finally { $img.Dispose() }
if ((Get-Item $preview).Length -gt 1000 * 1024) { throw "preview.png is larger than 1000 KB" }
