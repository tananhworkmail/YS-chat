@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-apk-for-web.ps1" %*
