import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_dnevna_predaja.dart';

/// Servis za tabelu v2_dnevna_predaja
/// Čuva koliko je vozač predao novca za određeni dan.
class V2DnevnaPredajaService {
  V2DnevnaPredajaService._();

  static const String _tabela = 'v2_dnevna_predaja';

  /// Dohvati predaju za vozača i datum.
  /// Vraća null ako zapis ne postoji.
  static Future<V2DnevnaPredaja?> get({
    required String vozacIme,
    required DateTime datum,
  }) async {
    try {
      final row = await supabase
          .from(_tabela)
          .select()
          .eq('vozac_ime', vozacIme)
          .eq('datum', V2DnevnaPredaja.datumStr(datum))
          .maybeSingle();
      if (row == null) return null;
      return V2DnevnaPredaja.fromJson(row);
    } catch (e) {
      debugPrint('[V2DnevnaPredajaService] get greška: $e');
      return null;
    }
  }

  /// Upsert — kreira ili ažurira predaju za vozača i datum.
  /// Vraća true ako je uspješno.
  static Future<bool> upsert({
    required String vozacIme,
    required DateTime datum,
    required double predaoIznos,
    double? ukupnoNaplaceno,
  }) async {
    try {
      final razlika = ukupnoNaplaceno != null ? predaoIznos - ukupnoNaplaceno : null;
      await supabase.from(_tabela).upsert(
        {
          'vozac_ime': vozacIme,
          'datum': V2DnevnaPredaja.datumStr(datum),
          'predao_iznos': predaoIznos,
          if (ukupnoNaplaceno != null) 'ukupno_naplaceno': ukupnoNaplaceno,
          if (razlika != null) 'razlika': razlika,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'vozac_ime,datum',
      );
      return true;
    } catch (e) {
      debugPrint('[V2DnevnaPredajaService] upsert greška: $e');
      return false;
    }
  }

  /// Lista svih predaja za određeni datum (svi vozači).
  static Future<List<V2DnevnaPredaja>> getByDatum(DateTime datum) async {
    try {
      final rows = await supabase.from(_tabela).select().eq('datum', V2DnevnaPredaja.datumStr(datum));
      return rows.map((r) => V2DnevnaPredaja.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2DnevnaPredajaService] getByDatum greška: $e');
      return [];
    }
  }

  /// Lista svih predaja za vozača (sve dane).
  static Future<List<V2DnevnaPredaja>> getByVozac(String vozacIme) async {
    try {
      final rows = await supabase.from(_tabela).select().eq('vozac_ime', vozacIme).order('datum', ascending: false);
      return rows.map((r) => V2DnevnaPredaja.fromJson(r)).toList();
    } catch (e) {
      debugPrint('[V2DnevnaPredajaService] getByVozac greška: $e');
      return [];
    }
  }
}
