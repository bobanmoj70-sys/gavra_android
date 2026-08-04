# 🚀 WINDOWS OPTIMIZACIJA ZA DEVELOPMENT

## 1. Power Settings
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  # High Performance

## 2. Disable Windows Search Indexing
sc config "WSearch" start= disabled
sc stop "WSearch"

## 3. Disable Windows Defender real-time (PAŽLJIVO!)
# Set-MpPreference -DisableRealtimeMonitoring $true

## 4. Increase Virtual Memory
# Idi u System Properties > Advanced > Performance > Settings > Advanced > Virtual Memory
# Postaviti na Custom size: Initial = 8192MB, Maximum = 12288MB

## 5. Disable Visual Effects
# System Properties > Advanced > Performance > Settings > "Adjust for best performance"

## 6. Clean Temp Files
Get-ChildItem -Path $env:TEMP -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Windows\Temp" -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

## 7. Disable Startup Programs
# Win+R > msconfig > Startup tab > Disable all except essential

## 8. Flutter/Android Optimization
$env:GRADLE_OPTS = "-Xmx2048m -XX:MaxPermSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8"
$env:ANDROID_SDK_ROOT = "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk"