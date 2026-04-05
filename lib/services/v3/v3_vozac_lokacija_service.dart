import 'package:flutter/foundation.dart';

import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozac_lokacija_repository.dart';

/// Model for driver location update metadata
class V3VozacLokacijaUpdate {
  final String vozacId;
  final double lat;
  final double lng;
  final double? brzina;
  final bool aktivno;

  V3VozacLokacijaUpdate({
    required this.vozacId,
    required this.lat,
    required this.lng,
    this.brzina,
    this.aktivno = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'vozac_id': vozacId,
      'lat': lat,
      'lng': lng,
      'brzina': brzina ?? 0,
      'aktivno': aktivno,
    };
  }
}

/// Service for managing driver GPS locations in real-time.
/// Targeted at the `v3_vozac_lokacije` table.
class V3VozacLokacijaService {
  V3VozacLokacijaService._();
  static final V3VozacLokacijaRepository _repo = V3VozacLokacijaRepository();

  /// Updates driver's location in the database using Fire-and-Forget.
  /// Poziva se često iz GPS stream-a i koristi se za ETA/status prikaz.
  static Future<void> updateLokacija(V3VozacLokacijaUpdate update) async {
    try {
      await _repo.upsert(update.toJson());
    } catch (e) {
      debugPrint('[V3VozacLokacijaService] updateLokacija error: $e');
      // Ne rethrow - GPS pozivi su fire-and-forget
    }
  }

  /// Sets driver's active status. When deactivated, the marker disappears for passengers.
  static Future<void> postaviAktivnost(String vozacId, bool aktivno) async {
    try {
      await _repo.updateByVozacId(vozacId, {'aktivno': aktivno});
    } catch (e) {
      debugPrint('[V3VozacLokacijaService] postaviAktivnost error: $e');
    }
  }

  /// Stream of all active driver locations for passengers to see markers on map.
  static Stream<List<Map<String, dynamic>>> streamAktivneLokacije() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_vozac_lokacije'],
      build: () {
        final cache = V3MasterRealtimeManager.instance.vozacLokacijeCache;
        return cache.values.where((l) => l['aktivno'] == true).toList();
      },
    );
  }

  /// Gets specific driver's location from the synchronized cache.
  static Map<String, dynamic>? getVozacLokacijaSync(String vozacId, {bool onlyActive = false}) {
    final cache = V3MasterRealtimeManager.instance.vozacLokacijeCache;
    // Note: cache key is UID of the record in v3_vozac_lokacije, not vozac_id.
    // We search the values for the matching vozac_id.
    try {
      return cache.values.firstWhere(
        (l) => l['vozac_id']?.toString() == vozacId && (!onlyActive || l['aktivno'] == true),
      );
    } catch (_) {
      return null;
    }
  }
}
