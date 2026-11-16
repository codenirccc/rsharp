@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist build mkdir build
set "FAILED=0"
if /i "%~1"=="up" goto :fixtures_up
if /i "%~1"=="down" goto :fixtures_down

for %%t in (
  t_hash t_hmac t_gcm t_bn t_der t_ec t_rsa t_sha t_x25519 t_x509 t_roots
  t_trust t_qtls t_tphex
  t_hpack t_qpack t_h2frame t_quic t_quicframe t_quicconn t_sec
) do call :run %%t

call :fixtures_up

for %%t in (t_transport t_tls t_https t_h2 t_request t_quiclive t_h3) do call :run %%t

call :fixtures_down

echo.
if "%FAILED%"=="0" (
  echo http suite: ok
  exit /b 0
)
echo http suite: %FAILED% failing
exit /b 1

:run
set "N=%~1"
if not exist "%N%.rsx" exit /b 0
call "..\..\rsc.cmd" "%N%.rsx" "build\%N%.exe" >nul 2>"build\%N%.err"
if errorlevel 1 (
  echo FAIL-BUILD %N%
  type "build\%N%.err"
  set /a FAILED+=1
  exit /b 0
)
"build\%N%.exe"
if errorlevel 1 (
  echo FAIL-RUN %N%
  set /a FAILED+=1
)
exit /b 0

:fixtures_up
start /b python server.py 8099 > build\fx_http.log 2>&1
start /b python https_server.py rsa 4433 > build\fx_https_rsa.log 2>&1
start /b python https_server.py ec 4434 > build\fx_https_ec.log 2>&1
start /b python http2_server.py rsa 4443 > build\fx_h2_rsa.log 2>&1
start /b python http2_server.py ec 4444 > build\fx_h2_ec.log 2>&1
start /b python proxy_server.py 8888 > build\fx_proxy.log 2>&1
start /b python h3_server.py 4445 > build\fx_h3.log 2>&1
ping -n 4 127.0.0.1 >nul
exit /b 0

:fixtures_down
for %%p in (http_8099 srv_rsa_4433 srv_ec_4434 srv_rsa_4443 srv_ec_4444 proxy_8888 h3_4445) do (
  if exist "%%p.pid" (
    set "FPID="
    set /p FPID=<"%%p.pid"
    if not "!FPID!"=="" taskkill /f /pid !FPID! >nul 2>&1
    del /q "%%p.pid" >nul 2>&1
  )
)
exit /b 0
