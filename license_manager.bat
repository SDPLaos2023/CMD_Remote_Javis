@echo off
title BB_JAVIS Owner License Manager
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\license_manager.ps1" %*
if "%1"=="" pause
