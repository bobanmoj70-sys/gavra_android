import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_time_utils.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

/// ============================================================================
/// JEDAN IZVOR ISTINE za "šta bi background tracking trebalo da radi":
///
/// Ceo auto-start/tracking sistem se svodi na JEDNO "željeno stanje" upisano
/// u obični `SharedPreferences` fajl (isti koji `package:shared_preferences`
/// koristi na Dart strani, sa `flutter.` prefiksom na ključevima). To stanje
/// upisuju DVA pisca:
///   1. `GavraFcmService.kt` (native, Kotlin) — kad stigne
///      `vozac_auto_start_tracking` push, BEZ OBZIRA na to da li je Flutter
///      engine živ (radi i kad je app potpuno ubijena).
///   2. `V3VozacLocationTrackingService` (Dart, main isolate) — kad korisnik
///      ručno pokrene/promeni/zaustavi tracking dok je app otvorena.
///
/// Ovaj background isolate (headless, pokreće ga `flutter_background_service`)
/// ima JEDAN posao: svakih 20s (i odmah pri startu) PROČITA to željeno stanje
/// i primeni razliku u odnosu na ono što trenutno radi:
///   - vozac_id prazan            → zaustavi tracking
///   - vozac_id nov/različit      → aktiviraj slot (upsert) + resetuj timer trajanja
///   - isti vozac, drugi termin   → aktiviraj slot za novi termin (bez resetovanja timera)
///   - ništa promenjeno           → samo pošalji GPS lokaciju kao i do sad
///
/// Zašto polling umesto event-a: ako se servis već izvršava (npr. prati
/// prethodni termin), `flutter_background_service`-ov Android sloj NE
/// restartuje headless Dart engine na sledeći `startForegroundService()` poziv
/// (`BackgroundService.java#runService` rano izlazi ako `isRunning`) — pa se
/// jednokratni "pending payload" event nikad ne bi pokupio za drugi termin.
/// Polling svakih 20s to rešava bez ikakve dodatne native logike: čim native
/// upiše novo stanje, sledeći tick ga vidi i primeni, bez obzira da li je
/// Android servis "restartovan" ili ne.
/// ============================================================================

const String _kActionStop = 'stop';
const String _kReady = 'ready';
const Duration _kInterval = Duration(seconds: 20);

/// Ime sledećeg putnika + ETA se upisuje DIREKTNO u istu notifikaciju koju
/// koristi foreground GPS servis (isti `id` i isti notifikacioni kanal kao u
/// `AndroidConfiguration` iz `main.dart`) — Android to tretira kao ažuriranje
/// postojeće notifikacije (isti `NotificationManager`), pa vozač vidi SAMO
/// jednu notifikaciju, ne dve. Ažurira se na svaki tick (20s).
const int _kForegroundNotifId = 888;
const String _kForegroundChannelId = 'gavra_gps_tracking';
const String _kForegroundChannelName = 'GPS Tracking';

/// Ključevi "željenog stanja" — MORAJU biti identični sa
/// `GavraFcmService.KEY_ACTIVE_*` konstantama na native (Kotlin) strani
/// (bez `flutter.` prefiksa ovde jer ga `package:shared_preferences` dodaje
/// sam; Kotlin strana ga mora dodati ručno).
const String _kKeyVozacId = 'bg_active_vozac_id';
const String _kKeyDatumIso = 'bg_active_datum_iso';
const String _kKeyGrad = 'bg_active_grad';
const String _kKeyVreme = 'bg_active_vreme';
const String _kKeyStartedAt = 'bg_active_started_at';

/// Supabase kredencijali i dalje idu preko `flutter_secure_storage` (osetljivi
/// podaci) — jedini deo koji Kotlin ne piše, već ih main isolate perzistuje
/// pre prvog starta servisa da bi cold-start (killed app) background isolate
/// imao pristup Supabase-u bez čekanja na main isolate.
const String _kStorageSupabaseUrl = 'bg_tracking_supabase_url';
const String _kStorageSupabaseAnonKey = 'bg_tracking_supabase_anon_key';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Globalni mutable state za background isolate — Dart dozvoljava top-level promenljive u entry-point fajlu.
String? _bgVozacId;
String _bgDatumIso = '';
String _bgGrad = '';
String _bgVreme = '';
DateTime? _bgTrackingStartedAt;
Timer? _bgMainTimer;
bool _bgInFlight = false;
SupabaseClient? _bgSupabaseClient;
String _bgSupabaseUrl = '';
String _bgSupabaseAnonKey = '';
ServiceInstance? _bgService;

