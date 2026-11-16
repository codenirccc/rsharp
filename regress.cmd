@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist build mkdir build
for %%f in (examples\*.rsx) do call :one "%%f"

echo.
rem the Mini compiler is an R# program, so its own suite rides along here
call mini\test.cmd
if errorlevel 1 exit /b 1
exit /b 0

:one
set "N=%~n1"
if /i "%N%"=="bench_mac" goto :bench_mac
call rsc.cmd "%~1" "build\%N%.exe" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  exit /b 0
)
"build\%N%.exe"
echo %N% exit=!ERRORLEVEL!
exit /b 0

:bench_mac
rem mach_absolute_time only resolves against a Mach-O image, so this one is
rem built for macOS and left unrun on a Windows host.
call rsc.cmd -t macos "%~1" "build\%N%.macho" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  exit /b 0
)
echo %N% built ^(macos image, not run here^)
exit /b 0
