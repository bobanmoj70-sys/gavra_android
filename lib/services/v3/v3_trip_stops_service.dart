import 'package:flutter/foundation.dart';

import '../../utils/v3_time_utils.dart';
import 'repositories/v3_trip_stops_repository.dart';
import 'v3_operativna_nedelja_service.dart';

class V3TripStopsService {
  V3TripStopsService._();

  static final V3TripStopsRepository _repo = V3TripStopsRepository();

  static int? _parseOrder(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static Future<String?> _resolveTripStateId({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String polazakVreme,
  }) async {
    final polazakNorm = V3TimeUtils.normalizeToHHmm(polazakVreme);
    if (polazakNorm.isEmpty) return null;

    try {
      final rowsRaw = await _repo.listTripStateByKey(
        vozacId: vozacId,
        datumIso: datumIso,
        grad: grad,
      );
      final rows = rowsRaw.cast<Map<String, dynamic>>();

      for (final row in rows) {
        final tripTime = V3TimeUtils.extractHHmmToken(row['polazak_vreme']?.toString());
        if (tripTime == polazakNorm) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) return id;
        }
      }
    } catch (e) {
      debugPrint('[V3TripStopsService] _resolveTripStateId error: $e');
    }

    return null;
  }

  static Future<void> upsertStopsForTermin({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String polazakVreme,
    required List<Map<String, dynamic>> optimizedData,
    String source = 'osrm',
  }) async {
    final gradUp = grad.trim().toUpperCase();
    final polazakNorm = V3TimeUtils.normalizeToHHmm(polazakVreme);

    if (vozacId.trim().isEmpty || datumIso.trim().isEmpty || gradUp.isEmpty || polazakNorm.isEmpty) {
      return;
    }

    final tripStateId = await _resolveTripStateId(
      vozacId: vozacId,
      datumIso: datumIso,
      grad: gradUp,
      polazakVreme: polazakNorm,
    );

    final futures = <Future<void>>[];

    for (final item in optimizedData) {
      final entry = item['entry'] as V3OperativnaNedeljaEntry?;
      if (entry == null || entry.id.isEmpty) continue;

      final stopOrder = _parseOrder(item['route_order']);
      if (stopOrder == null || stopOrder <= 0) continue;

      futures.add(
        _repo.upsert({
          'trip_state_id': tripStateId,
          'vozac_id': vozacId,
          'datum': datumIso,
          'grad': gradUp,
          'polazak_hhmm': polazakNorm,
          'operativna_id': entry.id,
          'putnik_id': entry.putnikId,
          'stop_order': stopOrder,
          'source': source,
        }),
      );
    }

    if (futures.isEmpty) return;

    try {
      await Future.wait(futures);
    } catch (e) {
      debugPrint('[V3TripStopsService] upsertStopsForTermin error: $e');
      rethrow;
    }
  }
}
