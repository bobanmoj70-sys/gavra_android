import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class V3RouteCoordinate {
  final double latitude;
  final double longitude;

  const V3RouteCoordinate({
    required this.latitude,
    required this.longitude,
  });
}

class V3RouteWaypoint {
  final String id;
  final String label;
  final V3RouteCoordinate coordinate;

  const V3RouteWaypoint({
    required this.id,
    required this.label,
    required this.coordinate,
  });
}

class V3OsrmEtaResult {
  final List<V3RouteWaypoint> orderedStops;
  final Map<String, int> etaByWaypointId;

  const V3OsrmEtaResult({
    required this.orderedStops,
    required this.etaByWaypointId,
  });
}

class V3OsrmRouteService {
  V3OsrmRouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl {
    final envValue = dotenv.maybeGet('OSRM_BASE_URL')?.trim() ?? '';
    if (envValue.isNotEmpty) return envValue;
    return 'https://router.project-osrm.org';
  }

  Future<List<V3RouteWaypoint>> optimizeWaypoints(
    List<V3RouteWaypoint> input, {
    V3RouteWaypoint? fixedDestination,
    V3RouteCoordinate? currentLocation,
  }) async {
    if (input.length <= 1) return List<V3RouteWaypoint>.from(input);

    const sourceId = '__driver_source__';
    final sourceWaypoint =
        currentLocation != null ? V3RouteWaypoint(id: sourceId, label: sourceId, coordinate: currentLocation) : null;

    final inputWithSource = sourceWaypoint != null ? <V3RouteWaypoint>[sourceWaypoint, ...input] : input;

    if (fixedDestination != null) {
      final withDestination = <V3RouteWaypoint>[...inputWithSource, fixedDestination];
      final optimized = await _optimizeRoute(
        withDestination,
        lockFirstAsSource: sourceWaypoint != null,
        lockLastAsDestination: true,
      );
      return optimized.where((item) => item.id != fixedDestination.id && item.id != sourceId).toList(growable: false);
    }

    final optimized = await _optimizeRoute(
      inputWithSource,
      lockFirstAsSource: sourceWaypoint != null,
    );
    return optimized.where((item) => item.id != sourceId).toList(growable: false);
  }

  Future<V3OsrmEtaResult?> computeEtaForStopsFromSource({
    required V3RouteCoordinate source,
    required List<V3RouteWaypoint> stops,
  }) async {
    if (stops.isEmpty) {
      return const V3OsrmEtaResult(
        orderedStops: <V3RouteWaypoint>[],
        etaByWaypointId: <String, int>{},
      );
    }

    final sourceWaypoint = V3RouteWaypoint(
      id: '__source__',
      label: '__source__',
      coordinate: source,
    );

    final chunk = <V3RouteWaypoint>[sourceWaypoint, ...stops];
    final solution = await _fetchTripSolution(
      chunk,
      lockFirstAsSource: true,
      lockLastAsDestination: false,
    );
    if (solution == null) return null;

    final orderedAll = solution.orderedWaypoints;
    if (orderedAll.isEmpty || orderedAll.first.id != sourceWaypoint.id) {
      return null;
    }

    final legs = solution.legs;
    if (legs.length < orderedAll.length - 1) return null;

    final etaByWaypointId = <String, int>{};
    var cumulative = 0;
    for (var index = 1; index < orderedAll.length; index++) {
      final leg = legs[index - 1];
      final durationSeconds = (leg['duration'] as num?)?.toInt();
      if (durationSeconds == null || durationSeconds < 0) return null;
      cumulative += durationSeconds;
      etaByWaypointId[orderedAll[index].id] = cumulative;
    }

    final orderedStops = orderedAll.where((item) => item.id != sourceWaypoint.id).toList(growable: false);

    return V3OsrmEtaResult(
      orderedStops: orderedStops,
      etaByWaypointId: etaByWaypointId,
    );
  }

