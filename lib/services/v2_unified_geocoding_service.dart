/// UNIFIED GEOCODING SERVICE
/// Centralizovani servis za geocoding sa:
/// - Paralelnim fetch-om koordinata
/// - Prioritetnim redosledom (Baza -> Nominatim API)
/// - Progress callback za UI
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/v2_route_config.dart';
import '../models/v2_putnik.dart';
import 'v2_adresa_supabase_service.dart';

/// Callback za pracenje progresa geocodinga
typedef GeocodingProgressCallback = void Function(
  int completed,
  int total,
  String currentAddress,
);

/// Rezultat geocodinga za jednog putnika
class V2GeocodingResult {
  const V2GeocodingResult({
    required this.putnik,
    this.position,
    this.source,
    this.error,
  });

  final V2Putnik putnik;
  final Position? position;
  final String? source; // 'database', 'nominatim'
  final String? error;

  bool get success => position != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2GeocodingResult &&
          runtimeType == other.runtimeType &&
          putnik == other.putnik &&
          source == other.source;

  @override
  int get hashCode => Object.hash(putnik, source);
}

/// UNIFIED GEOCODING SERVICE
class V2UnifiedGeocodingService {
  V2UnifiedGeocodingService._();

  // -----------------------------------------------------------------------
  // GLAVNA FUNKCIJA - Dobij koordinate za više putnika (PARALELNO)
  // -----------------------------------------------------------------------

  /// Dobij koordinate za listu putnika sa paralelnim fetch-om
  /// Vraca mapu V2Putnik -> Position samo za uspešno geocodirane
  static Future<Map<V2Putnik, Position>> getCoordinatesForPutnici(
    List<V2Putnik> putnici, {
    GeocodingProgressCallback? onProgress,
    bool saveToDatabase = true,
  }) async {
    final Map<V2Putnik, Position> coordinates = {};

    final putniciSaAdresama = putnici.where((p) => _hasValidAddress(p)).toList();

    if (putniciSaAdresama.isEmpty) {
      return coordinates;
    }

    final List<Future<V2GeocodingResult> Function()> tasks = [];
    int completed = 0;
    final int total = putniciSaAdresama.length;

    for (final putnik in putniciSaAdresama) {
      tasks.add(() async {
        final result = await _getCoordinatesForPutnik(putnik, saveToDatabase);
        completed++;
        onProgress?.call(completed, total, putnik.adresa ?? putnik.ime);
        return result;
      });
    }

    final results = await _executeWithRateLimit(
      tasks,
      delay: V2RouteConfig.nominatimBatchDelay,
    );

    for (final result in results) {
      if (result.success) {
        coordinates[result.putnik] = result.position!;
      }
    }

    return coordinates;
  }

  /// Dobij koordinate za jednog putnika
  static Future<V2GeocodingResult> _getCoordinatesForPutnik(
    V2Putnik putnik,
    bool saveToDatabase,
  ) async {
    try {
      Position? position;
      String? source;
      String? realAddressName;

      // PRIORITET 1: Koordinate iz baze (preko adresaId)
      if (putnik.adresaId != null && putnik.adresaId!.isNotEmpty) {
        final adresaFromDb = V2AdresaSupabaseService.getAdresaByUuid(
          putnik.adresaId!,
        );
        if (adresaFromDb != null) {
          realAddressName = adresaFromDb.naziv;

          if (adresaFromDb.latitude != null && adresaFromDb.longitude != null) {
            position = _createPosition(
              adresaFromDb.latitude!,
              adresaFromDb.longitude!,
            );
            source = 'database';
          }
        }
      }

      // PRIORITET 2: Nominatim API
      if (position == null) {
        final addressToGeocode = realAddressName ?? putnik.adresa ?? '';
        if (addressToGeocode.isEmpty) {
          return V2GeocodingResult(
            putnik: putnik,
            error: 'Nema adrese za geocodiranje',
          );
        }
        final coordsString = await _getKoordinateZaAdresu(
          putnik.grad,
          addressToGeocode,
        );

        if (coordsString != null) {
          position = _parsePosition(coordsString);
          if (position != null) {
            source = 'nominatim';

            if (saveToDatabase) {
              await _saveCoordinatesToDatabase(
                putnik: putnik,
                lat: position.latitude,
                lng: position.longitude,
              );
            }
          }
        }
      }

      return V2GeocodingResult(
        putnik: putnik,
        position: position,
        source: source,
        error: position == null ? 'Koordinate nisu pronadene' : null,
      );
    } catch (e) {
      return V2GeocodingResult(
        putnik: putnik,
        error: e.toString(),
      );
    }
  }

  // -----------------------------------------------------------------------
  // HELPER FUNKCIJE
  // -----------------------------------------------------------------------

