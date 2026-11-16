@echo off
setlocal
set "R=C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp"
cd /d "%~dp0"
if not exist build mkdir build
call "%R%\rsc.cmd" "%~1" "build\%~n1.exe"
if errorlevel 1 exit /b 1
"build\%~n1.exe"
echo exit=%errorlevel%
