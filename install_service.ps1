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
using System.Threading;

namespace BBJavisService
{
    public class JavisService : ServiceBase
    {
        private Process _agentProcess;
        private Thread _watchdogThread;
        private volatile bool _stopping = false;
        private readonly object _lock = new object();
        public const string ServiceNameString = "BB_JAVIS_Remote";

        public JavisService()
        {
            this.ServiceName = ServiceNameString;
            this.CanStop = true;
            this.CanShutdown = true;
        }

        private void RunAgentWatchdog()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, "start_remote_agent.ps1");
            if (!File.Exists(scriptPath))
            {
                scriptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BB_Javis", "start_remote_agent.ps1");
            }
            while (!_stopping)
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "powershell.exe";
                    psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Mode fix -AsService";
                    psi.WorkingDirectory = baseDir;
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;

                    Process proc = Process.Start(psi);
                    lock (_lock) { _agentProcess = proc; }
                    if (proc != null)
                    {
                        proc.WaitForExit();
                    }
                }
                catch { }
                if (!_stopping)
                {
                    Thread.Sleep(5000);
                }
            }
        }

        protected override void OnStart(string[] args)
        {
            _stopping = false;
            _watchdogThread = new Thread(new ThreadStart(RunAgentWatchdog));
            _watchdogThread.IsBackground = true;
            _watchdogThread.Start();
        }

        protected override void OnStop()
        {
            _stopping = true;
            lock (_lock)
            {
                try
                {
                    if (_agentProcess != null && !_agentProcess.HasExited) _agentProcess.Kill();
                } catch {}
            }
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
