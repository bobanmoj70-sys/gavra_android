import 'dart:convert';

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
  }) async {
    if (input.length <= 1) return List<V3RouteWaypoint>.from(input);
    if (fixedDestination != null) {
      final withDestination = <V3RouteWaypoint>[...input, fixedDestination];
      final optimized = await _optimizeRoute(withDestination, lockLastAsDestination: true);
      return optimized.where((item) => item.id != fixedDestination.id).toList(growable: false);
    }
    return _optimizeRoute(input);
  }

  Future<List<V3RouteWaypoint>> _optimizeRoute(
    List<V3RouteWaypoint> chunk, {
    bool lockLastAsDestination = false,
    bool lockFirstAsSource = false,
  }) async {
    if (chunk.length <= 2) return List<V3RouteWaypoint>.from(chunk);

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
    // ignore: avoid_print
    print('[OSRM] request URL: $uri');

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      // ignore: avoid_print
      print('[OSRM] statusCode=${response.statusCode} bodyLength=${response.body.length}');
      // ignore: avoid_print
      print('[OSRM] body=${response.body}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return List<V3RouteWaypoint>.from(chunk);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return List<V3RouteWaypoint>.from(chunk);
      if ((decoded['code']?.toString() ?? '') != 'Ok') return List<V3RouteWaypoint>.from(chunk);

      final rawWaypoints = decoded['waypoints'];
      if (rawWaypoints is! List || rawWaypoints.length != chunk.length) {
        return List<V3RouteWaypoint>.from(chunk);
      }

      // rawWaypoints[i].waypoint_index = optimized position of original input[i]
      final indexed = List.generate(chunk.length, (i) {
        final wp = rawWaypoints[i];
        final pos = wp is Map ? (wp['waypoint_index'] as num?)?.toInt() : null;
        return (originalIndex: i, optimizedPosition: pos ?? i);
      });
      indexed.sort((a, b) => a.optimizedPosition.compareTo(b.optimizedPosition));

      return indexed.map((e) => chunk[e.originalIndex]).toList(growable: false);
    } catch (e, st) {
      // ignore: avoid_print
      print('[OSRM] ERROR: $e\n$st');
      return List<V3RouteWaypoint>.from(chunk);
    }
  }
}
