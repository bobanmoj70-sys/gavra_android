import 'package:flutter/foundation.dart';

import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_kapacitet_slots_repository.dart';

class V3KapacitetSlotsService {
  V3KapacitetSlotsService._();

  static final V3KapacitetSlotsRepository _repo = V3KapacitetSlotsRepository();

  static Future<Map<String, dynamic>> upsertSlot({
    required String grad,
    required String vreme,
    required String datumIso,
    required int maxMesta,
    String? id,
  }) async {
    try {
      final row = await _repo.upsertSlot(
        grad: grad,
        vreme: vreme,
        datumIso: datumIso,
        maxMesta: maxMesta,
        id: id,
      );
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_kapacitet_slots', row);
      return row;
    } catch (e) {
      debugPrint('[V3KapacitetSlotsService] upsertSlot error: $e');
      rethrow;
    }
  }
}
