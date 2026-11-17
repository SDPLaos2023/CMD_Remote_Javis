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
