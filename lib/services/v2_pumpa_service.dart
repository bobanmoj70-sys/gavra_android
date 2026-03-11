import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_pumpa_config.dart';
import '../models/v2_pumpa_punjenje.dart';
import '../models/v2_pumpa_tocenje.dart';
import 'realtime/v2_master_realtime_manager.dart';

// =============================================================================
// v2_pumpa_service.dart
// Spoj 3 servisa: pumpa_config, pumpa_punjenja, pumpa_tocenja.
// Sva 3 klasa su zadržana bez izmene javnog API-ja.
// =============================================================================

// ---------------------------------------------------------------------------
// V2PumpaConfigService
// ---------------------------------------------------------------------------

/// Servis za tabelu v2_pumpa_config (konfiguracija kućne pumpe)
class V2PumpaConfigService {
  V2PumpaConfigService._();

  static const String tabela = 'v2_pumpa_config';

  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvati konfiguraciju pumpe — čita iz RM cache-a (0 DB upita)
  static V2PumpaConfig? getConfig() {
    final row = _rm.pumpaCache.values.firstOrNull;
    if (row == null) return null;
    return V2PumpaConfig.fromJson(row);
  }

  /// Ažuriraj konfiguraciju pumpe
  static Future<bool> updateConfig({
    double? kapacitet,
    double? alarmNivo,
    double? pocetnoStanje,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (kapacitet != null) data['kapacitet_litri'] = kapacitet;
      if (alarmNivo != null) data['alarm_nivo'] = alarmNivo;
      if (pocetnoStanje != null) data['pocetno_stanje'] = pocetnoStanje;

      await supabase.from(tabela).update(data);
      // Patch cache za sve redove (pumpa ima samo 1 red)
      final id = _rm.pumpaCache.keys.firstOrNull;
      if (id != null) _rm.v2PatchCache(tabela, id, data);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaConfigService] updateConfig greška: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// V2PumpaPunjenjaService
// ---------------------------------------------------------------------------

/// Servis za tabelu v2_pumpa_punjenja (nabavka goriva u kućnu pumpu)
class V2PumpaPunjenjaService {
  V2PumpaPunjenjaService._();

  static const String tabela = 'v2_pumpa_punjenja';
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvati sva punjenja iz RM cache-a — 0 DB upita, sortirana po datum DESC
  static List<V2PumpaPunjenje> getPunjenjaSync() {
    final rows = _rm.punjenjaCache.values.toList()
      ..sort((a, b) {
        final da = a['datum']?.toString() ?? '';
        final db = b['datum']?.toString() ?? '';
        final ca = a['created_at']?.toString() ?? '';
        final cb = b['created_at']?.toString() ?? '';
        final cmp = db.compareTo(da);
        return cmp != 0 ? cmp : cb.compareTo(ca);
      });
    return rows.map((r) => V2PumpaPunjenje.fromJson(r)).toList();
  }

  /// Async wrapper za kompatibilnost sa postojećim pozivima
  static Future<List<V2PumpaPunjenje>> getPunjenja({int limit = 50}) async => getPunjenjaSync().take(limit).toList();

  /// Stream punjenja — autorefresh kada se cache promijeni
  static Stream<List<V2PumpaPunjenje>> streamPunjenja({int limit = 50}) => _rm.v2StreamFromCache<List<V2PumpaPunjenje>>(
        tables: [tabela],
        build: () => getPunjenjaSync().take(limit).toList(),
      );

  /// Dodaj punjenje pumpe
  static Future<bool> addPunjenje({
    required DateTime datum,
    required double litri,
    double? cenaPoPLitru,
    String? napomena,
  }) async {
    try {
      final row = await supabase
          .from(tabela)
          .insert({
            'datum': datum.toIso8601String().split('T')[0],
            'litri': litri,
            'cena_po_litru': cenaPoPLitru,
            'ukupno_cena': (cenaPoPLitru != null) ? litri * cenaPoPLitru : null,
            'napomena': napomena,
          })
          .select()
          .single();
      _rm.v2UpsertToCache(tabela, row);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] addPunjenje greška: $e');
      return false;
    }
  }

  /// Obriši punjenje
  static Future<bool> deletePunjenje(String id) async {
    try {
      await supabase.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] deletePunjenje greška: $e');
      return false;
    }
  }

