# Gavra AI Server - Uputstvo za pokretanje

## Šta je potrebno

- Laptop sa Windows 10/11
- Python 3.12+ sa instaliranim paketima iz `requirements.txt`
- Besplatan Gemini API kljuc sa https://aistudio.google.com/app/apikey
- Tailscale (opciono) za pristup sa telefona van kuće

## Brzo pokretanje

### 1. Prvi put nakon velikih izmena

Ako si upravo ažurirao `main.py` i promenio se šema baze, obriši staru lokalnu bazu:

```powershell
Set-Location -Path 'c:\Users\Bojan\gavra_android\ml-service'
Remove-Item -Path 'gavra_ai.db' -ErrorAction SilentlyContinue
```

### 2. Podesi .env fajl

Kopiraj `.env.example` u `.env` i popuni:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
ML_API_KEY=your-secure-random-key-here
GEMINI_API_KEY=your-gemini-api-key
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

## OSRM konfiguracija (rute i ETA)

AI server (`main.py`) sada sadrži ugrađeni reverse proxy za OSRM na putanji `/osrm/*`.
To znači da Tailscale Funnel prosleđuje `/osrm` na `http://127.0.0.1:8000/osrm`, a AI server
skida `/osrm` prefiks i prosleđuje zahtev lokalnom OSRM Docker kontejneru na portu 5000.

### Potrebno u `.env` fajlu

```dotenv
# Lokalni OSRM (Docker) - obično se ne menja
OSRM_LOCAL_URL=http://127.0.0.1:5000

# Javna adresa koja se koristi u Supabase Edge Functions
# Tailscale Funnel primer:
OSRM_BASE_URL=https://tvoj-tailscale-url/osrm
# Lokalna mreža primer:
# OSRM_BASE_URL=http://192.168.x.x:8000/osrm
```

### Supabase Edge Functions

U Supabase Dashboard-u ili CLI-ju postavi sledeće secrete za funkcije:
- `v3-compute-eta`
- `v3-auto-prepare-termins`

Secreti:
- `OSRM_BASE_URL` — mora biti ista vrednost kao `OSRM_BASE_URL` iz `.env` fajla.
- `ML_API_KEY` — mora biti ista vrednost kao `ML_API_KEY` iz `.env` fajla. Ruta `/osrm/*` je
  zaštićena istim API ključem kao i ostatak AI servera (samo `/` health-check je izuzet), pa
  Edge Functions moraju slati `X-API-Key` header pri pozivu OSRM proxy-ja preko Funnel-a.

Postavljanje secreta primer:

```powershell
supabase secrets set ML_API_KEY=tvoj-isti-kljuc-kao-u-main-py
```

### Testiranje OSRM proxy-ja

Lokalno (bez ključa radi jer se lokalni Docker OSRM ne poziva preko `/osrm` proxy-ja iz browsera,
ali sam AI server i dalje zahteva `X-API-Key` za `/osrm/*`):

```powershell
$headers = @{ "X-API-Key" = "tvoj-ml-api-key" }
Invoke-RestMethod -Headers $headers -Uri "http://127.0.0.1:8000/osrm/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false"
```

Preko Tailscale Funnel-a:

```powershell
$headers = @{ "X-API-Key" = "tvoj-ml-api-key" }
Invoke-RestMethod -Headers $headers -Uri "https://tvoj-tailscale-url/osrm/route/v1/driving/21.4243,44.9028;21.3011,45.1187?overview=false"
```

Oba zahteva treba da vrate `code: Ok`. Bez header-a `X-API-Key` server vraća `401 Unauthorized`.

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
