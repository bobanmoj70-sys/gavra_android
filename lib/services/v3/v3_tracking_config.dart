import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_status_policy.dart';

const Duration v3TrackingMaxDuration = Duration(minutes: 55);

/// JEDAN IZVOR ISTINE za watchdog proveru "da li je tracking predugo aktivan"
/// — deljeno između Android background isolate-a, iOS tick-a i restore/resume
/// puta (main isolate). Ranije je identična provera (`now.difference(startedAt)
/// >= v3TrackingMaxDuration`) bila duplirana na 3 mesta.
bool v3TrackingTimedOut(DateTime? startedAt) {
  if (startedAt == null) return false;
  return DateTime.now().difference(startedAt) >= v3TrackingMaxDuration;
}

/// JEDAN IZVOR ISTINE za razmak između GPS/ETA tick-ova, deljen između
/// Android background isolate-a (`v3_background_location_handler.dart`) i
/// iOS tracking petlje (`v3_vozac_location_tracking_service.dart`). Ranije
/// je svaka platforma imala sopstvenu `Duration(seconds: 20)` konstantu —
/// definisane odvojeno, lako je moglo doći do razminuti (npr. jedna
/// promenjena, druga zaboravljena).
const Duration v3TrackingTickInterval = Duration(seconds: 20);

/// Maksimalno dozvoljeno trajanje JEDNOG tick-a ([onTick]) pre nego što se
/// prisilno prekine i zakaže sledeći — zaštita od trajno "zaglavljenog"
/// tick-a. `supabase` `functions.invoke()` (HTTP poziv koji `onTick` radi
/// iznutra) NEMA ugrađen timeout (`functions_client` paket ne postavlja
/// nikakav rok na `http.Client.send()`) — na lošoj/nestabilnoj mobilnoj mreži
/// konekcija ume da "visi" beskonačno (server prihvati konekciju ali nikad ne
/// pošalje odgovor). Bez ove zaštite, `V3SelfReschedulingTicker` bi zauvek
/// čekao takav `onTick` i NIKAD više ne bi zakazao sledeći tick — tracking bi
/// se potpuno (i trajno, do restarta aplikacije) zaustavio, što je GORE od
/// običnog kašnjenja. Mora biti VEĆA od [v3ComputeEtaNetworkTimeout] + GPS
/// fix-a (do 12s) + margine, da normalan (spor, ali validan) tick ne bude
/// prekinut od strane OVE spoljne zaštite pre unutrašnjeg mrežnog timeout-a.
const Duration v3TrackingTickTimeout = Duration(seconds: 90);

/// JEDAN IZVOR ISTINE za timeout na `v3-compute-eta` mrežni poziv (Supabase
/// Edge Function). `functions_client` paket ne postavlja sopstveni timeout
/// (vidi napomenu iznad [v3TrackingTickTimeout]) — ovaj `.timeout(...)` na
/// pozivaočevoj strani je JEDINA zaštita od beskonačnog čekanja. Edge
/// funkcija (`v3-compute-eta`) iznutra radi do 4 OSRM pokušaja (12s timeout
/// svaki) + do 7s eksponencijalnog backoff-a između njih — worst-case ~55s —
/// pa vrednost MORA biti veća od toga, inače bi ovaj client-side timeout
/// prekidao baš one spore-ali-legitimne OSRM retry pokušaje koje edge
/// funkcija radi namerno (vidi `OSRM_MAX_RETRIES`/`OSRM_REQUEST_TIMEOUT_MS`
/// u `supabase/functions/v3-compute-eta/index.ts`). Dodatih ~10s margine za
/// mrežni round-trip/DB upite van OSRM faze.
const Duration v3ComputeEtaNetworkTimeout = Duration(seconds: 65);

/// Sam-zakazujući tajmer — JEDAN IZVOR ISTINE za "kako se tick-uje svakih
/// [v3TrackingTickInterval]" na OBE platforme (Android background isolate i
/// iOS main isolate). Namerno NE koristi `Timer.periodic`: taj bi sledeći
/// tick okinuo tačno na `interval` OD POČETKA prethodnog, bez obzira da li
/// je prethodni [onTick] (GPS fix + `v3-compute-eta` poziv, koji iznutra
/// radi i do 3 OSRM retry-a sa eksponencijalnim backoff-om) još u toku —
/// pozivalac bi tada morao da tiho preskoči taj tick (in-flight guard), pa bi
/// efektivni razmak umeo da bude i 40s+ umesto 20s, bez ikakvog upozorenja.
///
/// Ovde se sledeći tick zakazuje TEK `interval` NAKON ŠTO SE prethodni
/// [onTick] završio — garantovano, bez tihog gubljenja tick-ova. Dodatno,
/// [onTick] se izvršava pod [v3TrackingTickTimeout] zaštitom — ako
/// "zaglavi" (npr. mrežni poziv bez timeout-a), tajmer nastavlja dalje umesto
/// da se trajno blokira.
class V3SelfReschedulingTicker {
  V3SelfReschedulingTicker({
    required this.interval,
    required this.onTick,
    this.tickTimeout = v3TrackingTickTimeout,
  });

