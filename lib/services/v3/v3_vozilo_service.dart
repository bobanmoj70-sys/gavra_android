import 'package:flutter/foundation.dart';

import '../../models/v3_vozilo.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozilo_repository.dart';

/// Service for V3 vehicles (`v3_vozila`).
class V3VoziloService {
  V3VoziloService._();
  static final V3VoziloRepository _repo = V3VoziloRepository();

  static List<V3Vozilo> getAllVozila() {
    final cache = V3MasterRealtimeManager.instance.vozilaCache.values;
    return cache.map((r) => V3Vozilo.fromJson(r)).toList()..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  static Stream<List<V3Vozilo>> streamVozila() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
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

      await _repo.upsert(data);
    } catch (e) {
      debugPrint('[V3VoziloService] Error: $e');
      rethrow;
    }
  }

  /// Ažurira kolsku knjigu vozila (samo proslijeđena polja).
  static Future<void> updateKolskaKnjiga(String voziloId, Map<String, dynamic> data) async {
    try {
      await _repo.updateById(voziloId, data);
    } catch (e) {
      debugPrint('[V3VoziloService] updateKolskaKnjiga error: $e');
      rethrow;
    }
  }
}
