@echo off
setlocal
set "HERE=%~dp0"

if "%~1"=="" (
  echo usage: run.cmd ^<file.mini^> [out.exe]
  exit /b 2
)

call "%HERE%build.cmd" >nul
if errorlevel 1 (
  echo run: could not build the compiler
  exit /b 1
)

set "IN=%~f1"
if not "%~2"=="" (
  set "OUT=%~f2"
) else (
  set "OUT=%~dpn1.exe"
)

"%HERE%mini.exe" --aot "%IN%" -o "%OUT%"
exit /b %errorlevel%
