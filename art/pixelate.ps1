# Turns the toon renders into pixel-art sprites (art/renders/pixel_<animal>_full.png) and
# builds design-preview/toon-lineup.png (sticker row + pixel row for all 8 pilots).
#   powershell -NoProfile -File art/pixelate.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $PSScriptRoot "renders"
$animals = "duck","mouse","dog","cat","bear","raccoon","monkey","penguin"
$sw = 80; $sh = 117; $up = 5   # sprite size and preview scale

function Pixelate($src, $dst) {
  $img = [System.Drawing.Image]::FromFile($src)
  $small = New-Object System.Drawing.Bitmap $sw, $sh
  $g = [System.Drawing.Graphics]::FromImage($small)
  $g.InterpolationMode = "HighQualityBicubic"
  $g.DrawImage($img, 0, 0, $sw, $sh); $g.Dispose(); $img.Dispose()
  for ($y = 0; $y -lt $sh; $y++) { for ($x = 0; $x -lt $sw; $x++) {
    $c = $small.GetPixel($x, $y)
    if ($c.A -lt 110) { $small.SetPixel($x, $y, [System.Drawing.Color]::Transparent); continue }
    $q = { param($v) [Math]::Min(255, [int]([Math]::Round($v / 17.0) * 17)) }
    $small.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, (& $q $c.R), (& $q $c.G), (& $q $c.B)))
  } }
  $small.Save($dst)
  return $small
}

$cw = 300
$sheet = New-Object System.Drawing.Bitmap ($cw * 8), 1160
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.ColorTranslator]::FromHtml("#1b2140"))
$font = New-Object System.Drawing.Font "Segoe UI", 18, ([System.Drawing.FontStyle]::Bold)
$small = New-Object System.Drawing.Font "Segoe UI", 11
$br = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#e6f1ee"))
$dim = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#8fa6b0"))
$sf = New-Object System.Drawing.StringFormat; $sf.Alignment = "Center"
$g.DrawString("STICKER", $small, $dim, 10, 6); $g.DrawString("PIXEL", $small, $dim, 10, 660)
for ($i = 0; $i -lt 8; $i++) {
  $a = $animals[$i]; $x = $i * $cw
  $full = Join-Path $dir "toon_${a}_full.png"
  $g.InterpolationMode = "HighQualityBicubic"
  $f = [System.Drawing.Image]::FromFile($full); $g.DrawImage($f, $x + 10, 30, 280, 410); $f.Dispose()
  $f = [System.Drawing.Image]::FromFile((Join-Path $dir "toon_${a}_face.png")); $g.DrawImage($f, $x + 50, 440, 200, 200); $f.Dispose()
  $px = Pixelate $full (Join-Path $dir "pixel_${a}_full.png")
  $g.InterpolationMode = "NearestNeighbor"; $g.PixelOffsetMode = "Half"
  $g.DrawImage($px, $x + 150 - ($sw * 3.4 / 2), 680, $sw * 3.4, $sh * 3.4); $px.Dispose()
  $g.PixelOffsetMode = "Default"
  $name = (Get-Culture).TextInfo.ToTitleCase($a)
  $g.DrawString($name, $font, $br, [System.Drawing.RectangleF]::new($x, 1085, $cw, 32), $sf)
  if ($a -eq "penguin") { $g.DrawString("DEV only", $small, $dim, [System.Drawing.RectangleF]::new($x, 1118, $cw, 24), $sf) }
}
$out = Join-Path $root "design-preview\toon-lineup.png"
$sheet.Save($out); $g.Dispose(); $sheet.Dispose()
"saved $out"
