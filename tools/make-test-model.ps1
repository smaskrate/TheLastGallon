<#
.SYNOPSIS
  Writes the model-import test asset into the harness mod (spec section 21, G13).
.DESCRIPTION
  An original stand-in for the fermentation vessel, drawn entirely by this
  script (it is the editable source): a barrel with lid, airlock and tap as
  a DirectX text mesh (.x), its 256x256 texture and a 32x32 inventory icon.
  The outputs go to the dev-only harness mod, which tools/package.ps1 never
  packages. Rerunning writes the same files.

  Mesh: metres, Y up, origin at the centre of the base, no scale in the
  model script (vanilla CubePuzzle.x is authored the same way: a 4.9 cm
  cube with mesh = CubePuzzle and no scale). Body radius 0.28 m, height
  0.70 m (about 172 L); the airlock stands on the lid at +Z, the tap
  sticks out near the base at +X. Triangles wind as vanilla's: (b-a)x(c-a)
  points out of the surface.

  Texture (V runs down the image, as in DirectX):
    rows 0-191    barrel side, the body's top at row 0. U goes round from
                  the seam at +X (red stripe); a label with an up arrow and
                  "TOP" at U 0.375-0.625; a fully transparent window at U
                  0.80-0.90, rows 90-127.
    rows 192-255  four 64x64 tiles: lid (grey, black cross, a notch at the
                  tile's top), base (dark grey), airlock (pale blue, alpha
                  0.4), tap (red).
  A screenshot then shows which way the mesh faces, whether V is flipped,
  and whether the engine honours full and partial transparency.
