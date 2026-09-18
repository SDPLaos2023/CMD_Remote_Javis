@echo off
title BB_JAVIS API Key Generator
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\gen_javis_key.ps1" %*
if "%1"=="" pause
