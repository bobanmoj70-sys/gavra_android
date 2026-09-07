# Pazar Realtime Arhitektura (V3)

Ovaj dokument opisuje kako je organizovan tok za obavezni unos pazara i gde su granice odgovornosti između realtime manager-a i UI sloja.

## Cilj

- Jedan centralni izvor realtime događaja.
- Poslovna logika van widget-a.
- UI sloj samo prikazuje popup kada dobije event.

## Komponente

- `lib/services/realtime/v3_master_realtime_manager.dart`
  - Drži cache i realtime revizije tabela.
  - Pokreće i zaustavlja pazar monitoring (`startPazarMonitoring`, `stopPazarMonitoring`).
  - Izračunava da li je potreban unos pazara.
  - Emituje `V3PazarPromptEvent` preko `pazarPromptStream`.

- `lib/widgets/v3_pazar_listener.dart`
  - Pretplaćuje se na `pazarPromptStream`.
  - Prikazuje `V3VozacPazarPopup`.
  - Ne sadrži poslovna pravila za proveru pazara.

## Tok događaja

1. `V3PazarListener` poziva `startPazarMonitoring()`.
2. `V3MasterRealtimeManager` sluša revizije:
   - `v3_uplata_pazara`
   - `v3_trenutna_dodela`
   - `v3_operativna_nedelja`
   i periodični timer.
3. Manager proverava:
   - da li je politika aktivna (`pazar_policy_start_date`),
   - stanje dnevne uplate za vozača,
   - da li je prošlo 60 minuta od poslednje vožnje,
   - da li postoji pazar > 0.
4. Ako treba, manager upisuje `zahtevanUnos=true` i emituje `V3PazarPromptEvent`.
5. UI prima event i otvara blokirajući popup.
6. Nakon snimanja popup poziva upis sa `zahtevanUnos=false`.

## Važna pravila

- `V3MasterRealtimeManager` ne sme da koristi `BuildContext`, `Navigator` ili `showDialog`.
- `V3PazarListener` ne sme da sadrži poslovnu logiku za izračun pravila.
- Za više listener-a koristi se subscriber count u manager-u da monitoring ne stane prerano.

## Ako se menja ponašanje

Kod budućih izmena:

- menjati pravila u manager-u,
- zadržati event kontrakt (`V3PazarPromptEvent`) stabilnim,
- UI menjati samo za prikaz i UX popup-a.
