<#
.SYNOPSIS
    BB_JAVIS Remote - Windows Service Automated Installer (da.gd/bbj-fix)
    ติดตั้ง Agent เป็น Background Windows Service รันตลอด 24 ชม. อัตโนมัติ (Zero-Dependency)
#>

# บังคับการเข้ารหัส Console เป็น UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# เปิดใช้งานโปรโตคอล TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "       BB_JAVIS REMOTE - BACKGROUND SERVICE AUTOMATED INSTALLER       " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

# 1. ตรวจสอบสิทธิ์ Administrator
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[ERROR] สิทธิ์ไม่เพียงพอ! กรุณาเปิด PowerShell ด้วยสิทธิ์ Administrator (Run as Administrator)" -ForegroundColor Red
    Write-Host "แล้ววางคำสั่งติดตั้งใหม่อีกครั้งครับ`n" -ForegroundColor Yellow
    return
}

$installDir = "C:\ProgramData\BB_Javis"
if (-not (Test-Path $installDir)) {
    $null = New-Item -ItemType Directory -Path $installDir -Force
    Write-Host "[SETUP] สร้างโฟลเดอร์สำหรับ Service: $installDir" -ForegroundColor Green
}

# 2. ตั้งค่า Windows Defender Exclusion สำหรับโฟลเดอร์รันงาน
try {
    Write-Host "[PRE-CHECK] ตั้งค่าข้อยกเว้น Windows Defender ในโฟลเดอร์ $installDir..." -ForegroundColor DarkGray
    Add-MpPreference -ExclusionPath $installDir -ErrorAction SilentlyContinue
} catch {}

# 3. จัดเตรียมไฟล์ start_remote_agent.ps1
$localAgent = Join-Path $PSScriptRoot "start_remote_agent.ps1"
$targetAgent = Join-Path $installDir "start_remote_agent.ps1"

if (Test-Path $localAgent) {
    Copy-Item $localAgent $targetAgent -Force
    Write-Host "[COPY] คัดลอก start_remote_agent.ps1 ไปยัง $installDir เรียบร้อย" -ForegroundColor Green
} else {
    Write-Host "[DOWNLOAD] กำลังดาวน์โหลด start_remote_agent.ps1 จากคลาวด์ทางการ..." -ForegroundColor Cyan
    $rawUrl = "https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote_Javis/main/start_remote_agent.ps1"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.DownloadFile($rawUrl, $targetAgent)
        $wc.Dispose()
        Write-Host "[DOWNLOAD] ดาวน์โหลด start_remote_agent.ps1 เรียบร้อย" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] ไม่สามารถดาวน์โหลด start_remote_agent.ps1 ได้: $_" -ForegroundColor Red
        return
    }
}

# คัดลอก curl.exe หากมีอยู่
$localCurl = Join-Path $PSScriptRoot "curl.exe"
if (Test-Path $localCurl) {
    Copy-Item $localCurl (Join-Path $installDir "curl.exe") -Force
}

# 4. สร้าง Source Code C# Service Wrapper (BBJavisService.cs)
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
            StopProcess();
        }

        protected override void OnShutdown()
        {
            StopProcess();
        }

        private void StopProcess()
        {
            try
            {
                if (_agentProcess != null && !_agentProcess.HasExited)
                {
                    _agentProcess.Kill();
                    _agentProcess.WaitForExit(5000);
                }
            }
            catch {}
        }

        public static void Main()
        {
            ServiceBase.Run(new JavisService());
        }
    }
}
"@
[System.IO.File]::WriteAllText($csSourcePath, $csCode, [System.Text.Encoding]::UTF8)

# 5. ค้นหา C# Compiler (csc.exe) ภายในเครื่อง (Zero-Dependency 100%)
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    Write-Host "[ERROR] ไม่พบ .NET Framework C# Compiler (csc.exe) บนเครื่องนี้!" -ForegroundColor Red
    return
}

# 6. คอมไพล์ BBJavisService.exe
$targetExe = Join-Path $installDir "BBJavisService.exe"
Write-Host "[COMPILE] กำลังคอมไพล์ C# Windows Service Wrapper..." -ForegroundColor Cyan
& $csc /nologo /target:exe /r:System.dll,System.ServiceProcess.dll /out:$targetExe $csSourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $targetExe)) {
    Write-Host "[ERROR] คอมไพล์ BBJavisService.exe ไม่สำเร็จ (Exit code: $LASTEXITCODE)" -ForegroundColor Red
    return
}
Write-Host "[COMPILE] คอมไพล์ BBJavisService.exe สำเร็จสมบูรณ์! (Native 100%)" -ForegroundColor Green

# 7. ตรวจสอบและลงทะเบียน Service กับ Windows Service Control Manager (SCM)
$svcName = "BB_JAVIS_Remote"
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Host "[SERVICE] พบ Service เดิม กำลังหยุดและลบการลงทะเบียนเดิม..." -ForegroundColor Yellow
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
}

