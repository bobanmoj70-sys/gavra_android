import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
// NAPOMENA: interval je sada JEDAN IZVOR ISTINE deljen sa iOS stranom —
// vidi `v3TrackingTickInterval` u v3_tracking_config.dart.

/// Ime sledećeg putnika + ETA se upisuje DIREKTNO u istu notifikaciju koju
/// koristi foreground GPS servis (isti `id` i isti notifikacioni kanal kao u
/// `AndroidConfiguration` iz `main.dart`) — Android to tretira kao ažuriranje
/// postojeće notifikacije (isti `NotificationManager`), pa vozač vidi SAMO
/// jednu notifikaciju, ne dve. Ažurira se na svaki tick (20s).
const int _kForegroundNotifId = 888;
const String _kForegroundChannelId = 'gavra_gps_tracking';
const String _kForegroundChannelName = 'GPS Tracking';

/// Ključevi "željenog stanja" (`v3Key*`) su sada JEDAN IZVOR ISTINE deljen sa
/// main isolate-om preko `v3_tracking_config.dart` (ranije duplirano ovde).
/// MORAJU ostati identični sa `KEY_ACTIVE_*` konstantama na native (Kotlin)
/// strani (bez `flutter.` prefiksa ovde jer ga `package:shared_preferences`
/// dodaje sam; Kotlin strana ga mora dodati ručno).

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
V3SelfReschedulingTicker? _bgTicker;
SupabaseClient? _bgSupabaseClient;
String _bgSupabaseUrl = '';
String _bgSupabaseAnonKey = '';
ServiceInstance? _bgService;
int _bgEmptyStateTicks = 0;
const int _bgMaxEmptyStateTicks = 6; // 6 tickova × 20s = 120s čekanja na željeno stanje

// 🗺️ Realtime broadcast pozicije (JEDAN IZVOR ISTINE, deljen sa main
// isolate-om preko `V3PozicijaBroadcaster` u v3_tracking_config.dart —
// ranije duplirana logika `_bgBroadcastPozicija`).
final V3PozicijaBroadcaster _bgPozicijaBroadcaster = V3PozicijaBroadcaster();

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
      // Prvo pokušaj SecureStorage (glavni izvor osetljivih podataka)
      final values = await _secureStorage.readAll();
      var url = (values[_kStorageSupabaseUrl] ?? '').trim();
      var anonKey = (values[_kStorageSupabaseAnonKey] ?? '').trim();

      // Fallback: ako SecureStorage ne radi u headless isolate-u (npr. zbog
      // enkripcije problema), pokušaj iz SharedPreferences.
      if (url.isEmpty || anonKey.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          url = (prefs.getString(_kStorageSupabaseUrl) ?? '').trim();
          anonKey = (prefs.getString(_kStorageSupabaseAnonKey) ?? '').trim();
          if (url.isNotEmpty && anonKey.isNotEmpty) {
            debugPrint('[BG] Supabase config učitan iz SharedPreferences fallback-a');
          }
        } catch (e) {
          debugPrint('[BG] Greška pri fallback čitanju Supabase config: $e');
        }
      }

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
  debugPrint('[BG] _bgSyncDesiredStateFromPrefs() poÄetak');
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final vozacId = (prefs.getString(v3KeyVozacId) ?? '').trim();
  final datumIso = (prefs.getString(v3KeyDatumIso) ?? '').trim();
  final grad = (prefs.getString(v3KeyGrad) ?? '').trim();
  final vreme = (prefs.getString(v3KeyVreme) ?? '').trim();
  final startedAtMs = prefs.getInt(v3KeyStartedAt) ?? 0;
  debugPrint(
      '[BG] Pročitano iz Prefs: vozacId=$vozacId datum=$datumIso grad=$grad vreme=$vreme startedAt=$startedAtMs');

  if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
    _bgEmptyStateTicks++;
    debugPrint('[BG] Željeno stanje nije kompletno — emptyStateTicks=$_bgEmptyStateTicks/${_bgMaxEmptyStateTicks}');
    if (_bgEmptyStateTicks >= _bgMaxEmptyStateTicks) {
      debugPrint('[BG] Željeno stanje nije kompletno nakon $_bgMaxEmptyStateTicks pokušaja — zaustavljam tracking');
      await _bgStopTracking(reason: 'sync_from_prefs');
    } else {
      debugPrint('[BG] Čekam sledeći tick pre nego što zaustavim servis');
    }
    return;
  }

  // Resetuj brojač kada dobijemo kompletno stanje
  if (_bgEmptyStateTicks > 0) {
    debugPrint('[BG] Željeno stanje ponovo kompletno, resetujem emptyStateTicks');
    _bgEmptyStateTicks = 0;
  }

  // Ako se vozač/termin nisu promenili, nema potrebe za resetom — samo
  // nastavi da šalje lokaciju u _bgSendLocation.
  if (_bgVozacId == vozacId && _bgDatumIso == datumIso && _bgGrad == grad && _bgVreme == vreme) {
    debugPrint('[BG] Željeno stanje se nije promenilo');
    return;
  }

  debugPrint('[BG] Primenujem novo željeno stanje: vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso');
  _bgVozacId = vozacId;
  _bgDatumIso = datumIso;
  _bgGrad = grad;
  _bgVreme = vreme;
  // Koristi sačuvani started_at iz main isolate-a (ili native push handler-a)
  // da 55-minutni timeout ne bi bio resetovan pri svakom restartu servisa.
  _bgTrackingStartedAt =
      startedAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(startedAtMs) : (_bgTrackingStartedAt ?? DateTime.now());
  debugPrint('[BG] _bgTrackingStartedAt=$_bgTrackingStartedAt');

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
    debugPrint('[BG] Supabase client nije spreman — activateSlot se ne poziva');
  }
}

