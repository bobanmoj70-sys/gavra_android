import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// V2OpenRouteService - Za realtime ETA
/// Koristi V2OpenRouteService Directions API za izračunavanje ETA tokom vožnje
/// API Key se čita iz environment varijable
///
/// Limit: 2000 zahteva/dan, 40/min
class V2OpenRouteService {
  V2OpenRouteService._();

  static const String _baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';

  // API key - hardkodiran jer je besplatan i nema sigurnosni rizik
  // Ako treba promeniti, promeni ovde
  static const String _apiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjAyNjhjZTg0YzQ5ZTRjMGE5YmJmNmI2NmNmM2IwOTIwIiwiaCI6Im11cm11cjY0In0=';

  /// Realtime ETA: Koristi Directions API za brzo osvežavanje ETA tokom vožnje
  /// Poziva se periodično (svakih 2 min) dok vozač vozi
  static Future<V2RealtimeEtaResult> getRealtimeEta({
    required Position currentPosition,
    required List<String> putnikImena,
    required Map<String, Position> putnikCoordinates,
  }) async {
    if (putnikImena.isEmpty) {
      return V2RealtimeEtaResult.failure('Nema putnika');
    }

    try {
      // Pripremi koordinate: vozač -> putnici u redosledu
      // V2OpenRouteService POST format: [[lon, lat], [lon, lat], ...]
      final coordinates = <List<double>>[];
      coordinates.add([currentPosition.longitude, currentPosition.latitude]);

      final validPutnici = <String>[];
      for (final ime in putnikImena) {
        final pos = putnikCoordinates[ime];
        if (pos != null) {
          coordinates.add([pos.longitude, pos.latitude]);
          validPutnici.add(ime);
        }
      }

      if (validPutnici.isEmpty) {
        return V2RealtimeEtaResult.failure('Nema putnika sa koordinatama');
      }

      // POST request sa JSON body
      final body = json.encode({'coordinates': coordinates});

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': _apiKey,
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return V2RealtimeEtaResult.failure('ORS error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Parsiraj GeoJSON response
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        return V2RealtimeEtaResult.failure('Nema rute');
      }

      final segments = routes[0]['segments'] as List?;
      if (segments == null || segments.isEmpty) {
        return V2RealtimeEtaResult.failure('Nema segmenata');
      }

      // Izračunaj kumulativni ETA za svakog putnika
      final putniciEta = <String, int>{};
      double cumulativeSec = 0;

      for (int i = 0; i < segments.length && i < validPutnici.length; i++) {
        final raw = segments[i];
        if (raw is! Map<String, dynamic>) continue;
        final segment = raw;
        final duration = (segment['duration'] as num?)?.toDouble() ?? 0;
        cumulativeSec += duration;
        putniciEta[validPutnici[i]] = (cumulativeSec / 60).round();
      }

      return V2RealtimeEtaResult.success(putniciEta);
    } catch (e) {
      return V2RealtimeEtaResult.failure('Greška: $e');
    }
  }
}

/// Rezultat realtime ETA poziva
class V2RealtimeEtaResult {
  final bool success;
  final Map<String, int>? putniciEta; // ime -> ETA u minutama
  final String? error;

  V2RealtimeEtaResult._({
    required this.success,
    this.putniciEta,
    this.error,
  });

  factory V2RealtimeEtaResult.success(Map<String, int> eta) {
    return V2RealtimeEtaResult._(success: true, putniciEta: eta);
  }

  factory V2RealtimeEtaResult.failure(String error) {
    return V2RealtimeEtaResult._(success: false, error: error);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2RealtimeEtaResult && success == other.success && error == other.error;

  @override
  int get hashCode => Object.hash(success, error);
}