// 🗺️ Realtime broadcast kanal (samo poslednja pozicija, bez čuvanja u bazi) —
// isti kanal kao u foreground servisu, koristi ga admin ekran za live mapu.
RealtimeChannel? _bgPozicijaChannel;
String? _bgPozicijaChannelVozacId;

Future<void> _bgBroadcastPozicija({
  required SupabaseClient client,
  required String vozacId,
  required double lat,
  required double lng,
}) async {
  try {
    if (_bgPozicijaChannel == null || _bgPozicijaChannelVozacId != vozacId) {
      final old = _bgPozicijaChannel;
      if (old != null) {
        unawaited(client.removeChannel(old));
      }
      final channel = client.channel('v3-vozac-pozicija-$vozacId');
      _bgPozicijaChannel = channel;
      _bgPozicijaChannelVozacId = vozacId;
      channel.subscribe();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _bgPozicijaChannel?.sendBroadcastMessage(
      event: 'pozicija',
      payload: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'ts': DateTime.now().toIso8601String(),
      },
    );
  } catch (e) {
    debugPrint('[BG] broadcast pozicija greška: $e');
    _bgPozicijaChannel = null;
    _bgPozicijaChannelVozacId = null;
  }
}

bool get _bgCanSendLocation =>
    _bgVozacId != null && _bgVozacId!.isNotEmpty && _bgDatumIso.isNotEmpty && _bgGrad.isNotEmpty && _bgVreme.isNotEmpty;

void _bgTryInitSupabaseClient() {
  if (_bgSupabaseClient != null) return;
  if (_bgSupabaseUrl.isEmpty || _bgSupabaseAnonKey.isEmpty) return;

  _bgSupabaseClient = SupabaseClient(
    _bgSupabaseUrl,
    _bgSupabaseAnonKey,
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
    ),
  );
  debugPrint('[BG] Supabase client inicijalizovan.');
}

/// Učitava Supabase URL/anon key iz SecureStorage (upisano od strane main
/// isolate-a) i pokušava da inicijalizuje klijenta. Sačeka do 5s ako
/// konfiguracija još nije stigla (cold-start race).
Future<void> _bgEnsureSupabaseClientReady() async {
  _bgTryInitSupabaseClient();
  if (_bgSupabaseClient != null) return;

  for (var i = 0; i < 10 && _bgSupabaseClient == null; i++) {
    try {
      final values = await _secureStorage.readAll();
      final url = (values[_kStorageSupabaseUrl] ?? '').trim();
      final anonKey = (values[_kStorageSupabaseAnonKey] ?? '').trim();
      if (url.isNotEmpty && anonKey.isNotEmpty) {
        _bgSupabaseUrl = url;
        _bgSupabaseAnonKey = anonKey;
        _bgTryInitSupabaseClient();
      }
    } catch (e) {
      debugPrint('[BG] Greška pri čitanju Supabase config: $e');
    }
    if (_bgSupabaseClient != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  if (_bgSupabaseClient == null) {
    debugPrint('[BG] ⚠️ Supabase client nije dostupan nakon čekanja.');
  }
}

/// Čita "željeno stanje" iz SharedPreferences i primeni razliku u odnosu na
/// trenutno stanje background isolate-a. Ovo je JEDINA funkcija koja odlučuje
/// šta treba da se promeni — poziva se odmah pri startu servisa i zatim na
/// svakih 20s (isti tick koji šalje i GPS lokaciju).
Future<void> _bgSyncDesiredStateFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final vozacId = (prefs.getString(_kKeyVozacId) ?? '').trim();

    if (vozacId.isEmpty) {
      if (_bgVozacId != null) {
        await _bgStopTracking(reason: 'desired_state_cleared');
      }
      return;
    }

    final datumIso = (prefs.getString(_kKeyDatumIso) ?? '').trim();
    final grad = (prefs.getString(_kKeyGrad) ?? '').trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(prefs.getString(_kKeyVreme) ?? '');
    if (datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
      debugPrint('[BG] Željeno stanje nepotpuno, ignorišem: vozac=$vozacId datum=$datumIso grad=$grad vreme=$vreme');
      return;
    }

    final isNewVozac = _bgVozacId == null || _bgVozacId != vozacId;
    final isTerminChanged = !isNewVozac && (_bgDatumIso != datumIso || _bgGrad != grad || _bgVreme != vreme);

    if (!isNewVozac && !isTerminChanged) {
      return; // ništa se nije promenilo
    }

    _bgVozacId = vozacId;
    _bgDatumIso = datumIso;
    _bgGrad = grad;
    _bgVreme = vreme;

    if (isNewVozac) {
      final startedAtMs = prefs.getInt(_kKeyStartedAt) ?? 0;
      _bgTrackingStartedAt = startedAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(startedAtMs) : DateTime.now();
      debugPrint('[BG] Novi vozač za tracking: $vozacId (grad=$grad vreme=$vreme datum=$datumIso)');
    } else {
      debugPrint('[BG] Termin promenjen za istog vozača: grad=$grad vreme=$vreme datum=$datumIso');
    }

    await _bgEnsureSupabaseClientReady();
    final client = _bgSupabaseClient;
    if (client != null) {
      unawaited(activateSlotWithRetry(
        client: client,
        vozacId: vozacId,
        datumIso: datumIso,
        grad: grad,
        vreme: vreme,
        logTag: '[BG]',
        log: debugPrint,
      ));
    } else {
      debugPrint('[BG] ⚠️ activateSlot preskočen: Supabase client nije dostupan.');
    }
  } catch (e) {
    debugPrint('[BG] Greška pri sinhronizaciji željenog stanja: $e');
  }
}

