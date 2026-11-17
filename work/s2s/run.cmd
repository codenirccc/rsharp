@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "ROOT=%~dp0..\.."
if not exist build mkdir build
call "%ROOT%\rsc.cmd" "%ROOT%\mini\s2s.rsx" "build\s2s.exe"
if errorlevel 1 (
  echo FAIL-BUILD s2s
  exit /b 1
)
set "FAIL=0"
for %%f in ("%ROOT%\mini\examples\*.mini") do (
  set "NAME=%%~nf"
  build\s2s.exe < "%%f" > "build\!NAME!.rsx"
  if errorlevel 1 (
    echo FAIL-S2S !NAME!
    set "FAIL=1"
  ) else (
    call "%ROOT%\rsc.cmd" "build\!NAME!.rsx" "build\!NAME!.exe" >nul
    if errorlevel 1 (
      echo FAIL-BUILD !NAME!
      set "FAIL=1"
    ) else (
      build\!NAME!.exe > "build\!NAME!.out"
      fc /b "build\!NAME!.out" "%ROOT%\mini\examples\!NAME!.out" >nul
      if errorlevel 1 (
        echo FAIL-RUN !NAME!
        set "FAIL=1"
      ) else (
        echo ok !NAME!
      )
    )
  )
)
for %%f in (*.mini) do (
  set "NAME=%%~nf"
  build\s2s.exe < "%%f" > "build\x_!NAME!.rsx"
  if errorlevel 1 (
    echo FAIL-S2S !NAME!
    set "FAIL=1"
  ) else (
    call "%ROOT%\rsc.cmd" "build\x_!NAME!.rsx" "build\x_!NAME!.exe" >nul
    if errorlevel 1 (
      echo FAIL-BUILD !NAME!
      set "FAIL=1"
    ) else (
      build\x_!NAME!.exe > "build\x_!NAME!.out"
      fc /b "build\x_!NAME!.out" "%~dp0!NAME!.out" >nul
      if errorlevel 1 (
        echo FAIL-RUN !NAME!
        set "FAIL=1"
      ) else (
        echo ok !NAME!
      )
    )
  )
)
if "%FAIL%"=="1" exit /b 1
echo s2s suite: ok
exit /b 0
