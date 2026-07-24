import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_time_utils.dart';
import 'v3_tracking_config.dart';

/// Konstante za background servis
const String _kVozacId = 'vozac_id';
const String _kSetSupabaseConfig = 'set_supabase_config';
const String _kSetStartPayload = 'set_start_payload';
const String _kActionStop = 'stop';
const String _kReady = 'ready';
const String _kRequestState = 'request_state';
const Duration _kInterval = Duration(seconds: 20);

/// Ključevi za perzistentno čuvanje aktivnog stanja (koristi se ako se
/// background isolate restartuje dok main isolate nije dostupan).
const String _kStorageVozacId = 'bg_tracking_vozac_id';
const String _kStorageDatumIso = 'bg_tracking_datum_iso';
const String _kStorageGrad = 'bg_tracking_grad';
const String _kStorageVreme = 'bg_tracking_vreme';
const String _kStorageStartedAt = 'bg_tracking_started_at';
const String _kStorageSupabaseUrl = 'bg_tracking_supabase_url';
const String _kStorageSupabaseAnonKey = 'bg_tracking_supabase_anon_key';

/// Ključevi za native→Dart "pending" payload koji `GavraFcmService.kt` upisuje
/// direktno u SharedPreferences kada stigne `vozac_auto_start_tracking` push,
/// BEZ obzira na Flutter engine stanje (radi i kad je app potpuno ubijena).
/// Moraju biti identični sa `GavraFcmService.KEY_PENDING_*` konstantama (bez
/// `flutter.` prefiksa ovde, jer ga `package:shared_preferences` dodaje sam).
const String _kPendingVozacId = 'bg_pending_vozac_id';
const String _kPendingDatumIso = 'bg_pending_datum_iso';
const String _kPendingGrad = 'bg_pending_grad';
const String _kPendingVreme = 'bg_pending_vreme';
const String _kPendingTimestamp = 'bg_pending_timestamp';

/// Payload se smatra "svežim" najviše 10 minuta — sprečava da se stari,
/// već obrađeni native payload ponovo pokrene ako iz nekog razloga ostane
/// u SharedPreferences (npr. servis se restartuje iz drugog razloga).
const Duration _kPendingPayloadMaxAge = Duration(minutes: 10);

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Globalni mutable state za background isolate — Dart dozvoljava top-level promenljive u entry-point fajlu.
String? _bgVozacId;
String _bgDatumIso = '';
String _bgGrad = '';
String _bgVreme = '';
DateTime? _bgTrackingStartedAt;
Timer? _bgTimer;
bool _bgInFlight = false;
SupabaseClient? _bgSupabaseClient;
String _bgSupabaseUrl = '';
String _bgSupabaseAnonKey = '';
bool _bgConfigReady = false;
ServiceInstance? _bgService;

bool get _bgCanSendLocation =>
    _bgVozacId != null && _bgVozacId!.isNotEmpty && _bgDatumIso.isNotEmpty && _bgGrad.isNotEmpty && _bgVreme.isNotEmpty;

