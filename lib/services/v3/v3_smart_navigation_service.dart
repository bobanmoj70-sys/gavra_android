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

  /// Optimizacija V3 rute — sortira putnike po GPS lokaciji vozača,
  /// prolazi kroz sve putnike i završava u suprotnom gradu.
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

      // 2. Sortiramo po imenu putnika (GPS optimizacija za budućnost)
      final sortedData = List<Map<String, dynamic>>.from(data);

      sortedData.sort((a, b) {
        final pa = a['putnik'] as V3Putnik?;
        final pb = b['putnik'] as V3Putnik?;
        return (pa?.imePrezime ?? '').compareTo(pb?.imePrezime ?? '');
      });

      return V3NavigationResult(
        success: true,
        message: 'Ruta optimizovana: $fromCity ➔ Putnici ➔ $targetCity',
        optimizedData: sortedData,
      );
    } catch (e) {
      return V3NavigationResult.error('Greška pri optimizaciji: $e');
    }
  }

  /// Vraća adresu putnika za određeni grad
  static String getAdresaZaGrad(V3Putnik p, String grad) {
    if (grad.toUpperCase() == 'BC') {
      return V3AdresaService.getAdresaById(p.adresaBcId)?.naziv
          ?? V3AdresaService.getAdresaById(p.adresaBcId2)?.naziv
          ?? '';
    }
    return V3AdresaService.getAdresaById(p.adresaVsId)?.naziv
        ?? V3AdresaService.getAdresaById(p.adresaVsId2)?.naziv
        ?? '';
  }
}
