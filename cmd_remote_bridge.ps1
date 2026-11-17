# ==============================================================================
# CMD_Remote Controller Turbo Bridge (Local Zero-Trust Daemon)
# Port: 127.0.0.1:5999
# Delegates commands through Zero-Trust send_remote_command.ps1 (E2E + Gateway)
# ==============================================================================
param(
    [int]$Port = 5999,
    [string]$GatewayUrl = "https://bb-javis-gateway.apisit-yimboa.workers.dev/",
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

$senderScript = Join-Path $PSScriptRoot "send_remote_command.ps1"
if (-not (Test-Path $senderScript)) {
    throw "Missing send_remote_command.ps1 next to cmd_remote_bridge.ps1."
}

$script:TotalRequestsServed = 0
$script:StartTime = [DateTime]::UtcNow

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "[BRIDGE] Listening on $prefix (Zero-Trust E2E mode)" -ForegroundColor Green

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $script:TotalRequestsServed++
        $path = $request.Url.AbsolutePath

        if ($path -eq "/api/health") {
            $uptime = [math]::Round(([DateTime]::UtcNow - $script:StartTime).TotalSeconds, 1)
            $json = @{
                status          = "ok"
                engine          = "Zero-Trust Controller Bridge"
                uptime_sec      = $uptime
                requests_served = $script:TotalRequestsServed
            } | ConvertTo-Json -Compress
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        if ($path -eq "/api/exec" -and $request.HttpMethod -eq "POST") {
            $sr = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $reqBody = $sr.ReadToEnd()
            $sr.Close()
            $reqObj = $reqBody | ConvertFrom-Json
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            $argsList = @{
                DeviceId = $reqObj.secret_key
                Mode     = $(if ($reqObj.mode) { $reqObj.mode } else { "PowerShell" })
                SqlQuery = $reqObj.command
            }
            if ($GatewayUrl) { $argsList.GatewayUrl = $GatewayUrl }
            if ($ApiKey) { $argsList.ApiKey = $ApiKey }
            if ($reqObj.timeout) { $argsList.TimeoutSec = [int]$reqObj.timeout }

            $outText = (& $senderScript @argsList | Out-String).TrimEnd()
            $sw.Stop()
            $respJson = @{
                status     = "success"
                output     = $outText
                error      = ""
                latency_ms = $sw.ElapsedMilliseconds
            } | ConvertTo-Json -Compress
            $buf = [System.Text.Encoding]::UTF8.GetBytes($respJson)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        $response.StatusCode = 404
        $response.Close()
    } catch {
        try {
            $errJson = @{ status = "failed"; error = $_.Exception.Message } | ConvertTo-Json -Compress
            $buf = [System.Text.Encoding]::UTF8.GetBytes($errJson)
            $response.StatusCode = 500
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
        } catch {}
    }
}
