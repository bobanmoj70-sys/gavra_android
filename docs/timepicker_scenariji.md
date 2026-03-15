# Timepicker scenariji — v3_putnik_profil_screen.dart

Putnik bira dan + grad + vreme kroz `_showTimePicker` → `_updatePolazak`.

---

## Scenario 1 — Nema zahteva
- `info = null`, `hasActive = false`
- Prikazuje se dugme **"dodaj"**
- Akcija: `createZahtev` → INSERT `v3_zahtevi` (`zeljeno_vreme`, `status=obrada`, `aktivno=true`)
- Trigger `fn_v3_sync` → kreira zapis u `v3_operativna_nedelja`
- **pg_cron** `fn_v3_pokreni_dispecera()` — pokreće se **svake minute**, pravila:
  - `dnevni` tip → **preskače, ide na ručnu obradu**
  - Čekanje: BC radnik/učenik(pre 16h) = 5 min, BC učenik(posle 16h) = čeka do 20h, VS = 10 min, pošiljka = 10 min
  - Kapacitet: čita `v3_app_settings.kapacitet_bc/vs`, broji zauzeta mesta u `v3_operativna_nedelja` za isti datum+grad+vreme
  - Ima mesta → `status=odobreno`, `dodeljeno_vreme = zeljeno_vreme` (do tada `dodeljeno_vreme = NULL`)
  - Nema mesta → `status=odbijeno`, `dodeljeno_vreme = NULL`, nudi max 2 alternative: `alt_vreme_pre` (prvi slobodan prije željenog) i `alt_vreme_posle` (prvi slobodan posle željenog)
- ✅ Ispravno

---

## Scenario 2 — Zahtev u obradi (`obrada`)
- `info != null`, status = `obrada`
- Ćelija prikazuje: **narandžasto-žuta boja + ⏳** (već ispravno u `_ZahtevCell`)
- Klik na ćeliju → **dijalog se NE otvara**
- Odmah se prikazuje snackbar: *"Vaš zahtev je u obradi. Nakon završetka možete poslati novi."*
- Razlog: putnik ne može spamovati kron — svaki UPDATE resetuje `updated_at` i čekanje kreće iznova
- Razlog: ne može otkazati zahtev u obradi — isti razlog (spam zaštita)
- Ostali dani i gradovi rade normalno
- ✅ Popravljeno — early return u `_showTimePicker` pre `showDialog`

---

## Scenario 3 — Zahtev odobren (`odobreno`)
- `info != null`, status = `odobreno`
- Putnik može promeniti vreme — **isto kao da šalje prvi put**
- `v3_zahtevi` se ažurira: `zeljeno_vreme = novo`, `dodeljeno_vreme = NULL`, `status = obrada`
- `dodeljeno_vreme = NULL` jer kron mora ponovo da odluči — kao da zahtev nikad nije bio odobren
- Trigger `fn_v3_sync_zahtev_to_operativna` → `COALESCE(NULL, novo_vreme)` → `v3_operativna_nedelja` dobija ispravno novo vreme
- Kron obrađuje od nule (čeka 5/10 min od `updated_at`)
- Nakon promene → ćelija prelazi u `obrada` (⏳ narandžasto) → Scenario 2 važi
- ✅ Popravljeno — `updateZeljenoVreme` sada šalje i `dodeljeno_vreme: null`

---

## Scenario 4 — Zahtev otkazan (`otkazano`)
- `info != null`, ali `hasActive = false`
- Prikazuje se samo grid vremena (bez Otkaži dugmeta)
- Klik na vreme → `createZahtev` (novi zahtev, status `obrada`)
- ✅ Ispravno

---

## Scenario 5 — Zaključavanje 15 minuta pre polaska
- Svako dugme u gridu ima svoju proveru: `now > polazak - 15min` → `onPressed: null`
- Dugme vizuelno zatamnjeno (bela boja 24% opacity, border white12)
- Razlog: kron treba max 10 min da obradi — 15 min je siguran buffer
- Važi za sve statuse osim `odobreno` — kod `odobreno` grid je zaključan ali **"Otkaži termin"** ostaje aktivan
- Implementacija: `datumPolaska = V3DanHelper.datumZaDanAbbr(dan)`, računato per-dugme u gridu
- ✅ Popravljeno

---

## Scenario 6 — Putnik pokupljen (`pokupljen`)
- `_ZahtevCell` prikazuje: **plava boja + 🚌** — vizualno OK, ne dira se
- Klik na ćeliju → **dijalog se NE otvara**
- Snackbar: *"🚌 Pokupljeni ste za ovo vreme. Nadamo se da ste imali ugodnu vožnju! 😊"*
- Implementacija: early return u `_showTimePicker` pre `showDialog`
- ✅ Popravljeno

---

## Napomene

- `_ZahtevCell` vizualni prikaz po statusu — ne dira se, ispravno
- Snack poruke su privremene — treba ih uskladiti u posebnom prolazu
- `updated_at` je auto-managed od DB trigera — Flutter ga ne šalje

---

## TODO

- [ ] Uskladiti sve snack poruke (tekst, tip: info/warning/error)
