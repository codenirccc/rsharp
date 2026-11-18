@echo off
setlocal
cd /d %~dp0
if not exist build mkdir build
set "FAIL=0"

call :build t_lspsrv
call :build t_lsp
call :build t_frames
call :build t_expect
if "%FAIL%"=="1" exit /b 1

build\t_lsp.exe
if errorlevel 1 (
  echo FAIL-RUN t_lsp
  set "FAIL=1"
)

build\t_frames.exe > build\session.in
if errorlevel 1 (
  echo FAIL-GEN frames
  set "FAIL=1"
)
build\t_expect.exe > build\expected.out
if errorlevel 1 (
  echo FAIL-GEN expect
  set "FAIL=1"
)

type build\session.in | build\t_lspsrv.exe > build\session.out
if errorlevel 1 (
  echo FAIL-RUN server
  set "FAIL=1"
)

fc /b build\session.out build\expected.out >nul
if errorlevel 1 (
  echo FAIL-PIPE transcript
  set "FAIL=1"
)

call "..\..\rsc.cmd" -t macos t_mac.rsx build\t_lspsrv.macho >nul 2>"build\t_mac.err"
if errorlevel 1 (
  echo FAIL-BUILD macos
  type "build\t_mac.err"
  set "FAIL=1"
)

if "%FAIL%"=="1" (
  echo lsp suite: failing
  exit /b 1
)
echo lsp pipe: ok
exit /b 0

:build
call "..\..\rsc.cmd" "%~1.rsx" "build\%~1.exe" >nul 2>"build\%~1.err"
if errorlevel 1 (
  echo FAIL-BUILD %~1
  type "build\%~1.err"
  set "FAIL=1"
)
exit /b 0
