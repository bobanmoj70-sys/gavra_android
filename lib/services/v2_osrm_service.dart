import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/v2_route_config.dart';
import '../models/v2_putnik.dart';
import 'v2_unified_geocoding_service.dart';

/// ??? OSRM SERVICE - OpenStreetMap Routing Machine
class OsrmService {
  OsrmService._();

  /// ?? GLAVNA FUNKCIJA: Optimizuj rutu pomocu OSRM Trip API
  static Future<OsrmResult> optimizeRoute({
    required Position startPosition,
    required List<V2Putnik> putnici,
    Position? endDestination,
    GeocodingProgressCallback? onGeocodingProgress,
  }) async {
    if (putnici.isEmpty) {
      return OsrmResult.error('Nema putnika za optimizaciju');
    }

    try {
      final coordinates = await UnifiedGeocodingService.getCoordinatesForPutnici(
        putnici,
        onProgress: onGeocodingProgress,
      );

      if (coordinates.isEmpty) {
        return OsrmResult.error('Nijedan V2Putnik nema validne koordinate');
      }

      final coordsList = <String>[];

      coordsList.add('${startPosition.longitude},${startPosition.latitude}');

      final putniciWithCoords = <V2Putnik>[];
      for (final V2Putnik in putnici) {
        if (coordinates.containsKey(V2Putnik)) {
          final pos = coordinates[V2Putnik]!;
          coordsList.add('${pos.longitude},${pos.latitude}');
          putniciWithCoords.add(V2Putnik);
        }
      }

      if (putniciWithCoords.isEmpty) {
        return OsrmResult.error('Nema putnika sa validnim koordinatama');
      }

      // ?? Dodaj krajnju destinaciju ako je zadata (Vrsac ili Bela Crkva)
      final hasEndDestination = endDestination != null;
      if (hasEndDestination) {
        coordsList.add('${endDestination.longitude},${endDestination.latitude}');
      }

      final coordsString = coordsList.join(';');

      final osrmResponse = await _callOsrmWithRetry(coordsString, hasEndDestination: hasEndDestination);

      if (osrmResponse == null) {
        return OsrmResult.error('OSRM server nije dostupan. Proverite internet konekciju.');
      }

      final parseResult = _parseOsrmResponse(
        osrmResponse,
        putniciWithCoords,
        coordinates,
        hasEndDestination: hasEndDestination,
      );

      if (parseResult == null) {
        return OsrmResult.error('Greška pri parsiranju OSRM odgovora');
      }

      return OsrmResult.success(
        optimizedPutnici: parseResult.orderedPutnici,
        totalDistanceKm: parseResult.distanceKm,
        totalDurationMin: parseResult.durationMin,
        coordinates: coordinates,
        putniciEta: parseResult.putniciEta, // ?? ETA za svakog putnika
      );
    } catch (e) {
      return OsrmResult.error('Greška pri optimizaciji: $e');
    }
  }

