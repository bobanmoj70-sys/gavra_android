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

  /// Optimizacija V3 rute preko OSRM-a.
  ///
  /// Očekuje da ulazni `data` već sadrži pripremljen `stop` (`V3OsrmStop`) po stavci.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // Sadrži 'putnik', 'entry' i 'stop'
    required String fromCity, // BC ili VS
    required double driverLat,
    required double driverLng,
  }) async {
    try {
      if (data.isEmpty) {
        return V3NavigationResult.error('Nema putnika za ETA obradu');
      }

      // 1. Odredimo ciljni grad (suprotan od polaznog)
      final targetCity = fromCity.toUpperCase() == 'BC' ? 'VS' : 'BC';

      // 2. Uzimamo unapred pripremljene stopove (fiksne koordinate)
      final candidates = <_V3RouteCandidate>[];
      for (final item in data) {
        final stop = item['stop'] as V3OsrmStop?;
        if (stop == null) continue;
        candidates.add(
          _V3RouteCandidate(
            item: item,
            stop: stop,
          ),
        );
      }

      if (candidates.isEmpty) {
        return V3NavigationResult.error('Nema putnika sa validnim fiksnim koordinatama za ETA obradu');
      }

      final osrmOrder = await V3OsrmService.optimizeStopOrderByDuration(
        originLat: driverLat,
        originLng: driverLng,
        stops: candidates
            .map((candidate) => V3OsrmStop(
                  id: candidate.stop.id,
                  lat: candidate.stop.lat,
                  lng: candidate.stop.lng,
                ))
            .toList(),
        destinationLat: _cityEndpoints[targetCity]?.lat,
        destinationLng: _cityEndpoints[targetCity]?.lng,
      );

      if (osrmOrder == null || osrmOrder.length != candidates.length) {
        return V3NavigationResult.error('OSRM servis trenutno nije vratio validan redosled');
      }

      final byId = <String, _V3RouteCandidate>{
        for (final candidate in candidates) candidate.stop.id: candidate,
      };

      final orderedCandidates = osrmOrder.map((id) => byId[id]).whereType<_V3RouteCandidate>().toList();

      if (orderedCandidates.length != candidates.length) {
        return V3NavigationResult.error('OSRM redosled nije kompletan');
      }

      final finalData = <Map<String, dynamic>>[];

      for (final candidate in orderedCandidates) {
        finalData.add({
          'putnik': candidate.item['putnik'],
          'entry': candidate.item['entry'],
        });
      }

      final message = 'OSRM redosled osvežen: $fromCity ➔ ${orderedCandidates.length} putnika ➔ $targetCity';

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
      return V3NavigationResult.error('Greška pri ETA obradi: $e');
    }
  }
}

class _V3RouteCandidate {
  final Map<String, dynamic> item;
  final V3OsrmStop stop;

  const _V3RouteCandidate({
    required this.item,
    required this.stop,
  });
}
