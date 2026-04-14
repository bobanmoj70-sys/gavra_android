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

      final tripResponse =
          await http.get(tripUri).timeout(const Duration(seconds: 8));
      if (tripResponse.statusCode != 200) {
        debugPrint(
            '[V3OsrmService] trip status=${tripResponse.statusCode} body=${tripResponse.body}');
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

  /// Računa trajanje rute kroz niz waypointa (min. 2).
  /// Waypoints su u redosledu: [vozač, putnik1, putnik2, ..., ovaj_putnik].
  /// Vraća ukupne minute od prve do poslednje tačke.
  static Future<int?> getEtaMinutes({
    required List<({double lat, double lng})> waypoints,
  }) async {
    if (waypoints.length < 2) return null;
    try {
      final coords = waypoints.map((w) => '${w.lng},${w.lat}').join(';');
      final uri = Uri.parse(
        '$_baseUrl/route/v1/driving/$coords?overview=false&steps=false',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('[V3OsrmService] eta status=${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['code'] != 'Ok') {
        debugPrint('[V3OsrmService] eta code=${decoded['code']}');
        return null;
      }

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;

      final firstRoute = routes.first;
      if (firstRoute is! Map<String, dynamic>) return null;

      final durationSeconds = (firstRoute['duration'] as num?)?.toDouble();
      if (durationSeconds == null ||
          !durationSeconds.isFinite ||
          durationSeconds <= 0) return null;

      final minutes = (durationSeconds / 60.0).ceil();
      return minutes < 1 ? 1 : minutes;
    } catch (e) {
      debugPrint('[V3OsrmService] getEtaMinutes error: $e');
      return null;
    }
  }
}
