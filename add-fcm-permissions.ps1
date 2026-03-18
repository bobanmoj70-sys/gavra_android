# Firebase Service Account IAM Permissions Script
# Svrha: Dodeljuje Firebase Admin i Cloud Messaging dozvole service account-u

param(
    [string]$ProjectId = "gavra-notif-20250920162521",
    [string]$ServiceAccountEmail = "gavra-play-store@gavra-notif-20250920162521.iam.gserviceaccount.com"
)

Write-Host "Firebase Service Account IAM Permissions Script" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Project ID: $ProjectId" -ForegroundColor Yellow
Write-Host "Service Account: $ServiceAccountEmail" -ForegroundColor Yellow
Write-Host ""

# Provera da li je gcloud instaliran
Write-Host "[*] Proveravam gcloud CLI..."
try {
    $gcloudVersion = gcloud --version 2>&1 | Select-Object -First 1
    Write-Host "[+] gcloud je instaliran: $gcloudVersion" -ForegroundColor Green
} catch {
    Write-Host "[-] gcloud CLI nije instaliran!" -ForegroundColor Red
    Write-Host "Preuzmi ga sa: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "[*] Autentifikacija sa Google Cloud..."
try {
    $authOutput = gcloud auth login 2>&1
    Write-Host "[+] Autentifikacija uspesna" -ForegroundColor Green
} catch {
    Write-Host "[-] Autentifikacija neuspesna" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[*] Postavljam aktivni projekat na: $ProjectId"
try {
    gcloud config set project $ProjectId --no-user-output-enabled 2>&1
    Write-Host "[+] Projekat postavljen" -ForegroundColor Green
} catch {
    Write-Host "[-] Greska pri postavljanju projekta" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[*] Dostupne dozvole koje cu dodeliti:" -ForegroundColor Cyan
Write-Host "  1. roles/firebase.admin - Firebase Admin" -ForegroundColor Yellow
Write-Host "  2. roles/firebase.serviceManagementServiceConsumer" -ForegroundColor Yellow
Write-Host "  3. roles/cloudmessaging.admin - Cloud Messaging Admin" -ForegroundColor Yellow
Write-Host ""

# Lista dozvola koje trebaju
$roles = @(
    "roles/firebase.admin",
    "roles/cloudmessaging.admin",
    "roles/firebase.serviceManagementServiceConsumer"
)

# Dodeli sve dozvole
$successCount = 0
$failureCount = 0

foreach ($role in $roles) {
    Write-Host "[*] Dodeljujem rolu: $role" -ForegroundColor Magenta
    try {
        $output = gcloud projects add-iam-policy-binding $ProjectId `
            --member="serviceAccount:$ServiceAccountEmail" `
            --role="$role" `
            --condition=None `
            --no-user-output-enabled 2>&1
        
        Write-Host "    [+] Rola dodeljena uspesno" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "    [!] Greska pri dodeli: $_" -ForegroundColor Yellow
        $failureCount++
    }
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "[*] Rezultati:" -ForegroundColor Cyan
Write-Host "    [+] Uspesne dozvole: $successCount" -ForegroundColor Green
Write-Host "    [-] Greske: $failureCount" -ForegroundColor Red
Write-Host ""

# Verifikuj dozvole
Write-Host "[*] Verifikujem dozvole..." -ForegroundColor Cyan
try {
    $bindings = gcloud projects get-iam-policy $ProjectId `
        --flatten="bindings[].members" `
        --filter="bindings.members:serviceAccount:$ServiceAccountEmail" `
        --format="table(bindings.role)" 2>&1
    
    Write-Host "[*] Dostupne dozvole za service account:" -ForegroundColor Yellow
    $bindings | Where-Object { $_ -and $_ -notmatch "^ROLE" } | ForEach-Object {
        Write-Host "    - $_" -ForegroundColor Cyan
    }
} catch {
    Write-Host "[!] Greska pri verifikaciji: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[+] Zavrseno!" -ForegroundColor Green
Write-Host ""
Write-Host "[*] Sledeci koraci:" -ForegroundColor Cyan
Write-Host "    1. Cekaj 30-60 sekundi da se dozvole primene" -ForegroundColor Yellow
Write-Host "    2. Testiraj push notifikacije iz app-a" -ForegroundColor Yellow
Write-Host "    3. Ako i dalje ne rade, proveri Firebase projekt konfiguraciju" -ForegroundColor Yellow
Write-Host ""
