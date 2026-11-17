@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "ROOT=%~dp0..\.."
if not exist build mkdir build
set "FAIL=0"
call "%ROOT%\rsc.cmd" t_linalg.rsx "build\t_linalg.exe"
if errorlevel 1 (
  echo FAIL-BUILD t_linalg
  exit /b 1
)
build\t_linalg.exe > "build\t_linalg.out"
fc /b "build\t_linalg.out" "%~dp0linalg.out" >nul
if errorlevel 1 (
  echo FAIL-DIFF t_linalg
  set "FAIL=1"
) else (
  echo ok t_linalg
)
set "PATH=%PATH%;C:\Program Files\Git\usr\bin;C:\Program Files\Git\bin"
"C:\Program Files\Git\usr\bin\bash.exe" "%ROOT%\rsc.sh" -t macos t_linalg.rsx build/t_linalg_mac
python "%ROOT%\work\gui\check_macho.py" build\t_linalg_mac >nul
if errorlevel 1 (
  echo FAIL-MACOS-IMAGE t_linalg
  set "FAIL=1"
) else (
  echo ok t_linalg macos image
)
if "%FAIL%"=="1" exit /b 1
echo linalg suite: ok
exit /b 0
