# Auto-start ML API + Tailscale Funnel
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
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting ML API..."
    Start-Process -FilePath "C:\Users\Bojan\AppData\Local\Programs\Python\Python312\python.exe" -ArgumentList "api/main.py" -WorkingDirectory $mlServicePath -WindowStyle Hidden -RedirectStandardOutput $mlLog -RedirectStandardError $mlErrLog
}

# Wait for ML API to be ready
Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Waiting for ML API on port 8000..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {}
}

if (-not $ready) {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): ERROR: ML API did not become ready"
    exit 1
}

# Check if Funnel is already running
$funnelStatus = & tailscale funnel status 2>$null
if ($funnelStatus -match "Funnel on") {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Tailscale Funnel already running"
} else {
    Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Starting Tailscale Funnel..."
    & tailscale funnel --bg 8000 2>&1 | Out-String | ForEach-Object { Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): $_" }
}

# Verify
$funnelStatus = & tailscale funnel status 2>$null
Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Final status:`n$funnelStatus"
Add-Content -Path "$logPath\startup.log" -Value "$(Get-Date): Done. Public URL: https://win-vfeglqf71ss.tail61b7a2.ts.net/"
