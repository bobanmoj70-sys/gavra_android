# Deploy ML service na Hugging Face Space
# Pokretanje: .\deploy-to-hf.ps1

$HF_REPO = "https://huggingface.co/spaces/gavriconi/gavra-ml-api"
$HF_DIR = "C:\Users\Bojan\hf-space-temp"
$ML_DIR = "C:\Users\Bojan\gavra_android\ml-service"

# Kloniraj ako ne postoji, inace pull
if (-Not (Test-Path $HF_DIR)) {
    Write-Host "Kloniram HF Space..." -ForegroundColor Cyan
    git clone $HF_REPO $HF_DIR
} else {
    Write-Host "Pullujem izmene..." -ForegroundColor Cyan
    git -C $HF_DIR pull
}

# Fajlovi i folderi za sync
$itemsToSync = @("api", "data", "models", "training", "services", "config.py", "requirements.txt", "Dockerfile", ".dockerignore")

foreach ($item in $itemsToSync) {
    $src = Join-Path $ML_DIR $item
    $dst = Join-Path $HF_DIR $item
    if (Test-Path $src) {
        Copy-Item $src $dst -Recurse -Force
        Write-Host "Kopiran: $item" -ForegroundColor Green
    }
}

# Commit i push
Set-Location $HF_DIR
git add -A

$status = git status --porcelain
if ($status) {
    $msg = Read-Host "Commit poruka (Enter za default)"
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = "Deploy ML service update"
    }
    git commit -m $msg
    git push
    Write-Host "Deploy uspešan!" -ForegroundColor Green
} else {
    Write-Host "Nema izmena za deploy." -ForegroundColor Yellow
}

Set-Location "C:\Users\Bojan\gavra_android"
