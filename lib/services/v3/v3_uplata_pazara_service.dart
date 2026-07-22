import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_uplata_pazara.dart';
import '../../utils/v3_date_utils.dart';

/// Servis za rad sa mesecnom uplatom pazara (`v3_uplata_pazara`).
class V3UplataPazaraService {
  V3UplataPazaraService._();

  /// Ucitava mesecnu evidenciju za vozaca i datum.
  static Future<V3UplataPazara?> getZaVozacaIMesec({
    required String vozacId,
    required DateTime datum,
  }) async {
    final id = vozacId.trim();
    if (id.isEmpty) return null;

    try {
      final res = await supabase
          .from('v3_uplata_pazara')
          .select()
          .eq('vozac_id', id)
          .eq('mesec', datum.month)
          .eq('godina', datum.year)
          .maybeSingle();

      if (res == null) return null;
      return V3UplataPazara.fromJson(res);
    } catch (e) {
      debugPrint('[V3UplataPazaraService] getZaVozacaIMesec error: $e');
      return null;
    }
  }

  /// Cuva ili azurira dnevnu uplatu pazara za vozaca i datum.
  static Future<void> sacuvajDnevnuUplatu({
    required String vozacId,
    required DateTime datum,
    required double predao,
    required double ukupno,
    bool zahtevanUnos = false,
  }) async {
    final id = vozacId.trim();
    if (id.isEmpty) return;

    final mesec = datum.month;
    final godina = datum.year;
    final dan = datum.day;

    debugPrint(
        '[V3UplataPazaraService] sacuvajDnevnuUplatu: vozacId=$id, dan=$dan.$mesec.$godina, predao=$predao, ukupno=$ukupno, zahtevanUnos=$zahtevanUnos');

    try {
      final existing = await supabase
          .from('v3_uplata_pazara')
          .select('id, dnevne_uplate_json')
          .eq('vozac_id', id)
          .eq('mesec', mesec)
          .eq('godina', godina)
          .maybeSingle();

      final novaUplata = V3DnevnaUplataPazara(
        dan: dan,
        predao: predao,
        ukupno: ukupno,
        razlika: predao - ukupno,
        zahtevanUnos: zahtevanUnos,
      );

      if (existing != null) {
        final uplata = V3UplataPazara.fromJson(existing);
        final updated = uplata.withUplata(novaUplata);

        debugPrint('[V3UplataPazaraService] ažuriram postojeći zapis id=${uplata.id}');
        await supabase.from('v3_uplata_pazara').update({
          'dnevne_uplate_json': updated.dnevneUplate.map((e) => e.toJson()).toList(),
          'updated_at': V3DateUtils.nowIsoUtc(),
        }).eq('id', uplata.id);
      } else {
        debugPrint('[V3UplataPazaraService] kreiram novi zapis');
        await supabase.from('v3_uplata_pazara').insert({
          'vozac_id': id,
          'mesec': mesec,
          'godina': godina,
          'dnevne_uplate_json': [novaUplata.toJson()],
        });
      }
      debugPrint('[V3UplataPazaraService] sacuvajDnevnuUplatu: uspešno');
    } catch (e) {
      debugPrint('[V3UplataPazaraService] sacuvajDnevnuUplatu error: $e');
      rethrow;
    }
  }

  /// Vraca iznos predaje za konkretan dan.
  static Future<double?> getPredaoZaDan({
    required String vozacId,
    required DateTime datum,
  }) async {
    final uplata = await getZaVozacaIMesec(vozacId: vozacId, datum: datum);
    final dnevna = uplata?.uplataZaDan(datum.day);
    if (dnevna == null) return null;
    return dnevna.predao;
  }
}
