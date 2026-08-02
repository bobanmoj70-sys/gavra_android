#Requires -Version 5.1
<#
    Pokrece scrcpy sa opcijama koje sprecavaju gasenje ekrana
    i olaksavaju upravljanje telefonom sa polomljenim ekranom.
#>

Write-Host "Provera ADB uredjaja..." -ForegroundColor Cyan
adb devices

Write-Host "Produzavam screen timeout na 30 min..." -ForegroundColor Cyan
adb shell settings put system screen_off_timeout 1800000

Write-Host "Budim ekran..." -ForegroundColor Cyan
adb shell input keyevent 224

Write-Host "Pokrecem scrcpy..." -ForegroundColor Green
# --stay-awake       : ekran (logicki) ne gasi dok je USB prikljucen
# --turn-screen-off  : GASI fizicki ekran telefona (stedi bateriju, sprecava
#                      slucajne dodire na razbijenom staklu) dok scrcpy i dalje
#                      normalno prikazuje i kontrolise telefon sa racunara
# --show-touches     : prikazuje gde klikas na telefonu, korisno za proveru
# -S / --turn-screen-off gasi ekran ODMAH pri pokretanju
scrcpy --stay-awake --turn-screen-off --show-touches
