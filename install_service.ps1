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
