import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class V3GeocodingResult {
  final double lat;
  final double lng;
  final String? label;

  const V3GeocodingResult({
    required this.lat,
    required this.lng,
    this.label,
  });
}

class V3PhotonGeocodingService {
  V3PhotonGeocodingService._();

  static const String _defaultBaseUrl = 'https://photon.komoot.io';

  static String get _baseUrl {
    final fromEnv = dotenv.maybeGet('PHOTON_BASE_URL')?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    return _defaultBaseUrl;
  }

  static Future<V3GeocodingResult?> geocodeAddress({
    required String address,
    String? city,
    String country = 'Serbia',
  }) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) return null;

    final queryParts = <String>[cleanAddress];
    final cityValue = city?.trim();
    if (cityValue != null && cityValue.isNotEmpty) {
      queryParts.add(cityValue);
    }
    queryParts.add(country);

    try {
      final uri = Uri.parse('$_baseUrl/api').replace(queryParameters: {
        'q': queryParts.join(', '),
        'limit': '1',
        'lang': 'sr',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint(
            '[V3PhotonGeocoding] status=${response.statusCode} body=${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'];
      if (features is! List || features.isEmpty) return null;

      final first = features.first;
      if (first is! Map<String, dynamic>) return null;

      final geometry = first['geometry'];
      if (geometry is! Map<String, dynamic>) return null;

      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) return null;

      final lng = (coordinates[0] as num?)?.toDouble();
      final lat = (coordinates[1] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final properties = first['properties'];
      final label = properties is Map<String, dynamic>
          ? properties['name']?.toString()
          : null;

      return V3GeocodingResult(lat: lat, lng: lng, label: label);
    } catch (e) {
      debugPrint('[V3PhotonGeocoding] geocodeAddress error: $e');
      return null;
    }
  }
}
