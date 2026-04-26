import 'package:flutter/foundation.dart';

import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozac_lokacija_repository.dart';

/// Model for driver location update metadata
class V3VozacLokacijaUpdate {
  final String vozacId;
  final double lat;
  final double lng;
  final double? brzina;

  V3VozacLokacijaUpdate({
    required this.vozacId,
    required this.lat,
    required this.lng,
    this.brzina,
  });

  Map<String, dynamic> toJson() {
    return {
      'created_by': vozacId,
      'updated_by': vozacId,
      'lat': lat,
      'lng': lng,
      'brzina': brzina ?? 0,
    };
  }
}

/// Service for managing driver GPS locations in real-time.
/// Targeted at the `v3_vozac_lokacije` table.
class V3VozacLokacijaService {
  V3VozacLokacijaService._();
  static final V3VozacLokacijaRepository _repo = V3VozacLokacijaRepository();
  static const Duration _activeLocationWindow = Duration(minutes: 3);

  /// Updates driver's location in the database using Fire-and-Forget.
  /// Poziva se često iz GPS stream-a i koristi se za status/prikaz lokacije.
  static Future<void> updateLokacija(V3VozacLokacijaUpdate update) async {
    try {
      await _repo.upsert(update.toJson());
    } catch (e) {
      debugPrint('[V3VozacLokacijaService] updateLokacija error: $e');
      // Ne rethrow - GPS pozivi su fire-and-forget
    }
  }

  /// Stream of all active driver locations for passengers to see markers on map.
  static Stream<List<Map<String, dynamic>>> streamAktivneLokacije() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_vozac_lokacije'],
      build: () {
        final cache = V3MasterRealtimeManager.instance.vozacLokacijeCache;
        return cache.values.where(_isLokacijaAktivna).toList();
      },
    );
  }

  /// Gets specific driver's location from the synchronized cache.
  static Map<String, dynamic>? getVozacLokacijaSync(String vozacId, {bool onlyActive = false}) {
    final cache = V3MasterRealtimeManager.instance.vozacLokacijeCache;
    // Note: cache key is UID of the record in v3_vozac_lokacije, not created_by.
    // We search the values for the matching created_by.
    try {
      return cache.values.firstWhere(
        (l) => l['created_by']?.toString() == vozacId && (!onlyActive || _isLokacijaAktivna(l)),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isLokacijaAktivna(Map<String, dynamic> row) {
    final updatedRaw = row['updated_at']?.toString() ?? row['created_at']?.toString() ?? '';
    final updatedAt = DateTime.tryParse(updatedRaw);
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt) <= _activeLocationWindow;
  }
}
