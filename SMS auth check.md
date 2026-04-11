# SMS Auth Check - Interna greška 39

## Lista zadataka:
- [x] **Korak 1: SHA ključevi** (Samo 4 ispravna u Firebase Console - obriši ostale da ne bude zabune):
  - **Upload SHA-1 (Sertifikat za otpremanje)**: `D0:53:FC:CB:E1:F9:DA:88:3B:2D:54:99:DB:70:4F:A5:7F:CE:B1:B7`
  - **Upload SHA-256 (Sertifikat za otpremanje)**: `B5:E4:70:C4:61:63:DF:76:A4:07:AC:79:0C:19:70:C2:A8:10:47:B2:AF:B6:87:BC:63:58:BA:BA:C9:E0:48:09`
  - **Play Store SHA-1 (App Signing / Integritet)**: `2F:FA:B3:81:40:1E:57:E4:65:8E:17:9A:87:EB:6C:75:79:53:A1:BF`
  - **Play Store SHA-256 (App Signing / Integritet)**: `8B:C2:36:86:16:30:63:02:9C:71:0C:AA:D1:BC:CF:14:EB:D3:88:87:F2:16:15:07:39:99:19:7E:F6:09:A2:BD`
  - ✅ **Status:** Odlično, ovo je i potvrđeno kao uneto u Firebase Console (Project Settings > General > Android apps).
- [x] **Korak 2: Play Integrity API** - Obezbeđeno u Google Cloud Console.
- [x] **Korak 3: google-services.json i info.plist** - Ažurirani.
- [x] **Korak 4: Testiranje** - Fizički uređaj (Play Store Live).
- [x] **Korak 5: Google Play App Signing ključevi** - Izdvojeni i dodati!

---
### Trenutni korak: Build i Puštanje novog AAB-a na Google Play
Pošto trenutna verzija na Google Play-u u sebi sadrži onaj *stari* `google-services.json`, ona neće prepoznati ove nove ključeve i promene dok ne objavimo novi update.
- [x] Izbildati novi Android App Bundle (AAB).
- [ ] Okačiti novu verziju (update) na Google Play Console.
- [ ] Sačekati odobrenje/process i testirati.
1. Uveri se da si ova dva Play Store ključa prekopirao u Firebase.
2. Sačekaj ~10-15 minuta da Google serveri sinhronizuju ove sertifikate.
3. Pokušaj ponovo SMS prijavu na živoj produkcijskoj aplikaciji sa telefona.
*(Napomena: Ako i posle 15 minuta nastavi po starom, moraćeš da ponovo učitaš `google-services.json`, izbildaš novi `.aab` i pustiš ga kao update na Play Store)*

