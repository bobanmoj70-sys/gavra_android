import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'v3_blocking_screen_service.dart';

enum V3LocationPrereqStatus {
  ok,
  serviceDisabled,
  denied,
  deniedForever,
}

class V3VozacLocationTrackingService {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();
  static const Duration _interval = Duration(seconds: 30);

  Timer? _timer;
  bool _inFlight = false;
  String _activeVozacId = '';
  Position? _lastSentPosition;
  bool _blockingScreenInitialized = false;

  /// Poziva se nakon svakog uspješnog slanja GPS pozicije.
  void Function(Position position)? onLocationSent;

  bool get isRunning => _timer != null;
  Position? get lastKnownPosition => _lastSentPosition;

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

    if (_activeVozacId == normalizedVozacId && _timer != null) return;

    stop();
    _activeVozacId = normalizedVozacId;

    await _sendCurrentLocation();
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_sendCurrentLocation());
    });

    // Deblokiraj ekran ako je bio blokiran
    V3BlockingScreenService.instance.onBlockingScreenDismissed();
  }

  /// Inicijalizuje blocking screen servis
  Future<void> initializeBlockingScreen() async {
    if (_blockingScreenInitialized) return;

    final blockingService = V3BlockingScreenService.instance;

    // Postavi callback za zaustavljanje tracking-a
    blockingService.onStopTracking = () async {
      stop();
    };

    // Postavi callback za proveru aktivnih putnika
    blockingService.hasActivePassengers = () async {
      // Proveri da li ima aktivnih putnika za ovog vozača
      if (_activeVozacId.isEmpty) return false;

      try {
        final response = await Supabase.instance.client
            .from('v3_trenutna_dodela')
            .select('termin_id')
            .eq('vozac_v3_auth_id', _activeVozacId)
            .eq('status', 'aktivan');

        if (response.isEmpty) return false;

        final terminIds = response.map((r) => r['termin_id'] as String).toList();

        final terminResponse = await Supabase.instance.client
            .from('v3_operativna_nedelja')
            .select('pokupljen_at, otkazano_at')
            .inFilter('id', terminIds);

        // Proveri da li bar jedan termin nije pokupljen/otkazan
        for (final termin in terminResponse) {
          final pokupljenAt = termin['pokupljen_at'];
          final otkazanoAt = termin['otkazano_at'];

          if (pokupljenAt == null && otkazanoAt == null) {
            return true; // Ima aktivnih putnika
          }
        }

        return false; // Nema aktivnih putnika
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] hasActivePassengers error: $e');
        return false;
      }
    };

    // Inicijalizuj blocking screen servis
    await blockingService.initialize();

    _blockingScreenInitialized = true;
    debugPrint('[V3VozacLocationTrackingService] Blocking screen service initialized');
  }

  void stop() {
    final vozacIdToClean = _activeVozacId;
    _timer?.cancel();
    _timer = null;
    _activeVozacId = '';
    _inFlight = false;
    _lastSentPosition = null;
    onLocationSent = null;
    if (vozacIdToClean.isNotEmpty) {
      unawaited(clearEtaForVozac(vozacId: vozacIdToClean));
    }
  }

  Future<void> _sendCurrentLocation() async {
    if (_inFlight || _activeVozacId.isEmpty) return;
    _inFlight = true;

    try {
      final locationStatus = await checkLocationPrerequisites();
      if (locationStatus != V3LocationPrereqStatus.ok) {
        debugPrint('[V3VozacLocationTrackingService] location unavailable: $locationStatus');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      _lastSentPosition = position;
      onLocationSent?.call(position);
      // Fire-and-forget: server računa ETA za sve putnike ovog vozača
      unawaited(
        _invokeComputeEta(
          vozacId: _activeVozacId,
          lat: position.latitude,
          lng: position.longitude,
        ).catchError((Object e) => debugPrint('[V3VozacLocationTrackingService] computeEta error: $e')),
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] send error: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// Odmah poziva ETA edge funkciju sa poslednjom poznatom pozicijom.
  /// Koristi se nakon optimizacije rute kada vozač stoji (pomak < threshold).
  Future<void> forceComputeEta() async {
    final pos = _lastSentPosition;
    if (pos == null || _activeVozacId.isEmpty) return;
    unawaited(
      _invokeComputeEta(
        vozacId: _activeVozacId,
        lat: pos.latitude,
        lng: pos.longitude,
      ).catchError((Object e) => debugPrint('[V3VozacLocationTrackingService] forceComputeEta error: $e')),
    );
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

  Future<void> _invokeComputeEta({
    required String vozacId,
    required double lat,
    required double lng,
  }) async {
    final supabase = Supabase.instance.client;
    final response = await supabase.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': lat,
        'lng': lng,
      },
    );
    debugPrint('[V3VozacLocationTrackingService] computeEta response: ${response.data}');
  }
}
