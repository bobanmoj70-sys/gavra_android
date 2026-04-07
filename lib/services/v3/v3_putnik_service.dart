import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_vozac.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_audit_korisnik.dart';
import '../../utils/v3_status_filters.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_putnik_repository.dart';

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
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(tables: ['v3_putnici'], build: () => getPutniciByTip(tip));

  static V3Putnik? getPutnikById(String id) {
    final data = V3MasterRealtimeManager.instance.putniciCache[id];
    return data != null ? V3Putnik.fromJson(data) : null;
  }

  static Future<Map<String, dynamic>?> getByPhoneOrCache(String normalizedPhone) async {
    final needle = normalizedPhone.trim();
    if (needle.isEmpty) return null;

    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    for (final row in cache) {
      final telefon1 = row['telefon_1']?.toString().trim() ?? '';
      final telefon2 = row['telefon_2']?.toString().trim() ?? '';
      if (telefon1 == needle || (telefon2.isNotEmpty && telefon2 == needle)) {
        return Map<String, dynamic>.from(row);
      }
    }

    final rows = await _repo.listByPhone(needle);
    if (rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    return null;
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
      final createdByUuid = V3AuditKorisnik.normalize(createdBy);
      final updatedByUuid = V3AuditKorisnik.normalize(updatedBy, fallback: createdByUuid);

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

  static Future<Map<String, String>> updatePushTokensOnLogin({
    required String putnikId,
    required String token,
    String? existingToken1,
    String? existingToken2,
  }) async {
    try {
      if (token.isEmpty) return const {};

      if (existingToken1 == null || existingToken1.isEmpty || existingToken1 == token) {
        await _repo.updateById(putnikId, {'push_token': token});
        return {'push_token': token};
      }

      if (existingToken2 == null || existingToken2.isEmpty || existingToken2 == token) {
        await _repo.updateById(putnikId, {'push_token_2': token});
        return {'push_token_2': token};
      }

      await _repo.updateById(putnikId, {'push_token_2': token});
      return {'push_token_2': token};
    } catch (e) {
      debugPrint('[V3PutnikService] updatePushTokensOnLogin error: $e');
      rethrow;
    }
  }

  /// Get all active v3 passengers + their requests for today
  static List<Map<String, dynamic>> getKombinovaniPutniciDanas() {
    final nowIso = V3DanHelper.todayIso();
    final rm = V3MasterRealtimeManager.instance;

    final rez = <Map<String, dynamic>>[];

    // 1. Pronađi sve zahteve za danas
    final danasnjiZahtevi = rm.zahteviCache.values
        .where((z) => z['datum'] == nowIso && !V3StatusFilters.isCanceledOrRejected(z['status']?.toString()))
        .toList();

    // 2. Za svaki zahtev nađi putnika
    for (final z in danasnjiZahtevi) {
      final pid = z['putnik_id'];
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
        .v3StreamFromRevisions(tables: ['v3_putnici', 'v3_zahtevi'], build: () => getKombinovaniPutniciDanas());
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
      final statusAllowed = !V3StatusFilters.isCanceledOrRejected(z['status']?.toString());
      final isGrad = z['grad'] == grad;
      final isVreme = z['zeljeno_vreme'] == vreme;
      return isDanas && statusAllowed && isGrad && isVreme;
    }).toList();

    for (final z in filtriraniZahtevi) {
      final pid = z['putnik_id'];
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
        tables: ['v3_putnici', 'v3_zahtevi'], build: () => getKombinovaniPutniciFiltrirano(grad: grad, vreme: vreme));
  }

  /// Streams V3 passengers who have an active request for a specific date.
  static Stream<List<V3Putnik>> streamPutniciByDatum({required String datumIso}) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_putnici', 'v3_zahtevi'],
      build: () {
        final rm = V3MasterRealtimeManager.instance;
        final matchingZahtevi = rm.zahteviCache.values.where((z) {
          final rDatum = V3DanHelper.parseIsoDatePart(z['datum'] as String? ?? '');
          return rDatum == datumIso && !V3StatusFilters.isCanceledOrRejected(z['status']?.toString());
        });

        final Set<String> uniquePutnikIds = matchingZahtevi.map((z) => z['putnik_id'] as String).toSet();

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
          z['zeljeno_vreme'] == vreme &&
          z['status'] != 'otkazano' &&
          z['status'] != 'odbijeno';
    });

    for (final z in zahtevi) {
      final pid = z['putnik_id']?.toString() ?? '';
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
