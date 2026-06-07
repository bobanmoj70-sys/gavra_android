# ML Server Auto-Startup (Windows)

## Šta ovo radi:
Automatski pokreće ML API server i ngrok tunnel kada se uloguješ na Windows.

## Fajlovi:
- `start-ml-server.ps1` - Glavna skripta koja pokreće ML API + ngrok
- `install-startup.bat` - Instalira auto-start (pokreni kao Administrator)
- `uninstall-startup.bat` - Uklanja auto-start (pokreni kao Administrator)

## Instalacija (JEDNOM):

1. **Desni klik** na `install-startup.bat`
2. Izaberi **"Run as administrator"**
3. Pritisni bilo koji taster kad završi

## Šta se dešava posle instalacije:

**Svaki put kad se uloguješ na Windows:**
- Pokrene se ML API server (http://localhost:8000)
- Pokrene se ngrok tunnel (javni URL)
- Sve radi u pozadini (ne vidiš prozore)

## Kako proveriti da li radi:

**1. Otvori browser i idi na:**
```
http://localhost:8000/health
```

**2. Ili proveri logove:**
```
C:\Users\Bojan\gavra_android\ml-service\logs\
```

## Važno:

**ngrok URL se menja svaki put!**
- Besplatni ngrok daje novi URL pri svakom pokretanju
- Flutter aplikacija mora koristiti aktuelni URL
- URL možeš videti u: `logs/ngrok-*.log`

## Za ručno pokretanje (bez restarta):

1. Otvori PowerShell
2. Pokreni:
```powershell
cd C:\Users\Bojan\gavra_android\ml-service
.\start-ml-server.ps1
```

## Za zaustavljanje:

**Option 1 - Task Manager:**
- Ctrl + Shift + Esc
- Nadji "python" i "ngrok"
- Desni klik → End task

**Option 2 - PowerShell:**
```powershell
Get-Process python, ngrok | Stop-Process -Force
```

## Uklanjanje auto-starta:

1. **Desni klik** na `uninstall-startup.bat`
2. Izaberi **"Run as administrator"**
