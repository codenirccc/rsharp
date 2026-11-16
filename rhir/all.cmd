@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
cargo build --release
if errorlevel 1 exit /b 1
if not exist tests mkdir tests
del /q tests\*.out*.rhir tests\*.exe 2>nul
for /f "delims=" %%f in ('dir /b /a-d "tests\*.rhir" ^| findstr /v /i /e /c:".out.rhir"') do (
  echo == %%f
  target\release\rhirc.exe "tests\%%f" -o "tests\%%~nf.exe"
  if errorlevel 1 exit /b 1
  target\release\rhirc.exe "tests\%%f" --emit-ir > "tests\%%~nf.out.rhir"
  if errorlevel 1 exit /b 1
  target\release\rhirc.exe "tests\%%~nf.out.rhir" -o "tests\%%~nf.rt.exe"
  if errorlevel 1 exit /b 1
  tests\%%~nf.exe
  set a=!ERRORLEVEL!
  tests\%%~nf.rt.exe
  set b=!ERRORLEVEL!
  echo exit=!a! roundtrip=!b!
  if not "!a!"=="!b!" exit /b 1
)
