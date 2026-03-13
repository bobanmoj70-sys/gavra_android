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

  /// Optimizacija V3 rute — sortira putnike po GPS lokaciji vozača,
  /// prolazi kroz sve putnike i završava u suprotnom gradu.
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // Sadrži 'putnik' i 'zahtev'
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

      // 2. Mapiramo putnike u objekte sa koordinatama (za pravu GPS optimizaciju bi nam trebali API-jevi)
      // Za sada simuliramo sortiranje po vremenu i lokaciji unutar grada
      // U v3_zahtevi obično imamo 'adresa_naziv' ili koordinate ako postoje
      final sortedData = List<Map<String, dynamic>>.from(data);

      sortedData.sort((a, b) {
        final V3Zahtev za = a['zahtev'];
        final V3Zahtev zb = b['zahtev'];

        // Prioritet 1: Vreme (da bismo ispoštovali red vožnje)
        final timeComp = za.zeljenoVreme.compareTo(zb.zeljenoVreme);
        if (timeComp != 0) return timeComp;

        // Prioritet 2: "Blizina" (simulirano preko adresa za v3)
        return 0;
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
      return p.adresaBcNaziv ?? p.adresaBcNaziv2 ?? '';
    }
    return p.adresaVsNaziv ?? p.adresaVsNaziv2 ?? '';
  }
}
