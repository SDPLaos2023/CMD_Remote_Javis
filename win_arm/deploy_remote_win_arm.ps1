<#
.SYNOPSIS
deploy_remote_win_arm.ps1 - One-Click Setup script to deploy win-arm on remote machines
Executed via CMD_Remote (send_remote_command.bat -Mode PowerShell)
#>

$TargetDir = "C:\Agent\win_arm"
Write-Output "[*] Starting win-arm deployment on target machine: $TargetDir"

# 1. Create target directory
if (!(Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

# 2. Check and install Python dependencies
Write-Output "[*] Installing Python dependencies (uiautomation, pillow, pyautogui)..."
python -m pip install --quiet uiautomation pillow pyautogui

# 3. Verify status
$check = python -c "import uiautomation, PIL, pyautogui; print('SUCCESS')" 2>$null
if ($check -match "SUCCESS") {
    Write-Output '{"success":true,"message":"win-arm dependencies installed successfully","target_dir":"C:\\Agent\\win_arm"}'
} else {
    Write-Output '{"success":false,"error":"Failed to install win-arm dependencies"}'
}
