@echo off
setlocal
cd /d %~dp0
dotnet build fixture\fixture.csproj -c Release --nologo -v q
if errorlevel 1 exit /b 1
copy /y fixture\fixture.runtimeconfig.json fixture\bin\Release\net10.0\fixture.runtimeconfig.json >nul
if errorlevel 1 (
  echo dotnet: runtimeconfig copy failed
  exit /b 1
)
if not exist build mkdir build
call ..\..\rsc.cmd t_clrhost.rsx build\t_clrhost.exe
if errorlevel 1 exit /b 1
build\t_clrhost.exe
if errorlevel 1 exit /b 1
call ..\..\rsc.cmd t_fnptr.rsx build\t_fnptr.exe
if errorlevel 1 exit /b 1
build\t_fnptr.exe
if errorlevel 1 exit /b 1
