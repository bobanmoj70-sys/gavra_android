/// UNIFIED GEOCODING SERVICE
/// Koordinate direktno iz adreseCache (rm) — bez API poziva za BC/VS putnike.
/// Nominatim/Photon fallback ostaje samo za dnevne putnike bez adresaId.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/v2_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Callback za pracenje progresa geocodinga
typedef GeocodingProgressCallback = void Function(
  int completed,
  int total,
  String currentAddress,
);

/// UNIFIED GEOCODING SERVICE
class V2UnifiedGeocodingService {
  V2UnifiedGeocodingService._();

  // -----------------------------------------------------------------------
  // GLAVNA FUNKCIJA
  // Vraca Map<String, Position> keyed by adresaId (ili putnik.id ako nema adresaId)
  // -----------------------------------------------------------------------

  /// Dobij koordinate za listu putnika.
  /// PRIORITET 1: direktno iz rm.adreseCache (sinhron, nema API-ja).
  /// PRIORITET 2: Photon/Nominatim — samo za dnevne putnike bez adresaId.
  static Future<Map<String, Position>> getCoordinatesForPutnici(
    List<V2Putnik> putnici, {
    GeocodingProgressCallback? onProgress,
    bool saveToDatabase = true,
  }) async {
    final Map<String, Position> coordinates = {};
    final rm = V2MasterRealtimeManager.instance;

    final List<Future<void>> apiFutures = [];
    int completed = 0;
    final int total = putnici.length;

    for (final putnik in putnici) {
      final key = putnik.adresaId ?? putnik.id?.toString() ?? '';
      if (key.isEmpty) continue;

      // PRIORITET 1: iz cache-a — sinhron, bez await
      if (putnik.adresaId != null && putnik.adresaId!.isNotEmpty) {
        final koord = rm.getAdresaKoordinate(putnik.adresaId!);
        if (koord != null) {
          coordinates[key] = _createPosition(koord['lat']!, koord['lng']!);
          onProgress?.call(++completed, total, putnik.adresa ?? putnik.ime);
          continue;
        }
      }

      // PRIORITET 2: API fallback — poziva se ako adresaId nema koordinate u cache-u, ili ako putnik nema adresaId
      final adresa = putnik.adresa ?? '';
      if (adresa.isEmpty || adresa == putnik.grad) continue;

      apiFutures.add(() async {
        final coordsString = await _getKoordinateZaAdresu(putnik.grad, adresa);
        if (coordsString != null) {
          final pos = _parsePosition(coordsString);
          if (pos != null) {
            coordinates[key] = pos;
            if (saveToDatabase && putnik.adresaId != null) {
              _saveKoordinateUCache(putnik.adresaId!, pos.latitude, pos.longitude);
            }
          }
        }
        onProgress?.call(++completed, total, adresa);
      }());
    }

    if (apiFutures.isNotEmpty) {
      await Future.wait(apiFutures);
    }

    return coordinates;
  }

  // -----------------------------------------------------------------------
  // HELPER FUNKCIJE
  // -----------------------------------------------------------------------

  /// Ažuriraj koordinate u lokalnom cache-u (bez DB upita)
  static void _saveKoordinateUCache(String adresaId, double lat, double lng) {
    final rm = V2MasterRealtimeManager.instance;
    final row = rm.adreseCache[adresaId];
    if (row != null) {
      rm.adreseCache[adresaId] = {...row, 'gps_lat': lat.toString(), 'gps_lng': lng.toString()};
    }
  }

  /// Parsiraj koordinate iz stringa "lat,lng"
  static Position? _parsePosition(String coords) {
    try {
      final parts = coords.split(',');
      if (parts.length != 2) return null;
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) return null;
      return _createPosition(lat, lng);
    } catch (e) {
      return null;
    }
  }

  static Position _createPosition(double lat, double lng) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API GEOCODING — Photon primarno, Nominatim fallback
  // ──────────────────────────────────────────────────────────────────────────

  static Future<String?> _getKoordinateZaAdresu(String grad, String adresa) async {
    String? coords = await _fetchFromPhoton(grad, adresa);
    coords ??= await _fetchFromNominatim(grad, adresa);
    return coords;
  }

  static Future<String?> _fetchFromNominatim(String grad, String adresa) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final query = Uri.encodeQueryComponent('$adresa, $grad, Serbia');
        final url = 'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1&countrycodes=rs';
        final response = await http.get(Uri.parse(url),
            headers: {'User-Agent': 'GavraAndroidApp/1.0 (transport app)'}).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final results = json.decode(response.body) as List<dynamic>;
          if (results.isNotEmpty) {
            final r = results[0] as Map<String, dynamic>;
            final lat = r['lat'] as String?;
            final lon = r['lon'] as String?;
            if (lat != null && lon != null) return '$lat,$lon';
          }
        }
      } catch (e) {
        if (attempt < 3) await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }

  static Future<String?> _fetchFromPhoton(String grad, String adresa) async {
    try {
      final query = Uri.encodeQueryComponent('$adresa, $grad');
      const bbox = '&bbox=18.82,41.85,23.01,46.19';
      final url = 'https://photon.komoot.io/api/?q=$query&limit=1$bbox';
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'GavraAndroid/1.0'}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>?;
        if (features != null && features.isNotEmpty) {
          final geometry = (features[0] as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List<dynamic>?;
          if (coords != null && coords.length >= 2) {
            final lon = (coords[0] as num?)?.toDouble();
            final lat = (coords[1] as num?)?.toDouble();
            if (lat != null && lon != null) return '$lat,$lon';
          }
        }
      }
    } catch (e) {
      debugPrint('[V2UnifiedGeocodingService] Photon greška: $e');
    }
    return null;
  }
}