Future<void> _bgClearDesiredState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await v3ClearDesiredState(prefs);
  } catch (e) {
    debugPrint('[BG] Greška pri brisanju željenog stanja: $e');
  }
}

Future<void> _bgClearEtaForVozac(String vozacId) async {
  final client = _bgSupabaseClient;
  if (client == null) return;
  await v3ClearEtaForVozac(client: client, vozacId: vozacId, logTag: '[BG]');
}

/// Proverava da li su svi putnici u aktivnom slotu završeni (pokupljeni ili
/// otkazani). Delegira na `v3AllPassengersCompleted` (JEDAN IZVOR ISTINE,
/// deljen sa main isolate-om) — ranije duplirana upitna logika, uključujući
/// i lokalni `_bgIsTimestampSet` (duplikat `V3StatusPolicy.isTimestampSet`),
/// sada u v3_tracking_config.dart.
Future<bool> _bgAllPassengersCompleted() async {
  if (!_bgCanSendLocation) return false;

  final client = _bgSupabaseClient;
  if (client == null) return false;

  return v3AllPassengersCompleted(
    client: client,
    datumIso: _bgDatumIso,
    grad: _bgGrad,
    vreme: _bgVreme,
    logTag: '[BG]',
  );
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
  _bgTicker?.cancel();
  _bgTicker = null;
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

  String? ime;
  if (putnikId != null && remainingCount > 0) {
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
  }

  // Deljena logika za tekst notifikacije (JEDAN IZVOR ISTINE, ranije
  // duplirana identično u `_iosUpdateTrackingNotification` na iOS strani) —
  // vidi `v3BuildTrackingNotificationText` u v3_tracking_config.dart.
  final text = v3BuildTrackingNotificationText(
    nextPutnikId: putnikId,
    nextPutnikIme: ime,
    etaSeconds: etaSeconds,
    remainingCount: remainingCount,
  );
  final title = text.title;
  final body = text.body;

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

Future<void> _bgSendLocation() async {
  debugPrint('[BG] _bgSendLocation() početak');
  final vozacId = _bgVozacId;
  debugPrint('[BG] _bgSendLocation vozacId=$vozacId canSend=$_bgCanSendLocation');
  if (vozacId == null || vozacId.isEmpty) {
    debugPrint('[BG] _bgSendLocation prekinut: prazan vozacId');
    return;
  }
  if (!_bgCanSendLocation) {
    debugPrint(
        '[BG] _bgSendLocation prekinut: _bgCanSendLocation=false (datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme)');
    return;
  }

  await _bgEnsureSupabaseClientReady();
  final client = _bgSupabaseClient;
  if (client == null) {
    debugPrint('[BG] Supabase client nije inicijalizovan u background isolate-u');
    return;
  }

  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[BG] GPS service enabled=$serviceEnabled');
    if (!serviceEnabled) {
      debugPrint('[BG] GPS isključen');
      return;
    }

    final permission = await Geolocator.checkPermission();
    debugPrint('[BG] Location permission=$permission');
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      debugPrint('[BG] Dozvola za lokaciju nije odobrena (background ne traži permission)');
      return;
    }

    debugPrint('[BG] Dohvatam trenutnu poziciju...');
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    debugPrint('[BG] Pozicija dobijena: ${position.latitude}, ${position.longitude}');

    // Prvo direktno upiši lokaciju u slot — ne čekaj v3-compute-eta.
    await _bgUpdateSlotLocation(lat: position.latitude, lng: position.longitude);

    debugPrint('[BG] Pozivam v3-compute-eta...');
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
    )
        // Zaštita od beskonačnog čekanja — `functions_client` nema sopstveni
        // timeout, pa na lošoj mreži poziv ume da "visi" bez kraja (vidi
        // napomenu uz `v3ComputeEtaNetworkTimeout` u v3_tracking_config.dart).
        .timeout(v3ComputeEtaNetworkTimeout);
    debugPrint('[BG] v3-compute-eta odgovor primljen');
    unawaited(_bgPozicijaBroadcaster.broadcast(
      client: client,
      vozacId: vozacId,
      lat: position.latitude,
      lng: position.longitude,
      logTag: '[BG]',
    ));
    final responseData = etaResponse.data;
    debugPrint('[BG] v3-compute-eta responseData: $responseData');
    if (responseData is Map && responseData['ok'] != true) {
      debugPrint('[BG] ETA greška: reason=${responseData['reason']} warning=${responseData['warning']}');
    } else {
      debugPrint(
          '[BG] Lokacija poslata: ${position.latitude}, ${position.longitude} updated=${responseData is Map ? responseData['updated'] : '?'} reason=${responseData is Map ? responseData['reason'] : '?'}');
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
  }
}

