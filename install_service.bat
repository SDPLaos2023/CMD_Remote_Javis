@echo off
chcp 65001 >nul
:: Check Administrator privileges, request UAC elevation if needed
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [BB_JAVIS] Requesting Administrator privileges to install service...
    powershell -Command "Start-Process cmd -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_service.ps1"
echo Press any key to exit...
pause >nul
