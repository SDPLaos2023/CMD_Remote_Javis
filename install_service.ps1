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
