param(
    [string]$GatewayUrl = "",
    [string]$DeviceName = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "      BB_JAVIS ZERO-TRUST - BACKGROUND SERVICE INSTALLER              " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges required." -ForegroundColor Red
    return
}

$svcName = "BB_JAVIS_Remote"
$installDir = "C:\ProgramData\BB_Javis"
if (-not (Test-Path $installDir)) {
    $null = New-Item -ItemType Directory -Path $installDir -Force
}

# Restrict directory ACL to SYSTEM and Administrators only
& icacls $installDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" 2>&1 | Out-Null

$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
}

foreach ($procName in @("BBJavisService", "BBJavisTunnel")) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmd -like "*BB_Javis*" -or $cmd -like "*start_remote_agent*"
    } catch { $false }
} | Stop-Process -Force -ErrorAction SilentlyContinue

$localAgent = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "start_remote_agent.ps1" } else { $null }
$targetAgent = Join-Path $installDir "start_remote_agent.ps1"

if ($localAgent -and (Test-Path $localAgent)) {
    Copy-Item $localAgent $targetAgent -Force
    $srcScripts = Join-Path $PSScriptRoot "scripts"
    if (Test-Path $srcScripts) {
        $dstScripts = Join-Path $installDir "scripts"
        if (-not (Test-Path $dstScripts)) { $null = New-Item -ItemType Directory -Path $dstScripts -Force }
        Copy-Item (Join-Path $srcScripts "lib_javis_*.ps1") $dstScripts -Force -ErrorAction SilentlyContinue
    }
} else {
    $embeddedGzipBase64 = "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"
    if (-not [string]::IsNullOrWhiteSpace($embeddedGzipBase64) -and -not $embeddedGzipBase64.StartsWith("__EMBEDDED")) {
        $gzBytes = [System.Convert]::FromBase64String($embeddedGzipBase64)
        $msIn = New-Object System.IO.MemoryStream(,$gzBytes)
        $gzStream = New-Object System.IO.Compression.GZipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
        $msOut = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 8192
        while (($read = $gzStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $msOut.Write($buffer, 0, $read)
        }
        $gzStream.Dispose()
        $msIn.Dispose()
        [System.IO.File]::WriteAllBytes($targetAgent, $msOut.ToArray())
        $msOut.Dispose()
    } else {
        throw "No local start_remote_agent.ps1 or embedded payload available."
    }
}

$csSourcePath = Join-Path $installDir "BBJavisService.cs"
$csCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;

namespace BBJavisService
{
    public class JavisService : ServiceBase
    {
        private Process _agentProcess;
        public const string ServiceNameString = "BB_JAVIS_Remote";

        public JavisService()
        {
            this.ServiceName = ServiceNameString;
            this.CanStop = true;
            this.CanShutdown = true;
        }

        protected override void OnStart(string[] args)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, "start_remote_agent.ps1");
            if (!File.Exists(scriptPath))
            {
                scriptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BB_Javis", "start_remote_agent.ps1");
            }
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Mode fix -AsService";
            psi.WorkingDirectory = baseDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            _agentProcess = Process.Start(psi);
        }

        protected override void OnStop()
        {
            try
            {
                if (_agentProcess != null && !_agentProcess.HasExited) _agentProcess.Kill();
            } catch {}
        }

        protected override void OnShutdown()
        {
            this.OnStop();
        }

        public static void Main()
        {
            ServiceBase.Run(new JavisService());
        }
    }
}
'@
[System.IO.File]::WriteAllText($csSourcePath, $csCode, $utf8NoBom)

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
$targetExe = Join-Path $installDir "BBJavisService.exe"
& $csc /nologo /target:exe /r:System.dll,System.ServiceProcess.dll /out:$targetExe $csSourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $targetExe)) {
    throw "Failed to compile BBJavisService.exe"
}

