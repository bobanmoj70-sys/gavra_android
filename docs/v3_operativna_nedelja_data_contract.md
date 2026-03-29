# V3 Operativna Nedelja — Data Contract (GPS/Route)

## Svrha
`v3_operativna_nedelja` je **izvor istine za operativni plan** po putniku/terminu.

- Ko je dodeljen kom terminu
- Koja adresa ide u pickup
- Status trackinga termina
- Redosled rute (`route_order`)

`v3_vozac_lokacije` ostaje odvojena tabela za live telemetriju vozača (`lat/lng`).

---

## Ključne kolone i odgovornosti

| Kolona | Svrha | Ko piše | Ko čita |
|---|---|---|---|
| `vozac_id` | Dodeljeni vozač za red | `v3_admin_raspored_screen.dart` (bulk/individual dodela) | `v3_vozac_screen.dart`, `v3_foreground_gps_service.dart`, admin/izveštaji |
| `datum` | Dan termina | sistem pri kreiranju reda | svi filteri termina |
| `grad` | Smer/grad termina (`BC`/`VS`) | sistem/admin | vozač/admin/filteri |
| `dodeljeno_vreme` / `zeljeno_vreme` | Termin vremena | dispečer/admin/sistem | vozač tracking i filteri |
| `status_final` | Operativni status reda | workflow zahteva/vozača/admina | vozač, tracking filteri |
| `aktivno` | Soft-aktivnost reda | workflow/admin | svi aktivni upiti |
| `adresa_id_override` | Ručno pregažena adresa za taj red | admin/operativni update | `V3SmartNavigationService`, kartice putnika |
| `koristi_sekundarnu` | Signal izbora sekundarne adrese | zahtevi/admin | putnik kartica, navigacija |
| `adresa_id` | Legacy snapshot adrese prilikom dodele vozača | admin dodela | trenutno nije deo OSRM toka |
| `pickup_naziv` | Legacy snapshot naziva pickup adrese | admin dodela | trenutno nije deo OSRM toka |
| `pickup_lat` / `pickup_lng` | Legacy snapshot pickup koordinata | admin dodela | trenutno nije deo OSRM toka |
| `route_order` | Redosled vožnje po putniku | vozač posle OSRM optimizacije (`v3_vozac_screen.dart`) | vozač prikaz, admin uvid |
| `gps_status` | Status trackinga termina (`pending`/`tracking`) | `v3_foreground_gps_service.dart`, admin reseti | vozač/admin monitoring |
| `notification_sent` | Da li je tracking notifikacija već krenula | foreground tracking + admin reset | workflow/monitoring |
| `estimated_pickup_time` | Legacy kolona (ne koristi se) | — | — |
| `polazak_vreme` | Informativno vreme polaska termina | admin dodela | GPS tracking tok |
| `activation_time` | Legacy kolona (više se ne upisuje) | — | — |

---

## Pravila upisa (must-have)

### 1) Dodela/izmena vozača
Pri promeni dodele (`vozac_id`) za red/termin obavezno:
- `route_order = null`
- `gps_status = 'pending'`
- `notification_sent = false`

### 2) Promena adrese ili vremena
Pri promeni bilo kog od:
- `adresa_id_override`
- `koristi_sekundarnu`
- `grad`
- `dodeljeno_vreme` / `zeljeno_vreme`

obavezno reset:
- `route_order = null`

### 3) Posle uspešne OSRM optimizacije
- Upisati `route_order` za svaki relevantan `id` reda.
- Upis treba da ide po `id` reda (ne samo po `putnik_id`) da se izbegnu kolizije kada isti putnik ima više redova.

---

## Trenutno stanje u kodu (verifikovano)

- `route_order` se sada upisuje iz `v3_vozac_screen.dart` posle uspešne OSRM optimizacije.
- Admin dodela sada puni samo operativne kolone (`vozac_id`, `gps_status`, `notification_sent`, `polazak_vreme`) i resetuje `route_order` pri uklanjanju dodele.
- `gps_status` i `notification_sent` sink se radi iz `v3_foreground_gps_service.dart`.

---

## Preporučeni sledeći koraci

1. **Legacy servis je uklonjen**: `v3_route_optimization_service.dart` više ne postoji u kodu.
2. **Dodati DB trigger/pravilo** za automatski reset `route_order` na promenu adrese/vremena/vozača.
3. **Obrisati legacy kolone iz baze**: `adresa_id`, `pickup_naziv`, `pickup_lat`, `pickup_lng`, `estimated_pickup_time`, `activation_time`.
4. **Zadržati operativni minimum**: `vozac_id`, `datum`, `grad`, `dodeljeno_vreme/zeljeno_vreme`, `status_final`, `aktivno`, `adresa_id_override`, `koristi_sekundarnu`, `route_order`, `gps_status`, `notification_sent`, `polazak_vreme`.

---

## Granica odgovornosti između tabela

- `v3_operativna_nedelja` = operativni plan i route metadata po putniku/terminu.
- `v3_vozac_lokacije` = trenutna telemetrija vozača (live pozicija).

Ne mešati putničke route metapodatke u `v3_vozac_lokacije`.
