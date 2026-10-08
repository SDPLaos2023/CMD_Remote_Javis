@echo off
chcp 65001 >nul
:: ตรวจสอบสิทธิ์ Admin หากยังไม่มี ให้ขอ UAC
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [BB_JAVIS] กำลังขอสิทธิ์ Administrator เพื่อติดตั้ง Service...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_service.ps1"
echo กดปุ่มใดๆ เพื่อปิดหน้าต่างนี้...
pause >nul
