import 'package:flutter/foundation.dart';

import '../../models/v3_putnik.dart';
import '../../models/v3_vozac.dart';
import '../../utils/v3_belgrade_time.dart';
import '../../utils/v3_putnik_id_resolver.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_putnik_repository.dart';
import 'v3_finansije_service.dart';
import 'v3_push_token_edge_service.dart';

/// Service for V3 passengers (logical `v3_putnici` cache backed by `v3_auth`).
class V3PutnikService {
  V3PutnikService._();
  static final V3PutnikRepository _repo = V3PutnikRepository();

  static V3Vozac? currentVozac;
  static Map<String, dynamic>? currentPutnik;

  static bool _isPoDanuTip(String tip) {
    final normalized = tip.trim().toLowerCase();
    return normalized == 'radnik' || normalized == 'ucenik';
  }

  static double _effectiveCena({
    required String tip,
    required double cenaPoDanu,
    required double cenaPoPokupljenju,
  }) {
    return _isPoDanuTip(tip) ? cenaPoDanu : cenaPoPokupljenju;
  }

  static Map<String, dynamic>? _getCurrentPutnikRow(String putnikId) {
    final safeId = putnikId.trim();
    if (safeId.isEmpty) return null;

    final rm = V3MasterRealtimeManager.instance;
    final fromPutnici = rm.putniciCache[safeId] ??
        rm.putniciCache[safeId.toLowerCase()] ??
        rm.putniciCache.entries
            .where((e) => e.key.toLowerCase() == safeId.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
    if (fromPutnici != null && fromPutnici.isNotEmpty) {
      return Map<String, dynamic>.from(fromPutnici);
    }

    final fromAuth = rm.authCache[safeId] ??
        rm.authCache[safeId.toLowerCase()] ??
        rm.authCache.entries.where((e) => e.key.toLowerCase() == safeId.toLowerCase()).map((e) => e.value).firstOrNull;
    if (fromAuth != null && fromAuth.isNotEmpty) {
      return Map<String, dynamic>.from(fromAuth);
    }

    return null;
  }

  static List<V3Putnik> getPutniciByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    return cache.where((r) => r['tip_putnika'] == tip).map((r) => V3Putnik.fromJson(r)).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Putnik>> streamPutniciByTip(String tip) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(tables: ['v3_auth'], build: () => getPutniciByTip(tip));

  static V3Putnik? getPutnikById(String id) {
    final data = V3MasterRealtimeManager.instance.putniciCache[id];
    return data != null ? V3Putnik.fromJson(data) : null;
  }

  static Future<Map<String, dynamic>?> getActiveById(String putnikId) async {
    final id = putnikId.trim();
    debugPrint('[V3PutnikService] getActiveById called with: $id');
    if (id.isEmpty) {
      debugPrint('[V3PutnikService] id is empty, returning null');
      return null;
    }

    final row = await _repo.getActiveById(id);
    debugPrint('[V3PutnikService] getActiveById repo returned: ${row != null ? 'data' : 'null'}');
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>?> getActiveByPushToken(String token) async {
    final safeToken = token.trim();
    if (safeToken.isEmpty) return null;

    final row = await _repo.getActiveByPushToken(safeToken);
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  static Future<void> addUpdatePutnik(V3Putnik putnik, {String? createdBy, String? updatedBy}) async {
    try {
      final data = putnik.toJson();
      final createdByUuid = V3UuidUtils.normalizeUuid(createdBy);
      final updatedByUuid = V3UuidUtils.normalizeUuid(updatedBy, fallback: createdByUuid);

      final existingId = putnik.id.trim();
      final existingRow = existingId.isNotEmpty ? _getCurrentPutnikRow(existingId) : null;

      final oldTip = (existingRow?['tip_putnika']?.toString() ?? existingRow?['tip']?.toString() ?? '').trim();
      final oldCenaPoDanu = (existingRow?['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
      final oldCenaPoPokupljenju = (existingRow?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
      final oldEffectiveCena = oldTip.isNotEmpty
          ? _effectiveCena(
              tip: oldTip,
              cenaPoDanu: oldCenaPoDanu,
              cenaPoPokupljenju: oldCenaPoPokupljenju,
            )
          : 0.0;

      final newEffectiveCena = _effectiveCena(
        tip: putnik.tipPutnika,
        cenaPoDanu: putnik.cenaPoDanu,
        cenaPoPokupljenju: putnik.cenaPoPokupljenju,
      );

      if (existingRow != null && oldTip.isNotEmpty && (oldEffectiveCena - newEffectiveCena).abs() > 0.009) {
        await V3FinansijeService.freezeLegacyNenaplaceneWithOldCena(
          putnikId: existingId,
          oldCena: oldEffectiveCena,
          newCena: newEffectiveCena,
        );
      }

      if (putnik.id.isEmpty) data.remove('id');
      if (putnik.id.isEmpty && createdByUuid != null) data['created_by'] = createdByUuid;
      if (updatedByUuid != null) data['updated_by'] = updatedByUuid;

      final row = await _repo.upsertReturning(data);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_auth', row);
    } catch (e) {
      debugPrint('[V3PutnikService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivatePutnik(String id) async {
    await _repo.deleteById(id);
    V3MasterRealtimeManager.instance.v3RemoveFromCache('v3_auth', id);
  }

  static Future<void> writePushTokenOnLogin({
    required String putnikId,
    required String pushToken,
    String? installationId,
    String? hardwareId,
  }) async {
    final safeId = putnikId.trim();
    final safeToken = pushToken.trim();
    final safeInstallationId = (installationId ?? '').trim();
    if (safeId.isEmpty || safeInstallationId.isEmpty) return;

    try {
      await V3PushTokenEdgeService.writeLoginColumns(
        v3AuthId: safeId,
        pushToken: safeToken,
        installationId: safeInstallationId,
        hardwareId: hardwareId,
      );
    } catch (e) {
      debugPrint('[V3PutnikService] writePushTokenOnLogin error: $e');
    }
  }

  /// Get active v3 passengers + their requests for today, filtered by city and time
  static List<Map<String, dynamic>> getKombinovaniPutniciFiltrirano({
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    final rm = V3MasterRealtimeManager.instance;
    final vremeNorm = V3BelgradeTime.normalizeToHHmm(vreme);
    final targetGrad = grad.trim().toUpperCase();

    return rm.operativnaNedeljaCache.values
        .where((row) {
          final rowDatum = V3BelgradeTime.parseIsoDatePart(row['datum'] as String? ?? '');
          if (rowDatum != datumIso) return false;

          final rowGrad = (row['grad']?.toString() ?? '').trim().toUpperCase();
          if (rowGrad != targetGrad) return false;

          final rowVreme = V3BelgradeTime.normalizeToHHmm(row['polazak_at']?.toString() ?? '');
          if (rowVreme != vremeNorm) return false;

          if (row['otkazano_at'] != null) return false;
          if (V3PutnikIdResolver.fromRow(row).isEmpty) return false;
          return true;
        })
        .map((row) {
          final pid = V3PutnikIdResolver.fromRow(row);
          final pData = rm.putniciCache[pid];
          return {
            'id': pid,
            'putnik_id': pid,
            'ime_prezime': pData?['ime'] ?? '',
            'operativna_row': row,
            if (pData != null) 'putnik': V3Putnik.fromJson(pData),
          };
        })
        .where((m) => (m['ime_prezime'] as String).isNotEmpty)
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> streamKombinovaniPutniciFiltrirano({
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_auth', 'v3_operativna_nedelja'],
        build: () => getKombinovaniPutniciFiltrirano(datumIso: datumIso, grad: grad, vreme: vreme));
  }
}
