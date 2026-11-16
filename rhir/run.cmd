@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist tests mkdir tests

target\release\rhirc.exe %*
