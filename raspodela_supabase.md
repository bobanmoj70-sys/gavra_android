# Raspodela — Supabase tabele

---

## Tabela: `vozac_raspored`

Raspodela **celog termina** vozaču.

| Kolona | Tip | Obavezno |
|---|---|---|
| `id` | uuid | DA (auto) |
| `dan` | text | DA |
| `grad` | text | DA |
| `vreme` | text | DA |
| `vozac` | text (ime) | DA |
| `vozac_id` | uuid | NE |

**Ključ:** `dan + grad + vreme` → jedinstveno identifikuje termin

**Trenutni podaci:**
| dan | grad | vreme | vozač |
|---|---|---|---|
| sre | BC | 18:00 | Voja |
| sre | VS | 19:00 | Voja |
| cet | BC | 15:30 | Voja |
| cet | BC | 18:00 | Voja |
| cet | VS | 17:00 | Voja |
| cet | VS | 19:00 | Voja |

---

## Tabela: `vozac_putnik`

Raspodela **pojedinačnog putnika** vozaču.

| Kolona | Tip | Obavezno |
|---|---|---|
| `id` | uuid | DA (auto) |
| `putnik_id` | uuid | DA |
| `vozac_id` | uuid | DA |
| `vozac` | text (ime) | DA |
| `dan` | text | DA |
| `grad` | text | DA |
| `vreme` | text | DA |
| `created_at` | timestamptz | DA (auto) |
| `updated_at` | timestamptz | DA (auto) |

**Trenutni podaci:** prazna tabela (nema individualnih raspodela)

---

## Veza između tabela

Obe tabele dele isti ključ: `dan + grad + vreme`

```
vozac_raspored          vozac_putnik
─────────────────       ──────────────────────────
dan  ─────────────────► dan
grad ─────────────────► grad
vreme ────────────────► vreme
vozac (ime)             vozac (ime)
vozac_id (nullable)     vozac_id (NOT NULL)
                        putnik_id → registrovani_putnici.id
```

---

## Logika u kodu

### `VozacRasporedService.filterPutniciZaVozaca`
- Ako termin nema unosa u `vozac_raspored` → putnik vidljiv **svima**
- Ako postoji unos → putnik vidljiv **samo tom vozaču**
- Poređenje: UUID-first (`vozac_id`), fallback na ime (`vozac`)

### `VozacPutnikService.filterKombinovan`
- Ako termin nema unosa u `vozac_raspored` → putnik **NIJE vidljiv** (nema raspodele)
- Ako postoji unos → putnik vidljiv samo vozaču termina
- Parametar `overrides` postoji ali je **neaktivan** (`// zadržano radi compat, nije u upotrebi`)

### `VozacPutnikService.set` (upis u `vozac_putnik`)
- Upisuje individualnu raspodelu putnika
- **Ne proverava** da li termin već postoji u `vozac_raspored` — ova logika nedostaje
- Treba dodati: pre `upsert` → query `vozac_raspored` po `dan + grad + vreme`

---

## Šta nedostaje / treba popraviti

- [ ] `VozacPutnikService.set` — dodati proveru `vozac_raspored` pre upisa
- [ ] UI (`vozac_raspored_screen.dart`) — sakriti dugme `+osoba` ako termin postoji u `vozac_raspored`
- [ ] `vozac_id` u `vozac_raspored` je nullable — provera vozača mora koristiti ime kao fallback (već implementirano u `jeVozacov`)
- [x] `filterOverrides` uklonjen iz koda
