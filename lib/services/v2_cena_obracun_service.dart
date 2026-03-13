import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';

/// Servis za obraÄun meseÄne cene za putnike
///
/// PRAVILA: Cena se MORA manuelno postaviti od strane admina - viÅ¡e nema default cena!
/// - RADNIK: Admin postavlja cenu (nema default-a)
/// - UÄŒENIK: Admin postavlja cenu (nema default-a)
/// - DNEVNI: Admin postavlja cenu (nema default-a)
/// - POÅ ILJKA: Admin postavlja cenu (osim "ZUBI" koji ima fiksnih 300 RSD)
class V2CenaObracunService {
  V2CenaObracunService._();

  /// Dobija cenu po danu za putnika (SAMO custom cena)
  static double getCenaPoDanu(V2RegistrovaniPutnik v2Putnik) {
    if ((v2Putnik.cena ?? 0) > 0) {
      return v2Putnik.cena!;
    }
    return 0.0;
  }

  /// Masovni obraÄun jedinica za listu putnika (optimizovano - jedan upit)
  ///
  /// [putnici] - Lista [V2RegistrovaniPutnik] objekata za obraÄun
  /// [mesec] - Mesec za koji se raÄuna (1â€“12)
  /// [godina] - Godina za koju se raÄuna
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
      final response = await supabase
          .from('v3_putnici_arhiva')
          .select('datum, broj_mesta, putnik_id')
          .inFilter('putnik_id', ids)
          .eq('tip', 'voznja')
          .gte('datum', pocetakMeseca.toIso8601String().split('T')[0])
          .lte('datum', krajMeseca.toIso8601String().split('T')[0]);

      final Map<String, int> rezultati = {for (var p in putnici) p.id: 0};

      // GrupiÅ¡i rekorde po putniku
      final Map<String, List<Map<String, dynamic>>> grupisanRekordi = {};
      for (final r in response) {
        final pid = r['putnik_id'] as String?;
        if (pid == null) continue;
        grupisanRekordi.putIfAbsent(pid, () => []).add(r);
      }

      for (final p in putnici) {
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
          // Za ostale (Radnik/UÄenik) brojimo unikatne dane i uzimamo MAX mesta po danu
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
      debugPrint('[V2CenaObracunService] prebrojJediniceMasovno greÅ¡ka: $e');
      return {};
    }
  }
}
