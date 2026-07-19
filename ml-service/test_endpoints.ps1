# Test svi endpointi - Za PowerShell na Windows

$BaseURL = "http://localhost:8000"
$ApiKey = "your-api-key-here"
$Headers = @{
    "x-api-key" = $ApiKey
    "Content-Type" = "application/json"
}

Write-Host "=== GAVRA AI - ENDPOINT TEST SUITE ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "1️⃣  Health Check" -ForegroundColor Green
Invoke-RestMethod -Uri "$BaseURL/" -Method Get | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "2️⃣  Živi logovi" -ForegroundColor Green
Invoke-RestMethod -Uri "$BaseURL/logs" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "3️⃣  Autoencoder - Osnovna anomalija detektuje" -ForegroundColor Green
Invoke-RestMethod -Uri "$BaseURL/neural" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "4️⃣  Živi tok razmišljanja mreže" -ForegroundColor Green
Invoke-RestMethod -Uri "$BaseURL/neural/thoughts" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "5️⃣  Entity Embeddings - Naučene veze" -ForegroundColor Green
Invoke-RestMethod -Uri "$BaseURL/neural/relations" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "6️⃣  🆕 TEMPORAL - Trend anomalije" -ForegroundColor Yellow
Invoke-RestMethod -Uri "$BaseURL/neural/temporal" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "7️⃣  🆕 CROSS-TABLE - FK veze i kontekst anomalije" -ForegroundColor Yellow
Invoke-RestMethod -Uri "$BaseURL/neural/cross-table" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "8️⃣  🆕 FEATURE IMPORTANCE - Koja kolona je kriva?" -ForegroundColor Yellow
Invoke-RestMethod -Uri "$BaseURL/neural/importance" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "9️⃣  🆕 USER FEEDBACK - Pošalji povratnu info" -ForegroundColor Yellow
$FeedbackBody = @{
    table = "orders"
    source_id = "12345"
    is_anomaly = $false
    user_note = "Normalno za tog korisnika"
} | ConvertTo-Json

Invoke-RestMethod -Uri "$BaseURL/neural/feedback" `
    -Method Post `
    -Headers $Headers `
    -Body $FeedbackBody | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "🔟 FEEDBACK SUMMARY - Pregled korisnikove povratne info" -ForegroundColor Yellow
Invoke-RestMethod -Uri "$BaseURL/neural/feedback-summary" -Method Get -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "🔄 RESYNC - Ručno osvežavanje učenja" -ForegroundColor Cyan
Invoke-RestMethod -Uri "$BaseURL/resync" -Method Post -Headers $Headers | ConvertTo-Json | Write-Host

Write-Host ""
Write-Host "✅ Svi testovi završeni!" -ForegroundColor Green
