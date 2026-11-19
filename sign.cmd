@echo off
setlocal
set "D=%LOCALAPPDATA%\rsharp\signing"
if not exist "%D%" mkdir "%D%" >nul 2>&1
copy /y "%~dp0sign.ps1" "%D%\sign.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%D%\sign.ps1" -Store "%D%" %*
exit /b %errorlevel%
