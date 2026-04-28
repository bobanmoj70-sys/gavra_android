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
  static const String _tableName = 'v3_vozac_lokacije';
  static const String _colVozacId = 'created_by';
  static const String _colLat = 'lat';
  static const String _colLng = 'lng';
  static const String _colUpdatedAt = 'updated_at';

  static const double _minDistanceMeters = 20.0;

  Timer? _timer;
  bool _inFlight = false;
  String _activeVozacId = '';
  Position? _lastSentPosition;

  bool get isRunning => _timer != null;

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
    _timer?.cancel();
    _timer = null;
    _activeVozacId = '';
    _inFlight = false;
    _lastSentPosition = null;
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
          debugPrint('[V3VozacLocationTrackingService] skip send — pomak ${distance.toStringAsFixed(1)}m < ${_minDistanceMeters}m');
          return;
        }
      }

      await _insertLocation(
        vozacId: _activeVozacId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _lastSentPosition = position;
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] send error: $e');
    } finally {
      _inFlight = false;
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

  Future<void> _insertLocation({
    required String vozacId,
    required double latitude,
    required double longitude,
  }) async {
    final supabase = Supabase.instance.client;

    final payload = <String, dynamic>{
      _colVozacId: vozacId,
      _colLat: latitude,
      _colLng: longitude,
      _colUpdatedAt: DateTime.now().toUtc().toIso8601String(),
    };

    await supabase.from(_tableName).upsert(payload, onConflict: _colVozacId);
    debugPrint(
      '[V3VozacLocationTrackingService] inserted vozac=$vozacId table=$_tableName lat=$latitude lng=$longitude',
    );
  }
}