  /// ?? Pozovi OSRM API sa exponential backoff retry
  static Future<Map<String, dynamic>?> _callOsrmWithRetry(
    String coordsString, {
    bool hasEndDestination = false,
  }) async {
    for (int attempt = 1; attempt <= RouteConfig.osrmMaxRetries; attempt++) {
      try {
        // ?? Ako imamo fiksnu krajnju destinaciju, dodaj destination=last
        final destinationParam = hasEndDestination ? '&destination=last' : '';
        final url = '${RouteConfig.osrmBaseUrl}/trip/v1/driving/$coordsString'
            '?source=first'
            '&roundtrip=false'
            '$destinationParam'
            '&geometries=polyline'
            '&overview=simplified'
            '&annotations=distance,duration';

        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'application/json'},
        ).timeout(RouteConfig.osrmTimeout);

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;

          if (data['code'] == 'Ok' && data['trips'] != null && (data['trips'] as List).isNotEmpty) {
            return data;
          }
        }
      } catch (e) {
        // Error logged silently
      }

      if (attempt < RouteConfig.osrmMaxRetries) {
        final delay = RouteConfig.getRetryDelay(attempt);
        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// ?? ISPRAVNO PARSIRANJE OSRM ODGOVORA
  static _OsrmParseResult? _parseOsrmResponse(
    Map<String, dynamic> data,
    List<V2Putnik> putniciWithCoords,
    Map<V2Putnik, Position> coordinates, {
    bool hasEndDestination = false,
  }) {
    try {
      final trips = data['trips'] as List;
      if (trips.isEmpty) return null;

      final trip = trips[0] as Map<String, dynamic>;
      final waypoints = data['waypoints'] as List?;
      final legs = trip['legs'] as List?;

      if (waypoints == null || waypoints.isEmpty) return null;

      final waypointsToProcess = hasEndDestination ? waypoints.length - 1 : waypoints.length;

      // ?? ISPRAVLJEN ALGORITAM:
      // waypoint_index govori: "ova tacka (iz originalne liste) treba biti na poziciji waypoint_index u optimizovanoj ruti"
      // waypoints[0] je START, waypoints[1..n] su putnici, waypoints[n+1] je END (ako postoji)

      // Kreiraj listu parova (V2Putnik, waypoint_index) - preskacemo START (index 0)
      final putniciWithWaypointIndex = <MapEntry<V2Putnik, int>>[];
      for (int i = 1; i < waypointsToProcess; i++) {
        final wp = waypoints[i] as Map<String, dynamic>;
        final waypointIndex = wp['waypoint_index'] as int;
        final putnikIndex = i - 1; // waypoints[1] = putnici[0], waypoints[2] = putnici[1], itd.
        if (putnikIndex >= 0 && putnikIndex < putniciWithCoords.length) {
          putniciWithWaypointIndex.add(MapEntry(putniciWithCoords[putnikIndex], waypointIndex));
        }
      }

      // Sortiraj po waypoint_index da dobijemo optimalan redosled
      putniciWithWaypointIndex.sort((a, b) => a.value.compareTo(b.value));

      final orderedPutnici = putniciWithWaypointIndex.map((e) => e.key).toList();

      // ?? Izracunaj ETA za svakog putnika iz legs
      final putniciEta = <String, int>{};

      if (legs != null && legs.isNotEmpty) {
        double cumulativeDurationSec = 0;

        final legsToProcess = hasEndDestination ? legs.length - 1 : legs.length;

        for (int i = 0; i < legsToProcess && i < orderedPutnici.length; i++) {
          final leg = legs[i] as Map<String, dynamic>;
          final legDuration = (leg['duration'] as num?)?.toDouble() ?? 0;
          cumulativeDurationSec += legDuration;

          final V2Putnik = orderedPutnici[i];
          final etaMinutes = (cumulativeDurationSec / 60).round();
          putniciEta[V2Putnik.ime] = etaMinutes;
        }
      }

      final distance = (trip['distance'] as num).toDouble() / 1000;
      final duration = (trip['duration'] as num).toDouble() / 60;

      return _OsrmParseResult(
        orderedPutnici: orderedPutnici,
        distanceKm: distance,
        durationMin: duration,
        putniciEta: putniciEta,
      );
    } catch (e) {
      return null;
    }
  }
}

class _OsrmParseResult {
  const _OsrmParseResult({
    required this.orderedPutnici,
    required this.distanceKm,
    required this.durationMin,
    required this.putniciEta,
  });

  final List<V2Putnik> orderedPutnici;
  final double distanceKm;
  final double durationMin;
  final Map<String, int> putniciEta;
}

/// ?? Rezultat OSRM optimizacije
class OsrmResult {
  OsrmResult._({
    required this.success,
    required this.message,
    this.optimizedPutnici,
    this.totalDistanceKm,
    this.totalDurationMin,
    this.coordinates,
    this.putniciEta,
  });

  factory OsrmResult.success({
    required List<V2Putnik> optimizedPutnici,
    required double totalDistanceKm,
    required double totalDurationMin,
    Map<V2Putnik, Position>? coordinates,
    Map<String, int>? putniciEta,
  }) {
    return OsrmResult._(
      success: true,
      message: '✅ Ruta optimizovana (OSRM)',
      optimizedPutnici: optimizedPutnici,
      totalDistanceKm: totalDistanceKm,
      totalDurationMin: totalDurationMin,
      coordinates: coordinates,
      putniciEta: putniciEta,
    );
  }

  factory OsrmResult.error(String message) {
    return OsrmResult._(
      success: false,
      message: message,
    );
  }

  final bool success;
  final String message;
  final List<V2Putnik>? optimizedPutnici;
  final double? totalDistanceKm;
  final double? totalDurationMin;
  final Map<V2Putnik, Position>? coordinates;
  final Map<String, int>? putniciEta;
}