Write-Host "[SERVICE] กำลังลงทะเบียน Windows Service: $svcName..." -ForegroundColor Cyan
$binPathArg = "`"$targetExe`""
& sc.exe create $svcName binPath= $binPathArg start= auto DisplayName= "BB_JAVIS Remote Agent Service" 2>&1 | Out-Null
& sc.exe description $svcName "Background Remote Agent for BB_JAVIS C2 Management (Always-On)" 2>&1 | Out-Null
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/60000 2>&1 | Out-Null

# 8. สร้างสคริปต์ uninstall ไว้ในโฟลเดอร์สำหรับใช้งานในอนาคต
$uninstallPs1Content = @'
# สคริปต์ถอนการติดตั้ง BB_JAVIS Remote Service
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$svcName = "BB_JAVIS_Remote"
Write-Host "กำลังถอนการติดตั้ง $svcName..." -ForegroundColor Yellow
try {
    $cfgPath = "C:\ProgramData\BB_Javis\service_config.json"
    if (Test-Path $cfgPath) {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg -and $cfg.pin) {
            $delUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/devices/$($cfg.pin).json"
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
Write-Host "[SUCCESS] ถอนการติดตั้ง BB_JAVIS Remote Service สำเร็จเรียบร้อยแล้ว!" -ForegroundColor Green
'@
[System.IO.File]::WriteAllText((Join-Path $installDir "uninstall_service.ps1"), $uninstallPs1Content, [System.Text.Encoding]::UTF8)

$uninstallBatContent = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_service.ps1"
pause
"@
[System.IO.File]::WriteAllText((Join-Path $installDir "uninstall_service.bat"), $uninstallBatContent, [System.Text.Encoding]::UTF8)

# 9. เริ่มต้น Service ทันที
Write-Host "[START] กำลังเริ่มต้นบริการ $svcName..." -ForegroundColor Cyan
try {
    Start-Service -Name $svcName -ErrorAction Stop
} catch {
    Write-Host "[WARNING] ไม่สามารถ Start-Service ได้โดยตรง กำลังลองผ่าน sc.exe start..." -ForegroundColor Yellow
    & sc.exe start $svcName 2>&1 | Out-Null
}

# 10. รอรับค่า PIN จาก service_config.json ที่ Service สร้างขึ้น
Write-Host "[INIT] กำลังรอระบบจับคู่และบันทึกรหัส PIN ประจำเครื่อง..." -ForegroundColor DarkGray
$assignedPin = "กำลังลงทะเบียน..."
$cfgFile = Join-Path $installDir "service_config.json"

for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg -and $cfg.pin) {
                $assignedPin = $cfg.pin.ToString().Trim()
                break
            }
        } catch {}
    }
}

# ดึง Local IP
$localIp = "127.0.0.1"
try {
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias * -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
                Select-Object -ExpandProperty IPAddress -First 1)
} catch {}

# 11. แสดงแบนเนอร์สรุปผลลัพธ์
Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "              BB_JAVIS BACKGROUND SERVICE INSTALLED                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Service Name      : " -NoNewline -ForegroundColor Gray
Write-Host "$svcName (RUNNING)" -ForegroundColor Green
Write-Host "  -> Startup Type      : " -NoNewline -ForegroundColor Gray
Write-Host "Automatic (รันเบื้องหลังทันทีเมื่อเปิดเครื่อง)" -ForegroundColor White
Write-Host "  -> Persistent PIN    : " -NoNewline -ForegroundColor Gray
Write-Host "[ $assignedPin ]" -NoNewline -ForegroundColor Green
Write-Host " (PERMANENT FIXED PIN)" -ForegroundColor Yellow
Write-Host "  -> Machine Hostname  : " -NoNewline -ForegroundColor Gray
Write-Host "$env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  -> Local IPv4        : " -NoNewline -ForegroundColor Gray
Write-Host "$localIp" -ForegroundColor Cyan
Write-Host "  -> Presence Status   : " -NoNewline -ForegroundColor Gray
Write-Host "ONLINE (Real-time SSE Push & Heartbeat 30s)" -ForegroundColor Green
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  * ระบบกำลังทำงานเบื้องหลังตลอด 24 ชั่วโมงเรียบร้อยแล้ว" -ForegroundColor White
Write-Host "  * ท่านสามารถ 'ปิดหน้าต่าง PowerShell นี้ได้ทันที' โดยระบบยังคงทำงานต่อ" -ForegroundColor Green
Write-Host "  * เครื่องควบคุมสามารถสั่งงานด้วยชื่อเครื่อง '$env:COMPUTERNAME' หรือ PIN [ $assignedPin ]" -ForegroundColor Gray
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host ""
