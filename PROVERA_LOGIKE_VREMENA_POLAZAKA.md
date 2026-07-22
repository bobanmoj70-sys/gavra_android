# 🔍 PROVERA LOGIKE ZA UREĐIVANJE VREMENA POLAZAKA

## 📍 Tok uređivanja vremena

### 1. **INICIJACIIJA - `v3_putnik_profil_screen.dart` (_updatePolazak)**

```dart
Future<void> _updatePolazak(String dan, String grad, String? novoVreme, ...)
```

**Ulazni parametri:**
- `dan` - dan u sedmici (npr. "Pon")
- `grad` - grad (BC/VS)
- `novoVreme` - željeno vreme u formatu HH:mm (ili null za otkazivanje)
- `trenutniInfo` - postojeći zahtev (ako ima)
- `koristiSekundarnu` - boolean za drugu adresu

**Validacije koje se izvršavaju:**

✅ **1. Debounce provera** (500ms)
```dart
if (V3StreamUtils.isTimerActive(_actionDebounceKey)) return;
```

✅ **2. Normalizacija vremena**
```dart
final validNovoVreme = _normalizeValidTime(novoVreme);
```
- Provera formata HH:mm
- Ako je neispravno → warning snackbar + return

✅ **3. Zaštita dnevnog putnika**
```dart
if (validNovoVreme != null && tipPutnika == 'dnevni' && !_isDnevniDatumAllowed(datumPolaska))
```
- Dnevni putnici mogu zakazati samo do nedelje (ne ponedeljak)
- Ako nije dozvoljeno → info snackbar + return

---

## 📋 SCENARIO 1: NOVO VREME (ZAHTEV ZA PROMENU)

Poziv: `_updatePolazak(dan, grad, novoVreme, ...)`

### **Faza A: Pronalaženje postojećeg zahteva**

```dart
final aktivni = _vidljiviRedoviPoKontekstu(
  putnikId: putnikId, 
  datum: datum, 
  grad: grad
);
```

**Logika `_vidljiviRedoviPoKontekstu`:**
- Traži sve **aktivne** zahteve za dati (putnik + datum + grad)
- Filtrira status - isključuje "otkazano" i "odbijeno"
- Vraća redove sortovane (najpre "odobreno"/"alternativa", zatim "obrada")

### **Faza B: AKO POSTOJI AKTIVNI ZAHTEV**

Ako je `aktivni.isNotEmpty`:

1. **Ako je status "alternativa" ili "odobreno"**
   ```dart
   if (V3StatusPolicy.isOfferLike(status)) {
     await updateStatus(rowKey, 'obrada', updatedBy: updatedBy);
   }
   ```
   → Promeni status na "obrada" pre nego što ažuriraš vreme

2. **Ažurira traženo vreme**
   ```dart
   await updateTrazeniPolazakAt(
     rowKey,
     novoVreme,
     koristiSekundarnu: koristiSekundarnu,
     updatedBy: updatedBy,
   );
   ```
   → Poziva `V3ZahtevDomainService.resetToObrada()`

3. **Sinhronizuj operativne dodelе**
   ```dart
   await _syncOperativnaAssignmentsForContext(
     putnikId: putnikId,
     datum: datum,
     grad: targetGrad,
     updatedBy: updatedBy,
   );
   ```

### **Faza C: AKO NEMA POSTOJEĆEG ZAHTEVA**

1. **Kreira NOVI zahtev**
   ```dart
   final zahtev = V3Zahtev(
     id: const Uuid().v4(),
     putnikId: putnikId,
     datum: datum,
     grad: grad,
     trazeniPolazakAt: novoVreme,
     status: 'obrada',
     koristiSekundarnu: koristiSekundarnu,
   );
   await createZahtev(zahtev, createdBy: updatedBy);
   ```

2. **Pronalazi slot dodelу**
   ```dart
   final slotKey = V3TrenutnaDodelaSlotService.slotKey(
     datumIso: datumIso,
     grad: targetGrad,
     vreme: novoVreme,
   );
   final assignedVozacId = (slotAssignments[slotKey] ?? '').trim();
   ```

