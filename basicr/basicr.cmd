@echo off
setlocal EnableDelayedExpansion
set "BASICR_SCRIPT=%~dp0basicr.ps1"
set "BASICR_ARGV=%TEMP%\basicr-argv-%RANDOM%-%RANDOM%.txt"
if exist "%BASICR_ARGV%" del "%BASICR_ARGV%" >nul 2>&1

:args
if "%~1"=="" goto run
>>"%BASICR_ARGV%" echo %~1
shift
goto args

:run
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a=@(); if (Test-Path -LiteralPath $env:BASICR_ARGV) { $a=@(Get-Content -LiteralPath $env:BASICR_ARGV) }; $s=[scriptblock]::Create((Get-Content -Raw -LiteralPath $env:BASICR_SCRIPT)); & $s @a"
set "RC=%ERRORLEVEL%"
del "%BASICR_ARGV%" >nul 2>&1
exit /b %RC%
