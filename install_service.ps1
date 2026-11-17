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

Start-Service -Name $svcName

$pairFile = Join-Path $installDir "pairing.txt"
$deadline = [DateTime]::UtcNow.AddSeconds(12)
while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $pairFile)) {
    Start-Sleep -Milliseconds 400
}

Write-Host "`n[INSTALLED] Service $svcName is RUNNING." -ForegroundColor Green
if (Test-Path $pairFile) {
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    Get-Content $pairFile -Encoding UTF8 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
}
