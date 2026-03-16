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

  static Future<void> addUpdateVozilo(V3Vozilo vozilo) async {
    try {
      final data = vozilo.toJson();
      data['updated_by'] = 'admin:sistem';

      await supabase.from('v3_vozila').upsert(data);
    } catch (e) {
      debugPrint('[V3VoziloService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivateVozilo(String id) async {
    try {
      await supabase.from('v3_vozila').update({'aktivno': false, 'updated_by': 'admin:sistem'}).eq('id', id);
    } catch (e) {
      debugPrint('[V3VoziloService] Deactivate error: $e');
      rethrow;
    }
  }

  /// Ažurira kolsku knjigu vozila (samo proslijeđena polja).
  static Future<void> updateKolskaKnjiga(String voziloId, Map<String, dynamic> data) async {
    try {
      await supabase.from('v3_vozila').update(data).eq('id', voziloId);
    } catch (e) {
      debugPrint('[V3VoziloService] updateKolskaKnjiga error: $e');
      rethrow;
    }
  }
}