  final Duration interval;
  final Future<void> Function() onTick;
  final Duration tickTimeout;

  Timer? _timer;
  bool _cancelled = true;
  DateTime? _nextTickAt;

  bool get isActive => !_cancelled;

  /// Pokreće ticker: odmah izvršava prvi [onTick], zatim samo-zakazuje
  /// sledeći tick tako da se održava fiksni razmak [interval] između
  /// POČETAKA tick-ova (ne između završetka i početka). Ako jedan tick
  /// potraje duže od [interval], sledeći kreće odmah — ne čeka dodatnih
  /// [interval] sekundi. Ovo rešava problem "lokacija se ne šalje na 20s"
  /// uzrokovan prethodnom implementacijom koja je dodavala trajanje tick-a
  /// na 20s pauzu.
  void start() {
    cancel();
    _cancelled = false;
    _nextTickAt = DateTime.now();
    unawaited(_scheduleNext());
  }

  Future<void> _scheduleNext() async {
    try {
      await onTick().timeout(tickTimeout);
    } catch (e) {
      // Tick je "zaglavio" (timeout) ili bacio grešku koju pozivalac nije
      // uhvatio — logujemo i NASTAVLJAMO dalje, ne dozvoljavamo da jedan
      // neuspeo tick zaustavi ceo tracking zauvek.
      debugPrint('[V3SelfReschedulingTicker] tick greška/timeout: $e');
    }
    // Ako je u međuvremenu pozvan cancel(), ne zakazuj sledeći tick.
    if (_cancelled) return;

    // Održavaj fiksne granice: sledeći tick treba da bude [interval] nakon
    // prethodnog planiranog trenutka, bez obzira koliko je trenutni tick
    // trajao. Ako smo već promašili granicu, kreći odmah.
    _nextTickAt = _nextTickAt!.add(interval);
    final now = DateTime.now();
    final delay = _nextTickAt!.isAfter(now) ? _nextTickAt!.difference(now) : Duration.zero;
    _timer = Timer(delay, () => unawaited(_scheduleNext()));
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _nextTickAt = null;
  }
}

/// JEDAN IZVOR ISTINE za SharedPreferences ključeve "željenog stanja"
/// tracking-a — deljeno između main isolate-a (`V3VozacLocationTrackingService`)
/// i Android background isolate-a (`v3_background_location_handler.dart`).
/// Ranije je svaki fajl imao sopstvene identične `_kKey*` konstante — lako je
/// moglo doći do razmimoilaženja. Vrednosti MORAJU ostati identične sa
/// `KEY_ACTIVE_*` konstantama u `GavraFcmService.kt` (Kotlin strana ne može
/// da uvozi ovaj Dart fajl, pa se sinhronizacija tamo održava ručno).
const String v3KeyVozacId = 'bg_active_vozac_id';
const String v3KeyDatumIso = 'bg_active_datum_iso';
const String v3KeyGrad = 'bg_active_grad';
const String v3KeyVreme = 'bg_active_vreme';
const String v3KeyStartedAt = 'bg_active_started_at';

/// JEDAN IZVOR ISTINE za brisanje "željenog stanja" tracking-a iz
/// SharedPreferences — deljeno između main isolate-a (`_clearDesiredState` u
/// `v3_vozac_location_tracking_service.dart`) i Android background isolate-a
/// (`_bgClearDesiredState` u `v3_background_location_handler.dart`). Ranije
/// je identičan niz `prefs.remove(...)` poziva bio dupliran na oba mesta.
Future<void> v3ClearDesiredState(SharedPreferences prefs) async {
  await prefs.remove(v3KeyVozacId);
  await prefs.remove(v3KeyDatumIso);
  await prefs.remove(v3KeyGrad);
  await prefs.remove(v3KeyVreme);
  await prefs.remove(v3KeyStartedAt);
}

