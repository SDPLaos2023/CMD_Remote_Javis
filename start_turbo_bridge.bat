@echo off
title CMD_Remote Controller Turbo Bridge (127.0.0.1:5999)
echo ============================================================
echo   Starting CMD_Remote Controller Turbo Bridge on Port 5999
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cmd_remote_bridge.ps1"
pause
