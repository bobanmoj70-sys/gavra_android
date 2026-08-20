import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_vozilo.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozilo_repository.dart';

/// Service for V3 vehicles (`v3_vozila`).
class V3VoziloService {
  V3VoziloService._();
  static final V3VoziloRepository _repo = V3VoziloRepository();
  static const Uuid _uuid = Uuid();

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

  static V3Vozilo? getVoziloForVozac(String vozacId) {
    final id = vozacId.trim();
    if (id.isEmpty) return null;
    for (final vozilo in getAllVozila()) {
      if ((vozilo.vozacId ?? '').trim() == id) return vozilo;
    }
    return null;
  }

  /// Dodeljuje kombi vozaču. Jedan vozač = jedan kombi.
  /// [vozacId] null/prazan skida dodelu sa tog kombija.
  static Future<void> assignVozacToVozilo({
    required String voziloId,
    String? vozacId,
  }) async {
    final targetId = voziloId.trim();
    final nextVozacId = (vozacId ?? '').trim();
    if (targetId.isEmpty) return;

    try {
      if (nextVozacId.isNotEmpty) {
        for (final other in getAllVozila()) {
          if (other.id == targetId) continue;
          if ((other.vozacId ?? '').trim() != nextVozacId) continue;
          final cleared = await _repo.updateByIdReturning(other.id, {'vozac_id': null});
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', cleared);
        }
      }

      final row = await _repo.updateByIdReturning(targetId, {
        'vozac_id': nextVozacId.isEmpty ? null : nextVozacId,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
    } catch (e) {
      debugPrint('[V3VoziloService] assignVozacToVozilo error: $e');
      rethrow;
    }
  }

  /// Dodeljuje (ili skida) kombi vozaču. Prazan [voziloId] skida trenutnu dodelu.
  static Future<void> assignVoziloToVozac({
    required String vozacId,
    String? voziloId,
  }) async {
    final driverId = vozacId.trim();
    if (driverId.isEmpty) return;
    final nextVoziloId = (voziloId ?? '').trim();
    if (nextVoziloId.isEmpty) {
      final current = getVoziloForVozac(driverId);
      if (current == null) return;
      await assignVozacToVozilo(voziloId: current.id);
      return;
    }
    await assignVozacToVozilo(voziloId: nextVoziloId, vozacId: driverId);
  }

  static Future<void> addUpdateVozilo(V3Vozilo vozilo) async {
    try {
      final data = vozilo.toJson();
      if (vozilo.id.isEmpty) {
        data['id'] = _uuid.v4();
      }
      final row = await _repo.upsertReturning(data);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
    } catch (e) {
      debugPrint('[V3VoziloService] Error: $e');
      rethrow;
    }
  }

  /// Briše vozilo po id.
  static Future<void> deleteVozilo(String id) async {
    try {
      await _repo.deleteById(id);
      V3MasterRealtimeManager.instance.v3RemoveFromCache('v3_vozila', id);
    } catch (e) {
      debugPrint('[V3VoziloService] deleteVozilo error: $e');
      rethrow;
    }
  }

  /// Ažurira kolsku knjigu vozila (samo proslijeđena polja).
  static Future<void> updateKolskaKnjiga(String voziloId, Map<String, dynamic> data) async {
    try {
      final row = await _repo.updateByIdReturning(voziloId, data);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
    } catch (e) {
      debugPrint('[V3VoziloService] updateKolskaKnjiga error: $e');
      rethrow;
    }
  }
}