3. **AKO POSTOJI SLOT DODELA**
   ```dart
   if (assignedVozacIdFromAll.isNotEmpty) {
     await V3OperativnaNedeljaService.createOrUpdateByVozac(
       putnikId: putnikId,
       datum: datumIso,
       grad: targetGrad,
       polazakAt: novoVreme,
       createdBy: updatedBy,
       koristiSekundarnu: koristiSekundarnu,
     );
   }
   ```
   → Automatski kreira operativni red

4. **AKO NEMA SLOT DODELЕ**
   ```dart
   else {
     await _syncOperativnaAssignmentsForContext(...);
   }
   ```
   → Sinhronizuje dodelе iz drugih izvora

---

## ❌ SCENARIO 2: OTKAZIVANJE (novoVreme == null)

Poziv: `_updatePolazak(dan, grad, null, trenutniInfo: info)`

### **Faza 1: Provera da li postoji zahtev**

```dart
if (validNovoVreme == null) {
  if (trenutniInfo == null) return;  // ← AKO NEMA, IZLAZI
  await V3ZahtevService.otkaziPolazakPutnikaPoKontekstu(...);
}
```

### **Faza 2: U `otkaziPolazakPutnikaPoKontekstu()`**

1. **Pronalazi aktivne zahteve**
   ```dart
   final aktivni = _vidljiviRedoviPoKontekstu(
     putnikId: putnikId, 
     datum: datum, 
     grad: grad
   );
   ```

2. **Ako postoji zahtev - označi kao "otkazano"**
   ```dart
   final status = row['status']?.toString();
   if (V3StatusPolicy.isOfferLike(status)) {
     await updateStatus(rowKey, 'obrada', updatedBy: updatedBy);
   }
   // ← AKO JE ALTERNATIVA, PRE TOGA PROMENI NA "OBRADA"
   ```

3. **Pronalazi i ažurira OPERATIVNE redove**
   ```dart
   final aktivniOperativni = await _operativnaRepository
     .selectByPutnikDatumGradAktivni(
       putnikId: putnikId,
       datumIso: datumIso,
       grad: targetGrad,
     );
   
   if (aktivniOperativni.isEmpty) {
     debugPrint('[...] Preskačem otkazivanje — nema aktivnih operativnih redova');
     return;  // ← RANA IZLAZNA TAČKA!
   }
   ```

4. **Ažurira sve aktivne operativne redove**
   ```dart
   final updatedOperativni = await _operativnaRepository
     .updateByPutnikDatumGradAktivniReturningList(...);
   
   for (final row in updatedOperativni) {
     V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
     await V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRow(...);
   }
   ```

---

## 🔧 KLJUČNE LOGIČKE PROVJERE

### **1. Normalizacija vremena**
```dart
String? _normalizeValidTime(String? vreme) {
  return V3StringUtils.trimTimeToHhMm(vreme);
  // Vraća "HH:mm" ili null ako je neispravno
}
```

### **2. Zaštita dnevnog putnika**
```dart
bool _isDnevniDatumAllowed(DateTime datumPolaska) {
  // Dnevni putnici mogu zakazati samo za:
  // - Utorak-Petak (u tekstašnoi sedmici)
  // - Ponedeljak naredne sedmice (se otvara subota u 03:00)
}

String _allowedDnevniDateLabel(String? grad) {
  // Vraća label sa dozvoljenim danima
}
```

### **3. Zaštita polaska - zaključavanje 15 minuta pre**
```dart
final polazak = DateTime(
  datumPolaska.year,
  datumPolaska.month,
  datumPolaska.day,
  int.parse(parts[0]),
  int.parse(parts[1]),
);
final isLocked = now.isAfter(polazak.subtract(const Duration(minutes: 15)));
```

### **4. Provera neiradnih dana**
```dart
final neradanRazlog = getNeradanDanRazlog(datumIso: datumIso, grad: grad);
if (neradanRazlog != null) {
  // Grad nema vožnji tog dana
  return;
}
```

### **5. Blokiranjeprenositelja koji su već pokupljeni**
```dart
if (V3StatusPolicy.isActionLocked(
  status: info?.status, 
  pokupljen: info?.pokupljen ?? false
)) {
  // Ne može otkazati - vozač je već pokupljen
  return;
}
```

---

## 💾 AŽURIRANJA U BAZI

### **Kada se uređuje vreme (`resetToObrada`)**

