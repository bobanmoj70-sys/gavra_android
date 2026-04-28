import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static const double _minDistanceMeters = 20.0;

  Timer? _timer;
  bool _inFlight = false;
  String _activeVozacId = '';
  Position? _lastSentPosition;

  /// Poziva se nakon svakog uspješnog slanja GPS pozicije.
  void Function(Position position)? onLocationSent;

  bool get isRunning => _timer != null;
  Position? get lastKnownPosition => _lastSentPosition;

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
      unawaited(
        Supabase.instance.client.from('v3_eta_results').delete().eq('vozac_id', vozacIdToClean).catchError((Object e) {
          debugPrint('[V3VozacLocationTrackingService] eta cleanup error: $e');
          return <Map<String, dynamic>>[];
        }),
      );
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

      if (_lastSentPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastSentPosition!.latitude,
          _lastSentPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (distance < _minDistanceMeters) {
          debugPrint(
              '[V3VozacLocationTrackingService] skip send — pomak ${distance.toStringAsFixed(1)}m < ${_minDistanceMeters}m');
          return;
        }
      }

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
