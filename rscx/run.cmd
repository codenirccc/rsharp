@echo off
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "OUT=%HERE%build"
set "EX=%HERE%..\examples"

if not exist "%OUT%" mkdir "%OUT%" >nul 2>&1

call "%HERE%..\rsc.cmd" "%HERE%main.rsx" "%OUT%\rsc2.exe"
if errorlevel 1 exit /b 1

call "%HERE%..\rsc.cmd" "%HERE%t_lex.rsx" "%OUT%\t_lex.exe"
if errorlevel 1 exit /b 1

"%OUT%\t_lex.exe"
if errorlevel 1 exit /b 1

call "%HERE%..\rsc.cmd" "%HERE%t_parse.rsx" "%OUT%\t_parse.exe"
if errorlevel 1 exit /b 1

"%OUT%\t_parse.exe"
if errorlevel 1 exit /b 1

call "%HERE%..\rsc.cmd" "%HERE%t_bx.rsx" "%OUT%\t_bx.exe"
if errorlevel 1 exit /b 1

call "%HERE%..\rsc.cmd" "%HERE%t_fold.rsx" "%OUT%\t_fold.exe"
if errorlevel 1 exit /b 1

set "FILES="
for %%F in (hello structs arrays enums pointers tuples literals generics closures edge limits) do (
    "%OUT%\rsc2.exe" "%EX%\%%F.rsx" -o "%OUT%\%%F.rsi"
    if errorlevel 1 exit /b 1
    set "FILES=!FILES! "%OUT%\%%F.rsi""
)

"%OUT%\t_bx.exe" %FILES%
if errorlevel 1 exit /b 1

"%OUT%\t_fold.exe" %FILES%
if errorlevel 1 exit /b 1

echo rscx: ok
exit /b 0
