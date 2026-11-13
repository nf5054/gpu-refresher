@echo off
setlocal
title GPU Refresher
set "GPU_REFRESHER_SCRIPT=%~dp0GPU-Refresher.ps1"
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%GPU_REFRESHER_SCRIPT%" %*
if errorlevel 1 (
  echo.
  echo GPU Refresher stopped. See the message above.
  pause
)
endlocal