& sc.exe create $svcName binPath= "`"$targetExe`"" start= auto DisplayName= "BB_JAVIS Remote Agent Service" 2>&1 | Out-Null
& sc.exe description $svcName "Zero-Trust Background Remote Agent for BB_JAVIS" 2>&1 | Out-Null
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/60000 2>&1 | Out-Null

$cfgFile = Join-Path $installDir "service_config.json"
$existingCfg = @{}
if (Test-Path $cfgFile) {
    try {
        $parsed = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $parsed.PSObject.Properties) { $existingCfg[$p.Name] = $p.Value }
    } catch {}
}

$resolvedGw = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl.Trim().TrimEnd('/') + "/" }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_GATEWAY_URL)) { $env:BB_JAVIS_GATEWAY_URL.Trim().TrimEnd('/') + "/" }
    elseif ($existingCfg.ContainsKey("gatewayUrl") -and $existingCfg["gatewayUrl"]) { $existingCfg["gatewayUrl"].ToString() }
    else { "https://bb-javis-gateway.apisit-yimboa.workers.dev/" }

if ([string]::IsNullOrWhiteSpace($resolvedGw) -and [Environment]::UserInteractive) {
    $enteredGw = Read-Host "Enter Cloudflare Gateway URL (e.g. https://bb-javis-gateway.example.workers.dev)"
    if (-not [string]::IsNullOrWhiteSpace($enteredGw)) { $resolvedGw = $enteredGw.Trim().TrimEnd('/') + "/" }
}
if ([string]::IsNullOrWhiteSpace($resolvedGw)) {
    throw "GatewayUrl is required."
}

$resolvedHost = if (-not [string]::IsNullOrWhiteSpace($DeviceName)) { $DeviceName.Trim() }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_HOST)) { $env:BB_JAVIS_HOST.Trim() }
    elseif ($existingCfg.ContainsKey("custom_name") -and $existingCfg["custom_name"]) { $existingCfg["custom_name"].ToString() }
    elseif ([Environment]::UserInteractive) {
        $inp = Read-Host "Enter custom machine name [Default: $env:COMPUTERNAME]"
        if ([string]::IsNullOrWhiteSpace($inp)) { $env:COMPUTERNAME } else { $inp.Trim() }
    } else { $env:COMPUTERNAME }

$existingCfg["gatewayUrl"] = $resolvedGw
$existingCfg["custom_name"] = $resolvedHost
$existingCfg["hostname"] = $env:COMPUTERNAME
$existingCfg["mode"] = "fix"
$existingCfg["updated_at"] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

[System.IO.File]::WriteAllText($cfgFile, ($existingCfg | ConvertTo-Json -Depth 5), $utf8NoBom)

$localUninstall = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "uninstall_service.ps1" } else { "" }
if ($localUninstall -and (Test-Path $localUninstall)) {
    Copy-Item $localUninstall (Join-Path $installDir "uninstall_service.ps1") -Force
}

$pairFile = Join-Path $installDir "pairing.txt"
$svcErrLog = Join-Path $installDir "service_error.log"
if (Test-Path $pairFile) { Remove-Item $pairFile -Force -ErrorAction SilentlyContinue }
if (Test-Path $svcErrLog) { Remove-Item $svcErrLog -Force -ErrorAction SilentlyContinue }

Start-Service -Name $svcName

$hasPairedAdmins = $false
if ($existingCfg["paired_admins"]) {
    $hasPairedAdmins = (@($existingCfg["paired_admins"].PSObject.Properties).Count -gt 0)
}
$alreadyPaired = (-not [string]::IsNullOrWhiteSpace($existingCfg["device_token_dpapi"])) -and $hasPairedAdmins
if ($alreadyPaired) {
    Start-Sleep -Seconds 2
    $svcState = (Get-Service -Name $svcName).Status
    if ($svcState -ne "Running") {
        if (Test-Path $svcErrLog) { Get-Content $svcErrLog -Encoding UTF8 | Write-Host -ForegroundColor Red }
        throw "Service $svcName failed to stay running (Status: $svcState)."
    }
    $savedPin = if ($existingCfg.ContainsKey("device_id")) { $existingCfg["device_id"] } else { "configured" }
    Write-Host "`n[READY] Service $svcName is RUNNING and ALREADY PAIRED (PIN: $savedPin)." -ForegroundColor Green
    return
}

Write-Host "`n[STARTED] Waiting for service to generate 4-digit Remote PIN..." -ForegroundColor Cyan
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $pairFile)) {
    if (Test-Path $svcErrLog) {
        Write-Host "`n[ERROR] Service agent reported a startup error:" -ForegroundColor Red
        Get-Content $svcErrLog -Encoding UTF8 | Write-Host -ForegroundColor Red
        throw "Service $svcName failed to initialize."
    }
    Start-Sleep -Milliseconds 400
}

if (-not (Test-Path $pairFile)) {
    $svcState = (Get-Service -Name $svcName).Status
    Write-Host "`n[WARN] Service status is $svcState, but pairing.txt did not appear within 30s." -ForegroundColor Yellow
    Write-Host "       Check outbound HTTPS to $($existingCfg['gatewayUrl']) or run start_remote_agent.bat to inspect." -ForegroundColor Gray
    return
}

$pairRaw = Get-Content $pairFile -Raw -Encoding UTF8
$pinCode = ""
if ($pairRaw -match "PAIRING_PIN=([A-Z0-9]{4,16})") { $pinCode = $Matches[1] }

Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "            BB_JAVIS SERVICE INSTALLED & READY TO PAIR                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Machine    : $resolvedHost ($env:COMPUTERNAME)" -ForegroundColor White
Write-Host "  -> Remote PIN : " -NoNewline -ForegroundColor Gray
Write-Host "[ $pinCode ]" -ForegroundColor Green
Write-Host "  -> Run on Dev : send_remote_command.bat -Pair $pinCode" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "Waiting up to 120s for Dev to run -Pair $pinCode (Service runs in background)..." -ForegroundColor Cyan

$waitPairDeadline = [DateTime]::UtcNow.AddSeconds(120)
while ([DateTime]::UtcNow -lt $waitPairDeadline -and (Test-Path $pairFile)) {
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $pairFile)) {
    Write-Host "[PAIRED & ONLINE] $resolvedHost paired successfully and is ready for remote commands!" -ForegroundColor Green
} else {
    Write-Host "[PENDING] Service $svcName stays RUNNING in background. Pair anytime using PIN: [ $pinCode ]" -ForegroundColor Yellow
}