Future<void> _bgClearDesiredState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKeyVozacId);
    await prefs.remove(_kKeyDatumIso);
    await prefs.remove(_kKeyGrad);
    await prefs.remove(_kKeyVreme);
    await prefs.remove(_kKeyStartedAt);
  } catch (e) {
    debugPrint('[BG] Greška pri brisanju željenog stanja: $e');
  }
}

Future<void> _bgClearEtaForVozac(String vozacId) async {
  final normalized = vozacId.trim();
  if (normalized.isEmpty) return;

  final client = _bgSupabaseClient;
  if (client == null) return;

  try {
    await client.from('v3_eta_results').delete().eq('vozac_id', normalized);
  } catch (e) {
    debugPrint('[BG] ETA cleanup error: $e');
  }
}

/// Proverava da li je vrednost timestamp setovana (string nije prazan ili nije null).
bool _bgIsTimestampSet(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  return true;
}

/// Proverava da li su svi putnici u aktivnom slotu završeni
/// (pokupljeni ili otkazani). Vraća false ako nema putnika.
Future<bool> _bgAllPassengersCompleted() async {
  if (!_bgCanSendLocation) return false;

  final client = _bgSupabaseClient;
  if (client == null) return false;

  try {
    final slotRows = await client
        .from('v3_trenutna_dodela_slot')
        .select('id, waypoints_json')
        .eq('datum', _bgDatumIso)
        .eq('grad', _bgGrad)
        .eq('vreme', _bgVreme);

    final activeSlot = (slotRows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
    if (activeSlot == null) return false;

    final waypointsJson = activeSlot['waypoints_json'] as Map<String, dynamic>?;
    final passengers = waypointsJson?['passengers'] as List<dynamic>?;
    if (passengers == null || passengers.isEmpty) return false;

    final slotTerminIds = passengers
        .whereType<Map<String, dynamic>>()
        .map((p) => p['termin_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();

    if (slotTerminIds.isEmpty) return false;

    final rows = await client
        .from('v3_operativna_nedelja')
        .select('id, pokupljen_at, otkazano_at')
        .inFilter('id', slotTerminIds.toList());

    if (rows.isEmpty) return false;

    for (final row in rows) {
      final pokupljen = _bgIsTimestampSet(row['pokupljen_at']);
      final otkazan = _bgIsTimestampSet(row['otkazano_at']);
      if (!pokupljen && !otkazan) return false;
    }
    return true;
  } catch (e) {
    debugPrint('[BG] Greška pri proveri putnika: $e');
    return false;
  }
}

/// Zaustavlja background tracking i čisti stanje.
Future<void> _bgStopTracking({String reason = 'unspecified'}) async {
  debugPrint('[BG] stop reason=$reason');
  final service = _bgService;
  final vozacIdToClean = _bgVozacId;
  _bgVozacId = null;
  _bgDatumIso = '';
  _bgGrad = '';
  _bgVreme = '';
  _bgTrackingStartedAt = null;
  await _bgClearDesiredState();
  if (vozacIdToClean != null && vozacIdToClean.isNotEmpty) {
    await _bgClearEtaForVozac(vozacIdToClean);
  }
  await _bgResetForegroundNotification();
  _bgMainTimer?.cancel();
  _bgMainTimer = null;
  _bgSupabaseUrl = '';
  _bgSupabaseAnonKey = '';
  _bgSupabaseClient = null;
  service?.stopSelf();
}

FlutterLocalNotificationsPlugin? _bgLocalNotifications;
bool _bgLocalNotificationsInitialized = false;

/// Lokalne notifikacije rade u zasebnom (headless) isolate-u, pa je potrebna
/// sopstvena instanca plugina i sopstvena inicijalizacija — nezavisno od
/// main isolate-a koji ima svoju (globalnu) instancu u `main.dart`.
Future<void> _bgEnsureLocalNotifications() async {
  if (_bgLocalNotificationsInitialized) return;
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: androidInit));
    _bgLocalNotifications = plugin;
    _bgLocalNotificationsInitialized = true;
  } catch (e) {
    debugPrint('[BG] Local notifications init greška: $e');
  }
}

