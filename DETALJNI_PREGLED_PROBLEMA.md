# 🔍 DETALJNI PREGLED PROBLEMA #1 i #2

## PROBLEM #1: RACE CONDITION U AUTO-PREPARE KRONU I TRACKING POKREĆU

### 📋 Tokovi i vremenske sekvence

#### SCENARIO 1A: Idealno (nije problem)
```
Time    Komponenta              Akcija                          Status
T0      v3-auto-prepare-termins Auto-prepare kron:
                                1. Pronađi termine (5 min prije) ✓
                                2. Create/update v3_trenutna_dodela_slot
                                   - datum=2026-07-22, grad=BC, vreme=05:00, vozac=ABC
                                   - Upiši auto_prepared_at=T0
T+1ms   v3-auto-prepare-termins 3. Pročitaj vozčevu lokaciju iz drugih slotova
T+5ms   v3-auto-prepare-termins 4. Call auto-prepare za putnikove (waypoints_json)
T+100ms v3-auto-prepare-termins 5. Pošalji push vozaču (notify_push RPC)
T+101ms v3-auto-prepare-termins 6. Upiši auto_driver_notified_at=T+100ms ✓ ← FLAG UPISEM
        
        ✅ TRANSAKCIJA COMMITOVANA ✓

T+500ms FCM              Push stigne vozaču sa:
                        - vozac_id=ABC
                        - datum=2026-07-22
                        - grad=BC
                        - vreme=05:00

T+600ms _autoStartVozacTrackingFromPush():
        1. Ekstrahuj: vozacId=ABC, grad=BC, vreme=05:00, datumIso=2026-07-22
        2. Call activateSlot(ABC, BC, 05:00) — UPSERT
           - onConflict: $colDatum,$colGrad,$colVreme,$colVozacId
           - Kron je već upisao, pa upsert samo osvežava updated_at
        3. Prosljeđi termin tracking servisu
        4. Pokreni tracking ✓

        ✅ SVEUKUPNO: Sve radi dobro — push dolazi POSLE nego što je kron upisao
```

#### SCENARIO 1B: RACE CONDITION - Push dolazi PRE nego kron commituje ⚠️
```
Time    Komponenta              Akcija                          DB Vidljivo
T0      v3-auto-prepare-termins Pronađi termine
        
T+50ms  v3-auto-prepare-termins Kreiruj slot (start transakcije)
        
T+100ms v3-auto-prepare-termins Popuni waypoints_json
        
T+150ms v3-auto-prepare-termins Pošalji push (RPC notify_push)
                                  — PUSH POČINJE DA SE ŠALJE
        
T+160ms v3-auto-prepare-termins Upiši auto_driver_notified_at=T+160ms
        ⚠️ ALI JE TRANSAKCIJA JOŠ U LETENJU - Supabase gotovo nije video upsert
        
T+180ms v3-auto-prepare-termins Commit transakcije
        ✓ Sad je sve vidljivo bazi: slot postoji
        
T+200ms FCM delivers push    Push stigne vozaču — OK, transport bio brž
        
T+220ms _autoStartVozacTrackingFromPush():
        1. activateSlot(ABC, BC, 05:00)
        2. setActiveTermin() — OK, informacija je sveža
        3. start() — POKRENI TRACKING ✓
        
        ✅ ALI: Ako bi push stigao T+170ms (PRE commit-a):
           - v3_trenutna_dodela_slot red još nije vidljiv
           - activateSlot() UPSERT će kreirati novi red
           - Kron će vidjeti dva reda (duplikat!) ili conflict
```

### 🔴 KRITIČNI DEO: `_autoStartVozacTrackingFromPush()` NEMA RETRY LOGIKE

**Trenutni kod u `main.dart` (line 1078):**
```dart
try {
  await V3TrenutnaDodelaSlotService.activateSlot(
    datumIso: datumIso,
    grad: grad,
    vreme: vreme,
    vozacId: vozacId,
    updatedBy: vozacId,
  );
} catch (e) {
  debugPrint('⚠️ [AUTO-START] activateSlot greška (nastavljam): $e');
  // ⚠️ GREŠKA SE IGNORIŠE - TRACKING POČINJE SVE ISTO!
}
```

