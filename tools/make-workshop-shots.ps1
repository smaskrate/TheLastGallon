<#
.SYNOPSIS
  Cuts the Workshop page's screenshots out of the harness's screenshots.
.DESCRIPTION
  The harness photographs the whole 1280x720 window
  (Core.TakeFullScreenshot, <cachedir>/Screenshots). The interface shots
  come from the docs-shots mode; they carry the debug build's marks (the
  red bug button at the lower left, "God Mode" and the coordinates at the
  lower right), which the cuts leave out. The scene shots come from the
  biodiesel, gas-wood, diesel-generator and machine-models modes, taken
  with the interface hidden.
  Each cut is a 16:9 rectangle of its source, saved as a JPEG in
  art-src/workshop. Nothing is scaled.
.PARAMETER Source
  Folder of the harness's screenshots (default: the development cache's).
.PARAMETER Out
  Folder the cuts are written to (default: art-src/workshop).
#>
param([string]$Source = "", [string]$Out = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path $env:LOCALAPPDATA "TheLastGallon\devcache\Screenshots" }
if (-not $Out) { $Out = Join-Path $repo "art-src\workshop" }
Add-Type -AssemblyName System.Drawing

# name, source, x, y, width, height
$cuts = @(
    @("01-fuel-menu",          "tlg_rtds_fuel_menu.png",            340,  30, 912, 513),
    @("02-kit-sample-result",  "tlg_rtds_kit_result.png",           240, 105, 800, 450),
    @("03-what-i-know",        "tlg_rtds_what_i_know.png",          240, 105, 800, 450),
    @("04-machine-menu",       "tlg_rtds_machine_menu.png",         400,  20, 860, 484),
    @("05-machine-status",     "tlg_rtds_vessel_status.png",        240, 105, 800, 450),
    @("06-workshop-menu",      "tlg_rtds_workshop_menu.png",        380,  20, 860, 484),
    @("07-project-status",     "tlg_rtds_project_status.png",       240, 105, 800, 450),
    @("08-crafting-window",    "tlg_rtds_crafting_window.png",      160,   0, 928, 522),
    @("09-item-tooltip",       "tlg_rtds_tooltip_pot_still.png",      0,   0, 672, 378),
    @("10-ethanol-machines",   "tlg_rtmm_beside_column_pot.png",     60, 135, 1040, 585),
    @("11-machines-in-a-row",  "tlg_rtbd_row.png",                  200, 170, 960, 540),
    @("12-wood-gasifier",      "tlg_rtgy_zoom_05.png",              400, 100, 800, 450),
    @("13-diesel-generators",  "tlg_rtdg_generators.png",           110, 190, 800, 450)
)

New-Item -ItemType Directory -Force $Out | Out-Null
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$params = New-Object System.Drawing.Imaging.EncoderParameters 1
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]92)
$failed = 0
foreach ($c in $cuts) {
    $path = Join-Path $Source $c[1]
    if (-not (Test-Path $path)) { Write-Host "MISSING $($c[1])"; $failed++; continue }
    $src = [System.Drawing.Bitmap]::FromFile($path)
    try {
        $rect = New-Object System.Drawing.Rectangle $c[2], $c[3], $c[4], $c[5]
        if ($rect.Right -gt $src.Width -or $rect.Bottom -gt $src.Height) {
            Write-Host "OUTSIDE $($c[1]): $($src.Width)x$($src.Height), cut $($c[2]),$($c[3]) $($c[4])x$($c[5])"; $failed++; continue
        }
        $cut = $src.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $file = Join-Path $Out ($c[0] + ".jpg")
        $cut.Save($file, $codec, $params)
        $cut.Dispose()
        Write-Host ("{0}.jpg {1}x{2} from {3} ({4}, {5} KB)" -f $c[0], $c[4], $c[5], $c[1],
            (Get-Item $path).LastWriteTime.ToString("yyyy-MM-dd HH:mm"), [math]::Round((Get-Item $file).Length / 1KB))
    } finally { $src.Dispose() }
}
if ($failed -gt 0) { Write-Host "$failed cut(s) not made"; exit 1 }
