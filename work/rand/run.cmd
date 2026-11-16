@echo off
setlocal
set "HERE=%~dp0"
set "RSC=%HERE%..\..\rsc.cmd"
cd /d "%HERE%"
if not exist build mkdir build

call "%RSC%" t_rand.rsx "build\t_rand.exe" >nul
if errorlevel 1 (
  echo rand suite: build failed
  exit /b 1
)
build\t_rand.exe
exit /b %errorlevel%
