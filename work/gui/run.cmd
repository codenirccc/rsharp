@echo off
setlocal
set "HERE=%~dp0"
cd /d "%HERE%"
if not exist build mkdir build
set "RSC=%HERE%..\..\rsc.cmd"

echo [1/5] headless core
call "%RSC%" t_core.rsx build\t_core.exe
if errorlevel 1 exit /b 1
build\t_core.exe
if errorlevel 1 exit /b 1

echo [2/5] pixel hash
call "%RSC%" p7.rsx build\p7.exe
if errorlevel 1 exit /b 1
build\p7.exe > build\p7.txt
if errorlevel 1 exit /b 1
findstr /c:"hash=-3815621724631491153" build\p7.txt >nul
if errorlevel 1 (
    echo gui suite: pixel hash drift
    exit /b 1
)

echo [3/5] window loop
call "%RSC%" t_win.rsx build\t_win.exe
if errorlevel 1 exit /b 1
build\t_win.exe
if errorlevel 1 exit /b 1

echo [4/5] windows demo
call "%RSC%" demo.rsx build\demo.exe
if errorlevel 1 exit /b 1

echo [5/5] macos cross-build
call "%RSC%" -t macos demo_mac.rsx build\demo_mac
if errorlevel 1 exit /b 1
python check_macho.py build\demo_mac
if errorlevel 1 exit /b 1

echo [6/6] paint selftest
call "%RSC%" paint.rsx build\paint.exe
if errorlevel 1 exit /b 1
call "%RSC%" t_paint.rsx build\t_paint.exe
if errorlevel 1 exit /b 1
cd /d "%HERE%build"
t_paint.exe
if errorlevel 1 exit /b 1
cd /d "%HERE%"
del build\paint.bmp >nul 2>&1

echo gui suite: ok