**Problem:**
```dart
// ODMAH POSLE CATCH-a (bez čekanja):
V3VozacLocationTrackingService.instance.setActiveTermin(...);
await V3VozacLocationTrackingService.instance.start(vozacId: vozacId);

// ALI AKO SLOT NIJE VIDLJIV BAZI JOŠ:
// 1. setActiveTermin() je OK (to je samo lokalna varijabla)
// 2. start() je OK (počinje GPS tracking)
// 3. ALI kada first GPS update stigne do v3-compute-eta...
//    → edge funkcija traži slot sa grad+vreme
//    → vj može biti race ako slot još nije vidljiv
//    → vraća "no_active_slot"
//    → ETA ne razmjenjuje - vozač vidi praznu listu putnika!
```

---

## PROBLEM #2: UPSERT CONFLICT U `v3_eta_results` SA VIŠE SLOTOVA

### 📋 Database schema problem

**Tabela `v3_eta_results`:**
```sql
CREATE TABLE v3_eta_results (
  id UUID PRIMARY KEY,
  vozac_id TEXT NOT NULL,
  termin_id TEXT NOT NULL,
  putnik_id TEXT NOT NULL,
  eta_seconds INT,
  computed_at TIMESTAMPTZ,
  UNIQUE(termin_id, putnik_id)  ← ⚠️ PROBLEM!
)
```

### 🔴 SCENARIO: Vozač ABC sa dva slota istog dana

```
Datum: 2026-07-22
Vozač: ABC (id=abc123)

SLOT 1: BC, 05:00 (ruta u Novi Sad)
  - Putnik P1: lat=45.00, lng=21.00
  - Putnik P2: lat=45.01, lng=21.01
  - Putnik P3: lat=45.02, lng=21.02

SLOT 2: VS, 06:00 (ruta u Variš - suprotni grad)
  - Putnik P4: lat=44.90, lng=21.42
  - Putnik P5: lat=44.91, lng=21.43
  - Putnik P1 (ISTI PUTNIK!): lat=44.92, lng=21.44
```

### 🔴 VREMENSKI REDOSLIJED PROBLEMA

