@echo off
title BB_JAVIS Zero-Trust Remote Execution Agent
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_remote_agent.ps1" %*
exit /b %ERRORLEVEL%
