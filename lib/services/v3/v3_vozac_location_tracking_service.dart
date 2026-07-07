import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_time_utils.dart';
import 'v3_trenutna_dodela_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';

enum V3LocationPrereqStatus {
  ok,
  serviceDisabled,
  denied,
  deniedForever,
}

class V3VozacLocationTrackingService {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  String _activeVozacId = '';
  String _activeDatumIso = '';
  String _activeGrad = '';
  String _activeVreme = '';
  Position? _lastSentPosition;
  bool _isRunning = false;

  /// Optimizovani redosled putnika (deljen između ekrana)
  final List<String> _optimizedPutnikIds = [];

  /// ETA vrednosti (deljene između ekrana)
  final Map<String, int> _etaSecondsCache = {};

  /// Poziva se nakon svakog uspješnog slanja GPS pozicije (foreground).
  void Function(Position position)? onLocationSent;

  bool get isRunning => _isRunning;

  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
  String get activeDatumIso => _activeDatumIso;
  String get activeGrad => _activeGrad;
  String get activeVreme => _activeVreme;
  Position? get lastKnownPosition => _lastSentPosition;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  String _normalizeDateIso(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return value.split('T').first;
  }

  Future<void> _syncBackgroundSupabaseConfig(FlutterBackgroundService service) async {
    try {
      if (!configService.isInitialized) {
        await configService.initializeBasic();
      }
      final url = configService.getSupabaseUrl().trim();
      final anonKey = configService.getSupabaseAnonKey().trim();
      if (url.isEmpty || anonKey.isEmpty) {
        debugPrint('[V3VozacLocationTrackingService] Supabase config empty, cannot sync to background');
        return;
      }
      service.invoke('set_supabase_config', {'url': url, 'anon_key': anonKey});
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Failed to sync Supabase config to background: $e');
    }
  }

  void setActiveTermin({required String datumIso, required String grad, required String vreme}) {
    _activeDatumIso = _normalizeDateIso(datumIso);
    _activeGrad = grad.trim().toUpperCase();
    _activeVreme = V3TimeUtils.normalizeToHHmm(vreme);

    // Očisti deljene ETA/redosled keševe jer je termin promenjen
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    // Prosledi background servisu da i on šalje pravilne vrednosti
    final service = FlutterBackgroundService();
    service.invoke('set_termin', {'datum_iso': _activeDatumIso, 'grad': _activeGrad, 'vreme': _activeVreme});

    if (_isRunning && _activeVozacId.isNotEmpty) {
      service.invoke('set_vozac_id', {
        'vozac_id': _activeVozacId,
        'datum_iso': _activeDatumIso,
        'grad': _activeGrad,
        'vreme': _activeVreme,
      });
    }
  }

