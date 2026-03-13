import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

  static List<V3Zahtev> getZahteviByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    // Filtriramo putnike iz cachea da nađemo one koji su traženog tipa
    final putnici = V3MasterRealtimeManager.instance.putniciCache.values
        .where((p) => (p['tip'] ?? '').toLowerCase() == tip.toLowerCase())
        .map((p) => p['id'] as String)
        .toSet();

    return cache.where((r) => putnici.contains(r['putnik_id'])).map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(2000)) ?? 0);
  }

  static Stream<List<V3Zahtev>> streamZahteviByTip(String tip) => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_zahtevi', 'v3_putnici'],
        build: () => getZahteviByTip(tip),
      );

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

  static List<V3Zahtev> getZahteviByDanAndGrad(String danUSedmici, String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    return cache
        .where((r) => r['dan_u_sedmici'] == danUSedmici && r['grad'] == grad && r['aktivno'] == true)
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => a.zeljenoVreme.compareTo(b.zeljenoVreme));
  }

  static Stream<List<V3Zahtev>> streamZahteviByDanAndGrad(String dan, String grad) =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_zahtevi'],
        build: () => getZahteviByDanAndGrad(dan, grad),
      );

  static Future<void> deleteZahtev(String id) async {
    try {
      await supabase.from('v3_zahtevi').delete().eq('id', id);
      V3MasterRealtimeManager.instance.zahteviCache.remove(id);
    } catch (e) {
      debugPrint('[V3ZahtevService] Delete error: $e');
      rethrow;
    }
  }
}
