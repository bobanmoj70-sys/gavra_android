import '../../models/v3_adresa.dart';
import '../../models/v3_putnik.dart';
import 'v3_adresa_service.dart';

class V3NavigationResult {
  final bool success;
  final String message;
  final List<Map<String, dynamic>>? optimizedData;

  V3NavigationResult({required this.success, required this.message, this.optimizedData});

  factory V3NavigationResult.error(String msg) => V3NavigationResult(success: false, message: msg);
}

class V3SmartNavigationService {
  V3SmartNavigationService._();

  /// Optimizacija V3 rute — sortira putnike po GPS udaljenosti od vozača,
  /// filtrira putnike bez validnih adresa i završava u suprotnom gradu.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // Sadrži 'putnik' i 'entry'
    required String fromCity, // BC ili VS
    double? driverLat,
    double? driverLng,
  }) async {
    try {
      if (data.isEmpty) {
        return V3NavigationResult.error('Nema putnika za optimizaciju');
      }

      // 1. Odredimo ciljni grad (suprotan od polaznog)
      final targetCity = fromCity.toUpperCase() == 'BC' ? 'VS' : 'BC';

      // 2. Filtriraj putnike sa validnim adresama
      final validData = <Map<String, dynamic>>[];
      final skippedData = <Map<String, dynamic>>[];

      for (final item in data) {
        final putnik = item['putnik'] as V3Putnik?;
        if (putnik == null) continue;

        // Dobij adresu za ciljni grad
        final adresaId =
            targetCity == 'BC' ? (putnik.adresaBcId ?? putnik.adresaBcId2) : (putnik.adresaVsId ?? putnik.adresaVsId2);

        final adresa = V3AdresaService.getAdresaById(adresaId);

        if (adresa != null && adresa.hasValidCoordinates) {
          validData.add(item);
        } else {
          skippedData.add(item);
        }
      }

      if (validData.isEmpty) {
        return V3NavigationResult.error('Nema putnika sa validnim adresama za optimizaciju');
      }

      // 3. GPS-bazirana optimizacija ako su prosleđene koordinate vozača
      if (driverLat != null && driverLng != null) {
        // Kreiraj virtuelnu adresu vozača za distance kalkulacije
        final driverLocation = V3Adresa(
          id: 'driver_location',
          naziv: 'Vozač lokacija',
          grad: fromCity,
          gpsLat: driverLat,
          gpsLng: driverLng,
          aktivno: true,
        );

        // Sortiri po udaljenosti od vozača
        validData.sort((a, b) {
          final putnikA = a['putnik'] as V3Putnik;
          final putnikB = b['putnik'] as V3Putnik;

          final adresaIdA = targetCity == 'BC'
              ? (putnikA.adresaBcId ?? putnikA.adresaBcId2)
              : (putnikA.adresaVsId ?? putnikA.adresaVsId2);

          final adresaIdB = targetCity == 'BC'
              ? (putnikB.adresaBcId ?? putnikB.adresaBcId2)
              : (putnikB.adresaVsId ?? putnikB.adresaVsId2);

          final adresaA = V3AdresaService.getAdresaById(adresaIdA);
          final adresaB = V3AdresaService.getAdresaById(adresaIdB);

          if (adresaA == null || adresaB == null) return 0;

          final distanceA = driverLocation.distanceTo(adresaA) ?? double.infinity;
          final distanceB = driverLocation.distanceTo(adresaB) ?? double.infinity;

          return distanceA.compareTo(distanceB);
        });
      } else {
        // Fallback: sortiranje po imenu putnika ako nema GPS koordinata
        validData.sort((a, b) {
          final pa = a['putnik'] as V3Putnik?;
          final pb = b['putnik'] as V3Putnik?;
          return (pa?.imePrezime ?? '').compareTo(pb?.imePrezime ?? '');
        });
      }

      // 4. Kombinuj preskočene (na vrhu) + optimizovane
      final finalData = [...skippedData, ...validData];

      final message = driverLat != null && driverLng != null
          ? 'Ruta GPS optimizovana: $fromCity ➔ ${validData.length} putnika ➔ $targetCity'
          : 'Ruta sortirana: $fromCity ➔ ${validData.length} putnika ➔ $targetCity';

      return V3NavigationResult(
        success: true,
        message: message,
        optimizedData: finalData,
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
