# START dugme — Optimizacija rute (VozacScreen)

## Gde se nalazi
`lib/screens/vozac_screen.dart` → `_buildOptimizeButton()`

---

## Stanja dugmeta

| Stanje | Boja | Tekst | Šta se dešava na klik |
|---|---|---|---|
| Ruta nije optimizovana | Bela | `START` | Pokreće optimizaciju rute |
| Ruta optimizovana, GPS ne radi | Zelena | `START` | Pokreće GPS tracking |
| GPS tracking aktivan | Narandžasta | `STOP` | Zaustavlja GPS tracking |

Dugme je **onemogućeno** (`canPress = false`) ako:
- `_isOptimizing` je `true` (optimizacija u toku)
- `_isLoading` je `true`
- Vozač nije validan (`_currentDriver == null` ili nije u `VozacCache`)

---

## Tok — 1. klik (optimizacija)

```
_buildOptimizeButton()
  └─> _optimizeCurrentRoute(filtriraniPutnici)
        ├─ Proveri vozača (VozacCache.isValidIme)
        ├─ Filtriraj putnike:
        │    - isti polazak kao _selectedVreme
        │    - nisu: otkazani / bez_polaska / pokupljeni / odsustvo / pending
        │    - imaju validnu adresu (adresaId ili adresa != grad)
        ├─> SmartNavigationService.optimizeRouteOnly()
        │     ├─> PermissionService.ensureGpsForNavigation()  ← traži GPS dozvolu
        │     ├─> Geolocator.getCurrentPosition()             ← GPS pozicija vozača
        │     ├─> UnifiedGeocodingService (geocoding adresa)  ← koordinate putnika
        │     └─> OsrmService.optimizeRoute()                 ← TSP algoritam (OSRM API)
        ├─ Postavi: _optimizedRoute, _isRouteOptimized, _putniciEta
        └─> AUTOMATSKI poziva _startGpsTracking()
```

**Putnici BEZ adrese** se dodaju na **početak** liste (preskočeni), ne izbacuju se.

---

## Tok — 2. klik (GPS tracking)

```
_buildOptimizeButton()
  └─> _startGpsTracking()
        ├─ Proveri: _isRouteOptimized && !_optimizedRoute.isEmpty && _currentDriver != null
        ├─> DriverLocationService.instance.startTracking(...)
        │     - vozacId, vozacIme, grad, vremePolaska, smer
        │     - putniciEta (ETA po imenu iz OSRM)
        │     - putniciRedosled (redosled iz optimizovane rute)
        │     - onAllPassengersPickedUp callback
        ├─ setState: _isGpsTracking = true
        └─> _sendVozacKrenulNotifikacije()
              └─ Za svakog aktivnog putnika u _optimizedRoute:
                   RealtimeNotificationService.sendNotificationToPutnik()
                   title: "🚌 [VozačIme] kreće!"
                   body:  "Dolazak za oko X min." / "Vozač je krenuo po vas!"
                   data:  { type: 'vozac_krenuo', vozac, eta_minuta, grad, vreme }
```

**Smer** se određuje automatski:
- Grad sadrži "bela" → `BC_VS`
- Ostalo → `VS_BC`

---

## Dozvole (GPS)

Poziva se u `SmartNavigationService._getCurrentPosition()`:

```
PermissionService.ensureGpsForNavigation()
```

Proverava:
1. `Permission.location` — da li je dozvoljena lokacija
2. `Geolocator.isLocationServiceEnabled()` — da li je GPS uključen na uređaju

Ako nešto nedostaje → baca `Exception('GPS dozvole nisu odobrene ili GPS nije uključen')` što `_startGpsTracking()` hvata i prikazuje kao `AppSnackBar.error`.

---

## Push notifikacije pri STARTu

Šalju se **samo putnicima** (ne vozačima):
- Samo aktivni putnici: nisu `jePokupljen`, `jeOtkazan`, `jeOdsustvo`, `jeBezPolaska`
- Token se čita iz tabele `push_tokens` po `putnik_id`
- Notifikacija tipa `vozac_krenuo` → putnik tapne → otvara se `VozacScreen` (realtime ETA prikaz)

---

## Automatska reoptimizacija

Nakon što vozač promeni status putnika (pokupljen/otkazan), automatski se poziva:
```
_reoptimizeAfterStatusChange()
  └─> SmartNavigationService.optimizeRouteOnly() (od trenutne GPS pozicije)
```
Pokreće se samo ako je `_isRouteOptimized == true`.

---

## Relevantni fajlovi

| Fajl | Uloga |
|---|---|
| `lib/screens/vozac_screen.dart` | UI dugme, orchestracija |
| `lib/services/smart_navigation_service.dart` | Optimizacija rute, GPS pozicija |
| `lib/services/osrm_service.dart` | TSP algoritam (OpenStreetMap Routing Machine) |
| `lib/services/unified_geocoding_service.dart` | Geocoding adresa putnika |
| `lib/services/driver_location_service.dart` | GPS tracking (realtime lokacija) |
| `lib/services/realtime_notification_service.dart` | Slanje push notifikacija putnicima |
| `lib/services/permission_service.dart` | GPS dozvole |
| `lib/config/route_config.dart` | Koordinate BC i VS |