/// Ažurira postojeću foreground "GPS Tracking" notifikaciju da prikazuje ime
/// sledećeg putnika i ETA (jedna notifikacija umesto dve). Poziva se posle
/// svakog uspešnog ETA tick-a. `putnikId == null` znači da nema više
/// preostalih putnika (svi pokupljeni/otkazani) — u tom slučaju se prikazuje
/// generička poruka dok se tracking sam ne zaustavi (auto-stop provera je
/// odvojena, ovo je samo UI).
Future<void> _bgUpdateNextPassengerNotification({
  required String? putnikId,
  required int? etaSeconds,
  required int remainingCount,
}) async {
  await _bgEnsureLocalNotifications();
  final plugin = _bgLocalNotifications;
  if (plugin == null) return;

  String title;
  String body;

  if (putnikId == null || remainingCount == 0) {
    title = 'GPS Tracking';
    body = 'Nema više putnika za pokupljanje.';
  } else {
    var ime = 'sledeći putnik';
    try {
      final client = _bgSupabaseClient;
      if (client != null) {
        final row = await client.from('v3_auth').select('ime_prezime').eq('id', putnikId).maybeSingle();
        final fetchedIme = (row?['ime_prezime'] as String?)?.trim();
        if (fetchedIme != null && fetchedIme.isNotEmpty) ime = fetchedIme;
      }
    } catch (e) {
      debugPrint('[BG] Greška pri dohvatanju imena putnika za notifikaciju: $e');
    }

    final etaMin = etaSeconds != null && etaSeconds >= 0 ? (etaSeconds / 60).round() : null;
    final etaText = etaMin != null ? ' · ETA $etaMin min' : '';
    final putnikLabel = remainingCount == 1 ? 'putnik' : 'putnika';
    title = 'GPS Tracking — $remainingCount $putnikLabel';
    body = 'Sledeći: $ime$etaText';
  }

  const androidDetails = AndroidNotificationDetails(
    _kForegroundChannelId,
    _kForegroundChannelName,
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
    onlyAlertOnce: true,
  );

  try {
    await plugin.show(
      _kForegroundNotifId,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  } catch (e) {
    debugPrint('[BG] Greška pri ažuriranju foreground notifikacije: $e');
  }
}

Future<void> _bgResetForegroundNotification() async {
  try {
    await _bgLocalNotifications?.show(
      _kForegroundNotifId,
      _kForegroundChannelName,
      'Praćenje lokacije aktivno',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kForegroundChannelId,
          _kForegroundChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          onlyAlertOnce: true,
        ),
      ),
    );
  } catch (_) {
    // ignoriši — nije kritično, servis se ionako gasi odmah nakon ovoga
  }
}

