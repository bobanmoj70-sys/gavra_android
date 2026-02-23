# 🪑 SEAT_REQUEST PRAVILA — ZAUVEK ZACEMENTIRANO

> **Ovo je jedini izvor istine za seat_requests logiku.**
> Svaki developer, svaki AI asistent, svaki refactor mora poštovati ovo.

---

## 1. ŠTA JE seat_requests

**Operativna tabela** — tekuće stanje vožnji za tekuću sedmicu.

```
putnik_id | datum | grad | zeljeno_vreme | status
```

- Jedan red = jedan putnik + jedan datum + jedan grad + jedno vreme
- **SME** da se briše i menja — to je njena svrha
- Čisti se subotom u 01:00 (redovi stariji od 30 dana)
- **NIJE** izvor za statistiku — za to postoji `voznje_log`

---

## 2. STATUSI — KOMPLETAN SPISAK

| Status | Ko ga setuje | Šta znači | Zauzima mesto? |
|--------|-------------|-----------|----------------|
| `pending` | Putnik (app) | Zahtev primljen, čeka dispečera | ✅ DA |
| `manual` | Putnik (app) | Dnevni putnik — admin obrađuje ručno | ✅ DA |
| `approved` | Dispečer / Admin | Odobreno, mesto zauzeto | ✅ DA |
| `confirmed` | Admin / Sync | Potvrđeno od admina ili sinhronizovano iz profila | ✅ DA |
| `pokupljen` | Vozač (app) | Putnik je fizički ušao u kombi | ✅ DA |
| `rejected` | Dispečer | Odbijeno — nema mesta, ponuđene alternative | ❌ NE |
| `otkazano` | Putnik / Vozač / Admin | Putnik otkazao vožnju — upisuje se u voznje_log | ❌ NE |
| `cancelled` | Sistem | Sistem poništio (npr. novo vreme izabrano) | ❌ NE |
| `bez_polaska` | Admin | Admin uklonio polazak (neutralno, NE upisuje se u log) | ❌ NE |

### Koji statusi ZAUZIMAJU MESTO (kapacitet):
```dart
['pending', 'manual', 'approved', 'confirmed']
// NE: pokupljen, rejected, otkazano, cancelled, bez_polaska
```

### Koji statusi su AKTIVNI (putnik se vozi):
```dart
['pending', 'manual', 'approved', 'confirmed', 'pokupljen']
```

### Koji statusi su OTKAZANI:
```dart
['otkazano', 'cancelled', 'rejected', 'bez_polaska']
```

---

## 3. ŽIVOTNI TOK STATUSA

```
                    ┌─────────────────────────────────┐
                    │          PUTNIK PRAVI ZAHTEV     │
                    └─────────────────┬───────────────┘
                                      │
                    ┌─────────────────▼───────────────┐
                    │  status = 'pending'              │
                    │  (mesečni/učenik/radnik)         │
                    └──────┬──────────────┬────────────┘
                           │              │
              dispečer     │              │  nema mesta
              odobri        │              │
                    ┌──────▼───┐    ┌─────▼──────────┐
                    │ approved │    │    rejected     │
                    └──────────┘    │ + alternative   │
                                    └─────────────────┘
            ─────────────────────────────────────────────
                    ┌─────────────────────────────────┐
                    │  DNEVNI PUTNIK (tip='dnevni')    │
                    └─────────────────┬───────────────┘
                                      │
                    ┌─────────────────▼───────────────┐
                    │  status = 'manual'               │
                    │  (admin odobrava ručno)          │
                    └──────────────────────────────────┘
            ─────────────────────────────────────────────
                    ┌─────────────────────────────────┐
                    │  ADMIN / SYNC IZ PROFILA         │
                    └─────────────────┬───────────────┘
                                      │
                    ┌─────────────────▼───────────────┐
                    │  status = 'confirmed'            │
                    │  (direktno, bez dispečera)       │
                    └──────────────────────────────────┘
            ─────────────────────────────────────────────
            IZ BILO KOG AKTIVNOG STATUSA:

            approved / confirmed / pokupljen
                    │
                    ├──── vozač klikne "Pokupljen" ──► status = 'pokupljen'
                    │
                    ├──── putnik/vozač/admin otkaže ──► status = 'otkazano'
                    │                                    + INSERT u voznje_log tip='otkazivanje'
                    │
                    └──── admin klikne "Bez polaska" ──► status = 'bez_polaska'
                                                          (NE upisuje se u log)
```

