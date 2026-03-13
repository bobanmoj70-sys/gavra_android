import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 passengers (unified `v3_putnici` table).
class V3PutnikService {
  V3PutnikService._();

  static List<V3Putnik> getPutniciByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    return cache.where((r) => r['tip_putnika'] == tip).map((r) => V3Putnik.fromJson(r)).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Putnik>> streamPutniciByTip(String tip) =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(tables: ['v3_putnici'], build: () => getPutniciByTip(tip));

  static V3Putnik? getPutnikById(String id) {
    final data = V3MasterRealtimeManager.instance.putniciCache[id];
    return data != null ? V3Putnik.fromJson(data) : null;
  }

  static Future<V3Putnik> addUpdatePutnik(V3Putnik putnik) async {
    try {
      final data = putnik.toJson();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final row = await supabase.from('v3_putnici').upsert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_putnici', row);
      return V3Putnik.fromJson(row);
    } catch (e) {
      debugPrint('[V3PutnikService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivatePutnik(String id) async {
    try {
      await supabase.from('v3_putnici').update({'aktivna': false}).eq('id', id);
      V3MasterRealtimeManager.instance.putniciCache.remove(id);
    } catch (e) {
      debugPrint('[V3PutnikService] Deactivate error: $e');
      rethrow;
    }
  }

  /// Get all active v3 passengers + their requests for today
  static List<Map<String, dynamic>> getKombinovaniPutniciDanas() {
    final nowIso = DateTime.now().toIso8601String().split('T')[0];
    final rm = V3MasterRealtimeManager.instance;

    final rez = <Map<String, dynamic>>[];

    // 1. Pronađi sve zahteve za danas
    final danasnjiZahtevi = rm.zahteviCache.values.where((z) => z['datum'] == nowIso && z['aktivno'] == true).toList();

    // 2. Za svaki zahtev nađi putnika
    for (final z in danasnjiZahtevi) {
      final pid = z['putnik_id'];
      final pData = rm.putniciCache[pid];
      if (pData != null && pData['aktivna'] == true) {
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
        .v3StreamFromCache(tables: ['v3_putnici', 'v3_zahtevi'], build: () => getKombinovaniPutniciDanas());
  }

  /// Get active v3 passengers + their requests for today, filtered by city and time
  static List<Map<String, dynamic>> getKombinovaniPutniciFiltrirano({
    required String grad,
    required String vreme,
  }) {
    final nowIso = DateTime.now().toIso8601String().split('T')[0];
    final rm = V3MasterRealtimeManager.instance;

    final rez = <Map<String, dynamic>>[];

    final filtriraniZahtevi = rm.zahteviCache.values.where((z) {
      final isDanas = z['datum'] == nowIso;
      final isAktivno = z['aktivno'] == true;
      final isGrad = z['grad'] == grad;
      final isVreme = z['zeljeno_vreme'] == vreme;
      return isDanas && isAktivno && isGrad && isVreme;
    }).toList();

    for (final z in filtriraniZahtevi) {
      final pid = z['putnik_id'];
      final pData = rm.putniciCache[pid];
      if (pData != null && pData['aktivna'] == true) {
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
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_putnici', 'v3_zahtevi'], build: () => getKombinovaniPutniciFiltrirano(grad: grad, vreme: vreme));
  }
}
