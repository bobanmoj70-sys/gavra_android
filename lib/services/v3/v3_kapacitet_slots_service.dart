import 'package:flutter/foundation.dart';

import '../../utils/v3_date_utils.dart';
import '../../utils/v3_string_utils.dart';
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
    final gradNorm = grad.trim().toUpperCase();
    final vremeNorm = V3StringUtils.trimTimeToHhMm(vreme);
    final datumNorm = V3DateUtils.parseIsoDatePart(datumIso);

    try {
      final row = await _repo.upsertSlot(
        grad: gradNorm,
        vreme: vremeNorm,
        datumIso: datumNorm,
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
