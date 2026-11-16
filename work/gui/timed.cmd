@echo off
setlocal
cd /d "%~dp0"
echo start %TIME%
"build\%~1.exe"
echo end %TIME% code=%errorlevel%
