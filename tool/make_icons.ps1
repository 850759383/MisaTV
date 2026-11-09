
# Generates the full icon set for MisaTV from one square PNG source.
# Usage: pwsh -File tool/make_icons.ps1 -Source <icon.png>
param(
  [string]$Source = "docs/icon/misatv-icon-1024.png"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not (Test-Path $Source)) { throw "source icon not found: $Source" }

$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source))

function New-Scaled([System.Drawing.Image]$img, [int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.DrawImage($img, 0, 0, $size, $size)
  $g.Dispose()
  return $bmp
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

# --- PNG bitmaps -----------------------------------------------------------
$sizes = @{ "mdpi" = 48; "hdpi" = 72; "xhdpi" = 96; "xxhdpi" = 144; "xxxhdpi" = 192 }
foreach ($k in $sizes.Keys) {
  $bmp = New-Scaled $src $sizes[$k]
  Save-Png $bmp ("android/app/src/main/res/mipmap-$k/ic_launcher.png")
  $bmp.Dispose()
}
$bmp = New-Scaled $src 256
Save-Png $bmp "assets/images/app_icon.png"
$bmp.Dispose()
foreach ($pair in @(@(192, "web/icons/Icon-192.png"), @(512, "web/icons/Icon-512.png"), @(32, "web/favicon.png"))) {
  $bmp = New-Scaled $src ([int]$pair[0])
  Save-Png $bmp ([string]$pair[1])
  $bmp.Dispose()
}
# Maskable: content confined to the inner 80% so Android's mask never clips it.
foreach ($size in 192, 512) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::White)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $inner = [int]($size * 0.8)
  $off = [int](($size - $inner) / 2)
  $g.DrawImage($src, $off, $off, $inner, $inner)
  $g.Dispose()
  Save-Png $bmp ("web/icons/Icon-maskable-$size.png")
  $bmp.Dispose()
}

# --- Multi-size .ico (BMP entries < 256px, PNG entry at 256px) -------------
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$entries = New-Object System.Collections.ArrayList
foreach ($s in $icoSizes) {
  $bmp = New-Scaled $src $s
  if ($s -ge 256) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    [void]$entries.Add(@{ Size = $s; Data = $ms.ToArray() })
  } else {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $bd.Stride
    $raw = New-Object byte[] ($stride * $s)
    [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $raw, 0, $raw.Length)
    $bmp.UnlockBits($bd)
    $maskRow = [int]([math]::Ceiling($s / 32.0) * 4)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $xorBytes = $s * $s * 4
    $maskBytes = $maskRow * $s
    $bw.Write([int]40); $bw.Write([int]$s); $bw.Write([int]($s * 2))
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]0)
    $bw.Write([int]($xorBytes + $maskBytes))
    $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $s - 1; $y -ge 0; $y--) { $bw.Write($raw, $y * $stride, $s * 4) }
    $bw.Write((New-Object byte[] $maskBytes))
    $bw.Flush()
    [void]$entries.Add(@{ Size = $s; Data = $ms.ToArray() })
  }
  $bmp.Dispose()
}

$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($out)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
  $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([int16]1); $w.Write([int16]32)
  $w.Write([int]$e.Data.Length); $w.Write([int]$offset)
  $offset += $e.Data.Length
}
foreach ($e in $entries) { $w.Write($e.Data) }
$w.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $root "windows/runner/resources/app_icon.ico"), $out.ToArray())
$w.Dispose(); $out.Dispose(); $src.Dispose()

# --- verify ---------------------------------------------------------------
$ic = New-Object System.Drawing.Icon((Join-Path $root "windows/runner/resources/app_icon.ico"))
"ico default frame: $($ic.Width)x$($ic.Height)"
$ic.Dispose()
Get-Item "windows/runner/resources/app_icon.ico", "assets/images/app_icon.png" |
  ForEach-Object { "$($_.Name): $($_.Length) bytes" }