  /// Proveri da li V2Putnik ima validnu adresu
  static bool _hasValidAddress(V2Putnik putnik) {
    // MESECNI PUTNICI: Imaju adresaId koji pokazuje na pravu adresu
    if (putnik.adresaId != null && putnik.adresaId!.isNotEmpty) {
      return true;
    }

    // DNEVNI PUTNICI: Moraju imati adresu koja nije samo grad
    if (putnik.adresa == null || putnik.adresa!.trim().isEmpty) {
      return false;
    }
    if (putnik.adresa!.toLowerCase().trim() == putnik.grad.toLowerCase().trim()) {
      return false;
    }
    return true;
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

  /// Sacuvaj koordinate u bazu
  static Future<void> _saveCoordinatesToDatabase({
    required V2Putnik putnik,
    required double lat,
    required double lng,
  }) async {
    try {
      if (putnik.adresaId != null && putnik.adresaId!.isNotEmpty) {
        await V2AdresaSupabaseService.updateKoordinate(
          putnik.adresaId!,
          lat: lat,
          lng: lng,
        );
      } else if (putnik.adresa != null && putnik.adresa!.isNotEmpty) {
        await V2AdresaSupabaseService.createOrGetAdresa(
          naziv: putnik.adresa!,
          grad: putnik.grad,
        );
      }
    } catch (e) {
      debugPrint('[V2UnifiedGeocodingService] _saveCoordinatesToDatabase greška: $e');
    }
  }

  static Future<List<V2GeocodingResult>> _executeWithRateLimit(
    List<Future<V2GeocodingResult> Function()> tasks, {
    required Duration delay,
  }) async {
    // Paralelizuj geocodiranje sa rate limiting.
    // Podeli zadatke na grupe od max 5 istovremenih poziva da izbegnemo rate limit.

    if (tasks.isEmpty) return [];

    const maxConcurrent = 5;
    final List<V2GeocodingResult> allResults = [];

    for (int batchStart = 0; batchStart < tasks.length; batchStart += maxConcurrent) {
      final batchEnd = (batchStart + maxConcurrent).clamp(0, tasks.length);
      final batch = tasks.sublist(batchStart, batchEnd);

      final batchResults = await Future.wait(
        batch.map((taskFn) => taskFn()),
      );

      allResults.addAll(batchResults);

      // Dodaj delay izmedu batch-eva, ali samo ako ima nominatim poziva
      final hasNominatimInBatch = batchResults.any((r) => r.source == 'nominatim');
      if (hasNominatimInBatch && batchEnd < tasks.length) {
        await Future.delayed(delay);
      }
    }

    return allResults;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GEOCODING IMPLEMENTACIJA (preseljeno iz V2GeocodingService)
  // ──────────────────────────────────────────────────────────────────────────

  static final Map<String, Completer<String?>> _pendingRequests = {};
  static final Set<String> _processingRequests = {};

  /// Dobij koordinate za adresu (Photon primarno, Nominatim fallback)
  static Future<String?> getKoordinateZaAdresu(
    String grad,
    String adresa,
  ) async {
    return _getKoordinateZaAdresu(grad, adresa);
  }

  static Future<String?> _getKoordinateZaAdresu(
    String grad,
    String adresa,
  ) async {
    if (_isCityBlocked(grad)) return null;

    final requestKey = '${grad}_$adresa';

    if (_processingRequests.contains(requestKey)) {
      return await (_pendingRequests[requestKey]?.future ?? Future.value(null));
    }

    final completer = Completer<String?>();
    _pendingRequests[requestKey] = completer;
    _processingRequests.add(requestKey);

    try {
      String? coords = await _fetchFromPhoton(grad, adresa);
      coords ??= await _fetchFromNominatim(grad, adresa);
      _completeGeoRequest(requestKey, coords);
    } catch (e) {
      _completeGeoRequest(requestKey, null);
    }

    return completer.future;
  }

  static void _completeGeoRequest(String requestKey, String? result) {
    final completer = _pendingRequests.remove(requestKey);
    _processingRequests.remove(requestKey);
    completer?.complete(result);
  }

  static Future<String?> _fetchFromNominatim(String grad, String adresa) async {
    const String baseUrl = 'https://nominatim.openstreetmap.org/search';
    const int maxRetries = 3;
    const Duration timeout = Duration(seconds: 10);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final query = '$adresa, $grad, Serbia';
        final encodedQuery = Uri.encodeComponent(query);
        final url = '$baseUrl?q=$encodedQuery&format=json&limit=1&countrycodes=rs';

        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'GavraAndroidApp/1.0 (transport app)'},
        ).timeout(timeout);

        if (response.statusCode == 200) {
          final List<dynamic> results = json.decode(response.body) as List<dynamic>;
          if (results.isNotEmpty) {
            final result = results[0] as Map<String, dynamic>;
            final lat = result['lat'] as String?;
            final lon = result['lon'] as String?;
            if (lat != null && lon != null) return '$lat,$lon';
          }
        }
      } catch (e) {
        if (attempt < maxRetries) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    return null;
  }

  static Future<String?> _fetchFromPhoton(String grad, String adresa) async {
    try {
      final query = '$adresa, $grad';
      final encodedQuery = Uri.encodeComponent(query);
      const String bbox = '&bbox=18.82,41.85,23.01,46.19';
      final url = 'https://photon.komoot.io/api/?q=$encodedQuery&limit=1$bbox';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'GavraAndroid/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>?;
        if (features != null && features.isNotEmpty) {
          final feature = features[0] as Map<String, dynamic>;
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List<dynamic>?;
          if (coordinates != null && coordinates.length >= 2) {
            final lon = coordinates[0];
            final lat = coordinates[1];
            if (lat != null && lon != null) return '$lat,$lon';
          }
        }
      }
    } catch (e) {
      debugPrint('[V2UnifiedGeocodingService] _fetchFromPhoton greška: $e');
    }
    return null;
  }

  static bool _isCityBlocked(String grad) {
    final normalizedGrad = grad.toLowerCase().trim();
    const allowedCities = [
      'vrsac',
      'straza',
      'straža',
      'vojvodinci',
      'potporanj',
      'oresac',
      'orešac',
      'bela crkva',
      'vracev gaj',
      'vraćev gaj',
      'dupljaja',
      'jasenovo',
      'kruscica',
      'kruščica',
      'kusic',
      'kusić',
      'crvena crkva',
    ];
    return !allowedCities.any((allowed) => normalizedGrad.contains(allowed));
  }
}
