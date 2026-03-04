import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_pumpa_punjenje.dart';

/// Servis za tabelu v2_pumpa_punjenja (nabavka goriva u kućnu pumpu)
class V2PumpaPunjenjaService {
  V2PumpaPunjenjaService._();

  static const String tabela = 'v2_pumpa_punjenja';

  static SupabaseClient get _db => supabase;

  /// Dohvati sva punjenja (najnovija prva)
  static Future<List<V2PumpaPunjenje>> getPunjenja({int limit = 50}) async {
    try {
      final response = await _db
          .from(tabela)
          .select('id,datum,litri,cena_po_litru,ukupno_cena,napomena,created_at')
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => V2PumpaPunjenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] getPunjenja error: $e');
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
      await _db.from(tabela).insert({
        'datum': datum.toIso8601String().split('T')[0],
        'litri': litri,
        'cena_po_litru': cenaPoPLitru,
        'ukupno_cena': (cenaPoPLitru != null) ? litri * cenaPoPLitru : null,
        'napomena': napomena,
      });
      debugPrint('[V2PumpaPunjenjaService] Punjenje dodato: $litri L');
      return true;
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] addPunjenje error: $e');
      return false;
    }
  }

  /// Obriši punjenje
  static Future<bool> deletePunjenje(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaPunjenjaService] deletePunjenje error: $e');
      return false;
    }
  }

  /// Posljednja cijena po litru
  static Future<double?> getPoslednaCenaPoPLitru() async {
    try {
      final response = await _db
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
      debugPrint('[V2PumpaPunjenjaService] getPoslednaCenaPoPLitru error: $e');
      return null;
    }
  }
}
