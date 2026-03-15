import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_vozac.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 passengers (unified `v3_putnici` table).
class V3PutnikService {
  V3PutnikService._();

  static V3Vozac? currentVozac;
  static Map<String, dynamic>? currentPutnik;

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

  static Future<void> addUpdatePutnik(V3Putnik putnik) async {
    try {
      final data = putnik.toJson();

      await supabase.from('v3_putnici').upsert(data);
    } catch (e) {
      debugPrint('[V3PutnikService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivatePutnik(String id) async {
    try {
      await supabase.from('v3_putnici').update({'aktivno': false}).eq('id', id);
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

  /// Streams V3 passengers who have an active request for a specific date.
  static Stream<List<V3Putnik>> streamPutniciByDatum({required String datumIso}) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_putnici', 'v3_zahtevi'],
      build: () {
        final rm = V3MasterRealtimeManager.instance;
        final matchingZahtevi = rm.zahteviCache.values.where((z) {
          final rDatum = (z['datum'] as String? ?? '').split('T')[0];
          return rDatum == datumIso && z['aktivno'] == true;
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
    return cache.where((p) => p['aktivna'] == true).map((p) => V3Putnik.fromJson(p)).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
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
      final rDatum = (z['datum'] as String? ?? '').split('T')[0];
      return rDatum == datumIso &&
          z['grad'] == grad &&
          z['zeljeno_vreme'] == vreme &&
          z['aktivno'] == true &&
          z['status'] != 'otkazano' &&
          z['status'] != 'odbijeno';
    });

    for (final z in zahtevi) {
      final pid = z['putnik_id']?.toString() ?? '';
      if (rez.containsKey(pid)) continue;
      final pData = rm.putniciCache[pid];
      if (pData != null && pData['aktivna'] == true) {
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
