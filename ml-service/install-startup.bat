@echo off
:: Install ML Server Auto-Start for Windows Task Scheduler
:: Run as Administrator

echo ============================================
echo Installing ML Server Auto-Startup
echo ============================================

:: Check if running as admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Please run as Administrator!
    pause
    exit /b 1
)

:: Create scheduled task
schtasks /create ^
    /tn "Gavra ML Server Auto-Start" ^
    /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Users\Bojan\gavra_android\ml-service\start-ml-server.ps1\"" ^
    /sc onlogon ^
    /rl highest ^
    /f

if %errorLevel% equ 0 (
    echo ============================================
    echo SUCCESS: Auto-start installed!
    echo ============================================
    echo.
    echo ML API and ngrok will start automatically when you log in.
    echo.
    echo To test now, run: start-ml-server.ps1
    echo To remove later, run: uninstall-startup.bat
    echo ============================================
) else (
    echo ERROR: Failed to create scheduled task.
    echo Try running this batch file as Administrator.
)

pause
