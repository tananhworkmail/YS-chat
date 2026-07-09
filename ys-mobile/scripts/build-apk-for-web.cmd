@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "DEBUG="

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell was not found in PATH.
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build-apk-for-web.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo Build APK failed with exit code %EXIT_CODE%.
)

exit /b %EXIT_CODE%