---

## 4. ZLATNO PRAVILO — SVAKA OPERACIJA MORA IMATI

```
putnik_id + datum + grad + zeljeno_vreme
```

**Nema izuzetaka.** Ako nedostaje grad ili vreme → operacija se ne radi.

### ✅ Ispravno:
```dart
supabase.from('seat_requests')
  .update({'status': 'pokupljen'})
  .eq('putnik_id', id)
  .eq('datum', datum)
  .eq('grad', grad)          // ← OBAVEZNO
  .eq('zeljeno_vreme', vreme) // ← OBAVEZNO
```

### ❌ Zabranjeno:
```dart
// BEZ GRADA I VREMENA — dira SVE termine tog dana
supabase.from('seat_requests')
  .update({'status': 'pokupljen'})
  .eq('putnik_id', id)
  .eq('datum', datum)
```

---

## 5. PRIORITET MATCHINGA (redosled pokušaja)

Svaka operacija (pokupljen, otkazano, plaćanje) mora pratiti ovaj redosled:

```
1. requestId (UUID) — PRIORITET 1, najtačniji
2. putnik_id + datum + grad + zeljeno_vreme — PRIORITET 2
3. Ako ni to ne nađe → logiraj grešku, NE radi fallback bez vremena
```

### ⛔ ZABRANJENO: fallback bez vremena
```dart
// NIKAD OVO:
if (requestId == null) {
  supabase.from('seat_requests')
    .update({...})
    .eq('putnik_id', id)
    .eq('datum', datum)
    // ← bez .eq('grad') i .eq('zeljeno_vreme') — ZABRANJENO
}
```

---

## 6. KADA SE UPISUJE U voznje_log

| Operacija | Upisuje se? | tip u logu |
|-----------|-------------|------------|
| Putnik pokupljen | ✅ DA | `'voznja'` |
| Putnik otkazan | ✅ DA | `'otkazivanje'` |
| Putnik platio (dnevni) | ✅ DA | `'uplata_dnevna'` |
| Putnik platio (mesečni) | ✅ DA | `'uplata_mesecna'` |
| Bez polaska | ❌ NE | — |
| cancelled (sistem) | ❌ NE | — |
| Termin zakazan | ✅ DA | `'zakazano'` |

### ⚠️ VAŽNO: voznje_log se NIKAD ne briše, NIKAD ne menja — samo INSERT

---

## 7. SYNC IZ PROFILA (_syncSeatRequestsWithTemplate)

Kada admin menja profil putnika (vreme, grad), sync funkcija kreira/ažurira seat_requests.

### Pravila synca:
- Ako je **vreme prazno** u formi → **preskoči, ne diraj ništa**
- Ako postoji seat_request sa statusom `otkazano` ili `pokupljen` → **ne ažuriraj**
- Ako postoji i status je isti i vreme je isto → **ne diraj**
- Ako ne postoji → **INSERT sa status='confirmed'**
- Ako postoji sa drugačijim vremenom → **UPDATE zeljeno_vreme + status='confirmed'**

### ⛔ ZABRANJENO u syncu:
```dart
// NIKAD postavljati bez_polaska kada je vreme prazno
if (vreme.isEmpty) {
  await supabase.from('seat_requests')
    .update({'status': 'bez_polaska'}) // ← ZABRANJENO
}
```

---

## 8. KAPACITET — KO ZAUZIMA MESTO

