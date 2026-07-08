# Gavra AI Server - Uputstvo za pokretanje

## Šta je potrebno

- Laptop sa Windows 10/11
- Python 3.12+ sa instaliranim paketima iz `requirements.txt`
- Ollama aplikacija pokrenuta na laptopu (`http://localhost:11434`)
- Tailscale (opciono) za pristup sa telefona van kuće

## Brzo pokretanje

### 1. Prvi put nakon velikih izmena

Ako si upravo ažurirao `main.py` i promenio se šema baze, obriši staru lokalnu bazu:

```powershell
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'
Remove-Item -Path 'gavra_ai.db' -ErrorAction SilentlyContinue
```

### 2. Proveri da li je Ollama pokrenuta

```powershell
ollama list
```

Ako nije, pokreni Ollama aplikaciju ili:

```powershell
ollama serve
```

### 3. Pokreni server ručno

```powershell
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'
.\start_ai_server.ps1
```

Server će biti dostupan na:

```
http://localhost:8000
```

### 4. Automatsko pokretanje pri uključivanju Windows-a

Pokreni kao **Administrator**:

```powershell
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'
.\setup_autostart.ps1
```

Nakon toga, server će se automatski pokretati svaki put kada se prijaviš u Windows.

Korisne komande:

```powershell
# Pokreni odmah
Start-ScheduledTask -TaskName 'GavraAI_Server_Autostart'

# Zaustavi
Stop-ScheduledTask -TaskName 'GavraAI_Server_Autostart'

# Ukloni automatsko pokretanje
Unregister-ScheduledTask -TaskName 'GavraAI_Server_Autostart' -Confirm:$false
```

## Povezivanje sa Flutter aplikacijom

U Flutter `.env` fajlu postavi:

```dotenv
ML_BASE_URL=http://IP_ADRESA_LAPTOPA:8000
ML_API_KEY=tvoj-ist-kljuc-kao-u-main-py
```

Ako koristiš Tailscale:

```dotenv
ML_BASE_URL=http://100.x.x.x:8000
```

## Logovi

- Konzola: prikazuje se u prozoru gde je pokrenut server
- Fajl: `c:\Users\Bojan\gavra_android\ml-service\gavra_ai.log`
- Watchdog log: `c:\Users\Bojan\gavra_android\ml-service\server_watchdog.log`

## Resync podataka

U Flutter aplikaciji pritisni dugme 🔄 na AI ekranu da ponovo učiš sve podatke iz Supabase-a.

## Testiranje

```powershell
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'
python -m pytest test_main.py -v
```