```
Time    Akcija                              DB State
-----   ----------------------------------------

T0      Vozač ABC pokreće START za BC 05:00

T+1s    v3-compute-eta edge funkcija:
        1. Pronađe aktivni slot: BC, 05:00 (grad=BC, vreme=05:00)
           activeslot.id = slot_bc_1
        
        2. Čita passengers iz waypoints_json:
           [P1@45.00,21.00, P2@45.01,21.01, P3@45.02,21.02]
        
        3. Poziva OSRM sa koordinatama
        
        4. Dobija optimizovani redoslijed: [P2, P1, P3]
        
        5. Pravi upsertRows:
           [
             {termin_id="t1", putnik_id="p1", vozac_id="abc", eta=120s},
             {termin_id="t2", putnik_id="p2", vozac_id="abc", eta=80s},
             {termin_id="t3", putnik_id="p3", vozac_id="abc", eta=180s},
           ]
        
        6. UPSERT sa onConflict: "termin_id,putnik_id"
           ✓ Sve ide OK — termin_id su RAZLIČITI (t1, t2, t3)
           
        v3_eta_results sada:
        ┌──────────────┬──────────┬─────────────────┐
        │ termin_id    │ putnik_id│ vozac_id        │
        ├──────────────┼──────────┼─────────────────┤
        │ t1           │ p1       │ abc             │
        │ t2           │ p2       │ abc             │
        │ t3           │ p3       │ abc             │
        └──────────────┴──────────┴─────────────────┘

T+5s    Vozač se prebacuje na SLOT 2: VS, 06:00 (ručno!)
        Poziva _handleSelectVreme(_selectedVreme = "06:00")
        
        PROBLEM: Trebalo bi da očisti ETA iz slot 1!
        ALI: Kod ne čisti automatski — vozač vidi stariju rutu

T+10s   Vozač klikne START za VS 06:00
        
T+11s   v3-compute-eta edge funkcija (DRUGI POZIV):
        1. setActiveTermin() postavi: grad=VS, vreme=06:00
        
        2. Pronađe aktivni slot: VS, 06:00
           activeSlot.id = slot_vs_1
        
        3. Čita passengers:
           [P4@44.90,21.42, P5@44.91,21.43, P1@44.92,21.44]
        
        4. OSRM optimizacija: [P4, P1, P5]
        
        5. Pravi upsertRows:
           [
             {termin_id="t4", putnik_id="p4", vozac_id="abc", eta=100s},
             {termin_id="t5", putnik_id="p1", vozac_id="abc", eta=150s},  ← P1 OPET!
             {termin_id="t6", putnik_id="p5", vozac_id="abc", eta=200s},
           ]
        
        6. UPSERT sa onConflict: "termin_id,putnik_id"
           
           ⚠️ ALI: Red (t5, p1) JE NOV
           🔴 ALI RED (t1, p1) JE STARI I OSTAJE U BAZI!
           
           REZULTAT: v3_eta_results sad sadrži:
           ┌──────────────┬──────────┬─────────────────┐
           │ termin_id    │ putnik_id│ vozac_id        │
           ├──────────────┼──────────┼─────────────────┤
           │ t1           │ p1       │ abc             │ ← STARADA!
           │ t2           │ p2       │ abc             │ ← STARADA!
           │ t3           │ p3       │ abc             │ ← STARADA!
           │ t4           │ p4       │ abc             │ ← NOVO
           │ t5           │ p1       │ abc             │ ← NOVO
           │ t6           │ p5       │ abc             │ ← NOVO
           └──────────────┴──────────┴─────────────────┘
           
           🚨 PUTNIK P1 IMA DVA REDA U ETA TABELI!
           - (t1, p1, eta=120s) — STARA vrednost iz BC slota
           - (t5, p1, eta=150s) — NOVA vrednost iz VS slota
           
           Aplikacija će prikazati oba ETA-a!
```

### 🔴 VEĆI PROBLEM: ETA SE NE BRIŠE KADA VOZAČ PROMENI SLOT

**Trenutna logika u v3-compute-eta:**
```ts
// Samo briši ETA za putnike koji više nisu u AKTIVNOM slotu
const remainingPutnikIds = new Set<string>(remaining.map((p) => p.putnik_id));

// Pronađi sve ETA redove za OVOG vozača
const { data: existingEtaRows } = await client
  .from("v3_eta_results")
  .select("putnik_id")
  .eq("vozac_id", vozacId);  ← GLEDA SVE ETAE ZA OVOG VOZAČA

// Pronađi koje putnike trebam izbrisati
const toDelete = (existingEtaRows ?? [])
  .map((r: any) => String(r.putnik_id ?? "").trim())
  .filter((pid: string) => pid && !remainingPutnikIds.has(pid));

// Briši
if (toDelete.length > 0) {
  await client.from("v3_eta_results").delete()
    .eq("vozac_id", vozacId)
    .in("putnik_id", toDelete);
}
```

**Problem:**
```
Scenario:
- Vozač ABC pregledava ETA za BC 05:00
  v3_eta_results sadrži: (t1,p1), (t2,p2), (t3,p3)

- Vozač prebacuje na VS 06:00 i klikne START
  setActiveTermin(grad=VS, vreme=06:00)
  
- v3-compute-eta se poziva sa grad=VS, vreme=06:00
  
- Pronalazi novi slot sa [p4, p5, p1]
  
- Filtrira ETA-e za VOZAČA (ne za slot!):
  remaining = {p4, p5, p1}
  
  Pronađi postojeće: {p1, p2, p3}
  toDelete = {p2, p3}  ← Samo P2 i P3 se brišu
  
  ⚠️ ALI: Red (t1, p1) OSTAJE u bazi jer je P1 i dalje u remaining!
  🔴 Problem: ETA iz BC slota za P1 će biti prikazan kao del VS slota
```

