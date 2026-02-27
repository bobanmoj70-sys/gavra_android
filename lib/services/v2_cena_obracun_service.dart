import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/registrovani_putnik.dart';

/// 💰 Servis za obračun mesečne cene za putnike
///
/// PRAVILA: Cena se MORA manuelno postaviti od strane admina - više nema default cena!
/// - RADNIK: Admin postavlja cenu (nema default-a)
/// - UČENIK: Admin postavlja cenu (nema default-a)
/// - DNEVNI: Admin postavlja cenu (nema default-a)
/// - POŠILJKA: Admin postavlja cenu (osim "ZUBI" koji ima fiksnih 300 RSD)
class CenaObracunService {
  static SupabaseClient get _supabase => supabase;

  /// Dobija cenu po danu za putnika (SAMO custom cena)
  static double getCenaPoDanu(RegistrovaniPutnik putnik) {
    // 1. Ako ima postavljenu custom cenu - koristi je
    if (putnik.cenaPoDanu != null && putnik.cenaPoDanu! > 0) {
      return putnik.cenaPoDanu!;
    }

    final tipLower = putnik.tip.toLowerCase();
    final imeLower = putnik.putnikIme.toLowerCase();

    // 2. STROGO FIKSNE CENE samo za specijalne slučajeve
    if (tipLower == 'posiljka' && imeLower.contains('zubi')) {
      return 300.0;
    }

    // 3. Ako nema custom cene - više nema default cena, vraća 0.0
    return 0.0;
  }

  /// Dobija default cenu po danu samo na osnovu tipa (String) - VRAĆA 0.0
  static double getDefaultCenaByTip(String tip) {
    return 0.0;
  }

  /// Izračunaj mesečnu cenu za putnika na osnovu pokupljenja
  ///
  /// [putnik] - RegistrovaniPutnik objekat
  /// [mesec] - Mesec za koji se računa (1-12)
  /// Masovni obračun jedinica za listu putnika (optimizovano - jedan upit)
  static Future<Map<String, int>> prebrojJediniceMasovno({
    required List<RegistrovaniPutnik> putnici,
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
        final pid = r['putnik_id'] as String;
        grupisanRekordi.putIfAbsent(pid, () => []).add(r);
      }

      for (var p in putnici) {
        final logs = grupisanRekordi[p.id] ?? [];
        if (logs.isEmpty) continue;

        final tipLower = p.tip.toLowerCase();
        final jeDnevni = tipLower == 'dnevni';
        final jePosiljka = tipLower == 'posiljka' || tipLower == 'pošiljka';

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
          dailyMaxSeats.forEach((key, value) => totalUnits += value);
          rezultati[p.id] = totalUnits;
        }
      }
      return rezultati;
    } catch (e) {
      return {};
    }
  }
}
