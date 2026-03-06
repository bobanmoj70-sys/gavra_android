import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_dnevna_predaja.dart';

/// Servis za tabelu v2_dnevna_predaja
/// Čuva koliko je vozač predao novca za određeni dan.
class V2DnevnaPredajaService {
  V2DnevnaPredajaService._();

  static const String _tabela = 'v2_dnevna_predaja';
  static SupabaseClient get _db => supabase;

  /// Dohvati predaju za vozača i datum.
  /// Vraća null ako zapis ne postoji.
  static Future<V2DnevnaPredaja?> get({
    required String vozacIme,
    required DateTime datum,
  }) async {
    try {
      final datumStr =
          '${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}';
      final row = await _db.from(_tabela).select().eq('vozac_ime', vozacIme).eq('datum', datumStr).maybeSingle();
      if (row == null) return null;
      return V2DnevnaPredaja.fromJson(row);
    } catch (_) {
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
      final predaja = V2DnevnaPredaja(
        id: '', // ignorisano pri upsertu
        vozacIme: vozacIme,
        datum: datum,
        predaoIznos: predaoIznos,
        ukupnoNaplaceno: ukupnoNaplaceno,
        razlika: razlika,
        updatedAt: DateTime.now(),
      );
      await _db.from(_tabela).upsert(predaja.toUpsertJson(), onConflict: 'vozac_ime,datum');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lista svih predaja za određeni datum (svi vozači).
  static Future<List<V2DnevnaPredaja>> getByDatum(DateTime datum) async {
    try {
      final datumStr =
          '${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}';
      final rows = await _db.from(_tabela).select().eq('datum', datumStr) as List;
      return rows.map((r) => V2DnevnaPredaja.fromJson(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lista svih predaja za vozača (sve dane).
  static Future<List<V2DnevnaPredaja>> getByVozac(String vozacIme) async {
    try {
      final rows = await _db.from(_tabela).select().eq('vozac_ime', vozacIme).order('datum', ascending: false) as List;
      return rows.map((r) => V2DnevnaPredaja.fromJson(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
