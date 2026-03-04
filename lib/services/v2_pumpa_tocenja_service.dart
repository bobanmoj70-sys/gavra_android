import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_pumpa_tocenje.dart';

/// Servis za tabelu v2_pumpa_tocenja (točenja goriva po vozilu)
class V2PumpaTocenjaService {
  V2PumpaTocenjaService._();

  static const String tabela = 'v2_pumpa_tocenja';

  static SupabaseClient get _db => supabase;

  /// Dohvati sva točenja (najnovija prva), opcionalno filtrirano po vozilu
  static Future<List<V2PumpaTocenje>> getTocenja({
    int limit = 100,
    String? voziloId,
  }) async {
    try {
      var query = _db.from(tabela).select('id,datum,vozilo_id,litri,km_vozila,napomena,created_at');

      final response = await (voziloId != null ? query.eq('vozilo_id', voziloId) : query)
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => V2PumpaTocenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] getTocenja error: $e');
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
      await _db.from(tabela).insert({
        'datum': datum.toIso8601String().split('T')[0],
        'vozilo_id': voziloId,
        'litri': litri,
        'km_vozila': kmVozila,
        'napomena': napomena,
      });
      debugPrint('[V2PumpaTocenjaService] Tocenje dodato: $litri L za vozilo $voziloId');
      return true;
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] addTocenje error: $e');
      return false;
    }
  }

  /// Obriši točenje
  static Future<bool> deleteTocenje(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] deleteTocenje error: $e');
      return false;
    }
  }

  /// Potrošnja po vozilu za period — raw data za statistike
  static Future<List<Map<String, dynamic>>> getTocenjaZaStatistike({
    DateTime? od,
    DateTime? do_,
  }) async {
    try {
      var query = _db.from(tabela).select('vozilo_id, litri, km_vozila, v2_vozila(registarski_broj, marka, model)');

      if (od != null) query = query.gte('datum', od.toIso8601String().split('T')[0]);
      if (do_ != null) query = query.lte('datum', do_.toIso8601String().split('T')[0]);

      return List<Map<String, dynamic>>.from(await query);
    } catch (e) {
      debugPrint('[V2PumpaTocenjaService] getTocenjaZaStatistike error: $e');
      return [];
    }
  }
}
