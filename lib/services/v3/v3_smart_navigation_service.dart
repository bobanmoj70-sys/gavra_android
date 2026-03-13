import '../../models/v3_putnik.dart';
import '../../models/v3_zahtev.dart';

class V3NavigationResult {
  final bool success;
  final String message;
  final List<Map<String, dynamic>>? optimizedData;

  V3NavigationResult({required this.success, required this.message, this.optimizedData});

  factory V3NavigationResult.error(String msg) => V3NavigationResult(success: false, message: msg);
}

class V3SmartNavigationService {
  V3SmartNavigationService._();

  /// Optimizacija V3 rute — sortira putnike po gradu i željenom vremenu.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // contains 'putnik' and 'zahtev'
    required String startCity,
  }) async {
    try {
      if (data.isEmpty) {
        return V3NavigationResult.error('Nema putnika za optimizaciju');
      }

      // Filtriramo samo putnike za traženi grad i sortiramo po zeljenoVreme
      final filtered = data.where((item) {
        final V3Zahtev z = item['zahtev'];
        return z.grad.toUpperCase() == startCity.toUpperCase();
      }).toList();

      filtered.sort((a, b) {
        final V3Zahtev za = a['zahtev'];
        final V3Zahtev zb = b['zahtev'];
        return za.zeljenoVreme.compareTo(zb.zeljenoVreme);
      });

      return V3NavigationResult(
        success: true,
        message: 'Ruta optimizovana za ${filtered.length} putnika',
        optimizedData: filtered,
      );
    } catch (e) {
      return V3NavigationResult.error('Greška pri optimizaciji: $e');
    }
  }

  /// Vraća adresu putnika za određeni grad
  static String getAdresaZaGrad(V3Putnik p, String grad) {
    if (grad.toUpperCase() == 'BC') {
      return p.adresaBcNaziv ?? p.adresaBcNaziv2 ?? '';
    }
    return p.adresaVsNaziv ?? p.adresaVsNaziv2 ?? '';
  }
}
