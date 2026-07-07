# Gavra ML Server startup skripta
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'

# Provera da li je server već pokrenut
$existing = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Server je već pokrenut na portu 8000." -ForegroundColor Yellow
    exit 0
}

Write-Host "Pokrećem Gavra ML Server..." -ForegroundColor Green
python main.py
