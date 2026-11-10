<#
.SYNOPSIS
  Reads sprites out of the game's texture packs (media/texturepacks/*.pack).
.DESCRIPTION
  Dot-source it for Get-PackSprite. A pack (BC TexturePackPage, version 1)
  is "PZPK", a version and a number of pages; each page is its name, a
  number of entries, a mask flag, the entries (name, then x, y, width and
  height in the page's picture, the offset inside the sprite's full frame
  and the frame's width and height) and the page's PNG with its length
  before it. Strings have their length before them; integers are 32 bits,
  low byte first.
  Get-PackSprite returns, for each name found, the sprite drawn in its
  full frame (a 128x256 tile keeps its place on the tile).
.PARAMETER Pack
  The pack file.
.PARAMETER Names
  Sprite names to read (exact). With -List, a regular expression: the
  matching names are returned with their page and frame, no picture.
#>
Add-Type -AssemblyName System.Drawing

function Get-PackSprite {
    param([string]$Pack, [string[]]$Names, [switch]$List)
    $fs = [IO.File]::OpenRead($Pack)
    $br = New-Object IO.BinaryReader($fs)
    $out = @{}
    try {
        $magic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($magic -ne "PZPK") { throw "$Pack is not a version 1 pack" }
        [void]$br.ReadInt32()
        $pages = $br.ReadInt32()
        for ($p = 0; $p -lt $pages; $p++) {
            $pageName = [Text.Encoding]::UTF8.GetString($br.ReadBytes($br.ReadInt32()))
            $count = $br.ReadInt32()
            [void]$br.ReadInt32()
            $wanted = @()
            for ($e = 0; $e -lt $count; $e++) {
                $name = [Text.Encoding]::UTF8.GetString($br.ReadBytes($br.ReadInt32()))
                $v = for ($k = 0; $k -lt 8; $k++) { $br.ReadInt32() }
                $entry = [pscustomobject]@{ Name = $name; Page = $pageName; X = $v[0]; Y = $v[1]; W = $v[2]; H = $v[3]
                    OX = $v[4]; OY = $v[5]; FW = $v[6]; FH = $v[7] }
                if ($List) { if ($name -match $Names[0]) { $out[$name] = $entry } }
                elseif ($Names -contains $name) { $wanted += $entry }
            }
            $length = $br.ReadInt32()
            if ($wanted.Count -eq 0) { [void]$fs.Seek($length, "Current"); continue }
            $ms = New-Object IO.MemoryStream(, $br.ReadBytes($length))
            $page = New-Object System.Drawing.Bitmap($ms)
            foreach ($w in $wanted) {
                $bmp = New-Object System.Drawing.Bitmap($w.FW, $w.FH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.DrawImage($page, (New-Object System.Drawing.Rectangle($w.OX, $w.OY, $w.W, $w.H)),
                    (New-Object System.Drawing.Rectangle($w.X, $w.Y, $w.W, $w.H)), [System.Drawing.GraphicsUnit]::Pixel)
                $g.Dispose()
                $out[$w.Name] = $bmp
            }
            $page.Dispose(); $ms.Dispose()
            if (-not $List -and $out.Count -eq $Names.Count) { break }
        }
    } finally { $br.Dispose(); $fs.Dispose() }
    return $out
}
