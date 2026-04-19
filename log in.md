Moj Plan

Ulaz 1: telefon/telefon_2 + uuid je minimum.
Posle ulaza 1: korisnik dopuni profil polja ako su prazna.
Upis uređaja: upis push_token + os_device_id.
Ulaz 2 (drugi uređaj): popuna push_token_2 + os_device_id_2.
Posle 2 uređaja: nema novih os_device_id upisa.

Baza (trenutno)

Triggeri: samo v3_auth_set_updated_at (timestamp), nema login pravila.
Policy: anon_all_v3_auth (ALL, true/true) je aktivan.
Dupli telefoni: trenutno 0 duplikat grupa normalizovanih telefona.

Kod (trenutno)

SMS ulaz: v3_sms_login_screen.dart lookup radi po telefonu (select('id,telefon,telefon_2')), ne po telefon + uuid.
Device upis: _syncDeviceAndPushForLogin poziva edge sync.
Edge slot logika: index.ts bira requestedSlot kad su oba device slota već puna (nije hard blok trećeg uređaja).

Novi Plan (bez rizika sada)

Sada: ne diramo app kod.
Backend soft: ne prepisivati postojeće slotove kad su oba puna; evidentirati incident.
Kasnije (posle objava): uvesti strict telefon + uuid i hard blok trećeg uređaja.