  /// Kao computeEtaForStopsFromSource ali koristi /route API — poštuje zadati redosled bez re-optimizacije.
  Future<V3OsrmEtaResult?> computeEtaForStopsFixedOrder({
    required V3RouteCoordinate source,
    required List<V3RouteWaypoint> stops,
  }) async {
    if (stops.isEmpty) {
      return const V3OsrmEtaResult(
        orderedStops: <V3RouteWaypoint>[],
        etaByWaypointId: <String, int>{},
      );
    }

    final allCoords = <V3RouteCoordinate>[source, ...stops.map((s) => s.coordinate)];
    final coordStr = allCoords.map((c) => '${c.longitude},${c.latitude}').join(';');
    final uri = Uri.parse('$_baseUrl/route/v1/driving/$coordStr').replace(
      queryParameters: {
        'steps': 'false',
        'overview': 'false',
        'annotations': 'false',
      },
    );

    try {
      final response = await _getWithRetry(uri);
      debugPrint('[OSRM/route] status=${response.statusCode} url=$uri');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[OSRM/route] ❌ bad status ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[OSRM/route] ❌ decoded nije Map');
        return null;
      }
      final code = decoded['code']?.toString() ?? '';
      if (code != 'Ok') {
        debugPrint('[OSRM/route] ❌ code=$code message=${decoded['message']}');
        return null;
      }

      final rawRoutes = decoded['routes'];
      if (rawRoutes is! List || rawRoutes.isEmpty) {
        debugPrint('[OSRM/route] ❌ routes prazan');
        return null;
      }
      final route = rawRoutes.first as Map<String, dynamic>;
      final rawLegs = route['legs'];
      if (rawLegs is! List || rawLegs.length != stops.length) {
        debugPrint(
            '[OSRM/route] ❌ legs.length=${rawLegs is List ? rawLegs.length : 'nije List'} stops.length=${stops.length}');
        return null;
      }

      final etaByWaypointId = <String, int>{};
      var cumulative = 0;
      for (var i = 0; i < stops.length; i++) {
        final leg = rawLegs[i];
        final durationSeconds = (leg is Map ? (leg['duration'] as num?)?.toInt() : null);
        if (durationSeconds == null || durationSeconds < 0) {
          debugPrint('[OSRM/route] ❌ leg[$i] duration null ili negativan: $durationSeconds');
          return null;
        }
        cumulative += durationSeconds;
        // __destination__ je samo za smer rute, ne vraćamo ETA za njega
        if (!stops[i].id.startsWith('__')) {
          etaByWaypointId[stops[i].id] = cumulative;
        }
      }
      debugPrint('[OSRM/route] ✅ etaByWaypointId keys=${etaByWaypointId.length}');

      return V3OsrmEtaResult(
        orderedStops: List<V3RouteWaypoint>.from(stops),
        etaByWaypointId: etaByWaypointId,
      );
    } catch (e) {
      debugPrint('[OSRM/route] ❌ exception: $e');
      return null;
    }
  }

  Future<List<V3RouteWaypoint>> _optimizeRoute(
    List<V3RouteWaypoint> chunk, {
    bool lockLastAsDestination = false,
    bool lockFirstAsSource = false,
  }) async {
    if (chunk.length <= 2) return List<V3RouteWaypoint>.from(chunk);

    final solution = await _fetchTripSolution(
      chunk,
      lockFirstAsSource: lockFirstAsSource,
      lockLastAsDestination: lockLastAsDestination,
    );
    if (solution == null) return List<V3RouteWaypoint>.from(chunk);
    return solution.orderedWaypoints;
  }

  Future<({List<V3RouteWaypoint> orderedWaypoints, List<Map<String, dynamic>> legs})?> _fetchTripSolution(
    List<V3RouteWaypoint> chunk, {
    bool lockLastAsDestination = false,
    bool lockFirstAsSource = false,
  }) async {
    if (chunk.length <= 1) {
      return (
        orderedWaypoints: List<V3RouteWaypoint>.from(chunk),
        legs: const <Map<String, dynamic>>[],
      );
    }

    final coords = chunk.map((w) => '${w.coordinate.longitude},${w.coordinate.latitude}').join(';');
    final uri = Uri.parse('$_baseUrl/trip/v1/driving/$coords').replace(
      queryParameters: {
        'source': lockFirstAsSource ? 'first' : 'any',
        if (lockLastAsDestination) 'destination': 'last',
        'roundtrip': 'false',
        'steps': 'false',
        'overview': 'false',
      },
    );

    try {
      final response = await _getWithRetry(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if ((decoded['code']?.toString() ?? '') != 'Ok') return null;

      final rawWaypoints = decoded['waypoints'];
      if (rawWaypoints is! List || rawWaypoints.length != chunk.length) return null;

      final rawTrips = decoded['trips'];
      if (rawTrips is! List || rawTrips.isEmpty || rawTrips.first is! Map<String, dynamic>) return null;
      final trip = rawTrips.first as Map<String, dynamic>;
      final rawLegs = trip['legs'];
      if (rawLegs is! List) return null;

      final indexed = List.generate(chunk.length, (i) {
        final wp = rawWaypoints[i];
        final pos = wp is Map ? (wp['waypoint_index'] as num?)?.toInt() : null;
        return (originalIndex: i, optimizedPosition: pos ?? i);
      });
      indexed.sort((a, b) => a.optimizedPosition.compareTo(b.optimizedPosition));

      final ordered = indexed.map((e) => chunk[e.originalIndex]).toList(growable: false);
      final legs = rawLegs.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList(growable: false);

      return (
        orderedWaypoints: ordered,
        legs: legs,
      );
    } catch (_) {
      return null;
    }
  }

  /// HTTP GET sa jednim retry-em nakon 2s pri mrežnoj grešci.
  Future<http.Response> _getWithRetry(Uri uri) async {
    try {
      return await _client.get(uri).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[OSRM] request failed, retry za 2s: $e');
      await Future<void>.delayed(const Duration(seconds: 2));
      return _client.get(uri).timeout(const Duration(seconds: 12));
    }
  }
}
