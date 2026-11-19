@echo off
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "EXE=%HERE%build\rmake.exe"

if /i "%~1"=="bootstrap" (
    call "%HERE%rsc.cmd" "%HERE%tools\rmake\main.rsx" "%EXE%"
    set "RC=%ERRORLEVEL%"
    exit /b !RC!
)

if not exist "%EXE%" (
    call "%HERE%rsc.cmd" "%HERE%tools\rmake\main.rsx" "%EXE%"
    if errorlevel 1 exit /b 1
)

if not exist ".rmake" mkdir ".rmake" >nul 2>&1
set "ARGS=%CD%\.rmake\cmd.txt"
set "FIRST=%~1"
>"%ARGS%" echo --rsc
>>"%ARGS%" echo %HERE%rsc.cmd

:args
if "%~1"=="" goto run
set "A=%~1"
>>"%ARGS%" echo(!A!
shift
goto args

:run
set "RMAKE_CMD=%ARGS%"
if /i "!FIRST!"=="help" goto plain
if /i "!FIRST!"=="--help" goto plain
if /i "!FIRST!"=="-h" goto plain
set "RMAKE_SEEK=1"

:seek
"%EXE%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="3" exit /b %RC%
set "LAST=%CD%"
cd ..
if "%CD%"=="%LAST%" goto notfound
goto seek

:notfound
echo rmake: no RMakefile in this directory or any parent
echo rmake: pass --manifest PATH to name a build file
exit /b 1

:plain
"%EXE%"
exit /b %ERRORLEVEL%