Kapacitet se računa samo za:
```sql
status IN ('pending', 'manual', 'approved', 'confirmed')
```

- `pokupljen` se NE računa u kapacitet (putnik je već u kombiju, slot je slobodan za sledeći dan)
- `rejected`, `otkazano`, `cancelled`, `bez_polaska` — ne zauzimaju

---

## 9. STATUS PRIORITET U PRIKAZU (UI)

Kada isti putnik ima više zahteva (edge case), prikazuje se po ovom prioritetu:

```dart
const statusPrioritet = {
  'bez_polaska': 0,
  'cancelled':   1,
  'otkazano':    2,
  'pending':     3,
  'manual':      4,
  'approved':    5,
  'confirmed':   6,
};
// Veći broj = prikazuje se (pregazi niži)
```

---

## 10. REGISTROVANI PUTNICI — PROFIL STATUS

Profil putnika (`registrovani_putnici.status`) je ODVOJEN od `seat_requests.status`.

| Profil status | Značenje | Utiče na seat_request? |
|--------------|----------|------------------------|
| `aktivan` | Normalno ide | ❌ — seat_request ima prednost |
| `bolovanje` | Na bolovanju | ✅ — override, prikazuje se 'bolovanje' |
| `godisnji` | Na godišnjem odmoru | ✅ — override, prikazuje se 'godišnji' |
| `neaktivan` | Ne vozi više | ❌ — nema novih seat_requests |

**Pravilo**: Ako je profil `bolovanje`/`godisnji` → to je primarna vrednost za prikaz bez obzira na seat_request status.

---

## 11. CACHE KLJUČEVI

Svaki cache koji uključuje seat_requests mora koristiti:

```
putnikId|datum|grad|vreme
```

### ❌ Zabranjeno (nedovoljno precizno):
```dart
'$putnikId|$datum'           // ← bez grad i vreme
'$putnikId|$datum|$grad'     // ← bez vreme
```

---

## 12. ČIŠĆENJE I RESET

| Kada | Šta | Ko |
|------|-----|----|
| Subota 01:00 | Fizičko brisanje seat_requests starijih od 30 dana | `ciscenje-seat-requests` cron |
| Subota 02:00 | Time picker se otključava za narednu sedmicu | Automatski |
| Svaki dan | Ćelija se zaključava kad nastupi njeno vreme | Frontend logika |

### ⛔ UKINUTO (ne postoji više):
- `sedmicni-reset-polazaka` — **OBRISANO**, ne vraćati

---

## 13. PUSH NOTIFIKACIJE ZA STATUS PROMENE

| Novi status | Notifikacija putniku |
|------------|---------------------|
| `approved` | "✅ Mesto osigurano!" |
| `rejected` + alternative | "⚠️ Termin pun — Izaberi alternativu" |
| `rejected` bez alternative | "❌ Termin pun — nema slobodnih mesta" |
| `otkazano` | (zavisi od ko je otkazao) |

Trigger: `notify_seat_request_update()` u Supabase — aktivira se **samo** ako se `status` promenio.

---

## ⛔ ZABRANJENA PONAŠANJA — KRATAK PREGLED

| Zabranjeno | Zašto |
|-----------|-------|
| Update/delete bez `grad` i `zeljeno_vreme` | Dira sve termine tog dana |
| Fallback bez vremena ako match ne uspe | Pokriva previše redova |
| Postavljanje `bez_polaska` kad je vreme prazno | Briše ručno kreirane termine |
| Korišćenje `voznje_log` za operativni prikaz | To je arhiva, ne tekuće stanje |
| Brisanje/menjanje redova u `voznje_log` | Trajni zapis, nikad se ne dira |
| Resetovanje svih seat_requests svakog tjedna | `sedmicni-reset` je ukinut |
| `UPDATE` bez `WHERE id = requestId` kada je requestId poznat | Uvek koristiti ID kada ga imaš |
