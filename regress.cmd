@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist build mkdir build
set "FAIL=0"
for %%f in (examples\*.rsx) do call :one "%%f"

echo.
call mini\test.cmd
if errorlevel 1 set "FAIL=1"

echo.
call rmake.cmd build >nul 2>"build\rmake.err"
if errorlevel 1 (
  echo FAIL-RMAKE-BUILD
  type "build\rmake.err"
  set "FAIL=1"
) else (
  call rmake.cmd test >"build\rmake.out" 2>&1
  if errorlevel 1 (
    echo FAIL-RMAKE-TEST
    type "build\rmake.out"
    set "FAIL=1"
  ) else (
    echo rmake ok
  )
)
exit /b !FAIL!

:one
set "N=%~n1"
if /i "%N%"=="bench_mac" goto :bench_mac
if /i "%N%"=="bench" goto :bench_skip
call rsc.cmd "%~1" "build\%N%.exe" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  set "FAIL=1"
  exit /b 0
)
"build\%N%.exe" >"build\%N%.out"
set "NAT=!ERRORLEVEL!"
call rsc.cmd --vm "%~1" "build\%N%.rvm" >nul 2>"build\%N%.verr"
if errorlevel 1 (
  echo FAIL-VM-BUILD %N%
  type "build\%N%.verr"
  set "FAIL=1"
  exit /b 0
)
backend\rscvm.exe "build\%N%.rvm" >"build\%N%.vout" 2>&1
set "VMR=!ERRORLEVEL!"
if not "!NAT!"=="!VMR!" (
  echo FAIL-VM-EXIT %N% native=!NAT! vm=!VMR!
  set "FAIL=1"
  exit /b 0
)
fc /b "build\%N%.out" "build\%N%.vout" >nul 2>&1
if errorlevel 1 (
  echo FAIL-VM-OUT %N%
  set "FAIL=1"
  exit /b 0
)
type "build\%N%.out"
echo %N% exit=!NAT!
exit /b 0

:bench_skip
call rsc.cmd "%~1" "build\%N%.exe" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  set "FAIL=1"
  exit /b 0
)
"build\%N%.exe"
echo %N% exit=!ERRORLEVEL! ^(vm parity skipped, long-running^)
exit /b 0

:bench_mac
call rsc.cmd -t macos "%~1" "build\%N%.macho" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  set "FAIL=1"
  exit /b 0
)
echo %N% built ^(macos image, not run here^)
exit /b 0