### 🔴 NAJVEĆI PROBLEM: JEDINSTVENI KLJUČ NE UKLJUČUJE SLOT

```sql
UNIQUE(termin_id, putnik_id)
```

**Trebalo bi:**
```sql
UNIQUE(vozac_id, grad, vreme, putnik_id)  ili
UNIQUE(slot_id, putnik_id)
```

**Jer:**
- Isti `putnik_id` može biti u više termin-a istog vozača na RAZLIČITIM danima
- Termin_id je jedinstveni po terminu (vozač-putnik-vrijeme)
- ALI P1 može biti kod vozača ABC u BC i VS simultano (oba su isti putnik_id)

---

## ANALIZA SEVERITETA

### Problem #1: Race condition u _autoStartVozacTrackingFromPush()

**Verovatnoća:** 🟡 SREDNJA
- Push dolazi obično 100-500ms nakon FCM servera
- Kron transakcija je obično završena za 200-300ms
- ALI: U slučaju high load-a ili kron kašnjenja, može se desiti

**Uticaj:** 🔴 CRITICAL
- Ako se desi, vozač pokreće tracking ALI edge funkcija vraća "no_active_slot"
- Nema ETA, nema putnika na mapi
- Vozač ne zna šta se dešava

**Sada se desava:** ⚠️ Povremeno
- Korisnici mogu vidjeti "Nema aktivnih putnika" pri prvom GPS tick-u
- After 1-2 sekunde, ETA se učita OK (retry loop)

---

### Problem #2: ETA prepisivanje sa više slotova

**Verovatnoća:** 🟡 VISOKA
- Svaki vozač sa 2+ slota ima šansu
- v3_eta_results će imati miješane rezultate

**Uticaj:** 🟡 MEDIUM-HIGH
- Vozač vidi kombinovane ETA-e (stare + nove)
- Putnik može biti dva puta na mapi
- Filtriranje i brisanje putnika može biti pogrešno

**Sada se desava:** ⚠️ SIGURNO se desava
- Ako vozač prebaci između slotova: P1 ostaje u ETA tabeli
- Redoslijed putnika može biti pogrešan

---

## ZAKLJUČAK

✅ **Problem #1** - Trebam RETRY sa exponential backoff u `_autoStartVozacTrackingFromPush()`

✅ **Problem #2** - Trebam promijeniti upsert logiku:
   - Ili koristiti `vozac_id, grad, vreme, putnik_id` kao unique key
   - Ili briši SVE ETA za vozača kada se promeni termin
   - Ili čuva `slot_id` u v3_eta_results tabeli

---

## PREDLOG POPRAVKE

### Popravka #1: RETRY sa backoff-om
```dart
// _autoStartVozacTrackingFromPush()
Future<void> _autoStartVozacTrackingFromPush(Map<String, String> data) async {
  // ... validacija ...
  
  // Retry loop sa exponential backoff
  int retryCount = 0;
  const maxRetries = 3;
  const initialDelay = Duration(milliseconds: 500);
  
  while (retryCount < maxRetries) {
    try {
      await V3TrenutnaDodelaSlotService.activateSlot(...);
      break; // Success, izlazimo
    } catch (e) {
      retryCount++;
      if (retryCount >= maxRetries) {
        debugPrint('❌ [AUTO-START] activateSlot sve retry-e iscrpio');
        return; // Odustaj
      }
      final delay = initialDelay * pow(2, retryCount - 1).toInt();
      debugPrint('⚠️ [AUTO-START] retry #$retryCount za $delay ms');
      await Future.delayed(delay);
    }
  }
  
  // Sada kreni tracking
  V3VozacLocationTrackingService.instance.setActiveTermin(...);
  await V3VozacLocationTrackingService.instance.start(...);
}
```