/// Direktno ažurira waypoints_json.location_by_vozac za aktivnog vozača u
/// aktivnom slotu sa trenutnom GPS pozicijom. Koristi per-vozač ključ da bi
/// se izbegao race condition kada više vozača deli isti slot.
Future<void> _bgUpdateSlotLocation({
  required double lat,
  required double lng,
}) async {
  if (!_bgCanSendLocation) {
    debugPrint('[BG] _bgUpdateSlotLocation preskačem: _bgCanSendLocation=false');
    return;
  }
  final client = _bgSupabaseClient;
  if (client == null) {
    debugPrint('[BG] _bgUpdateSlotLocation preskačem: Supabase client nije spreman');
    return;
  }

  try {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await client
        .from('v3_trenutna_dodela_slot')
        .select('id, waypoints_json')
        .eq('datum', _bgDatumIso)
        .eq('grad', _bgGrad)
        .eq('vreme', _bgVreme)
        .limit(1);

    final row = (rows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
    if (row == null) {
      debugPrint('[BG] _bgUpdateSlotLocation: slot nije pronađen');
      return;
    }

    final existing = row['waypoints_json'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final locationByVozac = (existing['location_by_vozac'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final updated = <String, dynamic>{
      ...existing,
      'location_by_vozac': <String, dynamic>{
        ...locationByVozac,
        _bgVozacId!: <String, dynamic>{
          'lat': lat,
          'lng': lng,
          'timestamp': nowIso,
          'note': 'background_gps_tick',
        },
      },
    };

    await client
        .from('v3_trenutna_dodela_slot')
        .update(<String, dynamic>{'waypoints_json': updated}).eq('id', row['id']);
    debugPrint('[BG] _bgUpdateSlotLocation: lokacija ažurirana $lat, $lng za vozača $_bgVozacId');
  } catch (e) {
    debugPrint('[BG] _bgUpdateSlotLocation greška: $e');
  }
}

/// Top-level callback za flutter_background_service.
/// Pokreće se u posebnom isolate-u. Svakih 20s: (1) sinhronizuje željeno
/// stanje, (2) proverava watchdog (max trajanje), (3) šalje GPS lokaciju.
@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  debugPrint('[BG] >>> onBackgroundServiceStart() POZVAN <<<');
  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[BG] WidgetsFlutterBinding.ensureInitialized() uspešan');
  } catch (e, stack) {
    debugPrint('[BG] >>> GREŠKA U WidgetsFlutterBinding.ensureInitialized(): $e');
    debugPrint('[BG] >>> STACK: $stack');
  }
  _bgService = service;

  try {
    service.on(_kActionStop).listen((event) async {
      final prefs = await SharedPreferences.getInstance();
      final vozacId = (prefs.getString(v3KeyVozacId) ?? '').trim();
      if (vozacId.isNotEmpty) {
        debugPrint('[BG] stop event ignored: novo željeno stanje prisutno');
        await _bgSyncDesiredStateFromPrefs();
        return;
      }
      await _bgStopTracking(reason: 'external_stop_event');
    });

    await _bgEnsureSupabaseClientReady();
    await _bgSyncDesiredStateFromPrefs();
    service.invoke(_kReady, {});
    debugPrint('[BG] Background servis spreman');

    Future<void> tick() async {
      debugPrint('[BG] tick() početak');
      await _bgSyncDesiredStateFromPrefs();

      if (v3TrackingTimedOut(_bgTrackingStartedAt)) {
        debugPrint('[BG] stop reason=timeout duration_minutes=${v3TrackingMaxDuration.inMinutes}');
        await _bgStopTracking(reason: 'timeout');
        return;
      }

      if (_bgCanSendLocation) {
        debugPrint('[BG] Uslov za slanje lokacije ispunjen, pozivam _bgSendLocation()');
        await _bgSendLocation();
      } else {
        debugPrint(
            '[BG] Uslov za slanje lokacije NIJE ispunjen: vozac=$_bgVozacId datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme');
      }
      debugPrint('[BG] tick() kraj');
    }

    // Sam-zakazujući tajmer (JEDAN IZVOR ISTINE, deljen sa iOS stranom preko
    // `V3SelfReschedulingTicker` u v3_tracking_config.dart) — fix za bug "ne
    // šalje lokaciju na 20s": `Timer.periodic` bi okinuo sledeći tick tačno na
    // 20s OD POČETKA prethodnog, bez obzira da li je prethodni tick (GPS fix +
    // `v3-compute-eta` poziv, koji iznutra radi i do 3 OSRM retry-a sa
    // eksponencijalnim backoff-om) još u toku — `_bgInFlight` guard bi tada
    // TIHO preskočio taj tick (efektivno 40s+ razmak, bez nadoknađivanja).
    _bgTicker?.cancel();
    _bgTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: tick)..start();
  } catch (e, stack) {
    debugPrint('[BG] >>> FATALNA GREŠKA U onBackgroundServiceStart: $e');
    debugPrint('[BG] >>> STACK: $stack');
    rethrow;
  }
}
