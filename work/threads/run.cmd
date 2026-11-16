@echo off
setlocal
set "HERE=%~dp0"
set "RSC=%HERE%..\..\rsc.cmd"
cd /d "%HERE%"
if not exist build mkdir build
call "%RSC%" mt.rsx "build\mt.exe"
if errorlevel 1 exit /b 1
build\mt.exe
exit /b %errorlevel%
