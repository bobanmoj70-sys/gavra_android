# Auto-start ML API and ngrok tunnel
# This script runs on Windows startup

$mlServicePath = "C:\Users\Bojan\gavra_android\ml-service"
$ngrokPath = "C:\Users\Bojan\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe"
$logPath = "$mlServicePath\logs"

# Create logs directory if not exists
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$mlLog = "$logPath\ml-api-$timestamp.log"
$mlErrLog = "$logPath\ml-api-error-$timestamp.log"
$ngrokLog = "$logPath\ngrok-$timestamp.log"
$ngrokErrLog = "$logPath\ngrok-error-$timestamp.log"

# Check if ML API is already running
$mlApiRunning = Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*api/main.py*" }
if ($mlApiRunning) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ML API already running, skipping..."
} else {
    # Start ML API in background
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting ML API..."
    Start-Process -FilePath "python" -ArgumentList "api/main.py" -WorkingDirectory $mlServicePath -WindowStyle Hidden -RedirectStandardOutput $mlLog -RedirectStandardError $mlErrLog
}

# Wait for ML API to start
Start-Sleep -Seconds 10

# Check if ngrok is already running
$ngrokRunning = Get-Process | Where-Object { $_.ProcessName -eq "ngrok" }
if ($ngrokRunning) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ngrok already running, skipping..."
} else {
    # Start ngrok tunnel
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting ngrok tunnel..."
    Start-Process -FilePath $ngrokPath -ArgumentList "http 8000" -WindowStyle Hidden -RedirectStandardOutput $ngrokLog -RedirectStandardError $ngrokErrLog
}

Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Startup complete. Check logs folder for URLs."
