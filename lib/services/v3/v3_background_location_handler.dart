import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_time_utils.dart';

/// Konstante za background servis
const String _kVozacId = 'vozac_id';
const String _kSetSupabaseConfig = 'set_supabase_config';
const String _kActionStop = 'stop';
const String _kReady = 'ready';
const String _kRequestState = 'request_state';
const Duration _kInterval = Duration(seconds: 20);

/// Tracking se automatski gasi ako traje duže od ovog vremena
/// (safety net ako se ne detektuje da su svi putnici pokupljeni).
const Duration _kMaxTrackingDuration = Duration(minutes: 55);

/// Ključevi za perzistentno čuvanje aktivnog stanja (koristi se ako se
/// background isolate restartuje dok main isolate nije dostupan).
const String _kStorageVozacId = 'bg_tracking_vozac_id';
const String _kStorageDatumIso = 'bg_tracking_datum_iso';
const String _kStorageGrad = 'bg_tracking_grad';
const String _kStorageVreme = 'bg_tracking_vreme';
const String _kStorageStartedAt = 'bg_tracking_started_at';

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
    debugPrint(
        '[BG] Učitano perzistentno stanje: vozacId=$vozacId datum=$datumIso grad=$grad vreme=$vreme startedAt=$startedAtRaw');
  } catch (e) {
    debugPrint('[BG] Greška pri učitavanju perzistentnog stanja: $e');
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

/// Proverava da li su svi putnici za aktivni slot završeni
/// (pokupljeni ili otkazani). Vraća false ako nema putnika ili ako
/// postoji bar jedan koji nije završen.
Future<bool> _bgAllPassengersCompleted() async {
  if (!_bgCanSendLocation) return false;

  final client = _bgSupabaseClient;
  if (client == null) return false;

  try {
    // Učitaj aktivni slot da znamo tačno koje putnike ovaj vozač treba da pokupi.
    final slotRows = await client
        .from('v3_trenutna_dodela_slot')
        .select('id, waypoints_json')
        .eq('vozac_v3_auth_id', _bgVozacId as Object)
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
Future<void> _bgStopTracking() async {
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
    }
  });

  service.on(_kActionStop).listen((event) async {
    await _bgStopTracking();
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
  await _bgLoadPersistedState();
  _bgStartTimerIfReady();
  service.invoke(_kReady, {});
  debugPrint('[BG] Background servis spreman');

  // Auto-stop watchdog: proverava svakih 20s da li je pređeno max trajanje trackinga.
  Timer.periodic(_kInterval, (_) {
    final startedAt = _bgTrackingStartedAt;
    if (startedAt == null) return;
    if (DateTime.now().difference(startedAt) < _kMaxTrackingDuration) return;

    debugPrint('[BG] Auto-stop: ${_kMaxTrackingDuration.inMinutes} min trackinga isteklo');
    unawaited(_bgStopTracking());
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
      debugPrint('[BG] Auto-stop: svi putnici su pokupljeni/otkazani');
      await _bgStopTracking();
      return;
    }
  } catch (e) {
    debugPrint('[BG] Greška pri slanju lokacije: $e');
  } finally {
    _bgInFlight = false;
  }
}
