import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../utils/v3_geo_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_adresa_service.dart';
import 'v3_osrm_route_service.dart';

class V3AddressCoordinateService {
  V3AddressCoordinateService({http.Client? client}) : _client = client ?? http.Client();

  /// Globalna singleton instanca sa dijeljenim cache-om koordinata.
  /// Koristi se u svim servisima i screenovima umjesto kreiranja novih instanci.
  static final V3AddressCoordinateService instance = V3AddressCoordinateService();

  final http.Client _client;

  // Globalni cache koordinata: adresaId → koordinata, i geocoding query → koordinata.
  // Dijeli se između svih pozivača koji koriste istu instancu.
  final Map<String, V3RouteCoordinate> _cache = <String, V3RouteCoordinate>{};

  Future<V3RouteCoordinate?> resolveCoordinate({
    required String? adresaId,
    required String fallbackQuery,
  }) async {
    final id = (adresaId ?? '').trim();
    if (id.isNotEmpty) {
      final cached = _cache[id];
      if (cached != null) return cached;

      final raw = V3MasterRealtimeManager.instance.adreseCache[id];
      final fromRow = _extractCoordinate(raw);
      if (fromRow != null) {
        _cache[id] = fromRow;
        return fromRow;
      }

      final naziv = V3AdresaService.getAdresaById(id)?.naziv.trim() ?? '';
      final grad = V3AdresaService.getAdresaById(id)?.grad?.trim() ?? '';
      final queryParts = <String>[if (naziv.isNotEmpty) naziv, if (grad.isNotEmpty) grad, 'Srbija'];
      final fallback = queryParts.join(', ');
      final geocoded = await _geocode(fallback.isNotEmpty ? fallback : fallbackQuery);
      if (geocoded != null) {
        _cache[id] = geocoded;
        return geocoded;
      }
    }

    return _geocode(fallbackQuery);
  }

  V3RouteCoordinate? _extractCoordinate(Map<String, dynamic>? row) {
    if (row == null) return null;

    final lat = _parseDouble(
      row['latitude'] ?? row['lat'] ?? row['geo_lat'] ?? row['gps_lat'] ?? row['gpsLat'] ?? row['y'],
    );
    final lng = _parseDouble(
      row['longitude'] ?? row['lng'] ?? row['lon'] ?? row['geo_lng'] ?? row['gps_lng'] ?? row['gpsLng'] ?? row['x'],
    );

    if (lat == null || lng == null) return null;
    return V3RouteCoordinate(latitude: lat, longitude: lng);
  }

  Future<V3RouteCoordinate?> _geocode(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;

    final cached = _cache[normalized];
    if (cached != null) return cached;

    final endpoint = dotenv.maybeGet('GEOCODING_SEARCH_URL')?.trim() ?? 'https://nominatim.openstreetmap.org/search';
    final uri = Uri.parse(endpoint).replace(queryParameters: {
      'q': normalized,
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'rs',
    });

    try {
      final response = await _client.get(uri, headers: {
        'User-Agent': 'gavra-android-osrm/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty || decoded.first is! Map<String, dynamic>) return null;

      final first = decoded.first as Map<String, dynamic>;
      final lat = _parseDouble(first['lat']);
      final lng = _parseDouble(first['lon']);
      if (lat == null || lng == null) return null;

      final coordinate = V3RouteCoordinate(latitude: lat, longitude: lng);
      _cache[normalized] = coordinate;
      return coordinate;
    } catch (_) {
      return null;
    }
  }

  /// Pre-geocodira koordinate za sve poznate gradove u sistemu (BC, VS).
  /// Treba pozvati jednom pri bootstrapu da se izbjegne Nominatim poziv
  /// pri svakom kliku na "Start" ili "Mapa".
  Future<void> warmUpCities() async {
    final grads = ['BC', 'VS'];
    final futures = <Future<void>>[];
    for (final grad in grads) {
      final label = V3GeoUtils.gradLabelForGeocoding(grad);
      final query = '$label, Srbija';
      if (_cache.containsKey(query)) continue;
      futures.add(
        _geocode(query).then((coord) {
          if (coord != null) {
            debugPrint('[V3AddressCoordinateService] warmUp grad=$grad → $coord');
          } else {
            debugPrint('[V3AddressCoordinateService] warmUp grad=$grad → NULL (geocoding failed)');
          }
        }).catchError((Object e) {
          debugPrint('[V3AddressCoordinateService] warmUp grad=$grad error: $e');
        }),
      );
    }
    await Future.wait(futures);
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }
}
