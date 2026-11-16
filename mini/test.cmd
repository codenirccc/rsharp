@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist "..\build" mkdir "..\build"
call build.cmd >nul
if errorlevel 1 (
  echo FAIL-BUILD mini
  exit /b 1
)

set "FAIL=0"

for %%f in (examples\*.mini) do (
  set "OK=1"
  "mini.exe" --aot "%%f" -o "..\build\%%~nf.exe" >nul 2>&1
  if errorlevel 1 (
    echo FAIL-AOT %%~nf
    set "FAIL=1"
    set "OK=0"
  )
  if "!OK!"=="1" (
    "..\build\%%~nf.exe" > "..\build\%%~nf.out" 2>nul
    fc /b "..\build\%%~nf.out" "examples\%%~nf.out" >nul
    if errorlevel 1 (
      echo FAIL-RUN %%~nf
      set "FAIL=1"
      set "OK=0"
    )
  )
  if "!OK!"=="1" (
    "mini.exe" --jit "%%f" > "..\build\%%~nf.jit" 2>nul
    if errorlevel 1 (
      echo FAIL-JIT %%~nf
      set "FAIL=1"
      set "OK=0"
    ) else (
      fc /b "..\build\%%~nf.jit" "examples\%%~nf.out" >nul
      if errorlevel 1 (
        echo FAIL-JIT-RUN %%~nf
        set "FAIL=1"
        set "OK=0"
      )
    )
  )
  if "!OK!"=="1" (
    "mini.exe" < "%%f" > "..\build\%%~nf.rsi"
    if errorlevel 1 (
      echo FAIL-FILTER %%~nf
      set "FAIL=1"
      set "OK=0"
    ) else (
      "..\backend\rscb.exe" "..\build\%%~nf.rsi" -o "..\build\%%~nf.f.exe" -t windows >nul 2>&1
      if errorlevel 1 (
        echo FAIL-LINK %%~nf
        set "FAIL=1"
        set "OK=0"
      )
    )
  )
  if "!OK!"=="1" echo ok %%~nf
)

"mini.exe" -v > "..\build\banner.txt" 2>&1
findstr /c:"mini Compiler for R# 1.2" "..\build\banner.txt" >nul
if errorlevel 1 (
  echo FAIL-BANNER title
  set "FAIL=1"
) else (
  findstr /c:"jit + aot - one file - no runtime" "..\build\banner.txt" >nul
  if errorlevel 1 (
    echo FAIL-BANNER tagline
    set "FAIL=1"
  ) else (
    echo ok banner
  )
)

if "%FAIL%"=="1" exit /b 1
exit /b 0