/// Top-level callback za flutter_background_service.
/// Pokreće se u posebnom isolate-u. Svakih 20s: (1) sinhronizuje željeno
/// stanje, (2) proverava watchdog (max trajanje), (3) šalje GPS lokaciju.
@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  _bgService = service;

  service.on(_kActionStop).listen((event) async {
    await _bgStopTracking(reason: 'external_stop_event');
  });

  await _bgEnsureSupabaseClientReady();
  await _bgSyncDesiredStateFromPrefs();
  service.invoke(_kReady, {});
  debugPrint('[BG] Background servis spreman');

  Future<void> tick() async {
    await _bgSyncDesiredStateFromPrefs();

    final startedAt = _bgTrackingStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) >= v3TrackingMaxDuration) {
      debugPrint('[BG] stop reason=timeout duration_minutes=${v3TrackingMaxDuration.inMinutes}');
      await _bgStopTracking(reason: 'timeout');
      return;
    }

    if (_bgCanSendLocation) {
      await _bgSendLocation();
    }
  }

  _bgMainTimer?.cancel();
  unawaited(tick()); // odmah prvi tick (isti model kao iOS _iosTick()), bez čekanja na prvi period
  _bgMainTimer = Timer.periodic(_kInterval, (_) => unawaited(tick()));
}

Future<void> _bgSendLocation() async {
  final vozacId = _bgVozacId;
  if (vozacId == null || vozacId.isEmpty || _bgInFlight) return;
  if (!_bgCanSendLocation) return;

  await _bgEnsureSupabaseClientReady();
  final client = _bgSupabaseClient;
  if (client == null) {
    debugPrint('[BG] Supabase client nije inicijalizovan u background isolate-u');
    return;
  }

  _bgInFlight = true;
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[BG] GPS isključen');
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      debugPrint('[BG] Dozvola za lokaciju nije odobrena (background ne traži permission)');
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    final etaResponse = await client.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': position.latitude,
        'lng': position.longitude,
        'grad': _bgGrad,
        'vreme': _bgVreme,
        'datum_iso': _bgDatumIso,
      },
    );
    unawaited(_bgBroadcastPozicija(client: client, vozacId: vozacId, lat: position.latitude, lng: position.longitude));
    final responseData = etaResponse.data;
    if (responseData is Map && responseData['ok'] != true) {
      debugPrint('[BG] ETA greška: reason=${responseData['reason']} warning=${responseData['warning']}');
    } else {
      debugPrint(
          '[BG] Lokacija poslata: ${position.latitude}, ${position.longitude} updated=${responseData is Map ? responseData['updated'] : '?'}');
    }

    // Ažuriraj persistentnu notifikaciju sa imenom sledećeg putnika + ETA,
    // na osnovu redosleda koji je server već optimizovao (eta_results je
    // sortiran po trip rangu — prvi element je sledeći na redu).
    if (responseData is Map) {
      final etaResultsRaw = responseData['eta_results'];
      final etaResults = etaResultsRaw is List ? etaResultsRaw : const [];
      if (etaResults.isEmpty) {
        unawaited(_bgUpdateNextPassengerNotification(putnikId: null, etaSeconds: null, remainingCount: 0));
      } else {
        final first = etaResults.first;
        final nextPutnikId = first is Map ? first['putnik_id']?.toString() : null;
        final nextEtaSeconds = first is Map ? (first['eta_seconds'] as num?)?.toInt() : null;
        unawaited(_bgUpdateNextPassengerNotification(
          putnikId: nextPutnikId,
          etaSeconds: nextEtaSeconds,
          remainingCount: etaResults.length,
        ));
      }
    }

    // Auto-stop: ako su svi putnici pokupljeni/otkazani, zaustavi tracking.
    if (await _bgAllPassengersCompleted()) {
      debugPrint('[BG] stop reason=all_passengers_completed source=bg_send_location');
      await _bgStopTracking(reason: 'all_passengers_completed');
      return;
    }
  } catch (e) {
    debugPrint('[BG] Greška pri slanju lokacije: $e');
  } finally {
    _bgInFlight = false;
  }
}