Future<void> _bgLoadPersistedState() async {
  try {
    final values = await _secureStorage.readAll();
    final vozacId = (values[_kStorageVozacId] ?? '').trim();
    final datumIso = (values[_kStorageDatumIso] ?? '').trim();
    final grad = (values[_kStorageGrad] ?? '').trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(values[_kStorageVreme] ?? '');
    final startedAtRaw = (values[_kStorageStartedAt] ?? '').trim();
    if (vozacId.isNotEmpty) _bgVozacId = vozacId;
    if (datumIso.isNotEmpty) _bgDatumIso = datumIso;
    if (grad.isNotEmpty) _bgGrad = grad;
    if (vreme.isNotEmpty) _bgVreme = vreme;
    if (startedAtRaw.isNotEmpty) {
      _bgTrackingStartedAt = DateTime.tryParse(startedAtRaw);
    }

    // Supabase config — potreban da background isolate radi i kad je
    // pokrenut direktno iz native koda (GavraFcmService), bez main isolate-a
    // koji bi inače poslao `set_supabase_config`.
    if (_bgSupabaseUrl.isEmpty || _bgSupabaseAnonKey.isEmpty) {
      final persistedUrl = (values[_kStorageSupabaseUrl] ?? '').trim();
      final persistedAnonKey = (values[_kStorageSupabaseAnonKey] ?? '').trim();
      if (persistedUrl.isNotEmpty && persistedAnonKey.isNotEmpty) {
        _bgSupabaseUrl = persistedUrl;
        _bgSupabaseAnonKey = persistedAnonKey;
        _bgTryInitSupabaseClient();
        if (_bgSupabaseClient != null) {
          _bgConfigReady = true;
        }
      }
    }

    debugPrint(
        '[BG] Učitano perzistentno stanje: vozacId=$vozacId datum=$datumIso grad=$grad vreme=$vreme startedAt=$startedAtRaw');
  } catch (e) {
    debugPrint('[BG] Greška pri učitavanju perzistentnog stanja: $e');
  }
}

/// Čita "pending" payload koji je `GavraFcmService.kt` upisao direktno u
/// nativni SharedPreferences fajl (isti koji `package:shared_preferences`
/// koristi), kada je stigao `vozac_auto_start_tracking` push — BEZ obzira
/// na to da li je Flutter main engine bio aktivan.
///
/// Ovo je "čisto" rešenje za auto-start: background isolate (headless,
/// pokrenut direktno iz native koda) sam pročita payload i sam pokreće
/// tracking, bez potrebe za tap-om na notifikaciju ili aktivnim main
/// isolate-om. Payload se briše nakon čitanja (idempotentno konzumiran).
///
/// Vraća true ako je pending payload pronađen i primenjen (setovao je
/// _bgVozacId/_bgDatumIso/_bgGrad/_bgVreme).
Future<bool> _bgConsumeNativePendingPayloadIfAny() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final vozacId = (prefs.getString(_kPendingVozacId) ?? '').trim();
    final datumIso = (prefs.getString(_kPendingDatumIso) ?? '').trim();
    final grad = (prefs.getString(_kPendingGrad) ?? '').trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(prefs.getString(_kPendingVreme) ?? '');
    final timestampMs = prefs.getInt(_kPendingTimestamp) ?? 0;

    if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
      return false;
    }

    // Konzumiraj (obriši) odmah da izbegnemo ponovnu obradu istog payload-a
    // pri sledećem restartu servisa.
    await prefs.remove(_kPendingVozacId);
    await prefs.remove(_kPendingDatumIso);
    await prefs.remove(_kPendingGrad);
    await prefs.remove(_kPendingVreme);
    await prefs.remove(_kPendingTimestamp);

    if (timestampMs > 0) {
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
      if (age > _kPendingPayloadMaxAge) {
        debugPrint('[BG] Native pending payload je zastareo (age=${age.inMinutes}min), ignorišem.');
        return false;
      }
    }

    debugPrint('[BG] Native pending payload pronađen: vozac=$vozacId datum=$datumIso grad=$grad vreme=$vreme');

    _bgVozacId = vozacId;
    _bgDatumIso = datumIso;
    _bgGrad = grad;
    _bgVreme = vreme;

    if (_bgTrackingStartedAt == null) {
      _bgTrackingStartedAt = DateTime.now();
      unawaited(_secureStorage.write(key: _kStorageStartedAt, value: _bgTrackingStartedAt!.toIso8601String()));
    }
    unawaited(_secureStorage.write(key: _kStorageVozacId, value: vozacId));
    unawaited(_secureStorage.write(key: _kStorageDatumIso, value: datumIso));
    unawaited(_secureStorage.write(key: _kStorageGrad, value: grad));
    unawaited(_secureStorage.write(key: _kStorageVreme, value: vreme));

    // Aktiviraj slot red (idempotentan upsert) direktno preko background
    // Supabase klijenta — ekvivalent `V3TrenutnaDodelaSlotService.activateSlot`,
    // ali bez zavisnosti od main isolate `globals.dart` supabase getter-a.
    unawaited(_bgActivateSlotWithRetry(vozacId: vozacId, datumIso: datumIso, grad: grad, vreme: vreme));

    return true;
  } catch (e) {
    debugPrint('[BG] Greška pri čitanju native pending payload-a: $e');
    return false;
  }
}