### Popravka #2: Očisti ETA pri promeni slota
```dart
// U v3_vozac_screen.dart, kada se vrši _rebuild() ili setActiveTermin()
void _rebuild() {
  final vozac = _efektivniVozac;
  if (vozac == null) return;
  
  final stariGrad = _selectedGrad;
  final staroVreme = _selectedVreme;
  
  // ... logika za odabir prvog termina ili sličnih ...
  
  // VAŽNO: Ako se izbor slota promijenio
  if (_selectedGrad != stariGrad || _selectedVreme != staroVreme) {
    // Očisti stare ETA-e
    unawaited(
      V3VozacLocationTrackingService.instance
          .clearEtaForVozac(vozacId: vozac.id.toString())
    );
  }
}
```

### Popravka #3: Prosledi slot_id u v3_eta_results
```sql
-- Migration
ALTER TABLE v3_eta_results
  ADD COLUMN slot_id UUID REFERENCES v3_trenutna_dodela_slot(id) ON DELETE CASCADE;

-- Unique constraint
ALTER TABLE v3_eta_results
  ADD CONSTRAINT unique_slot_putnik UNIQUE(slot_id, putnik_id);
```

```ts
// v3-compute-eta edge function
const upsertRows = [...];

// Dodaj slot_id
const upsertRowsWithSlot = upsertRows.map(r => ({
  ...r,
  slot_id: activeSlot.id,
}));


await client
  .from("v3_eta_results")
  .upsert(upsertRowsWithSlot, { onConflict: "slot_id,putnik_id" });
```

---

## 🔴 DODATNE EDGE CASE-OVE KOJE SAM PRONAŠAO

### Edge Case #1: Putnik se pojavljuje u više slotova ISTOG vozača, ISTOG dana

```
Scenario: Vozač ABC u BC 05:00 i VS 06:00 na istom danu
- BC 05:00: [P1, P2]  ← P1 je u BC
- VS 06:00: [P1, P3]  ← P1 JE I U VS (dodao se kasnije)

Timeline:
T0  Vozač Start BC 05:00
    v3-compute-eta→ upsert (t1, p1)
    
T+10s Novi termin se pojavljuje - P1 dodeljuje iz BC u VS 06:00
    
T+20s Vozač Start VS 06:00
    v3-compute-eta→ upsert (t5, p1)
    
REZULTAT:
  v3_eta_results sadrži DVA reda za P1:
  - (t1, p1, eta=120s)  ← iz BC, STARA
  - (t5, p1, eta=150s)  ← iz VS, NOVA
  
  UI će prikazati oba vremena!
```

**Kako se ovo desava:**
```ts
// v3-compute-eta
const remainingPutnikIds = new Set(remaining.map(p => p.putnik_id));
// remaining = [P1, P3] iz VS

// Briši ETA za putnike koji nisu više u OVOM slotu
const toDelete = existingEtaRows
  .map(r => r.putnik_id)
  .filter(pid => !remainingPutnikIds.has(pid));  // ← P1 JE U remaining, ne briše se!
  
// REZULTAT: Red (t1, p1) ostaje u bazi!
```

---

### Edge Case #2: Vozač se prebacuje između slotova u roku od 10 sekundi

```
Scenario: Brzo prebacivanje između slotova
T0      Vozač klikne START BC 05:00
T+1s    setActiveTermin(BC, 05:00)
T+2s    GPS update → v3-compute-eta za BC
        - upsert: (t1,p1,eta=120s), (t2,p2,eta=90s)
        
T+10s   Vozač klikne Cancel BC i Start VS 06:00
        - ALI: V3VozacLocationTrackingService nije okinuta stop()
        - Umesto toga: setActiveTermin(VS, 06:00)
        
T+11s   GPS update → v3-compute-eta za VS
        - upsert: (t3,p3,eta=110s)
        
PROBLEM: Tabela v3_eta_results ima:
  (t1,p1,eta=120s)  ← BC termin — STARI
  (t2,p2,eta=90s)   ← BC termin — STARI
  (t3,p3,eta=110s)  ← VS termin — NOVI

ALI: clearEtaForVozac() se nije pozvao jer setActiveTermin() 
     se ne gasi pravilno između slotova
```

---