.PARAMETER OutRoot
  The media folder written into (default: the harness mod's common/media).
#>
param([string]$OutRoot = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutRoot) { $OutRoot = Join-Path $repo "tests\ingame\TheLastGallonHarness\common\media" }
Add-Type -AssemblyName System.Drawing
$inv = [System.Globalization.CultureInfo]::InvariantCulture

$R = 0.28; $H = 0.70; $N = 24
$verts = New-Object System.Collections.ArrayList   # @(x, y, z, nx, ny, nz, u, v)
$tris = New-Object System.Collections.ArrayList    # @(a, b, c)

function Add-Vert([double]$x, [double]$y, [double]$z, [double]$nx, [double]$ny, [double]$nz, [double]$u, [double]$v) {
    [void]$verts.Add(@($x, $y, $z, $nx, $ny, $nz, $u, $v))
    return $verts.Count - 1
}
# Adds a triangle wound so that (b-a)x(c-a) points along the normal of a.
function Add-Tri([int]$a, [int]$b, [int]$c) {
    # PowerShell names ignore case: the vertices must not be called $A, $B, $C.
    $pa = $verts[$a]; $pb = $verts[$b]; $pc = $verts[$c]
    $e1 = @(($pb[0] - $pa[0]), ($pb[1] - $pa[1]), ($pb[2] - $pa[2]))
    $e2 = @(($pc[0] - $pa[0]), ($pc[1] - $pa[1]), ($pc[2] - $pa[2]))
    $nx = $e1[1] * $e2[2] - $e1[2] * $e2[1]
    $ny = $e1[2] * $e2[0] - $e1[0] * $e2[2]
    $nz = $e1[0] * $e2[1] - $e1[1] * $e2[0]
    if ($nx * $pa[3] + $ny * $pa[4] + $nz * $pa[5] -lt 0) { [void]$tris.Add(@($a, $c, $b)) } else { [void]$tris.Add(@($a, $b, $c)) }
}
# A cylinder's side, U across [u0,u1] and V from vTop (top) to vBottom.
function Add-Side([double]$cx, [double]$cz, [double]$r, [double]$y0, [double]$y1, [int]$n, [double]$u0, [double]$u1, [double]$vTop, [double]$vBottom) {
    $first = $verts.Count
    for ($i = 0; $i -le $n; $i++) {
        $t = 2 * [Math]::PI * $i / $n
        $c = [Math]::Cos($t); $s = [Math]::Sin($t)
        $u = $u0 + ($u1 - $u0) * $i / $n
        [void](Add-Vert ($cx + $r * $c) $y1 ($cz + $r * $s) $c 0 $s $u $vTop)
        [void](Add-Vert ($cx + $r * $c) $y0 ($cz + $r * $s) $c 0 $s $u $vBottom)
    }
    for ($i = 0; $i -lt $n; $i++) {
        $t0 = $first + 2 * $i; $b0 = $t0 + 1; $t1 = $t0 + 2; $b1 = $t0 + 3
        Add-Tri $t0 $b0 $t1
        Add-Tri $t1 $b0 $b1
    }
}
# A flat disk facing +Y (up) or -Y, mapped as a circle round (uc, vc).
function Add-Disk([double]$cx, [double]$cz, [double]$r, [double]$y, [int]$n, [double]$ny, [double]$uc, [double]$vc, [double]$ur) {
    $centre = Add-Vert $cx $y $cz 0 $ny 0 $uc $vc
    $first = $verts.Count
    for ($i = 0; $i -lt $n; $i++) {
        $t = 2 * [Math]::PI * $i / $n
        [void](Add-Vert ($cx + $r * [Math]::Cos($t)) $y ($cz + $r * [Math]::Sin($t)) 0 $ny 0 ($uc + $ur * [Math]::Cos($t)) ($vc + $ur * [Math]::Sin($t)))
    }
    for ($i = 0; $i -lt $n; $i++) { Add-Tri $centre ($first + $i) ($first + ($i + 1) % $n) }
}
# An axis-aligned box, every face sampling one texel (u, v).
function Add-Box([double]$x0, [double]$x1, [double]$y0, [double]$y1, [double]$z0, [double]$z1, [double]$u, [double]$v) {
    $faces = @(
        @(1, 0, 0, @(@($x1, $y0, $z0), @($x1, $y1, $z0), @($x1, $y1, $z1), @($x1, $y0, $z1))),
        @(-1, 0, 0, @(@($x0, $y0, $z0), @($x0, $y0, $z1), @($x0, $y1, $z1), @($x0, $y1, $z0))),
        @(0, 1, 0, @(@($x0, $y1, $z0), @($x0, $y1, $z1), @($x1, $y1, $z1), @($x1, $y1, $z0))),
        @(0, -1, 0, @(@($x0, $y0, $z0), @($x1, $y0, $z0), @($x1, $y0, $z1), @($x0, $y0, $z1))),
        @(0, 0, 1, @(@($x0, $y0, $z1), @($x1, $y0, $z1), @($x1, $y1, $z1), @($x0, $y1, $z1))),
        @(0, 0, -1, @(@($x0, $y0, $z0), @($x0, $y1, $z0), @($x1, $y1, $z0), @($x1, $y0, $z0))))
    foreach ($f in $faces) {
        $q = foreach ($p in $f[3]) { Add-Vert $p[0] $p[1] $p[2] $f[0] $f[1] $f[2] $u $v }
        Add-Tri $q[0] $q[1] $q[2]
        Add-Tri $q[0] $q[2] $q[3]
    }
}

Add-Side 0 0 $R 0 $H $N 0 1 0.002 0.748                      # body
Add-Disk 0 0 $R $H $N 1 0.125 0.875 0.109                    # lid
Add-Disk 0 0 $R 0 $N -1 0.375 0.875 0.109                    # base
Add-Side 0 0.12 0.025 $H ($H + 0.10) 8 0.625 0.625 0.875 0.875   # airlock tube
Add-Disk 0 0.12 0.025 ($H + 0.10) 8 1 0.625 0.875 0          # airlock top
Add-Box ($R - 0.01) ($R + 0.07) 0.05 0.10 -0.025 0.025 0.875 0.875   # tap

function F([double]$d) { $d.ToString("0.000000", $inv) }
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append(@"
xof 0303txt 0032

Material FermenterTestMat {
 1.000000;1.000000;1.000000;1.000000;;
 10.000000;
 0.000000;0.000000;0.000000;;
 0.000000;0.000000;0.000000;;
 TextureFilename {
  "FermenterTest.png";
 }
}

Frame FermenterTest {
 FrameTransformMatrix {
  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;
 }

 Mesh FermenterTest {

"@)
function Join-List($items, [scriptblock]$fmt) {
    $lines = for ($i = 0; $i -lt $items.Count; $i++) { "  " + (& $fmt $items[$i]) + $(if ($i -lt $items.Count - 1) { "," } else { ";" }) }
    return ($lines -join "`r`n") + "`r`n"
}
[void]$sb.Append("  $($verts.Count);`r`n")
[void]$sb.Append((Join-List $verts { param($v) "$(F $v[0]);$(F $v[1]);$(F $v[2]);" }))
[void]$sb.Append("  $($tris.Count);`r`n")
[void]$sb.Append((Join-List $tris { param($t) "3;$($t[0]),$($t[1]),$($t[2]);" }))
[void]$sb.Append("`r`n  MeshNormals {`r`n  $($verts.Count);`r`n")
[void]$sb.Append((Join-List $verts { param($v) "$(F $v[3]);$(F $v[4]);$(F $v[5]);" }))
[void]$sb.Append("  $($tris.Count);`r`n")
[void]$sb.Append((Join-List $tris { param($t) "3;$($t[0]),$($t[1]),$($t[2]);" }))
[void]$sb.Append("  }`r`n`r`n  MeshMaterialList {`r`n  1;`r`n  $($tris.Count);`r`n")
[void]$sb.Append((Join-List $tris { param($t) "0" }))
[void]$sb.Append("  { FermenterTestMat }`r`n  }`r`n`r`n  MeshTextureCoords {`r`n  $($verts.Count);`r`n")
[void]$sb.Append((Join-List $verts { param($v) "$(F $v[6]);$(F $v[7]);" }))
[void]$sb.Append("  }`r`n }`r`n}`r`n")

$meshDir = Join-Path $OutRoot "models_X\TLGHarness"
$texDir = Join-Path $OutRoot "textures\TLGHarness"
New-Item -ItemType Directory -Force $meshDir, $texDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $meshDir "FermenterTest.x"), $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

function Brush([int]$a, [int]$r, [int]$g, [int]$b) { New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $r, $g, $b)) }
function Pt([int]$x, [int]$y) { New-Object System.Drawing.Point $x, $y }
$wood = Brush 255 139 90 43; $stave = Brush 255 107 68 35; $hoop = Brush 255 58 58 58
$red = Brush 255 200 30 30; $white = Brush 255 240 240 235; $black = Brush 255 0 0 0
$grey = Brush 255 150 150 150; $dark = Brush 255 70 70 70; $clear = Brush 0 0 0 0
$airlock = Brush 102 170 210 255; $airlockSolid = Brush 255 170 210 255

$bmp = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.FillRectangle($clear, 0, 0, 256, 256)
$g.FillRectangle($wood, 0, 0, 256, 192)
for ($x = 0; $x -lt 256; $x += 16) { $g.FillRectangle($stave, $x, 0, 2, 192) }
$g.FillRectangle($hoop, 0, 18, 256, 10)
$g.FillRectangle($hoop, 0, 164, 256, 10)
$g.FillRectangle($red, 0, 0, 10, 192)
$g.FillRectangle($white, 96, 44, 64, 76)
$g.FillPolygon($black, [System.Drawing.Point[]]@((Pt 128 50), (Pt 144 68), (Pt 134 68), (Pt 134 86), (Pt 122 86), (Pt 122 68), (Pt 112 68)))
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$font = New-Object System.Drawing.Font "Arial", 14, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString("TOP", $font, $black, 111, 94)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.FillRectangle($clear, 205, 90, 26, 38)
$g.FillRectangle($grey, 0, 192, 64, 64)
$g.FillRectangle($black, 30, 196, 4, 56)
$g.FillRectangle($black, 4, 222, 56, 4)
$g.FillPolygon($black, [System.Drawing.Point[]]@((Pt 24 198), (Pt 40 198), (Pt 32 208)))
$g.FillRectangle($dark, 64, 192, 64, 64)
$g.FillRectangle($airlock, 128, 192, 64, 64)
$g.FillRectangle($red, 192, 192, 64, 64)
$g.Dispose()
$bmp.Save((Join-Path $texDir "FermenterTest.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$ico = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($ico)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.FillRectangle($clear, 0, 0, 32, 32)
$g.FillRectangle($wood, 9, 9, 14, 20)
foreach ($x in 12, 16, 20) { $g.FillRectangle($stave, $x, 9, 1, 20) }
$g.FillRectangle($hoop, 9, 11, 14, 2)
$g.FillRectangle($hoop, 9, 25, 14, 2)
$g.FillRectangle($grey, 8, 7, 16, 3)
$g.FillRectangle($airlockSolid, 18, 2, 3, 5)
$g.FillRectangle($red, 23, 23, 3, 2)
$g.Dispose()
$ico.Save((Join-Path $OutRoot "textures\Item_TLGHarness_FermenterTest.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$ico.Dispose()
Write-Host "mesh: $($verts.Count) vertices, $($tris.Count) triangles"
