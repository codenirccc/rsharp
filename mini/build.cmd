@echo off
setlocal
cd /d "%~dp0"

set "HOST=win"
set "TGT=windows"
set "OUT=mini.exe"

if /i "%~1"=="macos" (
  set "HOST=mac"
  set "TGT=macos"
  set "OUT=..\build\mini_mac"
)
if /i "%~1"=="windows" (
  set "HOST=win"
  set "TGT=windows"
  set "OUT=mini.exe"
)

if not exist "..\build" mkdir "..\build"
set "SRC=..\build\mini_%HOST%.rsx"

copy /b "src\mini.rsx" + "src\host_%HOST%.rsx" "%SRC%" >nul
if errorlevel 1 (
  echo build: cannot assemble %SRC%
  exit /b 1
)

call "..\rsc.cmd" -t %TGT% "%SRC%" "%OUT%"
exit /b %errorlevel%
