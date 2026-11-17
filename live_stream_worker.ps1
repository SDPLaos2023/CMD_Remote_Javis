# ==============================================================================
# CMD_Remote Adaptive Live Screen Worker (Gateway-Authenticated)
# ==============================================================================
param(
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [Parameter(Mandatory = $true)][string]$GatewayUrl,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [int]$Fps = 6,
    [int]$MaxFrames = 300
)

if ($GatewayUrl -notlike "*/") { $GatewayUrl += "/" }

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$tmp = Join-Path $env:TEMP "live_frame_$DeviceId.jpg"
$url = "${GatewayUrl}jobs/$DeviceId/live_frame.json"
$delayMs = [int](1000 / $Fps)

for ($f = 0; $f -lt $MaxFrames; $f++) {
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $g.Dispose()
    $bmp.Dispose()

    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    $b64 = [Convert]::ToBase64String($bytes)
    $payload = '{"frame":' + $f + ',"timestamp":"' + [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") + '","image":"' + $b64 + '"}'

    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "PUT"
        $req.Timeout = 1200
        $req.KeepAlive = $true
        $req.Headers["X-Javis-Key"] = $ApiKey
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
