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

  static const Map<String, ({double lat, double lng})> _cityEndpoints = {
    'BC': (lat: 44.8973, lng: 21.4177),
    'VS': (lat: 45.1190, lng: 21.3030),
  };

  // Vraća adresaId za pickup — uvek u gradu polaska (fromCity), ne odredišta.
  static String? _resolveAdresaIdForPickup({
    required V3Putnik putnik,
    required dynamic entry,
    required String fromCity,
  }) {
    final String? override = entry?.adresaIdOverride as String?;
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }

    if (fromCity.toUpperCase() == 'BC') {
      return putnik.adresaBcId;
    }

    return putnik.adresaVsId;
  }

  /// Optimizacija V3 rute preko OSRM-a.
  ///
  /// Filtrira putnike bez validnih adresa/koordinata i vraća grešku ako
  /// nema dostupne GPS pozicije vozača ili OSRM ne vrati validan redosled.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // Sadrži 'putnik' i 'entry'
    required String fromCity, // BC ili VS
    required double driverLat,
    required double driverLng,
  }) async {
    try {
      if (data.isEmpty) {
        return V3NavigationResult.error('Nema putnika za optimizaciju');
      }

      // 1. Odredimo ciljni grad (suprotan od polaznog)
      final targetCity = fromCity.toUpperCase() == 'BC' ? 'VS' : 'BC';

      // 2. Validiraj putnike sa fiksnim adresama i koordinatama
      final candidates = <_V3RouteCandidate>[];

      for (final item in data) {
        final putnik = item['putnik'] as V3Putnik?;
        if (putnik == null) continue;
        final entry = item['entry'];

        final adresaId = _resolveAdresaIdForPickup(
          putnik: putnik,
          entry: entry,
          fromCity: fromCity,
        );

        if (adresaId == null || adresaId.isEmpty) {
          return V3NavigationResult.error('Putnik ${putnik.imePrezime} nema fiksnu adresu za grad $fromCity');
        }

        final adresa = V3AdresaService.getAdresaById(adresaId);
        if (adresa == null) {
          return V3NavigationResult.error('Adresa $adresaId nije pronađena za putnika ${putnik.imePrezime}');
        }

        final lat = adresa.gpsLat;
        final lng = adresa.gpsLng;
        if (lat == null || lng == null) {
          return V3NavigationResult.error('Adresa ${adresa.naziv} nema fiksne GPS koordinate');
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
        destinationLat: _cityEndpoints[targetCity]?.lat,
        destinationLng: _cityEndpoints[targetCity]?.lng,
      );

      if (osrmOrder == null || osrmOrder.length != candidates.length) {
        return V3NavigationResult.error('OSRM servis trenutno nije vratio validan redosled');
      }

      final byId = <String, _V3RouteCandidate>{
        for (final candidate in candidates) candidate.putnik.id: candidate,
      };

      final orderedCandidates = osrmOrder.map((id) => byId[id]).whereType<_V3RouteCandidate>().toList();

      if (orderedCandidates.length != candidates.length) {
        return V3NavigationResult.error('OSRM redosled nije kompletan');
      }

      final finalData = <Map<String, dynamic>>[];

      for (var index = 0; index < orderedCandidates.length; index++) {
        final candidate = orderedCandidates[index];
        finalData.add({
          'putnik': candidate.item['putnik'],
          'entry': candidate.item['entry'],
          'route_order': index + 1,
        });
      }

      final message = 'OSRM optimizovana: $fromCity ➔ ${orderedCandidates.length} putnika ➔ $targetCity';

      return V3NavigationResult(
        success: true,
        message: message,
        optimizedData: finalData,
        metadata: {
          'engine': 'osrm',
          'from_city': fromCity,
          'target_city': targetCity,
          'optimized_count': orderedCandidates.length,
          'skipped_count': 0,
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
      return V3AdresaService.getAdresaById(p.adresaBcId)?.naziv ?? '';
    }
    return V3AdresaService.getAdresaById(p.adresaVsId)?.naziv ?? '';
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
