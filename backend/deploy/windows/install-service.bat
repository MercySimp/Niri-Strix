@echo off
REM ============================================================
REM  Deck Shell Backend - Windows Service Installer
REM  Uses NSSM (Non-Sucking Service Manager) to run uvicorn
REM  as a proper Windows service that survives reboots.
REM
REM  Prerequisites:
REM    1. Python 3.11+ installed and on PATH
 REM    2. NSSM downloaded to C:\nssm\nssm.exe
 REM       https://nssm.cc/download
REM    3. Run this script as Administrator
REM ============================================================

SET SERVICE_NAME=DeckShellBackend
SET BACKEND_DIR=%~dp0..\..
SET VENV_PYTHON=%BACKEND_DIR%\.venv\Scripts\python.exe
SET UVICORN=%BACKEND_DIR%\.venv\Scripts\uvicorn.exe
SET ENV_FILE=%BACKEND_DIR%\.env
SET NSSM=C:\nssm\nssm.exe
SET LOG_DIR=C:\DeckShell\logs

echo [1/5] Creating log directory...
mkdir "%LOG_DIR%" 2>nul

echo [2/5] Creating Python venv and installing dependencies...
cd /d "%BACKEND_DIR%"
python -m venv .venv
call .venv\Scripts\activate.bat
pip install -r requirements.txt

echo [3/5] Copying .env template if .env does not exist...
if not exist "%ENV_FILE%" (
    copy "%~dp0.env.template" "%ENV_FILE%"
    echo.
    echo  *** IMPORTANT: Edit %ENV_FILE% and set your DECK_SECRET and STEAM_API_KEY before starting the service. ***
    echo.
    pause
)

echo [4/5] Installing Windows service via NSSM...
"%NSSM%" install %SERVICE_NAME% "%UVICORN%"
"%NSSM%" set %SERVICE_NAME% AppParameters "main:app --host 127.0.0.1 --port 8000"
"%NSSM%" set %SERVICE_NAME% AppDirectory "%BACKEND_DIR%"

:: Load .env variables into the service environment
for /f "usebackq tokens=1,2 delims==" %%A in ("%ENV_FILE%") do (
    if not "%%A"=="" if not "%%A:~0,1%"=="#" (
        "%NSSM%" set %SERVICE_NAME% AppEnvironmentExtra "%%A=%%B"
    )
)

"%NSSM%" set %SERVICE_NAME% AppStdout "%LOG_DIR%\deck-backend.log"
"%NSSM%" set %SERVICE_NAME% AppStderr "%LOG_DIR%\deck-backend-error.log"
"%NSSM%" set %SERVICE_NAME% AppRotateFiles 1
"%NSSM%" set %SERVICE_NAME% AppRotateBytes 10485760
"%NSSM%" set %SERVICE_NAME% Start SERVICE_AUTO_START

echo [5/5] Starting service...
"%NSSM%" start %SERVICE_NAME%

echo.
echo Done. Service '%SERVICE_NAME%' is running.
echo Backend available at http://localhost:8000
echo Once Caddy is running: https://api.accesshomeserver.uk
pause
