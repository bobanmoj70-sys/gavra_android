@echo off
:: Remove ML Server Auto-Start from Windows Task Scheduler
:: Run as Administrator

echo ============================================
echo Removing ML Server Auto-Startup
echo ============================================

:: Check if running as admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Please run as Administrator!
    pause
    exit /b 1
)

:: Remove scheduled task
schtasks /delete /tn "Gavra ML Server Auto-Start" /f

if %errorLevel% equ 0 (
    echo ============================================
    echo SUCCESS: Auto-start removed!
    echo ============================================
) else (
    echo Task was already removed or not found.
)

pause
