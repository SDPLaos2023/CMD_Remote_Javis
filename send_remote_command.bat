@echo off
title BB_JAVIS Zero-Trust Command Sender
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send_remote_command.ps1" %*
exit /b %ERRORLEVEL%
