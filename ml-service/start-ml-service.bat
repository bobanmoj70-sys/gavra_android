@echo off
chcp 65001 >nul
cd /d "C:\Users\Bojan\gavra_android\ml-service"
if not exist "logs" mkdir logs
set LOGFILE=logs\ml-api-auto.log
set ERRFILE=logs\ml-api-auto-error.log
echo [%date% %time%] Starting Gavra ML API... >> %LOGFILE%
"C:\Users\Bojan\AppData\Local\Programs\Python\Python312\python.exe" api\main.py >> %LOGFILE% 2>> %ERRFILE%
