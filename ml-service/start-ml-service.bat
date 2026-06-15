@echo off
chcp 65001 >nul
cd /d "C:\Users\Bojan\gavra_android\ml-service"
if not exist "logs" mkdir logs
set LOGFILE=logs\ml-api-auto.log
set ERRFILE=logs\ml-api-auto-error.log

:: Ubij sve stare Python procese koji drze port 8000
echo [%date% %time%] Stopping old Python processes... >> %LOGFILE%
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%a /F >nul 2>&1
)
timeout /t 2 /nobreak >nul

echo [%date% %time%] Starting Gavra ML API... >> %LOGFILE%
"C:\Users\Bojan\AppData\Local\Programs\Python\Python312\python.exe" api\main.py >> %LOGFILE% 2>> %ERRFILE%
