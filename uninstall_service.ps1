$ErrorActionPreference = "SilentlyContinue"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
} catch {}

$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges required." -ForegroundColor Red
    return
}

$svcName = "BB_JAVIS_Remote"
$installDir = "C:\ProgramData\BB_Javis"
$cfgFile = Join-Path $installDir "service_config.json"

if (Test-Path $cfgFile) {
    try {
        $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg -and $cfg.device_id -and $cfg.gatewayUrl -and $cfg.device_token_dpapi) {
            $encBytes = [Convert]::FromBase64String($cfg.device_token_dpapi)
            $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($encBytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
            $devToken = [System.Text.Encoding]::UTF8.GetString($plainBytes)
            $gw = $cfg.gatewayUrl.ToString().TrimEnd('/') + "/"
            $delDevUrl = $gw + "devices/$($cfg.device_id).json"
            $req = [System.Net.HttpWebRequest]::Create($delDevUrl)
            $req.Method = "DELETE"
            $req.Timeout = 5000
            $req.Headers["X-Javis-Key"] = $devToken
            $resp = $req.GetResponse()
            $resp.Close()
            Write-Host "[CLOUD] Deregistered device $($cfg.device_id) via Gateway." -ForegroundColor Green
        }
    } catch {}
}

$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
}

foreach ($procName in @("BBJavisService", "BBJavisTunnel", "cloudflared")) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "$installDir*" -or $procName -ne "cloudflared"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}

Get-Process -Name "powershell" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmd -and ($cmd -like "*BB_Javis*" -or $cmd -like "*start_remote_agent*")) {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[SUCCESS] BB_JAVIS Remote Service uninstalled cleanly." -ForegroundColor Green
