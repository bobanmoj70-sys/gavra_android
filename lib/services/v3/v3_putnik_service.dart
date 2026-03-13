import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 passengers (unified `v3_putnici` table).
class V3PutnikService {
  V3PutnikService._();

  static List<V3Putnik> getPutniciByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    return cache.where((r) => r['tip_putnika'] == tip).map((r) => V3Putnik.fromJson(r)).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Putnik>> streamPutniciByTip(String tip) =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(tables: ['v3_putnici'], build: () => getPutniciByTip(tip));

  static V3Putnik? getPutnikById(String id) {
    final data = V3MasterRealtimeManager.instance.putniciCache[id];
    return data != null ? V3Putnik.fromJson(data) : null;
  }

  static Future<V3Putnik> addUpdatePutnik(V3Putnik putnik) async {
    try {
      final data = putnik.toJson();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final row = await supabase.from('v3_putnici').upsert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_putnici', row);
      return V3Putnik.fromJson(row);
    } catch (e) {
      debugPrint('[V3PutnikService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivatePutnik(String id) async {
    try {
      await supabase.from('v3_putnici').update({'aktivna': false}).eq('id', id);
      V3MasterRealtimeManager.instance.putniciCache.remove(id);
    } catch (e) {
      debugPrint('[V3PutnikService] Deactivate error: $e');
      rethrow;
    }
  }
}
