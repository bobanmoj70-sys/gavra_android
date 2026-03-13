import '../../models/v2_putnik.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v2_dan_utils.dart';
import '../v2_smart_navigation_service.dart';

class V3NavigationResult {
  final bool success;
  final String message;
  final List<Map<String, dynamic>>? optimizedData;

  V3NavigationResult({required this.success, required this.message, this.optimizedData});

  factory V3NavigationResult.error(String msg) => V3NavigationResult(success: false, message: msg);
}

class V3SmartNavigationService {
  V3SmartNavigationService._();

  /// Optimizacija V3 rute koristeći postojeći V2 engine
  static Future<V3NavigationResult> optimizeV3Route({
    required List<Map<String, dynamic>> data, // contains 'putnik' and 'zahtev'
    required String startCity,
  }) async {
    try {
      // 1. Mapiraj V3 podloge u V2Putnik format koji navigator razume
      final List<V2Putnik> v2ProxyList = data.map((item) {
        final V3Putnik p = item['putnik'];
        final V3Zahtev z = item['zahtev'];

        return V2Putnik(
          id: p.id,
          ime: p.imePrezime,
          brojTelefona: p.telefon1 ?? p.telefon2,
          grad: z.grad,
          dan: V2DanUtils.danas(),
          polazak: z.zeljenoVreme,
          // Mapiranje adresa na V2 format za geokodiranje
          adresa: p.tipPutnika == 'posiljka'
              ? (p.adresaBcNaziv ?? '')
              : (z.grad == 'BC' ? p.adresaBcNaziv : p.adresaVsNaziv),
          adresaId: z.grad == 'BC' ? p.adresaBcId : p.adresaVsId,
          status: z.status,
          placeno: false, // V3 ima drugaciji sistem, ovde samo proxy
        );
      }).toList();

      // 2. Pozovi provereni V2 optimizator
      final v2Result = await V2SmartNavigationService.optimizeRouteOnly(
        putnici: v2ProxyList,
        startCity: startCity,
      );

      if (!v2Result.success || v2Result.optimizedPutnici == null) {
        return V3NavigationResult.error(v2Result.message);
      }

      // 3. Vrati optimizovanu V3 listu na osnovu V2 rezultata
      final List<Map<String, dynamic>> optimizedV3 = [];
      for (final v2p in v2Result.optimizedPutnici!) {
        final matching = data.firstWhere((item) => (item['putnik'] as V3Putnik).id == v2p.id);
        optimizedV3.add(matching);
      }

      return V3NavigationResult(
        success: true,
        message: 'Ruta optimizovana za ${optimizedV3.length} putnika',
        optimizedData: optimizedV3,
      );
    } catch (e) {
      return V3NavigationResult.error('Greška pri optimizaciji: $e');
    }
  }
}
