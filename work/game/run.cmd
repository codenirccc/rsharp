@echo off
setlocal
set "HERE=%~dp0"
set "RSC=%HERE%..\..\rsc.cmd"
cd /d "%HERE%"
if not exist build mkdir build
call "%RSC%" t_game.rsx "build\t_game.exe"
if errorlevel 1 exit /b 1
build\t_game.exe
exit /b %errorlevel%
