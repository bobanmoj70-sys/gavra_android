import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_vozilo.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 vehicles (`v3_vozila`).
class V3VoziloService {
  V3VoziloService._();

  static List<V3Vozilo> getAllVozila() {
    final cache = V3MasterRealtimeManager.instance.vozilaCache.values;
    return cache.map((r) => V3Vozilo.fromJson(r)).toList()..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  static Stream<List<V3Vozilo>> streamVozila() => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_vozila'],
        build: () => getAllVozila(),
      );

  static V3Vozilo? getVoziloById(String id) {
    final data = V3MasterRealtimeManager.instance.vozilaCache[id];
    return data != null ? V3Vozilo.fromJson(data) : null;
  }

  static Future<V3Vozilo> addUpdateVozilo(V3Vozilo vozilo) async {
    try {
      final data = vozilo.toJson();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final row = await supabase.from('v3_vozila').upsert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
      return V3Vozilo.fromJson(row);
    } catch (e) {
      debugPrint('[V3VoziloService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivateVozilo(String id) async {
    try {
      await supabase.from('v3_vozila').update({'aktivno': false}).eq('id', id);
      V3MasterRealtimeManager.instance.vozilaCache.remove(id);
    } catch (e) {
      debugPrint('[V3VoziloService] Deactivate error: $e');
      rethrow;
    }
  }
}
