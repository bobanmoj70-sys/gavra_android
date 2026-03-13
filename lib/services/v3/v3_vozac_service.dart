import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_vozac.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 drivers (`v3_vozaci`).
class V3VozacService {
  V3VozacService._();

  static V3Vozac? currentVozac;

  static List<V3Vozac> getAllVozaci() {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    return cache.map((r) => V3Vozac.fromJson(r)).toList()..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Vozac>> streamVozaci() => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_vozaci'],
        build: () => getAllVozaci(),
      );

  static V3Vozac? getVozacById(String id) {
    final data = V3MasterRealtimeManager.instance.vozaciCache[id];
    return data != null ? V3Vozac.fromJson(data) : null;
  }

  static V3Vozac? getVozacByName(String name) {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    try {
      final match = cache.firstWhere(
        (r) => r['ime_prezime'].toString().toLowerCase() == name.toLowerCase(),
      );
      return V3Vozac.fromJson(match);
    } catch (_) {
      return null;
    }
  }

  static Future<V3Vozac> addUpdateVozac(V3Vozac vozac) async {
    try {
      final data = vozac.toJson();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final row = await supabase.from('v3_vozaci').upsert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozaci', row);
      return V3Vozac.fromJson(row);
    } catch (e) {
      debugPrint('[V3VozacService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivateVozac(String id) async {
    try {
      await supabase.from('v3_vozaci').update({'aktivno': false}).eq('id', id);
      V3MasterRealtimeManager.instance.vozaciCache.remove(id);
    } catch (e) {
      debugPrint('[V3VozacService] Deactivate error: $e');
      rethrow;
    }
  }
}
