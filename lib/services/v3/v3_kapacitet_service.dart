import 'package:flutter/foundation.dart';

import '../../config/v2_route_config.dart';
import '../../globals.dart';
import '../../utils/v2_grad_adresa_validator.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3KapacitetService {
  V3KapacitetService._();

  static List<String> get bcVremena => V2RouteConfig.getVremenaByNavType('BC');
  static List<String> get vsVremena => V2RouteConfig.getVremenaByNavType('VS');

  static Future<bool> setKapacitet(String grad, String vreme, int maxMesta) async {
    try {
      final res = await supabase
          .from('v3_postavke_kapaciteta')
          .upsert(
            {
              'grad': grad,
              'vreme': vreme,
              'max_mesta': maxMesta,
              'aktivno': true,
            },
            onConflict: 'grad,vreme',
          )
          .select()
          .single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_postavke_kapaciteta', res);
      return true;
    } catch (e) {
      debugPrint('[V3KapacitetService] setKapacitet error: $e');
      return false;
    }
  }

  static Map<String, Map<String, int>> getKapacitetSync() {
    final cache = V3MasterRealtimeManager.instance.postavkeKapacitetaCache;
    final result = <String, Map<String, int>>{'BC': {}, 'VS': {}};

    for (final row in cache.values) {
      final grad = row['grad'] as String? ?? '';
      final vreme = row['vreme'] as String? ?? '';
      final maxMesta = (row['max_mesta'] as int?) ?? 8;

      if (grad == 'BC' || grad == 'VS') {
        result[grad]![vreme] = maxMesta;
      }
    }
    return result;
  }

  static Stream<Map<String, Map<String, int>>> streamKapacitet() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_postavke_kapaciteta'],
      build: getKapacitetSync,
    );
  }

  /// Dohvati kapacitet za grad/vreme (čita iz rm.kapacitetCache — nema DB upita).
  /// Vraca default 8 ako nije dostupno.
  static int getKapacitetSyncValue(String grad, String vreme) {
    final normalizedVreme = V2GradAdresaValidator.normalizeTime(vreme);
    final gradKey = grad == 'BC' ? 'BC' : 'VS';

    final cache = V3MasterRealtimeManager.instance.postavkeKapacitetaCache;
    for (final row in cache.values) {
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
