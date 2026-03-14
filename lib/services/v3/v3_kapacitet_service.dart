import 'package:flutter/foundation.dart';

import '../../config/v2_route_config.dart';
import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3KapacitetService {
  V3KapacitetService._();

  static List<String> get bcVremena => V2RouteConfig.getVremenaByNavType('BC', navBarTypeNotifier.value);
  static List<String> get vsVremena => V2RouteConfig.getVremenaByNavType('VS', navBarTypeNotifier.value);

  /// ID ključ za cache: 'BC_0600'
  static String _cacheId(String grad, String vreme) => '${grad}_${vreme.replaceAll(':', '')}';

  /// Čita kapacitet za grad+vreme iz v3_kapacitet cache-a.
  /// Fallback: BC=20, VS=8
  static int getKapacitetSyncValue(String grad, String vreme) {
    final cache = V3MasterRealtimeManager.instance.kapacitetCache;
    final id = _cacheId(grad, vreme);
    final row = cache[id];
    if (row != null) return (row['max_mesta'] as num?)?.toInt() ?? _fallback(grad);
    // Probaj i bez sekundi ako je vreme u formatu 'HH:mm:ss'
    for (final r in cache.values) {
      if (r['grad'] == grad && _normalizeVreme(r['vreme']?.toString() ?? '') == _normalizeVreme(vreme)) {
        return (r['max_mesta'] as num?)?.toInt() ?? _fallback(grad);
      }
    }
    return _fallback(grad);
  }

  static int _fallback(String grad) => grad == 'BC' ? 20 : 8;

  /// Normalizuje vreme na 'HH:mm' format (uklanja sekunde)
  static String _normalizeVreme(String v) {
    final parts = v.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return v;
  }

  /// Upsertuje kapacitet za grad+vreme u v3_kapacitet tabeli.
  /// Kreira red ako ne postoji, ili updatuje ako postoji.
  static Future<bool> setKapacitet(String grad, String vreme, int maxMesta) async {
    try {
      final id = _cacheId(grad, vreme);
      await supabase.from('v3_kapacitet').upsert(
        {
          'id': id,
          'grad': grad,
          'vreme': vreme,
          'max_mesta': maxMesta,
          'aktivno': true,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'id',
      );
      // Lokalni cache update odmah
      final cache = V3MasterRealtimeManager.instance.kapacitetCache;
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_kapacitet', {
        ...?cache[id],
        'id': id,
        'grad': grad,
        'vreme': vreme,
        'max_mesta': maxMesta,
        'aktivno': true,
      });
      return true;
    } catch (e) {
      debugPrint('[V3KapacitetService] setKapacitet error: $e');
      return false;
    }
  }

  /// Sinkronizuje slotove trenutnog sezona iz V2RouteConfig u v3_kapacitet tabelu.
  /// Kreira redove koji nedostaju sa default vrijednostima (BC=20, VS=8).
  /// Postojeći redovi se NE mijenjaju (ignoreDuplicates=true).
  static Future<void> syncSlotsFromConfig() async {
    try {
      // Koristi samo trenutni sezon (navBarTypeNotifier.value)
      final slots = <(String, String)>{};
      for (final vreme in bcVremena) {
        slots.add(('BC', vreme));
      }
      for (final vreme in vsVremena) {
        slots.add(('VS', vreme));
      }

      final cache = V3MasterRealtimeManager.instance.kapacitetCache;
      final toInsert = <Map<String, dynamic>>[];

      for (final (grad, vreme) in slots) {
        final id = _cacheId(grad, vreme);
        if (!cache.containsKey(id)) {
          toInsert.add({
            'id': id,
            'grad': grad,
            'vreme': vreme,
            'max_mesta': _fallback(grad),
            'aktivno': true,
          });
        }
      }

      if (toInsert.isEmpty) {
        debugPrint('[V3KapacitetService] syncSlotsFromConfig: svi slotovi postoje, nema novih');
        return;
      }

      debugPrint('[V3KapacitetService] syncSlotsFromConfig: kreiram ${toInsert.length} novih slotova');
      await supabase.from('v3_kapacitet').upsert(toInsert, onConflict: 'id', ignoreDuplicates: true);

      // Dodaj u lokalni cache i notifikuj listenere
      for (final row in toInsert) {
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_kapacitet', row);
      }
    } catch (e) {
      debugPrint('[V3KapacitetService] syncSlotsFromConfig error: $e');
    }
  }

  /// Vraća mapu {grad: {vreme: maxMesta}} iz cache-a.
  static Map<String, Map<String, int>> getKapacitetSync() {
    final result = <String, Map<String, int>>{
      'BC': {for (final v in bcVremena) v: getKapacitetSyncValue('BC', v)},
      'VS': {for (final v in vsVremena) v: getKapacitetSyncValue('VS', v)},
    };
    return result;
  }

  static Stream<Map<String, Map<String, int>>> streamKapacitet() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_kapacitet'],
      build: getKapacitetSync,
    );
  }
}
