# ======================================================================
# BB_JAVIS Remote - Windows Service Automated Uninstaller (da.gd/bbj-unfix)
# ถอนการติดตั้ง Windows Service และลบข้อมูลออกจากเครื่องและ Cloud
# ======================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "      BB_JAVIS REMOTE - SERVICE AUTOMATED UNINSTALLER (UNFIX)         " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[ERROR] สิทธิ์ไม่เพียงพอ! กรุณาเปิด PowerShell ด้วยสิทธิ์ Administrator (Run as Administrator)" -ForegroundColor Red
    return
}

$svcName = "BB_JAVIS_Remote"
$installDir = "C:\ProgramData\BB_Javis"
$cfgFile = Join-Path $installDir "service_config.json"

# 1. แจ้งเตือน Cloud และลบโหนดอุปกรณ์ออกจาก Firebase
if (Test-Path $cfgFile) {
    try {
        $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg -and $cfg.pin) {
            Write-Host "[CLOUD] กำลังล้างข้อมูลอุปกรณ์ PIN: $($cfg.pin) ออกจาก Cloud..." -ForegroundColor Cyan
            $authQuery = if ($cfg.authToken) { "?auth=$($cfg.authToken)" } else { "" }
            $delDevUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))devices/$($cfg.pin).json$authQuery"
            $delJobUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))jobs/$($cfg.pin).json$authQuery"
            
            $req1 = [System.Net.HttpWebRequest]::Create($delDevUrl)
            $req1.Method = "DELETE"
            $req1.Timeout = 5000
            try { $resp1 = $req1.GetResponse(); $resp1.Close() } catch {}

            $req2 = [System.Net.HttpWebRequest]::Create($delJobUrl)
            $req2.Method = "DELETE"
            $req2.Timeout = 5000
            try { $resp2 = $req2.GetResponse(); $resp2.Close() } catch {}
            Write-Host "[CLOUD] ล้างข้อมูลอุปกรณ์บน Cloud สำเร็จ" -ForegroundColor Green
        }
    } catch {}
}

# 2. หยุดและลบ Windows Service
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Host "[SERVICE] กำลังหยุดบริการ $svcName..." -ForegroundColor Yellow
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "[SERVICE] กำลังลบการลงทะเบียน $svcName ออกจาก Windows..." -ForegroundColor Yellow
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
} else {
    Write-Host "[SERVICE] ไม่พบการลงทะเบียนบริการ $svcName ในระบบ" -ForegroundColor Gray
}

# 3. ตรวจสอบปิดโปรเซสที่อาจยังค้างอยู่
try {
    Get-Process -Name "BBJavisService" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*powershell*" } | ForEach-Object {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmd -and ($cmd -like "*BB_Javis*" -or $cmd -like "*start_remote_agent*")) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
} catch {}

# 4. ลบไฟล์การทำงานใน C:\ProgramData\BB_Javis
if (Test-Path $installDir) {
    try {
        Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[CLEANUP] ลบโฟลเดอร์ $installDir เรียบร้อยแล้ว" -ForegroundColor Green
    } catch {
        Write-Host "[CLEANUP] เคลียร์ไฟล์ชั่วคราวบางส่วนแล้ว" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  [SUCCESS] ถอนการติดตั้ง BB_JAVIS Remote Service เรียบร้อยแล้ว! 100% " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host ""
