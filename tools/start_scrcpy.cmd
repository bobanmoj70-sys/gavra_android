@echo off
REM Dvostruki klik: scrcpy na test Huawei telefon (razbijen ekran)
cd /d "%~dp0\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_scrcpy.ps1" %*
