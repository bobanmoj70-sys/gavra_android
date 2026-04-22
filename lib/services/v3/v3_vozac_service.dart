import 'package:flutter/material.dart';

import '../../models/v3_vozac.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozac_repository.dart';
import 'v3_push_token_edge_service.dart';

/// Service for V3 drivers (`v3_vozaci`).
class V3VozacService {
  V3VozacService._();
  static final V3VozacRepository _repo = V3VozacRepository();

  static V3Vozac? currentVozac;

  static List<V3Vozac> getAllVozaci() {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    return cache.map((r) => V3Vozac.fromJson(r)).toList()..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Vozac>> streamVozaci() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_auth'],
        build: () => getAllVozaci(),
      );

  static V3Vozac? getVozacById(String id) {
    final data = V3MasterRealtimeManager.instance.vozaciCache[id];
    return data != null ? V3Vozac.fromJson(data) : null;
  }

  static Future<V3Vozac?> getVozacByIdDirect(String authId) async {
    final id = authId.trim();
    if (id.isEmpty) return null;

    final row = await _repo.getById(id);
    if (row == null) return null;
    return V3Vozac.fromJson(row);
  }

  static Future<void> addUpdateVozac(V3Vozac vozac) async {
    try {
      final actorUuid = V3UuidUtils.normalizeUuid(currentVozac?.id);
      if (vozac.id.isNotEmpty) {
        // Edit — ne diramo push_token
        await _repo.updateById(vozac.id, {
          'ime_prezime': vozac.imePrezime,
          'telefon_1': vozac.telefon1,
          'telefon_2': vozac.telefon2,
          'boja': vozac.boja,
          if (actorUuid != null) 'updated_by': actorUuid,
        });
      } else {
        // Add — insert novog vozača (bez push_token, dobija ga pri prvom loginu)
        await _repo.insert({
          'ime_prezime': vozac.imePrezime,
          'telefon_1': vozac.telefon1,
          'telefon_2': vozac.telefon2,
          'boja': vozac.boja,
          if (actorUuid != null) 'created_by': actorUuid,
          if (actorUuid != null) 'updated_by': actorUuid,
        });
      }
    } catch (e) {
      debugPrint('[V3VozacService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivateVozac(String id) async {
    await _repo.deleteById(id);
  }

  static Future<void> writePushTokenOnLogin({
    required String vozacId,
    required String pushToken,
    String? installationId,
    String? pushToken2,
  }) async {
    final safeId = vozacId.trim();
    final safeToken = pushToken.trim();
    final safeInstallationId = (installationId ?? '').trim();
    final safeToken2 = (pushToken2 ?? '').trim();
    if (safeId.isEmpty || safeInstallationId.isEmpty) return;

    try {
      await V3PushTokenEdgeService.writeLoginColumns(
        v3AuthId: safeId,
        pushToken: safeToken,
        installationId: safeInstallationId,
        pushToken2: safeToken2,
      );
    } catch (e) {
      debugPrint('[V3VozacService] writePushTokenOnLogin error: $e');
    }
  }

  static Future<bool> hasActiveVozacWithPushToken({
    required String vozacId,
    required String pushToken,
  }) async {
    final id = vozacId.trim();
    final token = pushToken.trim();
    if (id.isEmpty || token.isEmpty) return false;

    final row = await _repo.getActiveByIdAndPushToken(vozacId: id, pushToken: token);
    return row != null;
  }
}
