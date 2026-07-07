@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture-android-crash.ps1" %*
