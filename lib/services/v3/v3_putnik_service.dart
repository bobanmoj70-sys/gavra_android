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
    String? pushToken2,
    String? androidDeviceId,
    String? androidDeviceId2,
    String? androidBuildId,
    String? androidBuildId2,
    String? iosDeviceId,
    String? iosDeviceId2,
    String? iosBuildId,
    String? iosBuildId2,
  }) async {
    final safeId = putnikId.trim();
    final safeToken = pushToken.trim();
    final safeToken2 = (pushToken2 ?? '').trim();
    final safeAndroidDeviceId = (androidDeviceId ?? '').trim();
    final safeAndroidDeviceId2 = (androidDeviceId2 ?? '').trim();
    final safeAndroidBuildId = (androidBuildId ?? '').trim();
    final safeAndroidBuildId2 = (androidBuildId2 ?? '').trim();
    final safeIosDeviceId = (iosDeviceId ?? '').trim();
    final safeIosDeviceId2 = (iosDeviceId2 ?? '').trim();
    final safeIosBuildId = (iosBuildId ?? '').trim();
    final safeIosBuildId2 = (iosBuildId2 ?? '').trim();
    if (safeId.isEmpty || safeToken.isEmpty) return;

    try {
      await V3PushTokenEdgeService.writeLoginColumns(
        v3AuthId: safeId,
        pushToken: safeToken,
        pushToken2: safeToken2,
        androidDeviceId: safeAndroidDeviceId,
        androidDeviceId2: safeAndroidDeviceId2,
        androidBuildId: safeAndroidBuildId,
        androidBuildId2: safeAndroidBuildId2,
        iosDeviceId: safeIosDeviceId,
        iosDeviceId2: safeIosDeviceId2,
        iosBuildId: safeIosBuildId,
        iosBuildId2: safeIosBuildId2,
      );
    } catch (e) {
      debugPrint('[V3PutnikService] writePushTokenOnLogin error: $e');
    }
  }

  /// Get all active v3 passengers + their requests for today
  static List<Map<String, dynamic>> getKombinovaniPutniciDanas() {
    final nowIso = V3DanHelper.todayIso();
    final rm = V3MasterRealtimeManager.instance;

    final rez = <Map<String, dynamic>>[];

    // 1. Pronađi sve zahteve za danas
    final danasnjiZahtevi = rm.zahteviCache.values
        .where((z) => z['datum'] == nowIso && !V3StatusPolicy.isCanceledOrRejected(z['status']?.toString()))
        .toList();

    // 2. Za svaki zahtev nađi putnika
    for (final z in danasnjiZahtevi) {
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

  static Stream<List<Map<String, dynamic>>> streamKombinovaniPutniciDanas() {
    return V3MasterRealtimeManager.instance
        .v3StreamFromRevisions(tables: ['v3_auth', 'v3_zahtevi'], build: () => getKombinovaniPutniciDanas());
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

  /// Streams V3 passengers who have an active request for a specific date.
  static Stream<List<V3Putnik>> streamPutniciByDatum({required String datumIso}) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_auth', 'v3_zahtevi'],
      build: () {
        final rm = V3MasterRealtimeManager.instance;
        final matchingZahtevi = rm.zahteviCache.values.where((z) {
          final rDatum = V3DanHelper.parseIsoDatePart(z['datum'] as String? ?? '');
          return rDatum == datumIso && !V3StatusPolicy.isCanceledOrRejected(z['status']?.toString());
        });

        final Set<String> uniquePutnikIds = matchingZahtevi.map((z) => z['created_by'] as String).toSet();

        return uniquePutnikIds
            .map((id) {
              final pData = rm.putniciCache[id];
              if (pData != null) {
                return V3Putnik.fromJson(pData);
              }
              return null;
            })
            .whereType<V3Putnik>()
            .toList()
          ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
      },
    );
  }

  static Future<List<V3Putnik>> getAllAktivniPutnici() async {
    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    return cache.map((p) => V3Putnik.fromJson(p)).toList()..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  /// Filtrira putnike po tačnom datumu, gradu i vremenu.
  /// Korišćeno za štampanje spiska polaska i prikaz u home screenu.
  static List<Map<String, dynamic>> getKombinovaniPutniciByDatumGradVreme({
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    final rm = V3MasterRealtimeManager.instance;
    final rez = <String, Map<String, dynamic>>{};

    final zahtevi = rm.zahteviCache.values.where((z) {
      final rDatum = V3DanHelper.parseIsoDatePart(z['datum'] as String? ?? '');
      return rDatum == datumIso &&
          z['grad'] == grad &&
          z['trazeni_polazak_at'] == vreme &&
          !V3StatusPolicy.isCanceledOrRejected(z['status']?.toString());
    });

    for (final z in zahtevi) {
      final pid = z['created_by']?.toString() ?? '';
      if (rez.containsKey(pid)) continue;
      final pData = rm.putniciCache[pid];
      if (pData != null) {
        rez[pid] = {
          'id': pid,
          'ime_prezime': pData['ime_prezime']?.toString() ?? '',
          'putnik': V3Putnik.fromJson(pData),
          'zahtev': V3Zahtev.fromJson(z),
        };
      }
    }

    final lista = rez.values.toList();
    lista.sort((a, b) => (a['ime_prezime'] as String).compareTo(b['ime_prezime'] as String));
    return lista;
  }
}