/// Idempotentan upsert u `v3_trenutna_dodela_slot` — ekvivalent
/// `V3TrenutnaDodelaSlotService.activateSlot`, sa retry logikom (isti
/// pattern kao main isolate `_autoStartVozacTrackingFromPush`), samo
/// implementiran direktno preko background Supabase client-a jer
/// `V3TrenutnaDodelaSlotService` zavisi od main isolate `globals.dart`.
Future<void> _bgActivateSlotWithRetry({
  required String vozacId,
  required String datumIso,
  required String grad,
  required String vreme,
}) async {
  _bgTryInitSupabaseClient();
  var client = _bgSupabaseClient;

  // Supabase config možda još nije stigao (npr. cold-start iz native koda
  // bez main isolate-a) — sačekaj do 5s da `set_supabase_config`/persisted
  // config postane dostupan.
  for (var i = 0; i < 10 && client == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _bgTryInitSupabaseClient();
    client = _bgSupabaseClient;
  }

  if (client == null) {
    debugPrint('[BG] activateSlot: Supabase client nije dostupan nakon čekanja, odustajem.');
    return;
  }

  const maxRetries = 3;
  const initialDelayMs = 500;
  var retryCount = 0;

  while (retryCount < maxRetries) {
    try {
      await client.from('v3_trenutna_dodela_slot').upsert(
        <String, dynamic>{
          'datum': datumIso,
          'grad': grad,
          'vreme': vreme,
          'vozac_v3_auth_id': vozacId,
          'updated_by': vozacId,
        },
        onConflict: 'datum,grad,vreme',
      );
      debugPrint('[BG] ✅ activateSlot uspešan (attempt ${retryCount + 1})');
      return;
    } catch (e) {
      retryCount++;
      if (retryCount >= maxRetries) {
        debugPrint('⚠️ [BG] activateSlot greška nakon $maxRetries pokušaja: $e (nastavljam bez slota)');
        return;
      }
      final delayMs = initialDelayMs * (1 << (retryCount - 1));
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}

Future<void> _bgClearPersistedState() async {
  try {
    await _secureStorage.delete(key: _kStorageVozacId);
    await _secureStorage.delete(key: _kStorageDatumIso);
    await _secureStorage.delete(key: _kStorageGrad);
    await _secureStorage.delete(key: _kStorageVreme);
    await _secureStorage.delete(key: _kStorageStartedAt);
  } catch (e) {
    debugPrint('[BG] Greška pri brisanju perzistentnog stanja: $e');
  }
}

Future<void> _bgClearEtaForVozac(String vozacId) async {
  final normalized = vozacId.trim();
  if (normalized.isEmpty) return;

  _bgTryInitSupabaseClient();
  final client = _bgSupabaseClient;
  if (client == null) return;

  try {
    await client.from('v3_eta_results').delete().eq('vozac_id', normalized);
  } catch (e) {
    debugPrint('[BG] ETA cleanup error: $e');
  }
}

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
  debugPrint('[BG] Supabase client inicijalizovan iz main isolate konfiguracije');
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
  _bgTimer?.cancel();
  _bgTimer = null;
  _bgVozacId = null;
  _bgDatumIso = '';
  _bgGrad = '';
  _bgVreme = '';
  _bgTrackingStartedAt = null;
  await _bgClearPersistedState();
  if (vozacIdToClean != null && vozacIdToClean.isNotEmpty) {
    await _bgClearEtaForVozac(vozacIdToClean);
  }
  _bgSupabaseUrl = '';
  _bgSupabaseAnonKey = '';
  _bgSupabaseClient = null;
  service?.stopSelf();
}

/// Top-level callback za flutter_background_service.
/// Pokreće se u posebnom isolate-u i šalje GPS lokaciju svakih 30 sekundi.
@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  _bgService = service;

  // Supabase konfiguraciju očekujemo iz main isolate-a preko service.invoke.
  service.on(_kSetSupabaseConfig).listen((event) {
    _bgSupabaseUrl = (event?['url'] ?? '').toString().trim();
    _bgSupabaseAnonKey = (event?['anon_key'] ?? '').toString().trim();
    _bgSupabaseClient = null;
    _bgConfigReady = false;
    _bgTryInitSupabaseClient();
    if (_bgSupabaseClient != null) {
      _bgConfigReady = true;
      if (_bgCanSendLocation) {
        _bgStartTimerIfReady();
      }
    }
  });

  service.on(_kSetStartPayload).listen((event) {
    final id = (event?[_kVozacId] ?? '').toString().trim();
    final datumIso = (event?['datum_iso'] ?? '').toString().trim();
    final grad = (event?['grad'] ?? '').toString().trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm((event?['vreme'] ?? '').toString());
    final startedAtRaw = (event?['started_at'] ?? '').toString().trim();
    final supabaseUrl = (event?['supabase_url'] ?? '').toString().trim();
    final supabaseAnonKey = (event?['supabase_anon_key'] ?? '').toString().trim();

    if (id.isNotEmpty) {
      _bgVozacId = id;
    }
    if (datumIso.isNotEmpty) {
      _bgDatumIso = datumIso;
    }
    if (grad.isNotEmpty) {
      _bgGrad = grad;
    }
    if (vreme.isNotEmpty) {
      _bgVreme = vreme;
    }

    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      _bgSupabaseUrl = supabaseUrl;
      _bgSupabaseAnonKey = supabaseAnonKey;
      _bgSupabaseClient = null;
      _bgConfigReady = false;
      _bgTryInitSupabaseClient();
      if (_bgSupabaseClient != null) {
        _bgConfigReady = true;
      }
    }

    if (_bgTrackingStartedAt == null) {
      _bgTrackingStartedAt = DateTime.tryParse(startedAtRaw) ?? DateTime.now();
      unawaited(_secureStorage.write(key: _kStorageStartedAt, value: _bgTrackingStartedAt!.toIso8601String()));
    }

    debugPrint(
        '[BG] Unified start payload primljen: vozac=$_bgVozacId datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme configReady=$_bgConfigReady');
    _bgStartTimerIfReady();
  });

  service.on(_kActionStop).listen((event) async {
    await _bgStopTracking(reason: 'external_stop_event');
  });

  // Glavni isolate šalje vozac_id preko invoke
  service.on('set_vozac_id').listen((event) {
    final id = (event?[_kVozacId] as String?)?.trim();
    debugPrint('[BG] set_vozac_id event received: id=$id');
    if (id != null && id.isNotEmpty) {
      _bgVozacId = id;
      final datumIso = (event?['datum_iso'] ?? '').toString().trim();
      final grad = (event?['grad'] ?? '').toString().trim().toUpperCase();
      final vreme = V3TimeUtils.normalizeToHHmm((event?['vreme'] ?? '').toString());
      debugPrint('[BG] set_vozac_id termin: datum=$datumIso grad=$grad vreme=$vreme');
      if (datumIso.isNotEmpty) _bgDatumIso = datumIso;
      if (grad.isNotEmpty) _bgGrad = grad;
      if (vreme.isNotEmpty) _bgVreme = vreme;
      if (_bgTrackingStartedAt == null) {
        _bgTrackingStartedAt = DateTime.now();
        unawaited(_secureStorage.write(key: _kStorageStartedAt, value: _bgTrackingStartedAt!.toIso8601String()));
      }
      _bgStartTimerIfReady();
    }
  });

  // Glavni isolate šalje aktivni termin (grad+vreme)
  service.on('set_termin').listen((event) {
    final datumIso = (event?['datum_iso'] ?? '').toString().trim();
    final grad = (event?['grad'] ?? '').toString().trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm((event?['vreme'] ?? '').toString());
    if (datumIso.isNotEmpty) _bgDatumIso = datumIso;
    if (grad.isNotEmpty) _bgGrad = grad;
    if (vreme.isNotEmpty) _bgVreme = vreme;
    debugPrint('[BG] Termin ažuriran: datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme');
    _bgStartTimerIfReady();
  });

  // Glavni isolate traži ponovno slanje stanja (npr. nakon resume)
  service.on(_kRequestState).listen((event) async {
    await _bgLoadPersistedState();
    _bgStartTimerIfReady();
    debugPrint('[BG] Stanje osveženo na zahtev: datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme');
  });

  // Obavesti main isolate da su listener-i registrovani i da je stanje učitano
  // Native pending payload (upisan direktno iz GavraFcmService.kt) ima
  // prioritet nad perzistentnim stanjem — to je "čisto" auto-start rešenje
  // koje radi i kad je app potpuno ubijena (bez tap-a na notifikaciju).
  final consumedNative = await _bgConsumeNativePendingPayloadIfAny();
  if (!consumedNative) {
    await _bgLoadPersistedState();
  }
  _bgStartTimerIfReady();
  service.invoke(_kReady, {});
  debugPrint('[BG] Background servis spreman');

  // Auto-stop watchdog: proverava svakih 20s da li je pređeno max trajanje trackinga.
  Timer.periodic(_kInterval, (_) {
    final startedAt = _bgTrackingStartedAt;
    if (startedAt == null) return;
    if (DateTime.now().difference(startedAt) < v3TrackingMaxDuration) return;

    debugPrint('[BG] stop reason=timeout source=watchdog duration_minutes=${v3TrackingMaxDuration.inMinutes}');
    unawaited(_bgStopTracking(reason: 'timeout'));
  });
}

