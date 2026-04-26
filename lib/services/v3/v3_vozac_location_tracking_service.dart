import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class V3VozacLocationTrackingService {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();
  static const Duration _interval = Duration(seconds: 30);
  static const String _tableName = 'v3_vozac_lokacije';
  static const String _colVozacId = 'created_by';
  static const String _colLat = 'lat';
  static const String _colLng = 'lng';
  static const String _colUpdatedAt = 'updated_at';

  Timer? _timer;
  bool _inFlight = false;
  String _activeVozacId = '';

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
  }

  Future<void> _sendCurrentLocation() async {
    if (_inFlight || _activeVozacId.isEmpty) return;
    _inFlight = true;

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        debugPrint('[V3VozacLocationTrackingService] location permission/service unavailable');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await _insertLocation(
        vozacId: _activeVozacId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] send error: $e');
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
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
