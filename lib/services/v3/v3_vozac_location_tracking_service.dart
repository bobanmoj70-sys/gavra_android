import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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

  String _activeVozacId = '';
  Position? _lastSentPosition;
  bool _blockingScreenInitialized = false;
  bool _inFlight = false;
  bool _isRunning = false;

  /// Poziva se nakon svakog uspješnog slanja GPS pozicije (foreground).
  void Function(Position position)? onLocationSent;

  bool get isRunning => _isRunning;

  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
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

    if (_activeVozacId == normalizedVozacId && _isRunning) return;

    // Ako je drugi vozač — stop pre nego što pokrenemo novi
    if (_activeVozacId != normalizedVozacId) {
      await stop();
    }
    _activeVozacId = normalizedVozacId;
    _isRunning = true;

    final service = FlutterBackgroundService();
    final isServiceRunning = await service.isRunning();
    if (!isServiceRunning) {
      await service.startService();
    }
    // Prosledi vozac_id background servisu
    service.invoke('set_vozac_id', {'vozac_id': normalizedVozacId});

    // Odmah pošalji i iz foreground-a (za brzu povratnu informaciju)
    unawaited(_sendCurrentLocation());

    // Deblokiraj ekran ako je bio blokiran
    V3BlockingScreenService.instance.onBlockingScreenDismissed();
  }

  /// Inicijalizuje blocking screen servis
  Future<void> initializeBlockingScreen() async {
    if (_blockingScreenInitialized) return;

    final blockingService = V3BlockingScreenService.instance;
    await blockingService.initialize();

    _blockingScreenInitialized = true;
    debugPrint('[V3VozacLocationTrackingService] Blocking screen service initialized');
  }

  Future<void> stop() async {
    final vozacIdToClean = _activeVozacId;
    _activeVozacId = '';
    _lastSentPosition = null;
    _isRunning = false;
    onLocationSent = null;

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }

    if (vozacIdToClean.isNotEmpty) {
      unawaited(clearEtaForVozac(vozacId: vozacIdToClean));
    }
  }

  /// Pomoćna metoda za odmah slanje iz foreground-a (za brz UI feedback).
  Future<void> _sendCurrentLocation() async {
    if (_inFlight || _activeVozacId.isEmpty) return;
    _inFlight = true;

    try {
      final locationStatus = await checkLocationPrerequisites();
      if (locationStatus != V3LocationPrereqStatus.ok) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      _lastSentPosition = position;
      onLocationSent?.call(position);

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
