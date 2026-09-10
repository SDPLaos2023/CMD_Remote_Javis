<#
.SYNOPSIS
deploy_remote_win_arm.ps1 - สคริปต์ One-Click Setup สำหรับติดตั้ง win-arm บนเครื่อง Remote/สาขา
ทำงานผ่าน CMD_Remote (send_remote_command.bat -Mode PowerShell)
#>

$TargetDir = "C:\Agent\win_arm"
Write-Output "[*] เริ่มกระบวนการติดตั้ง win-arm บนเครื่องเป้าหมาย: $TargetDir"

# 1. สร้างไดเรกทอรีเป้าหมาย
if (!(Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

# 2. ตรวจสอบและติดตั้ง Python dependencies
Write-Output "[*] กำลังตรวจสอบและติดตั้ง dependencies (uiautomation, pillow, pyautogui)..."
python -m pip install --quiet uiautomation pillow pyautogui

# 3. ยืนยันสถานะ
$check = python -c "import uiautomation, PIL, pyautogui; print('SUCCESS')" 2>$null
if ($check -match "SUCCESS") {
    Write-Output '{"success":true,"message":"win-arm dependencies installed successfully","target_dir":"C:\\Agent\\win_arm"}'
} else {
    Write-Output '{"success":false,"error":"Failed to install win-arm dependencies"}'
}
