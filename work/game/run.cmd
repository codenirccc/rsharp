@echo off
setlocal
set "HERE=%~dp0"
set "RSC=%HERE%..\..\rsc.cmd"
cd /d "%HERE%"
if not exist build mkdir build
set "FAIL=0"
call "%RSC%" t_game.rsx "build\t_game.exe"
if errorlevel 1 set "FAIL=1"
if "%FAIL%"=="0" (
  build\t_game.exe
  if errorlevel 1 set "FAIL=1"
)
call "%RSC%" physics_test.rsx "build\physics_test.exe"
if errorlevel 1 set "FAIL=1"
if "%FAIL%"=="0" (
  build\physics_test.exe
  if errorlevel 1 set "FAIL=1"
)
if "%FAIL%"=="1" exit /b 1
echo game suite: ok
exit /b 0
