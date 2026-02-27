/// UNIFIED GEOCODING SERVICE
/// Centralizovani servis za geocoding sa:
/// - Paralelnim fetch-om koordinata
/// - Prioritetnim redosledom (Baza ? Memory ? Disk ? API)
/// - Progress callback za UI
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../config/v2_route_config.dart';
import '../models/v2_putnik.dart';
import 'v2_adresa_supabase_service.dart';
import 'v2_geocoding_service.dart';

/// Callback za pracenje progresa geocodinga
typedef GeocodingProgressCallback = void Function(
  int completed,
  int total,
  String currentAddress,
);

/// Rezultat geocodinga za jednog putnika
class GeocodingResult {
  const GeocodingResult({
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
}

/// UNIFIED GEOCODING SERVICE
class UnifiedGeocodingService {
  UnifiedGeocodingService._();

  // -----------------------------------------------------------------------
  // GLAVNA FUNKCIJA - Dobij koordinate za vi�e putnika (PARALELNO)
  // -----------------------------------------------------------------------

  /// Dobij koordinate za listu putnika sa paralelnim fetch-om
  /// Vraca mapu V2Putnik -> Position samo za uspe�no geocodirane
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

    final List<Future<GeocodingResult> Function()> tasks = [];
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
      delay: RouteConfig.nominatimBatchDelay,
    );

    for (final result in results) {
      if (result.success) {
        coordinates[result.putnik] = result.position!;
      }
    }

    return coordinates;
  }

  /// Dobij koordinate za jednog putnika
  static Future<GeocodingResult> _getCoordinatesForPutnik(
    V2Putnik putnik,
    bool saveToDatabase,
  ) async {
    try {
      Position? position;
      String? source;
      String? realAddressName;

      // PRIORITET 1: Koordinate iz baze (preko adresaId)
      if (putnik.adresaId != null && putnik.adresaId!.isNotEmpty) {
        final adresaFromDb = await V2AdresaSupabaseService.getAdresaByUuid(
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

      // PRIORITET 3: Nominatim API
      if (position == null) {
        final addressToGeocode = realAddressName ?? putnik.adresa!;
        final coordsString = await GeocodingService.getKoordinateZaAdresu(
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

      return GeocodingResult(
        putnik: putnik,
        position: position,
        source: source,
        error: position == null ? 'Koordinate nisu pronadene' : null,
      );
    } catch (e) {
      return GeocodingResult(
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

  /// Kreiraj Position objekat
  static Position _createPosition(double lat, double lng) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
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
          lat: lat,
          lng: lng,
        );
      }
    } catch (e) {
      // ?? Ignore
    }
  }

  /// IzVrsava taskove sekvencijalno sa pauzom izmedu zahteva
  static Future<List<GeocodingResult>> _executeWithRateLimit(
    List<Future<GeocodingResult> Function()> tasks, {
    required Duration delay,
  }) async {
    // ? OPTIMIZACIJA 1: Parallelizuj geocodiranje sa rate limiting
    // Umesto sekvencijalnog await (50-100 sek za 50 putnika),
    // paralelizuj sa delayom izmedu nominatim API poziva

    if (tasks.isEmpty) return [];

    // Podeli zadatke na grupe da izbegnemo rate limit
    const maxConcurrent = 5; // Max istovremenih geocoding poziva
    final List<GeocodingResult> allResults = [];

    for (int batchStart = 0; batchStart < tasks.length; batchStart += maxConcurrent) {
      final batchEnd = (batchStart + maxConcurrent).clamp(0, tasks.length);
      final batch = tasks.sublist(batchStart, batchEnd);

      // ? Paralelizuj sve u batch-u istovremeno
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

  // -----------------------------------------------------------------------
  // STATISTIKE I DEBUG
}
