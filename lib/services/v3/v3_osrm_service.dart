import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class V3OsrmStop {
  final String id;
  final double lat;
  final double lng;

  const V3OsrmStop({
    required this.id,
    required this.lat,
    required this.lng,
  });
}

class V3OsrmService {
  V3OsrmService._();

  static const String _defaultBaseUrl = 'https://router.project-osrm.org';

  static String get _baseUrl {
    final fromEnv = dotenv.maybeGet('OSRM_BASE_URL')?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    return _defaultBaseUrl;
  }

  static Future<List<String>?> optimizeStopOrderByDuration({
    required double originLat,
    required double originLng,
    required List<V3OsrmStop> stops,
    double? destinationLat,
    double? destinationLng,
  }) async {
    if (stops.isEmpty) return const <String>[];

    try {
      final hasDestination = destinationLat != null && destinationLng != null;
      final allCoords = <String>[
        '$originLng,$originLat',
        ...stops.map((s) => '${s.lng},${s.lat}'),
        if (hasDestination) '$destinationLng,$destinationLat',
      ];

      final tripUri = Uri.parse(
        '$_baseUrl/trip/v1/driving/${allCoords.join(';')}?source=first${hasDestination ? '&destination=last' : ''}&roundtrip=false&overview=false&steps=false',
      );

      final tripResponse = await http.get(tripUri).timeout(const Duration(seconds: 8));
      if (tripResponse.statusCode != 200) {
        debugPrint('[V3OsrmService] trip status=${tripResponse.statusCode} body=${tripResponse.body}');
        return null;
      }

      final tripDecoded = jsonDecode(tripResponse.body) as Map<String, dynamic>;
      if (tripDecoded['code'] != 'Ok') {
        debugPrint('[V3OsrmService] trip code=${tripDecoded['code']}');
        return null;
      }

      final waypointsRaw = tripDecoded['waypoints'];
      if (waypointsRaw is! List || waypointsRaw.length != allCoords.length) {
        debugPrint('[V3OsrmService] trip waypoints invalid');
        return null;
      }

      final ordered = <({int waypointIndex, String stopId})>[];

      for (var inputIndex = 1; inputIndex <= stops.length; inputIndex++) {
        final wp = waypointsRaw[inputIndex];
        if (wp is! Map<String, dynamic>) continue;
        final wpIndex = (wp['waypoint_index'] as num?)?.toInt();
        if (wpIndex == null) continue;
        ordered.add((waypointIndex: wpIndex, stopId: stops[inputIndex - 1].id));
      }

      if (ordered.length != stops.length) {
        debugPrint('[V3OsrmService] trip ordered stops incomplete');
        return null;
      }

      ordered.sort((a, b) => a.waypointIndex.compareTo(b.waypointIndex));
      return ordered.map((e) => e.stopId).toList();
    } catch (e) {
      debugPrint('[V3OsrmService] optimizeStopOrderByDuration error: $e');
      return null;
    }
  }
}
