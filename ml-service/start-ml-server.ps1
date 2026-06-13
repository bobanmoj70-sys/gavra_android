# Auto-start ML API (Tailscale Funnel handles public HTTPS)
# This script runs on Windows startup

$mlServicePath = "C:\Users\Bojan\gavra_android\ml-service"
$logPath = "$mlServicePath\logs"

# Create logs directory if not exists
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$mlLog = "$logPath\ml-api-$timestamp.log"
$mlErrLog = "$logPath\ml-api-error-$timestamp.log"

# Check if ML API is already running
$mlApiRunning = Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*api/main.py*" }
if ($mlApiRunning) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ML API already running, skipping..."
} else {
    # Start ML API in background
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting ML API..."
    Start-Process -FilePath "C:\Users\Bojan\AppData\Local\Programs\Python\Python312\python.exe" -ArgumentList "api/main.py" -WorkingDirectory $mlServicePath -WindowStyle Hidden -RedirectStandardOutput $mlLog -RedirectStandardError $mlErrLog
}

Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ML API started. Tailscale Funnel must be running separately: tailscale funnel 8000"