### Edge Case #3: Auto-stop se aktivira jer su P2 i P3 pokupljeni, ALI P1 je i dalje visi

```
Scenario: Dela putnika je pokupljena, dela nije
BC 05:00: [P1, P2, P3]

T0  Vozač pokreće start

T+20m P2 je pokupljen (vozač je preskočio ili već preuzeo)
T+22m P3 je pokupljen

_rebuild() se osvežava:
- Preostali putnici: [P1]
- Svi putnci: [P1, P2, P3]
- SVI SU ZAVRŠENI? Ne - P1 je AKTIVNA
→ Ne poziva se _maybeAutoStopTracking()

T+25m Vozač se prebacuje na VS 06:00
- setActiveTermin(VS, 06:00)
- Sad je _selectedVreme = "06:00"
- _rebuild() se osvežava za SAMO VS termin
- Ako je VS prazan ili svi završeni...
  → _maybeAutoStopTracking() se poziva
  → STOP tracking

PROBLEM: BC termin još ima P1 u bazi, ALI tracking je već zaustavljen!
```

---

### Edge Case #4: RPC za slanje push notifikacija vozaču/putnicima padne

```
Scenario: Network glitch tokom slanja push-a
T0      v3-auto-prepare-termins kron:
        1. Pronađi termine
        2. Create/update slot
        3. Prosleđi push vozaču RPC (notify_push)
        
        ❌ RPC PADNE - Network timeout
        
        4. await client.from(...).update({auto_driver_notified_at})
           ← Ovo se i dalje izvršava - flag se upisa!
        
        5. RPC za putnike (v3_notify_passengers_driver_started)
           ← Ni vozač niti putnici nisu informisani!

REZULTAT:
- auto_driver_notified_at = T0 (upisano)
- auto_notified_at = NULL (nije upisano jer nije pokušano)
- Vozač dobija "start_tracking" na svojoj push notifikaciji
  ALI putnici NE dobijaju obaveštenje
```

**Veća problema:**
```ts
// Kod u v3-auto-prepare-termins
try {
  const vozacTokens = [...];
  if (vozacTokens.length > 0) {
    await client.rpc("notify_push", {...});
    console.log(`Driver notified`);
  }
} catch (e) {
  console.error(`Driver notify error: ${e}`);
  // ⚠️ ALI: await client.from(...).update({auto_driver_notified_at}) 
  // se i dalje izvršava PRE nego što se catch pokrene!
}

// Flag se upisa čak i ako je push failed
await client.from("v3_trenutna_dodela_slot")
  .update({auto_driver_notified_at: now})
  .eq("id", slotId);
```

---

## 📊 PRIORITIZACIJA POPRAVKI

| # | Problem | Verovatnoća | Uticaj | Napor | Prioritet |
|---|---------|-----------|--------|-------|-----------|
| 1 | Race condition u _autoStartVozacTrackingFromPush | SREDNJA | CRITICAL | 30 min | 🔴 P0 |
| 2 | Jedinstveni ključ v3_eta_results | VISOKA | MEDIUM | 2 hours | 🔴 P0 |
| 2a | ETA se ne briše pri promeni slota | VISOKA | MEDIUM | 1 hour | 🟡 P1 |
| 3 | Putnik u više slotova | SREDNJA | LOW | 1 hour | 🟡 P1 |
| 4 | RPC padne tokom push-a | NISKA | MEDIUM | 30 min | 🟢 P2 |

---

## ✅ FINALNA PREPORUKA

**Trebao bi ODMAH popraviti:**
1. ✅ **Problem #1** - Retry sa backoff-om (5 linija koda)
2. ✅ **Problem #2** - Dodaj slot_id u v3_eta_results (migration + 3 linije)
3. ✅ **Edge Case #1** - Očisti ETA pri promeni slota (2 linije)

**Trebao bi popraviti u SLEDEĆOJ iteraciji:**
4. 🟡 Edge Case #2 - Implementiraj pravilno stop() između slotova
5. 🟡 Edge Case #4 - Poboljšaj error handling u RPC-ima

---
