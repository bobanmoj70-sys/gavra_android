# Auto-start ML API and Cloudflare tunnel
# This script runs on Windows startup

$mlServicePath = "C:\Users\Bojan\gavra_android\ml-service"
$cloudflaredPath = "$mlServicePath\cloudflared.exe"
$logPath = "$mlServicePath\logs"

# Create logs directory if not exists
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$mlLog = "$logPath\ml-api-$timestamp.log"
$mlErrLog = "$logPath\ml-api-error-$timestamp.log"
$tunnelLog = "$logPath\tunnel-$timestamp.log"
$tunnelErrLog = "$logPath\tunnel-error-$timestamp.log"

# Check if ML API is already running
$mlApiRunning = Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*api/main.py*" }
if ($mlApiRunning) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ML API already running, skipping..."
} else {
    # Start ML API in background
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting ML API..."
    Start-Process -FilePath "C:\Users\Bojan\AppData\Local\Programs\Python\Python312\python.exe" -ArgumentList "api/main.py" -WorkingDirectory $mlServicePath -WindowStyle Hidden -RedirectStandardOutput $mlLog -RedirectStandardError $mlErrLog
}

# Wait for ML API to start
Start-Sleep -Seconds 10

# Check if cloudflared is already running
$cloudflaredRunning = Get-Process | Where-Object { $_.ProcessName -eq "cloudflared" }
if ($cloudflaredRunning) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): cloudflared already running, skipping..."
} else {
    # Start Cloudflare quick tunnel
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting Cloudflare tunnel..."
    Start-Process -FilePath $cloudflaredPath -ArgumentList "tunnel","--url","http://localhost:8000","--no-autoupdate" -WorkingDirectory $mlServicePath -WindowStyle Hidden -RedirectStandardOutput $tunnelLog -RedirectStandardError $tunnelErrLog
}

Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Startup complete. Check logs folder for URLs."
