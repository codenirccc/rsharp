@echo off
setlocal
set "HERE=%~dp0"
set "FRONT=%HERE%frontend\target\release\rsc.exe"
set "BACK=%HERE%backend\rscb.exe"

set "TGT=windows"
if /i "%~1"=="-t" (
    set "TGT=%~2"
    shift
    shift
)

if "%~1"=="" (
    echo usage: rsc [-t windows^|macos] ^<file.rsx^> [out]
    exit /b 2
)

if not exist "%FRONT%" (
    echo rsc: front end not built - run build.ps1
    exit /b 1
)
if not exist "%BACK%" (
    echo rsc: back end not built - run build.ps1
    exit /b 1
)

set "IN=%~f1"
for %%F in ("%IN%") do (
    set "DIR=%%~dpF"
    set "STEM=%%~nF"
)

if "%TGT%"=="macos" (set "EXT=") else (set "EXT=.exe")
if "%~2"=="" (set "OUT=%DIR%%STEM%%EXT%") else (set "OUT=%~f2")
set "IR=%DIR%%STEM%.rsi"

for %%D in ("%OUT%") do if not exist "%%~dpD" mkdir "%%~dpD" >nul 2>&1

"%FRONT%" "%IN%" -o "%IR%"
if errorlevel 1 exit /b 1

"%BACK%" "%IR%" -o "%OUT%" -s "%IN%" -t "%TGT%"
if errorlevel 1 exit /b 1

del "%IR%" >nul 2>&1
echo built %OUT%
