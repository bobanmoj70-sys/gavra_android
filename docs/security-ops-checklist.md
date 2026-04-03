# Security Ops Checklist

Kratka operativna lista za rad sa tajnama i release pipeline-om.

## 1) Lokalni setup (jednom po mašini)

- Koristi samo `.env.example` kao template.
- Pravi lokalni `.env` fajl i nikad ga ne commit-uj.
- Tajne drži u env varijablama ili `*_FILE` varijantama (za fajl putanje).
- Ne čuvaj realne tokene u `README`, `*.md`, `*.txt`, niti u skriptama.

## 2) Git pravila pre svakog commita

- Proveri status:
  - `git status --short`
- Proveri da nema token patterna:
  - `ghp_`, `github_pat_`, `AIza`, `BEGIN PRIVATE KEY`
- Ako nešto nađeš:
  - ukloni iz fajla,
  - prebaci u `.env`/Secrets manager,
  - tek onda commit.

## 3) MCP skripte i tajne

- `github-mcp/setup-secrets.cjs` koristi env (`GITHUB_TOKEN`, `GOOGLE_PLAY_KEY_B64`, ...).
- Za osetljive vrednosti koristi i `*_FILE` opcije kad je praktičnije.
- Nikad ne hardkoduj lozinke, key alias ili lokalne putanje do tajnih fajlova.

## 4) iOS/Android secret fajlovi

- U repou drži samo primer fajlove (`*.example*`).
- Realne fajlove sa tajnama drži lokalno ili u CI Secrets.
- `ios/github-secrets.example.txt` služi kao template, ne kao realan config.

## 5) CI/CD praksa

- Sve produkcione tajne drži u GitHub/Codemagic Secrets.
- Rotacija tajni na incident ili sumnju kompromitacije.
- Ograniči scope tokena na minimum potreban za workflow.

## 6) Brza pre-push provera

```powershell
git status --short
git grep -n -E "ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z\-_]{20,}|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----" -- .
```

Ako druga komanda vrati rezultat, stopiraj push dok se nalaz ne očisti.
