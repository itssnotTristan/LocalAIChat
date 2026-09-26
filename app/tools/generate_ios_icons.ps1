param(
    [Parameter(Mandatory = $true)]
    [string]$Source
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$iconDirectory = Join-Path $PSScriptRoot '..\ios\Runner\Assets.xcassets\AppIcon.appiconset'
$catalog = Get-Content (Join-Path $iconDirectory 'Contents.json') -Raw | ConvertFrom-Json
$sourceImage = [System.Drawing.Image]::FromFile((Resolve-Path $Source).Path)

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The icon source must be square.'
    }

    foreach ($entry in $catalog.images) {
        $points = [double]($entry.size -split 'x')[0]
        $scale = [int]($entry.scale -replace 'x', '')
        $pixels = [int][Math]::Round($points * $scale)
        $target = Join-Path $iconDirectory $entry.filename

        $bitmap = [System.Drawing.Bitmap]::new($pixels, $pixels, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Black)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.DrawImage($sourceImage, 0, 0, $pixels, $pixels)
            }
            finally {
                $graphics.Dispose()
            }

            $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
        }
    }
}
finally {
    $sourceImage.Dispose()
}
