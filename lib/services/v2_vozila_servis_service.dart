import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_vozila_servis.dart';

/// Servis za tabelu v2_vozila_servis (servisna knjiga vozila)
class V2VozilaServisService {
  V2VozilaServisService._();

  static const String tabela = 'v2_vozila_servis';

  static SupabaseClient get _db => supabase;

  /// Dohvati servisnu istoriju za vozilo
  static Future<List<V2VozilaServis>> getIstorijuServisa(String voziloId) async {
    try {
      final response = await _db
          .from(tabela)
          .select('id,vozilo_id,tip,datum,km,opis,cena,pozicija,created_at')
          .eq('vozilo_id', voziloId)
          .order('datum', ascending: false);
      return (response as List).map((r) => V2VozilaServis.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2VozilaServisService] getIstorijuServisa error: $e');
      return [];
    }
  }

  /// Dodaj zapis u servisnu istoriju
  static Future<bool> addIstorijuServisa({
    required String voziloId,
    required String tip,
    DateTime? datum,
    int? km,
    String? opis,
    double? cena,
    String? pozicija,
  }) async {
    try {
      await _db.from(tabela).insert({
        'vozilo_id': voziloId,
        'tip': tip,
        'datum': datum?.toIso8601String().split('T')[0],
        'km': km,
        'opis': opis,
        'cena': cena,
        'pozicija': pozicija,
      });
      return true;
    } catch (e) {
      debugPrint('[V2VozilaServisService] addIstorijuServisa error: $e');
      return false;
    }
  }

  /// Obriši servisni zapis
  static Future<bool> deleteIstorijuServisa(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2VozilaServisService] deleteIstorijuServisa error: $e');
      return false;
    }
  }
}
