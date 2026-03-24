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
  }) async {
    if (stops.isEmpty) return const <String>[];

    try {
      final allCoords = <String>[
        '$originLng,$originLat',
        ...stops.map((s) => '${s.lng},${s.lat}'),
      ];

      final uri = Uri.parse(
        '$_baseUrl/table/v1/driving/${allCoords.join(';')}?annotations=duration',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('[V3OsrmService] table status=${response.statusCode} body=${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['code'] != 'Ok') {
        debugPrint('[V3OsrmService] table code=${decoded['code']}');
        return null;
      }

      final durationsRaw = decoded['durations'];
      if (durationsRaw is! List || durationsRaw.isEmpty) return null;

      final matrix = durationsRaw
          .whereType<List>()
          .map((row) => row.map<double?>((value) => (value as num?)?.toDouble()).toList())
          .toList();

      if (matrix.length < 2) return null;

      final unvisited = <int>{for (int i = 1; i <= stops.length; i++) i};
      final orderedStopIds = <String>[];
      var currentIndex = 0;

      while (unvisited.isNotEmpty) {
        int? bestIndex;
        double? bestCost;

        for (final candidate in unvisited) {
          final row = currentIndex < matrix.length ? matrix[currentIndex] : const <double?>[];
          final cost = candidate < row.length ? row[candidate] : null;
          if (cost == null || cost.isNaN || cost.isInfinite) continue;
          if (bestCost == null || cost < bestCost) {
            bestCost = cost;
            bestIndex = candidate;
          }
        }

        bestIndex ??= unvisited.first;
        orderedStopIds.add(stops[bestIndex - 1].id);
        unvisited.remove(bestIndex);
        currentIndex = bestIndex;
      }

      return orderedStopIds;
    } catch (e) {
      debugPrint('[V3OsrmService] optimizeStopOrderByDuration error: $e');
      return null;
    }
  }
}
