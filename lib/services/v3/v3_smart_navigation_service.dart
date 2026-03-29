import 'dart:math' as math;

import '../../models/v3_putnik.dart';
import 'v3_adresa_service.dart';
import 'v3_osrm_service.dart';

class V3NavigationResult {
  final bool success;
  final String message;
  final List<Map<String, dynamic>>? optimizedData;
  final Map<String, dynamic>? metadata;

  V3NavigationResult({required this.success, required this.message, this.optimizedData, this.metadata});

  factory V3NavigationResult.error(String msg) => V3NavigationResult(success: false, message: msg);
}

class V3SmartNavigationService {
  V3SmartNavigationService._();

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _haversineKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.pow(math.sin(dLng / 2), 2);

    return earthRadiusKm * 2 * math.asin(math.sqrt(a));
  }

  static String? _resolveAdresaIdForTargetCity({
    required V3Putnik putnik,
    required dynamic entry,
    required String targetCity,
  }) {
    final String? override = entry?.adresaIdOverride as String?;
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }

    final bool koristiSekundarnu = entry?.koristiSekundarnu == true;
    if (targetCity.toUpperCase() == 'BC') {
      return koristiSekundarnu ? (putnik.adresaBcId2 ?? putnik.adresaBcId) : (putnik.adresaBcId ?? putnik.adresaBcId2);
    }

    return koristiSekundarnu ? (putnik.adresaVsId2 ?? putnik.adresaVsId) : (putnik.adresaVsId ?? putnik.adresaVsId2);
  }

  /// Optimizacija V3 rute — sortira putnike po GPS udaljenosti od vozača,
  /// filtrira putnike bez validnih adresa i završava u suprotnom gradu.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // Sadrži 'putnik' i 'entry'
    required String fromCity, // BC ili VS
    double? driverLat,
    double? driverLng,
    bool osrmOnly = false,
  }) async {
    try {
      if (data.isEmpty) {
        return V3NavigationResult.error('Nema putnika za optimizaciju');
      }

      // 1. Odredimo ciljni grad (suprotan od polaznog)
      final targetCity = fromCity.toUpperCase() == 'BC' ? 'VS' : 'BC';

      // 2. Filtriraj putnike sa validnim adresama i postojećim koordinatama
      final candidates = <_V3RouteCandidate>[];
      final skippedData = <Map<String, dynamic>>[];

      for (final item in data) {
        final putnik = item['putnik'] as V3Putnik?;
        if (putnik == null) continue;
        final entry = item['entry'];

        final adresaId = _resolveAdresaIdForTargetCity(
          putnik: putnik,
          entry: entry,
          targetCity: targetCity,
        );

        if (adresaId == null || adresaId.isEmpty) {
          skippedData.add(item);
          continue;
        }

        final adresa = V3AdresaService.getAdresaById(adresaId);
        if (adresa == null) {
          skippedData.add(item);
          continue;
        }

        final lat = adresa.gpsLat;
        final lng = adresa.gpsLng;
        if (lat == null || lng == null) {
          skippedData.add(item);
          continue;
        }

        candidates.add(
          _V3RouteCandidate(
            item: item,
            putnik: putnik,
            lat: lat,
            lng: lng,
          ),
        );
      }

      if (candidates.isEmpty) {
        return V3NavigationResult.error('Nema putnika sa validnim GPS koordinatama za optimizaciju');
      }

      // 3. GPS-bazirana optimizacija ako su prosleđene koordinate vozača
      var usedOsrm = false;
      List<_V3RouteCandidate> orderedCandidates = List<_V3RouteCandidate>.from(candidates);

      if (osrmOnly && (driverLat == null || driverLng == null)) {
        return V3NavigationResult.error('OSRM optimizacija zahteva dostupnu GPS poziciju vozača');
      }

      if (driverLat != null && driverLng != null) {
        final osrmOrder = await V3OsrmService.optimizeStopOrderByDuration(
          originLat: driverLat,
          originLng: driverLng,
          stops: candidates
              .map((candidate) => V3OsrmStop(
                    id: candidate.putnik.id,
                    lat: candidate.lat,
                    lng: candidate.lng,
                  ))
              .toList(),
        );

        if (osrmOrder != null && osrmOrder.length == candidates.length) {
          final byId = <String, _V3RouteCandidate>{
            for (final candidate in candidates) candidate.putnik.id: candidate,
          };

          orderedCandidates = osrmOrder.map((id) => byId[id]).whereType<_V3RouteCandidate>().toList();

          if (orderedCandidates.length == candidates.length) {
            usedOsrm = true;
          } else {
            orderedCandidates = List<_V3RouteCandidate>.from(candidates);
          }
        }

        if (!usedOsrm) {
          if (osrmOnly) {
            return V3NavigationResult.error('OSRM servis trenutno nije vratio validan redosled');
          }
          orderedCandidates.sort((a, b) {
            final distanceA = _haversineKm(
              lat1: driverLat,
              lng1: driverLng,
              lat2: a.lat,
              lng2: a.lng,
            );
            final distanceB = _haversineKm(
              lat1: driverLat,
              lng1: driverLng,
              lat2: b.lat,
              lng2: b.lng,
            );
            return distanceA.compareTo(distanceB);
          });
        }
      } else {
        if (osrmOnly) {
          return V3NavigationResult.error('OSRM optimizacija zahteva aktivan GPS vozača');
        }
        // Fallback: sortiranje po imenu putnika ako nema GPS koordinata
        orderedCandidates.sort((a, b) {
          return a.putnik.imePrezime.compareTo(b.putnik.imePrezime);
        });
      }

      // 4. Kombinuj preskočene (na vrhu) + optimizovane
      final finalData = <Map<String, dynamic>>[
        ...skippedData.map((item) => {
              'putnik': item['putnik'],
              'entry': item['entry'],
              'route_order': null,
            }),
      ];

      for (var index = 0; index < orderedCandidates.length; index++) {
        final candidate = orderedCandidates[index];
        finalData.add({
          'putnik': candidate.item['putnik'],
          'entry': candidate.item['entry'],
          'route_order': index + 1,
        });
      }

      final skippedText = skippedData.isNotEmpty ? ' • preskočeno bez koordinata: ${skippedData.length}' : '';
      final modeText = osrmOnly
          ? 'OSRM optimizovana'
          : (usedOsrm ? 'OSRM optimizovana' : (driverLat != null && driverLng != null ? 'GPS sortirana' : 'Sortirana'));
      final message = '$modeText: $fromCity ➔ ${orderedCandidates.length} putnika ➔ $targetCity$skippedText';

      return V3NavigationResult(
        success: true,
        message: message,
        optimizedData: finalData,
        metadata: {
          'engine': usedOsrm ? 'osrm' : (driverLat != null && driverLng != null ? 'haversine' : 'name_sort'),
          'from_city': fromCity,
          'target_city': targetCity,
          'optimized_count': orderedCandidates.length,
          'skipped_count': skippedData.length,
          'input_count': data.length,
        },
      );
    } catch (e) {
      return V3NavigationResult.error('Greška pri optimizaciji: $e');
    }
  }

  /// Vraća adresu putnika za određeni grad
  static String getAdresaZaGrad(V3Putnik p, String grad) {
    if (grad.toUpperCase() == 'BC') {
      return V3AdresaService.getAdresaById(p.adresaBcId)?.naziv ??
          V3AdresaService.getAdresaById(p.adresaBcId2)?.naziv ??
          '';
    }
    return V3AdresaService.getAdresaById(p.adresaVsId)?.naziv ??
        V3AdresaService.getAdresaById(p.adresaVsId2)?.naziv ??
        '';
  }
}

class _V3RouteCandidate {
  final Map<String, dynamic> item;
  final V3Putnik putnik;
  final double lat;
  final double lng;

  const _V3RouteCandidate({
    required this.item,
    required this.putnik,
    required this.lat,
    required this.lng,
  });
}
