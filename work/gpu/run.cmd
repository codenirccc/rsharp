@echo off
setlocal
cd /d "%~dp0"
set "ROOT=%~dp0..\.."
if not exist build mkdir build
set "FAIL=0"
call "%ROOT%\rsc.cmd" t_gl.rsx "build\t_gl.exe"
if errorlevel 1 set "FAIL=1"
if "%FAIL%"=="0" (
  build\t_gl.exe
  if errorlevel 1 set "FAIL=1"
)
call "%ROOT%\rsc.cmd" t_vk.rsx "build\t_vk.exe"
if errorlevel 1 set "FAIL=1"
if "%FAIL%"=="0" (
  build\t_vk.exe
  if errorlevel 1 set "FAIL=1"
)
if "%FAIL%"=="1" exit /b 1
echo gpu suite: ok
exit /b 0