  Future<void> clearEtaForVozac({required String vozacId}) async {
    final normalized = vozacId.trim();
    if (normalized.isEmpty) return;

    try {
      await Supabase.instance.client.from('v3_eta_results').delete().eq('vozac_id', normalized);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] eta cleanup error: $e');
    }
  }

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    if (normalizedVozacId.isEmpty) return;

    if (_activeVozacId == normalizedVozacId && _isRunning) return;

    // Ako je drugi vozač — stop pre nego što pokrenemo novi
    if (_activeVozacId != normalizedVozacId) {
      await stop();
    }
    _activeVozacId = normalizedVozacId;

    final service = FlutterBackgroundService();
    var isServiceRunning = await service.isRunning();
    if (!isServiceRunning) {
      try {
        await service.startService();
      } catch (e) {
        _activeVozacId = '';
        _isRunning = false;
        debugPrint('[V3VozacLocationTrackingService] Failed to start background service: $e');
        return;
      }
      isServiceRunning = await service.isRunning();
      if (!isServiceRunning) {
        _activeVozacId = '';
        _isRunning = false;
        debugPrint('[V3VozacLocationTrackingService] Background service did not start.');
        return;
      }
    }

    await _syncBackgroundSupabaseConfig(service);

    _isRunning = true;

    // Prosledi termin background servisu ako je setovan
    if (_activeDatumIso.isNotEmpty || _activeGrad.isNotEmpty || _activeVreme.isNotEmpty) {
      debugPrint(
          '[V3VozacLocationTrackingService] Šaljem termin background servisu: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
      service.invoke('set_termin', {'datum_iso': _activeDatumIso, 'grad': _activeGrad, 'vreme': _activeVreme});
    }

    // Prosledi vozac_id background servisu (+ fallback aktivni termin)
    service.invoke('set_vozac_id', {
      'vozac_id': normalizedVozacId,
      'datum_iso': _activeDatumIso,
      'grad': _activeGrad,
      'vreme': _activeVreme,
    });
  }

  Future<void> stop() async {
    final vozacIdToClean = _activeVozacId;
    final datumIsoToClean = _activeDatumIso;
    final gradToClean = _activeGrad;
    final vremeToClean = _activeVreme;
    _activeVozacId = '';
    _activeDatumIso = '';
    _activeGrad = '';
    _activeVreme = '';
    _lastSentPosition = null;
    _isRunning = false;
    onLocationSent = null;
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }

    if (vozacIdToClean.isNotEmpty) {
      await clearEtaForVozac(vozacId: vozacIdToClean);
      if (datumIsoToClean.isNotEmpty && gradToClean.isNotEmpty && vremeToClean.isNotEmpty) {
        try {
          final slotId = await V3TrenutnaDodelaSlotService.fetchSlotId(
            datumIso: datumIsoToClean,
            grad: gradToClean,
            vreme: vremeToClean,
            vozacId: vozacIdToClean,
          );
          if (slotId != null) {
            await V3TrenutnaDodelaService.deleteBySlotId(slotId);
          }
        } catch (e) {
          debugPrint('[V3VozacLocationTrackingService] deleteBySlotId error: $e');
        }
      }
    }

    if (datumIsoToClean.isNotEmpty && gradToClean.isNotEmpty && vremeToClean.isNotEmpty) {
      try {
        await V3TrenutnaDodelaSlotService.deleteSlot(
          datumIso: datumIsoToClean,
          grad: gradToClean,
          vreme: vremeToClean,
          vozacId: vozacIdToClean,
        );
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] deleteSlot error: $e');
      }
    }
  }

  /// Dobavi trenutnu GPS poziciju i odmah izračunaj ETA.
  /// Ispravka: _lastSentPosition nije mogao biti setovan iz background isolate-a,
  /// pa se GPS pozicija sada dobavlja direktno.
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      return (etaMap: <String, int>{}, order: <String>[]);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _lastSentPosition = position;
      return await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] fetchPositionAndComputeEta error: $e');
      return (etaMap: <String, int>{}, order: <String>[]);
    }
  }

  Future<V3LocationPrereqStatus> checkLocationPrerequisites() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return V3LocationPrereqStatus.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return V3LocationPrereqStatus.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      return V3LocationPrereqStatus.denied;
    }

    return V3LocationPrereqStatus.ok;
  }

  Future<({Map<String, int> etaMap, List<String> order})> computeEta({
    required String vozacId,
    required double lat,
    required double lng,
    required String grad,
    required String vreme,
    String? datumIso,
  }) async {
    final supabase = Supabase.instance.client;
    final response = await supabase.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': lat,
        'lng': lng,
        'grad': grad,
        'vreme': vreme,
        if (datumIso != null && datumIso.isNotEmpty) 'datum_iso': datumIso,
      },
    );
    debugPrint('[V3VozacLocationTrackingService] computeEta response: ${response.data}');

    final etaMap = <String, int>{};
    final order = <String>[];
    final data = response.data;
    if (data is Map && data['ok'] == true) {
      final etaList = data['eta_results'];
      if (etaList is List) {
        for (final item in etaList) {
          if (item is Map) {
            final pid = item['putnik_id']?.toString();
            final sec = (item['eta_seconds'] as num?)?.toInt();
            if (pid != null && pid.isNotEmpty && sec != null) {
              etaMap[pid] = sec;
            }
          }
        }
      }
      // Koristi eksplicitni optimizovani redosled iz OSRM
      final optimizedOrder = data['optimized_order'];
      if (optimizedOrder is List) {
        for (final pid in optimizedOrder) {
          if (pid is String && pid.isNotEmpty) {
            order.add(pid);
          }
        }
      }

      // Čuvaj u zajednički cache za sve ekrane
      _optimizedPutnikIds
        ..clear()
        ..addAll(order);
      _etaSecondsCache
        ..clear()
        ..addAll(etaMap);
    }
    return (etaMap: etaMap, order: order);
  }
}
