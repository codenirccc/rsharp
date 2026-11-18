@echo off
setlocal
set "HERE=%~dp0"
set "OUT=%HERE%build"

if not exist "%OUT%" mkdir "%OUT%" >nul 2>&1

call "%HERE%..\rsc.cmd" "%HERE%t_lex.rsx" "%OUT%\t_lex.exe"
if errorlevel 1 exit /b 1

"%OUT%\t_lex.exe"
if errorlevel 1 exit /b 1

echo rscx: ok
exit /b 0
