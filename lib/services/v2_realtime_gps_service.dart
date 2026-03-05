import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'v2_permission_service.dart';

/// Real-time GPS position service
class V2RealtimeGpsService {
  V2RealtimeGpsService._();
  static final _positionController = StreamController<Position>.broadcast();
  static final _speedController = StreamController<double>.broadcast();
  static StreamSubscription<Position>? _positionSubscription;

  /// Stream GPS pozicije
  static Stream<Position> get positionStream => _positionController.stream;

  /// Stream brzine (km/h)
  static Stream<double> get speedStream => _speedController.stream;

  /// Pokreće GPS tracking
  static Future<void> startTracking() async {
    // CENTRALIZOVANA PROVERA GPS DOZVOLA
    final hasPermission = await V2PermissionService.ensureGpsForNavigation();
    if (!hasPermission) {
      throw Exception('GPS dozvole nisu odobrene');
    }

    // Konfiguriši GPS settings — update TAČNO svakih 30 sekundi.
    // distanceFilter: 0 → ne šalje po metražu, samo po timeru.
    // Bez ovog, vozač koji brzo vozi bi trigerovao update i pre timera
    // što bi zajedno sa _locationTimer-om pravilo duple DB upise.
    final androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 30),
    );

    // Pokreni tracking
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: androidSettings,
    ).listen(
      (Position position) {
        _positionController.add(position);

        // Kalkuliši brzinu (km/h)
        final speedMps = position.speed; // meters per second
        final speedKmh = speedMps * 3.6; // convert to km/h
        _speedController.add(speedKmh);
      },
      onError: (error) {
      },
    );
  }

  /// Zaustavlja GPS tracking
  static Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Oslobađa resurse — poziva se samo pri gašenju aplikacije
  static Future<void> dispose() async {
    await stopTracking();
    _positionController.close();
    _speedController.close();
  }
}