void _bgStartTimerIfReady() {
  if (_bgCanSendLocation) {
    if (_bgTimer == null || !_bgTimer!.isActive) {
      _bgStartTimer();
    }
  } else {
    _bgTimer?.cancel();
    _bgTimer = null;
    debugPrint('[BG] Timer zaustavljen: nedostaju podaci za slanje lokacije');
  }
}

void _bgStartTimer() {
  _bgTimer?.cancel();
  _bgTimer = Timer.periodic(_kInterval, (_) {
    unawaited(_bgSendLocation());
  });
  // Prvo slanje odmah, ali samo ako su svi uslovi ispunjeni
  if (_bgCanSendLocation && _bgConfigReady) {
    unawaited(_bgSendLocation());
  } else {
    debugPrint('[BG] Odlažem prvo slanje: canSend=$_bgCanSendLocation configReady=$_bgConfigReady');
  }
}

Future<void> _bgSendLocation() async {
  final vozacId = _bgVozacId;
  if (vozacId == null || vozacId.isEmpty || _bgInFlight) return;

  if (!_bgCanSendLocation) {
    // Očekivano stanje dok se termin ne postavi — ne logujemo kao grešku
    return;
  }

  if (!_bgConfigReady) {
    _bgTryInitSupabaseClient();
    if (_bgSupabaseClient != null) {
      _bgConfigReady = true;
    } else {
      debugPrint('[BG] Supabase config još nije spreman, preskačem slanje');
      return;
    }
  }

  final client = _bgSupabaseClient;
  if (client == null) {
    _bgTryInitSupabaseClient();
  }

  final activeClient = _bgSupabaseClient;
  if (activeClient == null) {
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

    final etaResponse = await activeClient.functions.invoke(
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
    final responseData = etaResponse.data;
    if (responseData is Map && responseData['ok'] != true) {
      debugPrint('[BG] ETA greška: reason=${responseData['reason']} warning=${responseData['warning']}');
    } else {
      debugPrint(
          '[BG] Lokacija poslata: ${position.latitude}, ${position.longitude} updated=${responseData is Map ? responseData['updated'] : '?'}');
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
