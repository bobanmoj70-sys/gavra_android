import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';

/// Servis za obračun mesečne cene za putnike
///
/// PRAVILA: Cena se MORA manuelno postaviti od strane admina - više nema default cena!
/// - RADNIK: Admin postavlja cenu (nema default-a)
/// - UČENIK: Admin postavlja cenu (nema default-a)
/// - DNEVNI: Admin postavlja cenu (nema default-a)
/// - POŠILJKA: Admin postavlja cenu (osim "ZUBI" koji ima fiksnih 300 RSD)
class CenaObracunService {
  CenaObracunService._();

  static SupabaseClient get _supabase => supabase;

  /// Dobija cenu po danu za putnika (SAMO custom cena)
  static double getCenaPoDanu(V2RegistrovaniPutnik v2Putnik) {
    // 1. Ako ima postavljenu custom cenu - koristi je
    if (v2Putnik.cena != null && v2Putnik.cena! > 0) {
      return v2Putnik.cena!;
    }

    final imeLower = v2Putnik.ime.toLowerCase();

    // 2. STROGO FIKSNE CENE samo za specijalne slučajeve
    if (v2Putnik.v2Tabela == 'v2_posiljke' && imeLower.contains('zubi')) {
      return 300.0;
    }

    // 3. Ako nema custom cene - više nema default cena, vraća 0.0
    return 0.0;
  }

  /// Izračunaj mesečnu cenu za putnika na osnovu pokupljenja
  ///
  /// [V2Putnik] - V2RegistrovaniPutnik objekat
  /// [mesec] - Mesec za koji se računa (1-12)
  /// Masovni obračun jedinica za listu putnika (optimizovano - jedan upit)
  static Future<Map<String, int>> prebrojJediniceMasovno({
    required List<V2RegistrovaniPutnik> putnici,
    required int mesec,
    required int godina,
  }) async {
    if (putnici.isEmpty) return {};

    final ids = putnici.map((p) => p.id).toList();
    final pocetakMeseca = DateTime(godina, mesec, 1);
    final krajMeseca = DateTime(godina, mesec + 1, 0);

    try {
      final response = await _supabase
          .from('v2_statistika_istorija')
          .select('datum, broj_mesta, putnik_id')
          .inFilter('putnik_id', ids)
          .eq('tip', 'voznja')
          .gte('datum', pocetakMeseca.toIso8601String().split('T')[0])
          .lte('datum', krajMeseca.toIso8601String().split('T')[0]);

      final records = response as List;
      final Map<String, int> rezultati = {for (var p in putnici) p.id: 0};

      // Grupiši rekorde po putniku
      final Map<String, List<dynamic>> grupisanRekordi = {};
      for (var r in records) {
        final pid = r['putnik_id'] as String?;
        if (pid == null) continue;
        grupisanRekordi.putIfAbsent(pid, () => []).add(r);
      }

      for (var p in putnici) {
        final logs = grupisanRekordi[p.id] ?? [];
        if (logs.isEmpty) continue;

        final jeDnevni = p.v2Tabela == 'v2_dnevni';
        final jePosiljka = p.v2Tabela == 'v2_posiljke';

        if (jeDnevni || jePosiljka) {
          int totalUnits = 0;
          for (final record in logs) {
            totalUnits += (record['broj_mesta'] as num?)?.toInt() ?? 1;
          }
          rezultati[p.id] = totalUnits;
        } else {
          // Za ostale (Radnik/Učenik) brojimo unikatne dane i uzimamo MAX mesta po danu
          final Map<String, int> dailyMaxSeats = {};
          for (final record in logs) {
            final datumStr = record['datum'] as String?;
            if (datumStr != null) {
              final datum = datumStr.split('T')[0];
              final bm = (record['broj_mesta'] as num?)?.toInt() ?? 1;
              if (bm > (dailyMaxSeats[datum] ?? 0)) {
                dailyMaxSeats[datum] = bm;
              }
            }
          }
          int totalUnits = 0;
          for (final value in dailyMaxSeats.values) {
            totalUnits += value;
          }
          rezultati[p.id] = totalUnits;
        }
      }
      return rezultati;
    } catch (e) {
      debugPrint('CenaObracunService.prebrojJediniceMasovno error: $e');
      return {};
    }
  }
}
