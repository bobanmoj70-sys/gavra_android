import 'package:flutter/foundation.dart';

import '../../utils/v3_audit_actor.dart';
import '../../utils/v3_time_utils.dart';
import 'repositories/v3_gps_trip_state_repository.dart';

class V3GpsTripStateService {
  V3GpsTripStateService._();
  static final V3GpsTripStateRepository _repo = V3GpsTripStateRepository();

  static String normalizeTime(String? value) {
    return V3TimeUtils.normalizeToHHmm(value);
  }

  static DateTime? _toPolazakTs({
    required String datumIso,
    required String polazakVreme,
  }) {
    final normalized = normalizeTime(polazakVreme);
    if (datumIso.trim().isEmpty || normalized.isEmpty) return null;
    return DateTime.tryParse('${datumIso.trim()}T$normalized:00');
  }

  static Future<void> upsertTripState({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String polazakVreme,
    String gpsStatus = 'pending',
    bool notificationSent = false,
    String? navBarType,
    DateTime? trackingStartedAt,
    DateTime? trackingStoppedAt,
    String? updatedBy,
    String? createdBy,
  }) async {
    final gradUp = grad.trim().toUpperCase();
    final polazakTs = _toPolazakTs(datumIso: datumIso, polazakVreme: polazakVreme);
    if (vozacId.trim().isEmpty || datumIso.trim().isEmpty || gradUp.isEmpty || polazakTs == null) return;

    try {
      final payload = <String, dynamic>{
        'vozac_id': vozacId,
        'datum': datumIso,
        'grad': gradUp,
        'polazak_vreme': polazakTs.toIso8601String(),
        'gps_status': gpsStatus,
        'notification_sent': notificationSent,
        if (navBarType != null) 'nav_bar_type': navBarType,
        if (trackingStartedAt != null) 'tracking_started_at': trackingStartedAt.toIso8601String(),
        if (trackingStoppedAt != null) 'tracking_stopped_at': trackingStoppedAt.toIso8601String(),
        if (createdBy != null) 'created_by': V3AuditActor.normalize(createdBy),
        if (updatedBy != null) 'updated_by': V3AuditActor.normalize(updatedBy),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _repo.upsert(payload);
    } catch (e) {
      debugPrint('[V3GpsTripStateService] upsertTripState error: $e');
      rethrow;
    }
  }

  static Future<void> updateTrackingStatus({
    required String vozacId,
    required String grad,
    required String polazakVreme,
    required String gpsStatus,
    String? datumIso,
    String? updatedBy,
  }) async {
    final gradUp = grad.trim().toUpperCase();
    final timeNorm = normalizeTime(polazakVreme);
    if (vozacId.trim().isEmpty || gradUp.isEmpty || timeNorm.isEmpty) return;

    final now = DateTime.now();
    final fromDate = datumIso ?? DateTime(now.year, now.month, now.day).toIso8601String().split('T').first;
    final toDate = datumIso ??
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toIso8601String().split('T').first;

    try {
      final rowsRaw = await _repo.listByVozacGradAndDateRange(
        vozacId: vozacId,
        grad: gradUp,
        fromDate: fromDate,
        toDate: toDate,
      );

      final rows = (rowsRaw).cast<Map<String, dynamic>>();

      String? rowTime(Map<String, dynamic> row) {
        final raw = row['polazak_vreme']?.toString();
        if (raw == null || raw.trim().isEmpty) return null;
        return normalizeTime(raw);
      }

      final targetIds = rows
          .where((row) => rowTime(row) == timeNorm)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      if (targetIds.isEmpty) return;

      await _repo.updateByIds(ids: targetIds, payload: {
        'gps_status': gpsStatus,
        if (gpsStatus == 'tracking') 'notification_sent': true,
        if (gpsStatus == 'tracking') 'tracking_started_at': now.toIso8601String(),
        if (gpsStatus != 'tracking') 'tracking_stopped_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        if (updatedBy != null) 'updated_by': V3AuditActor.normalize(updatedBy),
      });
    } catch (e) {
      debugPrint('[V3GpsTripStateService] updateTrackingStatus error: $e');
      rethrow;
    }
  }

  static Future<void> removeTripsByTermin({
    required String datumIso,
    required String grad,
    required String polazakVreme,
    String? vozacId,
  }) async {
    final gradUp = grad.trim().toUpperCase();
    final polazakTs = _toPolazakTs(datumIso: datumIso, polazakVreme: polazakVreme);
    if (datumIso.trim().isEmpty || gradUp.isEmpty || polazakTs == null) return;

    try {
      await _repo.deleteByTermin(
        datumIso: datumIso,
        grad: gradUp,
        polazakVremeIso: polazakTs.toIso8601String(),
        vozacId: vozacId,
      );
    } catch (e) {
      debugPrint('[V3GpsTripStateService] removeTripsByTermin error: $e');
      rethrow;
    }
  }

  static Future<void> cleanupOrphanTripsForTermin({
    required String datumIso,
    required String grad,
    required String polazakVreme,
  }) async {
    final gradUp = grad.trim().toUpperCase();
    final timeNorm = normalizeTime(polazakVreme);
    final polazakTs = _toPolazakTs(datumIso: datumIso, polazakVreme: polazakVreme);
    if (datumIso.trim().isEmpty || gradUp.isEmpty || timeNorm.isEmpty || polazakTs == null) return;

    try {
      final tripsRaw = await _repo.listByTermin(
        datumIso: datumIso,
        grad: gradUp,
        polazakVremeIso: polazakTs.toIso8601String(),
      );

      final trips = (tripsRaw).cast<Map<String, dynamic>>();
      if (trips.isEmpty) return;

      final operativnaRaw = await _repo.listOperativnaAssignedByTermin(
        datumIso: datumIso,
        grad: gradUp,
      );

      final operativna = (operativnaRaw).cast<Map<String, dynamic>>();

      final assignedVozacIds = operativna
          .where((row) {
            final status = (row['status_final']?.toString() ?? '').trim().toLowerCase();
            if (status == 'otkazano' || status == 'odbijeno') return false;
            final raw = row['dodeljeno_vreme']?.toString() ?? row['zeljeno_vreme']?.toString();
            return normalizeTime(raw) == timeNorm;
          })
          .map((row) => row['vozac_id']?.toString())
          .whereType<String>()
          .toSet();

      final staleTripIds = trips
          .where((trip) => !assignedVozacIds.contains(trip['vozac_id']?.toString()))
          .map((trip) => trip['id']?.toString())
          .whereType<String>()
          .toList();

      if (staleTripIds.isNotEmpty) {
        await _repo.deleteByIds(staleTripIds);
      }
    } catch (e) {
      debugPrint('[V3GpsTripStateService] cleanupOrphanTripsForTermin error: $e');
      rethrow;
    }
  }
}
