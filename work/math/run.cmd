@echo off
setlocal
set "HERE=%~dp0"
set "RSC=%HERE%..\..\rsc.cmd"
cd /d "%HERE%"
if not exist build mkdir build
call "%RSC%" t_math.rsx "build\t_math.exe"
if errorlevel 1 exit /b 1
build\t_math.exe
exit /b %errorlevel%
