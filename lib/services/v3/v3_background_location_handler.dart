import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_time_utils.dart';

/// Konstante za background servis
const String _kVozacId = 'vozac_id';
const String _kSetSupabaseConfig = 'set_supabase_config';
const String _kActionStop = 'stop';
const Duration _kInterval = Duration(seconds: 30);

/// Globalni mutable state za background isolate — Dart dozvoljava top-level promenljive u entry-point fajlu.
String? _bgVozacId;
String _bgDatumIso = '';
String _bgGrad = '';
String _bgVreme = '';
Timer? _bgTimer;
bool _bgInFlight = false;
SupabaseClient? _bgSupabaseClient;
String _bgSupabaseUrl = '';
String _bgSupabaseAnonKey = '';

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

/// Top-level callback za flutter_background_service.
/// Pokreće se u posebnom isolate-u i šalje GPS lokaciju svakih 30 sekundi.
@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  // Supabase konfiguraciju očekujemo iz main isolate-a preko service.invoke.
  service.on(_kSetSupabaseConfig).listen((event) {
    _bgSupabaseUrl = (event?['url'] ?? '').toString().trim();
    _bgSupabaseAnonKey = (event?['anon_key'] ?? '').toString().trim();
    _bgSupabaseClient = null;
    _bgTryInitSupabaseClient();
  });

  service.on(_kActionStop).listen((event) {
    final vozacIdToClean = _bgVozacId;
    _bgTimer?.cancel();
    _bgTimer = null;
    if (vozacIdToClean != null && vozacIdToClean.isNotEmpty) {
      unawaited(_bgClearEtaForVozac(vozacIdToClean));
    }
    _bgVozacId = null;
    _bgDatumIso = '';
    _bgSupabaseUrl = '';
    _bgSupabaseAnonKey = '';
    _bgSupabaseClient = null;
    service.stopSelf();
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
      _bgStartTimer();
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
  });
}

void _bgStartTimer() {
  _bgTimer?.cancel();
  _bgTimer = Timer.periodic(_kInterval, (_) {
    unawaited(_bgSendLocation());
  });
  // Prvo slanje odmah
  unawaited(_bgSendLocation());
}

Future<void> _bgSendLocation() async {
  final vozacId = _bgVozacId;
  if (vozacId == null || vozacId.isEmpty || _bgInFlight) return;

  if (_bgDatumIso.isEmpty || _bgGrad.isEmpty || _bgVreme.isEmpty) {
    debugPrint('[BG] Preskačem upis lokacije: termin nije postavljen (datum=$_bgDatumIso grad=$_bgGrad vreme=$_bgVreme)');
    debugPrint('[BG] Stack trace: ${StackTrace.current}');
    return;
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
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('[BG] Dozvola za lokaciju nije odobrena (background ne traži permission)');
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    // Čuvaj trenutnu lokaciju u waypoints_json
    try {
        final currentLocation = <Map<String, dynamic>>[
          {
            'lat': position.latitude,
            'lng': position.longitude,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ];

        final updatedRows = await activeClient
            .from('v3_trenutna_dodela_slot')
            .update({'waypoints_json': currentLocation})
            .eq('datum', _bgDatumIso)
            .eq('grad', _bgGrad)
            .eq('vreme', _bgVreme)
            .eq('vozac_v3_auth_id', vozacId)
            .eq('status', 'aktivan')
            .select('datum');

        if (updatedRows.isEmpty) {
          debugPrint('[BG] updateCurrentLocation: 0 rows updated for slot=$_bgDatumIso|$_bgGrad|$_bgVreme vozac=$vozacId');
        }

        debugPrint('[BG] Trenutna lokacija sačuvana');
      } catch (e) {
        debugPrint('[BG] Greška pri čuvanju trenutne lokacije: $e');
      }

    await activeClient.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': position.latitude,
        'lng': position.longitude,
        'grad': _bgGrad,
        'vreme': _bgVreme,
      },
    );
    debugPrint('[BG] Lokacija poslata: ${position.latitude}, ${position.longitude}');
  } catch (e) {
    debugPrint('[BG] Greška pri slanju lokacije: $e');
  } finally {
    _bgInFlight = false;
  }
}
