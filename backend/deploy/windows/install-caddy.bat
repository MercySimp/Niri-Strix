@echo off
REM ============================================================
REM  Caddy Web Server - Download and service install
REM  Run as Administrator
REM ============================================================

SET CADDY_DIR=C:\Caddy
SET CADDY_EXE=%CADDY_DIR%\caddy.exe
SET CADDY_CONFIG=%CADDY_DIR%\Caddyfile
SET LOG_DIR=%CADDY_DIR%\logs

echo [1/4] Creating Caddy directory...
mkdir "%CADDY_DIR%" 2>nul
mkdir "%LOG_DIR%" 2>nul

echo [2/4] Downloading latest Caddy for Windows amd64...
powershell -Command "Invoke-WebRequest -Uri 'https://caddyserver.com/api/download?os=windows&arch=amd64' -OutFile '%CADDY_EXE%'"

echo [3/4] Copying Caddyfile...
copy /y "%~dp0Caddyfile" "%CADDY_CONFIG%"

echo [4/4] Installing Caddy as a Windows service...
"%CADDY_EXE%" add-package github.com/mholt/caddy-ratelimit 2>nul
"%CADDY_EXE%" install-service --config "%CADDY_CONFIG%"

net start caddy

echo.
echo Caddy is running. TLS cert for api.accesshomeserver.uk will be issued
echo automatically on first request (port 80 + 443 must be open in your router).
pause
