@echo off
setlocal
set "HERE=%~dp0"
set "OUT=%HERE%..\..\build"
set "PATH=C:\msys64\mingw64\bin;%PATH%"
if not exist "%OUT%" mkdir "%OUT%"
gcc -O2 -shared -o "%OUT%\c_add.dll" "%HERE%c_add.c"
if errorlevel 1 exit /b 1
g++ -O2 -shared -o "%OUT%\cpp_shim.dll" "%HERE%cpp_shim.cpp"
if errorlevel 1 exit /b 1
echo built build\c_add.dll and build\cpp_shim.dll
