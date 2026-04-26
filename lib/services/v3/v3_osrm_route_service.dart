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

  Future<List<V3RouteWaypoint>> optimizeWaypoints(List<V3RouteWaypoint> input) async {
    if (input.length <= 1) return List<V3RouteWaypoint>.from(input);
    return _optimizeRoute(input);
  }

  Future<List<V3RouteWaypoint>> _optimizeRoute(List<V3RouteWaypoint> chunk) async {
    if (chunk.length <= 2) return List<V3RouteWaypoint>.from(chunk);

    final coords = chunk.map((w) => '${w.coordinate.longitude},${w.coordinate.latitude}').join(';');
    final uri = Uri.parse('$_baseUrl/trip/v1/driving/$coords').replace(
      queryParameters: {
        'source': 'first',
        'roundtrip': 'false',
        'steps': 'false',
        'overview': 'false',
      },
    );

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return List<V3RouteWaypoint>.from(chunk);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return List<V3RouteWaypoint>.from(chunk);
      if ((decoded['code']?.toString() ?? '') != 'Ok') return List<V3RouteWaypoint>.from(chunk);

      final trips = decoded['trips'];
      if (trips is! List || trips.isEmpty || trips.first is! Map<String, dynamic>) {
        return List<V3RouteWaypoint>.from(chunk);
      }

      final rawOrder = (trips.first as Map<String, dynamic>)['waypoint_order'];
      if (rawOrder is! List) return List<V3RouteWaypoint>.from(chunk);

      final parsedOrder = rawOrder.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
      if (parsedOrder.isEmpty) return List<V3RouteWaypoint>.from(chunk);

      final normalizedOrder = _normalizeOrder(parsedOrder, chunk.length);
      if (normalizedOrder.length != chunk.length) return List<V3RouteWaypoint>.from(chunk);

      return normalizedOrder.map((i) => chunk[i]).toList(growable: false);
    } catch (_) {
      return List<V3RouteWaypoint>.from(chunk);
    }
  }

  List<int> _normalizeOrder(List<int> raw, int length) {
    final unique = <int>[];
    final seen = <int>{};

    for (final value in raw) {
      if (value < 0 || value >= length) continue;
      if (seen.add(value)) unique.add(value);
    }

    if (unique.length == length - 1 && !seen.contains(0)) {
      unique.insert(0, 0);
      seen.add(0);
    }

    for (var index = 0; index < length; index++) {
      if (seen.add(index)) unique.add(index);
    }

    return unique;
  }
}
