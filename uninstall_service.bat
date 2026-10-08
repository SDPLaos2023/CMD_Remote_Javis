@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [BB_JAVIS] กำลังขอสิทธิ์ Administrator เพื่อถอนการติดตั้ง Service...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_service.ps1"
echo กดปุ่มใดๆ เพื่อปิดหน้าต่างนี้...
pause >nul
