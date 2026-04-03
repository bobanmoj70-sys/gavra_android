# 🔐 GitHub MCP Server - Secrets Management

MCP server za upravljanje GitHub repository secretima kroz Copilot.

## Setup

### 1. Kreiraj GitHub Personal Access Token

1. Idi na: https://github.com/settings/tokens
2. Klikni "Generate new token"
3. Odaberi "tokens (classic)"
4. Dodaj scopes:
   - `repo` (full control of private repositories)
   - `read:org` (read organization data)
5. Generiši token i sačuvaj ga negdje bezbedno

### 2. Konfiguriši .env fajl

```bash
cp .env.example .env
```

Uredi `.env` i dodaj:
```
GITHUB_TOKEN=YOUR_GITHUB_TOKEN_HERE
GITHUB_REPO_OWNER=lakisa-code
GITHUB_REPO_NAME=gavra_android
```

Ako koristiš `setup-secrets.cjs`, dodaj i Android secret vrednosti
(direktno ili preko `*_FILE` varijanti):

```
GOOGLE_PLAY_KEY_B64=
GOOGLE_PLAY_KEY_B64_FILE=
ANDROID_KEYSTORE_B64=
ANDROID_KEYSTORE_B64_FILE=
ANDROID_KEYSTORE_PASSWORD=
ANDROID_KEYSTORE_PASSWORD_FILE=
ANDROID_KEY_PASSWORD=
ANDROID_KEY_PASSWORD_FILE=
ANDROID_KEY_ALIAS=
```

### 3. Instalacija zavisnosti

```bash
npm install
```

### 4. Build

```bash
npm run build
```

## Korišćenje sa Copilot

### Postavi jedan secret

```
Postavi GitHub secret:
- Ime: GOOGLE_PLAY_KEY_B64
- Vrednost: [Base64 encoded key]

Koristi github_set_secret alat
```

### Postavi više secreta odjednom

```
Postavi ove GitHub secrete:
- GOOGLE_PLAY_KEY_B64: [value]
- ANDROID_KEYSTORE_B64: [value]
- ANDROID_KEYSTORE_PASSWORD: [value]
- ANDROID_KEY_PASSWORD: [value]
- ANDROID_KEY_ALIAS: gavra_key

Koristi github_set_secrets_batch alat sa svim secretima
```

### Pregled svih secreta

```
Prikaži sve GitHub secrete u repozitorijumu

Koristi github_list_secrets alat
```

### Obriši secret

```
Obriši GitHub secret: GOOGLE_PLAY_KEY_B64

Koristi github_delete_secret alat
```

## Dostupni Alati

### `github_set_secret`
Postavi ili ažuriraj jedan secret

**Input:**
- `secret_name`: Ime sekreata
- `secret_value`: Vrednost sekreata

**Primer:**
```json
{
  "secret_name": "GOOGLE_PLAY_KEY_B64",
  "secret_value": "eyJhbGciOiJIUzI1NiIs..."
}
```

### `github_list_secrets`
Prikaži sve secrete u repozitorijumu

**Input:** Bez parametara

### `github_delete_secret`
Obriši secret

**Input:**
- `secret_name`: Ime sekreata za brisanje

### `github_set_secrets_batch`
Postavi više secreta odjednom

**Input:**
- `secrets`: Objekat sa secret imenima kao ključevi i vrednostima kao vrednosti

**Primer:**
```json
{
  "secrets": {
    "GOOGLE_PLAY_KEY_B64": "eyJhbGciOiJIUzI1NiIs...",
    "ANDROID_KEYSTORE_B64": "...",
    "ANDROID_KEYSTORE_PASSWORD": "mypassword"
  }
}
```

## Bezbednost

⚠️ **Važno:**
- Nikada ne deli tvoj GitHub token sa drugima
- Čuvaj `.env` fajl lokalno, ne pushuj ga na git
- Secreti su enkriptovani sa GitHub javnim ključem repozitorijuma

## Troubleshooting

### Greška: "Missing required environment variable: GITHUB_TOKEN"
- Proveri da li je `.env` fajl konfigurisan
- Proveri da li je `GITHUB_TOKEN` postavljen

### Greška: "Authentication failed"
- Proveri da li je token validan
- Proveri da li token ima potrebne scope-ove (`repo`)

### Greška: "Repository not found"
- Proveri `GITHUB_REPO_OWNER` i `GITHUB_REPO_NAME`
- Proveri da li token ima pristup tom repozitorijumu

## Integracija sa Copilot

Dodaj u Copilot konfiguraciju:

```json
{
  "mcpServers": {
    "github": {
      "command": "node",
      "args": ["path/to/github-mcp/dist/index.js"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}",
        "GITHUB_REPO_OWNER": "lakisa-code",
        "GITHUB_REPO_NAME": "gavra_android"
      }
    }
  }
}
```

---

Za dodatnu pomoć, vidi: GitHub Actions setup dokumentaciju
