param(
  [string]$OutputDirectory = 'D:\LocalAIChat\fixtures',
  [string]$Ffmpeg = 'C:\Users\tristam\Documents\Codex\2026-09-23\make\work\app\tools\ffmpeg.exe'
)

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Add-Type -AssemblyName System.Drawing
$bitmap = [System.Drawing.Bitmap]::new(640, 400)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
try {
  $canvas.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $canvas.Clear([System.Drawing.Color]::FromArgb(93, 185, 246))
  $canvas.FillRectangle([System.Drawing.Brushes]::ForestGreen, 0, 280, 640, 120)
  $canvas.FillEllipse([System.Drawing.Brushes]::Gold, 480, 35, 110, 110)
  $canvas.FillEllipse([System.Drawing.Brushes]::Red, 175, 160, 210, 210)
  $canvas.FillRectangle([System.Drawing.Brushes]::SaddleBrown, 275, 135, 20, 55)
  $canvas.FillEllipse([System.Drawing.Brushes]::DarkGreen, 292, 130, 80, 35)
  $bitmap.Save((Join-Path $OutputDirectory 'red_apple_scene.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $canvas.Dispose()
  $bitmap.Dispose()
}

if (Test-Path -LiteralPath $Ffmpeg) {
  $video = Join-Path $OutputDirectory 'red_then_green.mp4'
  & $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=c=red:s=320x240:d=1:r=10' -f lavfi -i 'color=c=green:s=320x240:d=1:r=10' -filter_complex '[0:v][1:v]concat=n=2:v=1:a=0' -c:v libx264 -pix_fmt yuv420p $video
  if ($LASTEXITCODE -ne 0) { throw 'Could not create the two-color test video.' }
  $flash = Join-Path $OutputDirectory 'brief_blue_flash.mp4'
  & $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=c=red:s=320x240:d=1.5:r=24' -f lavfi -i 'color=c=blue:s=320x240:d=0.25:r=24' -f lavfi -i 'color=c=green:s=320x240:d=2.25:r=24' -filter_complex '[0:v][1:v][2:v]concat=n=3:v=1:a=0' -c:v libx264 -pix_fmt yuv420p $flash
  if ($LASTEXITCODE -ne 0) { throw 'Could not create the brief-change test video.' }
}

Get-ChildItem -LiteralPath $OutputDirectory | Select-Object Name,Length
