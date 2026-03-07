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

  /// Dohvati sva punjenja (najnovija prva)
  static Future<List<V2PumpaPunjenje>> getPunjenja({int limit = 50}) async {
    try {
      final response = await supabase
          .from(tabela)
          .select('id,datum,litri,cena_po_litru,ukupno_cena,napomena,created_at')
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => V2PumpaPunjenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] getPunjenja greška: $e');
      return [];
    }
  }

  /// Dodaj punjenje pumpe
  static Future<bool> addPunjenje({
    required DateTime datum,
    required double litri,
    double? cenaPoPLitru,
    String? napomena,
  }) async {
    try {
      await supabase.from(tabela).insert({
        'datum': datum.toIso8601String().split('T')[0],
        'litri': litri,
        'cena_po_litru': cenaPoPLitru,
        'ukupno_cena': (cenaPoPLitru != null) ? litri * cenaPoPLitru : null,
        'napomena': napomena,
      });
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
      return true;
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] deletePunjenje greška: $e');
      return false;
    }
  }

  /// Posljednja cijena po litru
  static Future<double?> getPoslednaCenaPoPLitru() async {
    try {
      final response = await supabase
          .from(tabela)
          .select('cena_po_litru')
          .not('cena_po_litru', 'is', null)
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return (response['cena_po_litru'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] getPoslednaCenaPoPLitru greška: $e');
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// V2PumpaTocenjaService
// ---------------------------------------------------------------------------

/// Servis za tabelu v2_pumpa_tocenja (točenja goriva po vozilu)
class V2PumpaTocenjaService {
  V2PumpaTocenjaService._();

  static const String tabela = 'v2_pumpa_tocenja';

  /// Dohvati sva točenja (najnovija prva), opcionalno filtrirano po vozilu
  static Future<List<V2PumpaTocenje>> getTocenja({
    int limit = 100,
    String? voziloId,
  }) async {
    try {
      var query = supabase
          .from(tabela)
          .select('id,datum,vozilo_id,litri,km_vozila,napomena,created_at,v2_vozila(registarski_broj,marka,model)');

      final response = await (voziloId != null ? query.eq('vozilo_id', voziloId) : query)
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => V2PumpaTocenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] getTocenja greška: $e');
      return [];
    }
  }

  /// Dodaj točenje
  static Future<bool> addTocenje({
    required DateTime datum,
    required String voziloId,
    required double litri,
    int? kmVozila,
    String? napomena,
  }) async {
    try {
      await supabase.from(tabela).insert({
        'datum': datum.toIso8601String().split('T')[0],
        'vozilo_id': voziloId,
        'litri': litri,
        'km_vozila': kmVozila,
        'napomena': napomena,
      });
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
      return true;
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] deleteTocenje greška: $e');
      return false;
    }
  }

  /// Potrošnja po vozilu za period — raw data za statistike
  static Future<List<Map<String, dynamic>>> getTocenjaZaStatistike({
    DateTime? od,
    DateTime? do_,
  }) async {
    try {
      var query =
          supabase.from(tabela).select('vozilo_id, litri, km_vozila, v2_vozila(registarski_broj, marka, model)');

      if (od != null) query = query.gte('datum', od.toIso8601String().split('T')[0]);
      if (do_ != null) query = query.lte('datum', do_.toIso8601String().split('T')[0]);

      return List<Map<String, dynamic>>.from(await query);
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] getTocenjaZaStatistike greška: $e');
      return [];
    }
  }
}
