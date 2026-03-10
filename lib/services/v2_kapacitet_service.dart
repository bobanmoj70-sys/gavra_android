import 'package:flutter/foundation.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje kapacitetom polazaka.
/// Cache se čita direktno iz V2MasterRealtimeManager — nema vlastitog DB upita.
class V2KapacitetService {
  V2KapacitetService._();

  /// Vremena polazaka za Belu Crkvu (prema navBarType)
  static List<String> get bcVremena => V2RouteConfig.getVremenaByNavType('BC');

  /// Vremena polazaka za Vrsac (prema navBarType)
  static List<String> get vsVremena => V2RouteConfig.getVremenaByNavType('VS');

  /// Dohvati vremena za grad (sezonski)
  static List<String> getVremenaZaGrad(String grad) {
    if (grad == 'BC') return bcVremena;
    if (grad == 'VS') return vsVremena;
    debugPrint('[V2KapacitetService] getVremenaZaGrad: nepoznat grad "$grad"');
    assert(false, 'getVremenaZaGrad: nepoznat grad "$grad"');
    return bcVremena;
  }

  /// Admin: Promeni kapacitet za odredeni polazak (atomski upsert — nema race condition)
  static Future<bool> setKapacitet(String grad, String vreme, int maxMesta) async {
    try {
      final row = await supabase
          .from('v2_kapacitet_polazaka')
          .upsert(
            {'grad': grad, 'vreme': vreme, 'max_mesta': maxMesta, 'aktivan': true},
            onConflict: 'grad,vreme',
          )
          .select()
          .single();
      V2MasterRealtimeManager.instance.v2UpsertToCache('v2_kapacitet_polazaka', row);
      return true;
    } catch (e) {
      debugPrint('[V2KapacitetService] setKapacitet greška: $e');
      return false;
    }
  }

  /// Dohvati kapacitet za sve gradove — iz rm.kapacitetCache (nema DB upita).
  /// Format: {'BC': {'06:00': 8, '07:00': 10, ...}, 'VS': {...}}
  static Map<String, Map<String, int>> getKapacitet() {
    final rm = V2MasterRealtimeManager.instance;
    final result = <String, Map<String, int>>{'BC': {}, 'VS': {}};
    for (final row in rm.kapacitetCache.values) {
      final grad = row['grad'] as String? ?? '';
      final vreme = row['vreme'] as String? ?? '';
      final maxMesta = (row['max_mesta'] as int?) ?? 8;
      if (grad == 'BC' || grad == 'VS') {
        result[grad]![vreme] = maxMesta;
      }
    }
    return result;
  }

  static Stream<Map<String, Map<String, int>>> streamKapacitet() =>
      V2MasterRealtimeManager.instance.v2StreamFromCache(tables: ['v2_kapacitet_polazaka'], build: getKapacitet);

  /// Dohvati kapacitet za grad/vreme (čita iz rm.kapacitetCache — nema DB upita).
  /// Vraca default 8 ako nije dostupno.
  static int getKapacitetSync(String grad, String vreme) {
    final normalizedVreme = V2GradAdresaValidator.normalizeTime(vreme);
    final gradKey = grad == 'BC' ? 'BC' : 'VS';

    final rm = V2MasterRealtimeManager.instance;
    for (final row in rm.kapacitetCache.values) {
      final rowGrad = row['grad'] as String? ?? '';
      if (rowGrad != gradKey) continue;
      final rawVreme = row['vreme'] as String? ?? '';
      if (V2GradAdresaValidator.normalizeTime(rawVreme) == normalizedVreme) {
        return (row['max_mesta'] as int?) ?? 8;
      }
    }
    return 8;
  }
}
