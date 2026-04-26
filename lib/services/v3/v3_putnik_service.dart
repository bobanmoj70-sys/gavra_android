import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_vozac.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_putnik_repository.dart';
import 'v3_push_token_edge_service.dart';

/// Service for V3 passengers (logical `v3_putnici` cache backed by `v3_auth`).
class V3PutnikService {
  V3PutnikService._();
  static final V3PutnikRepository _repo = V3PutnikRepository();

  static V3Vozac? currentVozac;
  static Map<String, dynamic>? currentPutnik;

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

  static int normalizeBrojMestaForPutnik({
    required String putnikId,
    required int brojMesta,
  }) {
    final putnik = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    final tipPutnika = (putnik?['tip_putnika']?.toString() ?? '').trim().toLowerCase();
    if (tipPutnika == 'posiljka') return 0;
    return brojMesta;
  }

  static Future<Map<String, dynamic>?> getActiveById(String putnikId) async {
    final id = putnikId.trim();
    if (id.isEmpty) return null;

    final row = await _repo.getActiveById(id);
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

      if (putnik.id.isEmpty) data.remove('id');
      if (putnik.id.isEmpty && createdByUuid != null) data['created_by'] = createdByUuid;
      if (updatedByUuid != null) data['updated_by'] = updatedByUuid;

      await _repo.upsert(data);
    } catch (e) {
      debugPrint('[V3PutnikService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivatePutnik(String id) async {
    await _repo.deleteById(id);
  }

  static Future<void> writePushTokenOnLogin({
    required String putnikId,
    required String pushToken,
    String? installationId,
    String? pushToken2,
  }) async {
    final safeId = putnikId.trim();
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
      debugPrint('[V3PutnikService] writePushTokenOnLogin error: $e');
    }
  }

  /// Get active v3 passengers + their requests for today, filtered by city and time
  static List<Map<String, dynamic>> getKombinovaniPutniciFiltrirano({
    required String grad,
    required String vreme,
  }) {
    final nowIso = V3DanHelper.todayIso();
    final rm = V3MasterRealtimeManager.instance;

    final rez = <Map<String, dynamic>>[];

    final filtriraniZahtevi = rm.zahteviCache.values.where((z) {
      final isDanas = z['datum'] == nowIso;
      final statusAllowed = !V3StatusPolicy.isCanceledOrRejected(z['status']?.toString());
      final isGrad = z['grad'] == grad;
      final isVreme = z['trazeni_polazak_at'] == vreme;
      return isDanas && statusAllowed && isGrad && isVreme;
    }).toList();

    for (final z in filtriraniZahtevi) {
      final pid = z['created_by'];
      final pData = rm.putniciCache[pid];
      if (pData != null) {
        rez.add({
          'putnik': V3Putnik.fromJson(pData),
          'zahtev': V3Zahtev.fromJson(z),
        });
      }
    }

    return rez;
  }

  static Stream<List<Map<String, dynamic>>> streamKombinovaniPutniciFiltrirano({
    required String grad,
    required String vreme,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_auth', 'v3_zahtevi'], build: () => getKombinovaniPutniciFiltrirano(grad: grad, vreme: vreme));
  }
}