/// JEDAN IZVOR ISTINE za brisanje zaostalih ETA redova za vozača —
/// deljeno između main isolate-a (`clearEtaForVozac`) i Android background
/// isolate-a (`_bgClearEtaForVozac`). Ranije identičan upit dupliran na oba
/// mesta.
Future<void> v3ClearEtaForVozac({
  required SupabaseClient client,
  required String vozacId,
  String logTag = '[v3ClearEtaForVozac]',
}) async {
  final normalized = vozacId.trim();
  if (normalized.isEmpty) return;

  try {
    await client.from('v3_eta_results').delete().eq('vozac_id', normalized);
  } catch (e) {
    debugPrint('$logTag ETA cleanup error: $e');
  }
}

/// JEDAN IZVOR ISTINE za proveru "da li su svi putnici u aktivnom slotu
/// završeni (pokupljeni ili otkazani)" — deljeno između main isolate-a
/// (iOS tracking petlja) i Android background isolate-a. Ranije je ista
/// upitna logika bila duplirana (`_allPassengersCompleted` /
/// `_bgAllPassengersCompleted`), uključujući i lokalnu proveru timestamp-a
/// (`_bgIsTimestampSet` je bio duplikat `V3StatusPolicy.isTimestampSet`).
/// Vraća `false` ako slot/putnici ne postoje (konzervativno — ne zaustavlja
/// tracking ako se stanje ne može pouzdano utvrditi).
Future<bool> v3AllPassengersCompleted({
  required SupabaseClient client,
  required String datumIso,
  required String grad,
  required String vreme,
  String logTag = '[v3AllPassengersCompleted]',
}) async {
  if (datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return false;

  try {
    final slotRows = await client
        .from('v3_trenutna_dodela_slot')
        .select('id')
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('vreme', vreme);

    final activeSlot = (slotRows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
    if (activeSlot == null) return false;

    final dodelaRows = await client.from('v3_trenutna_dodela').select('termin_id').eq('slot_id', activeSlot['id']);

    final slotTerminIds = (dodelaRows as List<dynamic>?)
        ?.map((r) => (r as Map<String, dynamic>)['termin_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();

    if (slotTerminIds == null || slotTerminIds.isEmpty) return false;

    final rows = await client
        .from('v3_operativna_nedelja')
        .select('id, pokupljen_at, otkazano_at')
        .inFilter('id', slotTerminIds.toList());

    if (rows.isEmpty) return false;

    for (final row in rows) {
      final pokupljen = V3StatusPolicy.isTimestampSet(row['pokupljen_at']);
      final otkazan = V3StatusPolicy.isTimestampSet(row['otkazano_at']);
      if (!pokupljen && !otkazan) return false;
    }
    return true;
  } catch (e) {
    debugPrint('$logTag Greška pri proveri putnika: $e');
    return false;
  }
}

/// JEDAN IZVOR ISTINE za proveru da li su lokacijski preduslovi zadovoljeni
/// (GPS uključen + dozvola za lokaciju). Deljeno između main isolate-a
/// (`V3VozacLocationTrackingService`) i Android background isolate-a
/// (`v3_background_location_handler.dart`). Ranije je ista logika bila
/// duplirana na oba mesta, a u main isolate-u je bila umotana u nepotrebnu
/// `V3LocationPrereqStatus` enum klasu.
///
/// [requestIfDenied] treba biti `true` samo u foreground-u (main isolate), jer
/// background isolate ne može da prikaže permission dijalog.
Future<bool> v3CheckLocationPrerequisites({
  bool requestIfDenied = false,
  void Function(String message)? log,
  String logTag = '[v3CheckLocationPrerequisites]',
}) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    log?.call('$logTag GPS servis isključen');
    return false;
  }

  var permission = await Geolocator.checkPermission();
  if (requestIfDenied && permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
    log?.call('$logTag Dozvola za lokaciju nije odobrena: $permission');
    return false;
  }

  return true;
}

/// JEDAN IZVOR ISTINE za upsert trenutne GPS pozicije vozača u
/// `v3_vozac_location`. Deljeno između main isolate-a
/// (`V3VozacLocationTrackingService`) i Android background isolate-a.
Future<void> v3UpdateVozacLocation({
  required SupabaseClient client,
  required String? vozacId,
  required double lat,
  required double lng,
  String logTag = '[v3UpdateVozacLocation]',
  void Function(String message)? log,
}) async {
  if (vozacId == null || vozacId.isEmpty) {
    log?.call('$logTag preskačem: nedostaje vozacId');
    return;
  }

  try {
    await client.from('v3_vozac_location').upsert(<String, dynamic>{
      'vozac_id': vozacId,
      'lat': lat,
      'lng': lng,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    log?.call('$logTag lokacija ažurirana $lat, $lng za vozača $vozacId');
  } catch (e) {
    log?.call('$logTag greška: $e');
  }
}