  /// Posljednja cijena po litru — iz cache-a
  static Future<double?> getPoslednaCenaPoPLitru() async {
    final rows = getPunjenjaSync();
    return rows.firstOrNull?.cenaPoPLitru;
  }
}

// ---------------------------------------------------------------------------
// V2PumpaTocenjaService
// ---------------------------------------------------------------------------

/// Servis za tabelu v2_pumpa_tocenja (točenja goriva po vozilu)
class V2PumpaTocenjaService {
  V2PumpaTocenjaService._();

  static const String tabela = 'v2_pumpa_tocenja';
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvati sva točenja iz RM cache-a — 0 DB upita, sortirana po datum DESC
  static List<V2PumpaTocenje> getTocenjaSync({String? voziloId}) {
    final rows =
        _rm.tocenjaCache.values.where((r) => voziloId == null || r['vozilo_id']?.toString() == voziloId).toList()
          ..sort((a, b) {
            final da = a['datum']?.toString() ?? '';
            final db = b['datum']?.toString() ?? '';
            final ca = a['created_at']?.toString() ?? '';
            final cb = b['created_at']?.toString() ?? '';
            final cmp = db.compareTo(da);
            return cmp != 0 ? cmp : cb.compareTo(ca);
          });
    // Enrichuj sa vozilo podacima iz vozilaCache
    return rows.map((r) {
      final voziloRow = _rm.vozilaCache[r['vozilo_id']?.toString()];
      return V2PumpaTocenje.fromJson({
        ...r,
        if (voziloRow != null)
          'v2_vozila': {
            'registarski_broj': voziloRow['registarski_broj'],
            'marka': voziloRow['marka'],
            'model': voziloRow['model'],
          },
      });
    }).toList();
  }

  /// Async wrapper za kompatibilnost sa postojećim pozivima
  static Future<List<V2PumpaTocenje>> getTocenja({int limit = 100, String? voziloId}) async =>
      getTocenjaSync(voziloId: voziloId).take(limit).toList();

  /// Stream točenja — autorefresh kada se cache promijeni
  static Stream<List<V2PumpaTocenje>> streamTocenja({int limit = 100, String? voziloId}) =>
      _rm.v2StreamFromCache<List<V2PumpaTocenje>>(
        tables: [tabela, 'v2_vozila'],
        build: () => getTocenjaSync(voziloId: voziloId).take(limit).toList(),
      );

  /// Dodaj točenje
  static Future<bool> addTocenje({
    required DateTime datum,
    required String voziloId,
    required double litri,
    int? kmVozila,
    String? napomena,
  }) async {
    try {
      final row = await supabase
          .from(tabela)
          .insert({
            'datum': datum.toIso8601String().split('T')[0],
            'vozilo_id': voziloId,
            'litri': litri,
            'km_vozila': kmVozila,
            'napomena': napomena,
          })
          .select()
          .single();
      _rm.v2UpsertToCache(tabela, row);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] addTocenje greška: $e');
      return false;
    }
  }

  /// Obriši točenje
  static Future<bool> deleteTocenje(String id) async {
    try {
      await supabase.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] deleteTocenje greška: $e');
      return false;
    }
  }

  /// Potrošnja po vozilu za period — iz cache-a
  static Future<List<Map<String, dynamic>>> getTocenjaZaStatistike({
    DateTime? od,
    DateTime? do_,
  }) async {
    final odStr = od?.toIso8601String().split('T')[0];
    final doStr = do_?.toIso8601String().split('T')[0];
    return _rm.tocenjaCache.values.where((r) {
      final d = r['datum']?.toString() ?? '';
      if (odStr != null && d.compareTo(odStr) < 0) return false;
      if (doStr != null && d.compareTo(doStr) > 0) return false;
      return true;
    }).map((r) {
      final voziloRow = _rm.vozilaCache[r['vozilo_id']?.toString()];
      return <String, dynamic>{
        ...r,
        if (voziloRow != null)
          'v2_vozila': {
            'registarski_broj': voziloRow['registarski_broj'],
            'marka': voziloRow['marka'],
            'model': voziloRow['model'],
          },
      };
    }).toList();
  }
}
