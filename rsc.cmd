@echo off
setlocal
set "HERE=%~dp0"
set "FRONT=%HERE%frontend\target\release\rsc.exe"
set "BACK=%HERE%backend\rscb.exe"

set "TGT=windows"
set "VM="
if /i "%~1"=="--vm" (
    set "VM=1"
    shift
)
if /i "%~1"=="-t" (
    if not defined VM (
        set "TGT=%~2"
        shift
        shift
    )
)

if "%~1"=="" (
    echo usage: rsc [--vm] [-t windows^|macos^|linux] ^<file.rsx^> [out]
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

if defined VM (
    set "EXT=.rvm"
) else if /i "%TGT%"=="windows" (
    set "EXT=.exe"
) else (
    set "EXT="
)
if "%~2"=="" (set "OUT=%DIR%%STEM%%EXT%") else (set "OUT=%~f2")
set "IR=%DIR%%STEM%.rsi"

for %%D in ("%OUT%") do if not exist "%%~dpD" mkdir "%%~dpD" >nul 2>&1

"%FRONT%" "%IN%" -o "%IR%"
if errorlevel 1 exit /b 1

if defined VM (
    "%BACK%" "%IR%" --vm -o "%OUT%" -s "%IN%"
) else (
    "%BACK%" "%IR%" -o "%OUT%" -s "%IN%" -t "%TGT%"
)
if errorlevel 1 exit /b 1

del "%IR%" >nul 2>&1
echo built %OUT%
