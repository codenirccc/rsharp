@echo off
setlocal
set "RSC_ROOT=%~dp0"
if /i "%~1"=="-Clean" set "RSC_CLEAN=1"
if /i "%~1"=="--clean" set "RSC_CLEAN=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content -Raw -LiteralPath ($env:RSC_ROOT + 'build.ps1'))"
exit /b %ERRORLEVEL%
