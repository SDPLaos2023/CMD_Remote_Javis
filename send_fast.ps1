# ==============================================================================
# CMD_Remote Fast CLI (Via Controller Turbo Bridge)
# Latency: Sub-Second (1.7 - 1.9s)
# ==============================================================================
param(
    [Parameter(Position=0)][string]$SecretKey = "2816",
    [Parameter(Position=1)][string]$Command = "whoami; Get-Date -Format 'yyyy-MM-dd HH:mm:ss'",
    [string]$Mode = "PowerShell",
    [int]$TimeoutSec = 15
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$bridgeHealth = "http://127.0.0.1:5999/api/health"
$bridgeExec = "http://127.0.0.1:5999/api/exec"

# Check if Bridge is online
$isBridgeUp = $false
try {
    $req = [System.Net.HttpWebRequest]::Create($bridgeHealth)
    $req.Timeout = 300
    $resp = $req.GetResponse()
    if ($resp.StatusCode -eq 200) { $isBridgeUp = $true }
    $resp.Close()
} catch {}

if (-not $isBridgeUp) {
    Write-Host "[WARNING] Turbo Bridge (Port 5999) is not running. Starting background bridge..." -ForegroundColor Yellow
    $bridgeScript = Join-Path $PSScriptRoot "cmd_remote_bridge.ps1"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$bridgeScript`""
    Start-Sleep -Milliseconds 800
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$payload = @{
    secret_key = $SecretKey
    command = $Command
    mode = $Mode
    timeout = $TimeoutSec
} | ConvertTo-Json -Compress

try {
    $req = [System.Net.HttpWebRequest]::Create($bridgeExec)
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.Timeout = ($TimeoutSec + 5) * 1000
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $req.ContentLength = $bytes.Length
    $st = $req.GetRequestStream()
    $st.Write($bytes, 0, $bytes.Length)
    $st.Close()

    $resp = $req.GetResponse()
    $rd = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $json = $rd.ReadToEnd()
    $rd.Close()
    $resp.Close()

    $sw.Stop()

    $res = $json | ConvertFrom-Json
    if ($res.status -eq "success") {
        if ($res.output) { Write-Output $res.output.Trim() }
        if ($res.error) { Write-Host $res.error.Trim() -ForegroundColor Red }
        Write-Host "`n[COMPLETED in $($sw.ElapsedMilliseconds)ms | Bridge Latency: $($res.latency_ms)ms]" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] $($res.error)" -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Failed to communicate with Bridge: $_" -ForegroundColor Red
}
