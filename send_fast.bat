@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send_fast.ps1" %*
