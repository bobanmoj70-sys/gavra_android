import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

  static List<V3Zahtev> getPendingZahteviByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    return cache.where((r) => r['grad'] == grad && r['status'] == 'obrada').map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => a.datum.compareTo(b.datum));
  }

  static Stream<List<V3Zahtev>> streamPendingZahteviByGrad(String grad) => V3MasterRealtimeManager.instance
      .v3StreamFromCache(tables: ['v3_zahtevi'], build: () => getPendingZahteviByGrad(grad));

  static V3Zahtev? getZahtevById(String id) {
    final data = V3MasterRealtimeManager.instance.zahteviCache[id];
    return data != null ? V3Zahtev.fromJson(data) : null;
  }

  static Future<V3Zahtev> createZahtev(V3Zahtev zahtev) async {
    try {
      final data = zahtev.toJson();
      final row = await supabase.from('v3_zahtevi').insert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
      return V3Zahtev.fromJson(row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Error: $e');
      rethrow;
    }
  }

  static Future<void> updateStatus(String id, String newStatus) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await supabase
          .from('v3_zahtevi')
          .update({'status': newStatus, 'updated_at': now})
          .eq('id', id)
          .select()
          .single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Status update error: $e');
      rethrow;
    }
  }
}
