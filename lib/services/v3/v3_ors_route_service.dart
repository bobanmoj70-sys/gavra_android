import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'v3_route_models.dart';

class V3OrsRouteService {
  V3OrsRouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _apiKey {
    return dotenv.maybeGet('ORS_API_KEY')?.trim() ?? '';
  }

  /// Prima vozača i listu stanica. Vraća indeks originalnih stanica (od 0 do n-1)
  /// optimizovanim redosledom koristeći ORS Optimization API.
  Future<List<int>?> optimizeWaypoints({
    required V3RouteCoordinate driverLocation,
    required List<V3RouteWaypoint> waypoints,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      debugPrint('[V3OrsRouteService] Greška: ORS_API_KEY nije setovan u .env fajlu.');
      return null; // Očekujemo null da UI prikaže upozorenje
    }

    if (waypoints.isEmpty) return [];
    if (waypoints.length == 1) return [0];

    // Formiranje request body-ja za VROOM (ORS Optimization API)
    // format: https://api.openrouteservice.org/optimization

    final vehicle = {
      'id': 1,
      'profile': 'driving-car',
      'start': [driverLocation.longitude, driverLocation.latitude],
    };

    final jobs = <Map<String, dynamic>>[];
    for (var i = 0; i < waypoints.length; i++) {
      jobs.add({
        'id': i, // koristi index kao ID za lakše mapiranje kasnije
        'location': [waypoints[i].coordinate.longitude, waypoints[i].coordinate.latitude],
      });
    }

    final body = {
      'vehicles': [vehicle],
      'jobs': jobs,
    };

    try {
      final response = await _client
          .post(
            Uri.parse('https://api.openrouteservice.org/optimization'),
            headers: {
              'Authorization': apiKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Parsiranje rezultata
        final routes = data['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) return null;

        final steps = routes.first['steps'] as List<dynamic>?;
        if (steps == null) return null;

        final optimizedIndices = <int>[];
        for (var step in steps) {
          if (step['type'] == 'job') {
            final jobId = step['job'] ?? step['id'];
            if (jobId != null) {
              optimizedIndices.add(jobId as int);
            }
          }
        }

        return optimizedIndices;
      } else {
        debugPrint('[V3OrsRouteService] Greška od ORS servera: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[V3OrsRouteService] Izuzetak pri optimizaciji: $e');
      return null;
    }
  }
}
