import 'package:flutter/material.dart';

import '../../globals.dart';
import '../../models/v3_vozac.dart';
import '../../utils/v3_audit_korisnik.dart';
import '../../utils/v3_phone_utils.dart';
import '../../utils/v3_status_filters.dart';
import '../../utils/v3_validation_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozac_repository.dart';

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
        tables: ['v3_vozaci'],
        build: () => getAllVozaci(),
      );

  static V3Vozac? getVozacById(String id) {
    final data = V3MasterRealtimeManager.instance.vozaciCache[id];
    return data != null ? V3Vozac.fromJson(data) : null;
  }

  static V3Vozac? getVozacByName(String name) {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    try {
      final match = cache.firstWhere(
        (r) => r['ime_prezime'].toString().toLowerCase() == name.toLowerCase(),
      );
      return V3Vozac.fromJson(match);
    } catch (_) {
      return null;
    }
  }

  static V3Vozac? getVozacByPhone(String normalizedPhone) {
    if (normalizedPhone.isEmpty) return null;
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    try {
      final match = cache.firstWhere((r) {
        final t1 = V3PhoneUtils.normalize(r['telefon_1']?.toString() ?? '');
        final t2 = V3PhoneUtils.normalize(r['telefon_2']?.toString() ?? '');
        return t1 == normalizedPhone || (t2.isNotEmpty && t2 == normalizedPhone);
      });
      return V3Vozac.fromJson(match);
    } catch (_) {
      return null;
    }
  }

  static Future<void> addUpdateVozac(V3Vozac vozac) async {
    try {
      final actorUuid = V3AuditKorisnik.normalize(currentVozac?.id);
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

  static Future<void> updatePushToken({
    required String vozacId,
    String? pushToken,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (pushToken != null && pushToken.isNotEmpty) {
        payload['push_token'] = pushToken;
      }
      if (payload.isEmpty) return;

      await _repo.updateById(vozacId, payload);
    } catch (e) {
      debugPrint('[V3VozacService] updatePushToken error: $e');
      rethrow;
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

  /// Vraća boju vozača raspoređenog za dati dan/grad/vreme.
  /// [danPuni] — puni naziv dana (npr. 'Ponedeljak'), konvertuje se u ISO datum aktivne sedmice.
  static Color? getVozacColorForTermin(String danPuni, String grad, String vreme) {
    final datumIso = V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(danPuni, anchor: V3DanHelper.schedulingWeekAnchor());
    if (datumIso.isEmpty) return null;

    String normV(String? v) {
      if (v == null || v.isEmpty) return '';
      final p = v.split(':');
      if (p.length >= 2) {
        final hour = V3ValidationUtils.safeParseInt(p[0]);
        final minute = V3ValidationUtils.safeParseInt(p[1]);
        return V3DanHelper.formatVreme(hour, minute);
      }
      return v;
    }

    final vremeNorm = normV(vreme);
    final rm = V3MasterRealtimeManager.instance;

    // DEBUG: print search parameters
    print(
        '🔍 VOZAC COLOR SEARCH: danPuni=$danPuni → datumIso=$datumIso, grad=$grad, vreme=$vreme → vremeNorm=$vremeNorm');

    try {
      final matchingTermini = rm.v3GpsRasporedCache.values.where(
        (r) {
          final datumMatch = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') == datumIso;
          final gradMatch = r['grad']?.toString().toUpperCase() == grad.toUpperCase();
          final vremeMatch = normV(r['vreme']?.toString()) == vremeNorm;
          final status = r['status_final']?.toString();
          final statusMatch = !V3StatusFilters.isCanceledOrRejected(status);
          final masterTermin = r['created_by'] == null; // ← SAMO MASTER ZAPISI

          if (datumMatch && gradMatch && vremeMatch) {
            print(
                '🎯 MATCH: ${r['id']} datum=${r['datum']} grad=${r['grad']} vreme=${r['vreme']} status=${r['status_final']} vozac_id=${r['vozac_id']} master=$masterTermin');
          }

          return datumMatch && gradMatch && vremeMatch && statusMatch && masterTermin;
        },
      );

      if (matchingTermini.isEmpty) {
        print('❌ NO MATCH FOUND in cache for $datumIso $grad $vremeNorm - cache size: ${rm.v3GpsRasporedCache.length}');
        // Print first few cache items for debug
        final cacheItems = rm.v3GpsRasporedCache.values.take(3).toList();
        for (final item in cacheItems) {
          print(
              '   Cache sample: datum=${item['datum']} grad=${item['grad']} vreme=${item['vreme']} status=${item['status_final']}');
        }
        return null;
      }

      final termin = matchingTermini.first;
      final vozacId = termin['vozac_id']?.toString();
      if (vozacId == null) {
        print('❌ VOZAC_ID is null for termin ${termin['id']}');
        return null;
      }
      final vozac = rm.vozaciCache[vozacId];
      if (vozac == null) {
        print('❌ VOZAC not found in cache for vozac_id $vozacId');
        return null;
      }
      final hex = vozac['boja']?.toString();
      if (hex == null || hex.isEmpty) {
        print('❌ VOZAC BOJA is null/empty for vozac $vozacId');
        return null;
      }
      final clean = hex.replaceFirst('#', '');
      final color = Color(int.parse('FF$clean', radix: 16));
      print('✅ VOZAC COLOR FOUND: $hex → $color for vozac $vozacId');
      return color;
    } catch (e) {
      print('❌ ERROR in getVozacColorForTermin: $e');
      return null;
    }
  }
}