```dart
{
  'status': 'obrada',              // ← Nova obrada
  'trazeni_polazak_at': novoVreme, // ← Novo vreme
  'polazak_at': null,              // ← Resetuj
  'scheduled_at': null,            // ← Resetuj
  'alternativa_pre_at': null,      // ← Resetuj
  'alternativa_posle_at': null,    // ← Resetuj
  'created_at': nowIsoUtc,         // ← Ažuriramo "created_at" (novi pokušaj!)
  'updated_by': updatedBy,
  'koristi_sekundarnu': koristiSekundarnu
}
```

**⚠️ VAŽNO:** `created_at` se resetuje! To je novi pokušaj zakazivanja.

### **Kada se otkazuje**

```dart
// U v3_zahtevi:
{
  'status': 'otkazano',
  'otkazano_by': otkazaoPutnikId,
  'otkazano_at': V3DateUtils.nowIsoUtc(),
  'updated_by': updatedBy,
}

// U v3_operativna_nedelja:
{
  'otkazano_by': otkazaoPutnikId,
  'otkazano_at': nowIsoUtc,
  'updated_by': updatedBy,
}
```

---

## 🎯 MOGUĆA ISSUE-A

### **Issue 1: Duplo resetovanje `created_at`**
- Svaki put kada putnik izmeni vreme, `created_at` se resetuje
- Ovo znači da je to tehnički "novi zahtev" iz perspektive vremenske linije
- **Mogućnost problema:** Stari zahtev sa `status='alternativa'` se ne očisti

**Preporuka:** Provera kako se rukuje starim zahtevima kada se kreira novi

### **Issue 2: Race condition u otkazivanju**
```dart
if (aktivniOperativni.isEmpty) {
  debugPrint('[...] Preskačem otkazivanje — nema aktivnih redova');
  return;  // ← Šta ako do tada ostane samo "zahtev" bez "operativnog"?
}
```

**Mogućnost problema:** Zahtev ostaje, operativni se ne otkazuje

### **Issue 3: Slot dodela logika**
- Ako se kreira nov zahtev, traži se slot dodela
- Ali ako se MENJA postojeći zahtev, slot se NE TRAŽI PONOVO
- Stanica je samo sinhronizovana

**Mogućnost problema:** Ako se vreme promeni, stara slot dodela se ne gasi

### **Issue 4: `koristiSekundarnu` flag**
- Može se promeniti bez promene vremena
- Reset logika sinhronizuje to

**Mogućnost problema:** Šta ako vozač već ide prema osnovnoj adresi?

---

## 📊 REDOSLED AKCIJA ZA SIGURNU PROMENU

1. ✅ **Validacija** - format, dnevni putnik, neradni dan, zaključavanje
2. ✅ **Pronalaženje postojećeg** - da li već postoji zahtev
3. ✅ **Resetovanje statusa** - ako je alternativa, postavi na "obrada"
4. ✅ **Ažuriranje vremena** - resetuj sve polazak polja
5. ✅ **Pronalaženje slota** - da li postoji vozač za novo vreme
6. ✅ **Sinhronizacija operativnih** - ažuriranje ili brisanje

---

## 🔐 SIGURNOSNE PROVERE

1. **Debounce** - sprečava dupli klik (500ms)
2. **Tipizacija putnika** - dnevni imaju ograničenja
3. **15-minutna zaštita** - ne možeš menjati 15 min pre
4. **Zaštita pokupljenih** - ne možeš otkazati nakon što je vozač pokupljen
5. **Neiradni dani** - ne mogu se zakazati
6. **Duplo otkazivanje** - preskače ako je već otkazano

---

## ✨ ZAKLJUČAK

Logika je **kompleksna ali čini se da je robusna**:
- Ima dovoljno validacija
- Koristi kontekst (putnik + datum + grad)
- Rukuje slotovima i operativnim redovima
- Štiti se od duplog otkazivanja

**Preporuka za testiranje:**
1. Prosledi zahtev → promeni vreme → prosledi ponovo (dva puta)
2. Otkaži nakon što je pokupljen (treba da bude odbijeno)
3. Promeni `koristiSekundarnu` bez promene vremena
4. Zakaži za neiradandan (treba da bude odbijeno)
5. Dnevni putnik - zakaži sa zabranom (treba da bude odbijeno)
