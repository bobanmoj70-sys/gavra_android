import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje istorijom vožnji.
/// Tabela: putnik_id, datum, tip (voznja/otkazivanje/uplata), iznos, vozac_id
/// Sve statistike se čitaju iz ove tabele.
class V2StatistikaIstorijaService {
  V2StatistikaIstorijaService._();

  static SupabaseClient get _supabase => supabase;

  /// Detalji o aktivnostima — provjera postojanja log zapisa.
  static Future<Map<String, dynamic>?> getLogEntry({
    required String putnikId,
    required String datum,
    required String tip,
    String? grad,
    String? vreme,
  }) async {
    try {
      var query = _supabase
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('datum', datum)
          .eq('tip', tip);

      if (grad != null) {
        final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
        query = query.eq('grad', gradKey);
      }
      if (vreme != null) {
        final normVreme = V2GradAdresaValidator.normalizeTime(vreme);
        query = query.eq('vreme', normVreme);
      }

      return await query.maybeSingle();
    } catch (e) {
      debugPrint('[V2StatistikaIstorijaService] Greška u getLogEntry: $e');
      return null;
    }
  }

  /// Dodaj uplatu za putnika
  static Future<void> dodajUplatu({
    required String putnikId,
    required DateTime datum,
    required double iznos,
    String? vozacId,
    String? vozacImeParam, // direktan fallback ako UUID lookup ne uspe
    int? placeniMesec,
    int? placenaGodina,
    String tipUplate = 'uplata_dnevna',
    String? tipPlacanja,
    String? status,
    String? grad,
    String? vreme,
  }) async {
    final String? gradKod = grad != null ? V2GradAdresaValidator.normalizeGrad(grad) : null;
    final String? vremeNormalizovano = vreme != null ? V2GradAdresaValidator.normalizeTime(vreme) : null;

    // Dohvati vozac_ime direktno iz baze (garantovano)
    String? vozacIme;
    if (vozacId != null && vozacId.isNotEmpty) {
      // Prvo pokušaj iz lokalnog cache-a (brže, bez mrežnog zahteva)
      vozacIme = V2VozacCache.getImeByUuid(vozacId);
      // Ako nije u cache-u, dohvati iz baze
      if (vozacIme == null || vozacIme.isEmpty) {
        try {
          final vozacData = await _supabase.from('v2_vozaci').select('ime').eq('id', vozacId).maybeSingle();
          vozacIme = vozacData?['ime'] as String?;
          debugPrint('[dodajUplatu] vozacId=$vozacId -> vozac_ime=$vozacIme');
        } catch (e) {
          debugPrint('[V2StatistikaIstorijaService] Greška pri dohvatanju vozac_ime: $e');
        }
      }
      // Poslednji fallback: direktno prosledeno ime
      if ((vozacIme == null || vozacIme.isEmpty) && vozacImeParam != null && vozacImeParam.isNotEmpty) {
        vozacIme = vozacImeParam;
      }
    } else if (vozacImeParam != null && vozacImeParam.isNotEmpty) {
      vozacIme = vozacImeParam;
      debugPrint('[dodajUplatu] vozacId NULL, koristim vozacImeParam=$vozacIme');
    } else {
      debugPrint('[V2StatistikaIstorijaService] dodajUplatu: vozacId je NULL ili prazan');
    }

    await _supabase.from('v2_statistika_istorija').insert({
      'putnik_id': putnikId,
      'datum': datum.toIso8601String().split('T')[0],
      'tip': tipUplate,
      'iznos': iznos,
      'vozac_id': vozacId,
      'vozac_ime': vozacIme,
      'grad': gradKod,
      'vreme': vremeNormalizovano,
      'placeni_mesec': placeniMesec ?? datum.month,
      'placena_godina': placenaGodina ?? datum.year,
    });
  }

  /// Logovanje generičke akcije u statistika_istorija tabelu.
  static Future<void> logGeneric({
    required String tip,
    String? putnikId,
    String? vozacId,
    String? vozacImeOverride, // direktno ime ako vozacId nije poznat (npr. 'V2Putnik', 'Admin')
    double iznos = 0,
    int brojMesta = 1,
    String? detalji,
    int? satiPrePolaska,
    String? tipPlacanja,
    String? status,
    String? datum, // NOVO: Mogucnost prosledivanja specificnog datuma
    String? grad,
    String? vreme,
  }) async {
    try {
      final now = DateTime.now();
      final datumStr = (datum != null && datum.isNotEmpty) ? datum : now.toIso8601String().split('T')[0];

      final String? gradKod = grad != null ? V2GradAdresaValidator.normalizeGrad(grad) : null;
      final String? vremeNormalizovano = vreme != null ? V2GradAdresaValidator.normalizeTime(vreme) : null;

      // Dohvati vozac_ime iz cache-a (bez async DB query)
      // Fallback: DB trigger sync_vozac_ime_on_log ce popuniti ako ostane null
      String? vozacIme = vozacImeOverride;
      if (vozacIme == null && vozacId != null && vozacId.isNotEmpty) {
        vozacIme = V2VozacCache.getImeByUuid(vozacId);
      }

      final datumParsed = DateTime.tryParse(datumStr);
      if (datumParsed == null) {
        debugPrint(
            '[V2StatistikaIstorijaService] logGeneric: neispravan datumStr="$datumStr", placeni_mesec/godina se nece upisati');
      }
      await _supabase.from('v2_statistika_istorija').insert({
        'tip': tip,
        'putnik_id': putnikId,
        'vozac_id': vozacId,
        'vozac_ime': vozacIme,
        'iznos': iznos,
        'datum': datumStr,
        'detalji': detalji,
        'grad': gradKod,
        'vreme': vremeNormalizovano,
        if (datumParsed != null) 'placeni_mesec': datumParsed.month,
        if (datumParsed != null) 'placena_godina': datumParsed.year,
      });
    } catch (e, stack) {
      debugPrint('[V2StatistikaIstorijaService] Greška pri logovanju akcije ($tip): $e\n$stack');
    }
  }

  /// Logovanje potvrde zahteva (kada sistem ili admin potvrdi pending zahtev).
  static Future<void> logPotvrda({
    required String putnikId,
    required String dan,
    required String vreme,
    required String grad,
    String? tipPutnika,
    String detalji = 'Zahtev potvrden',
  }) async {
    final typeStr = tipPutnika != null ? ' ($tipPutnika)' : '';
    return logGeneric(
      tip: 'potvrda_zakazivanja',
      putnikId: putnikId,
      detalji: '$detalji$typeStr: $dan u $vreme ($grad)',
      grad: grad,
      vreme: vreme,
    );
  }

  /// Logovanje greške pri obradi zahteva.
  static Future<void> logGreska({
    String? putnikId, // Može biti null za nove putnike koji nisu još sacuvani
    required String greska,
  }) async {
    return logGeneric(tip: 'greska_aplikacije', putnikId: putnikId, detalji: 'Greška: $greska');
  }

  /// Placeholder — stream se automatski gasi, eksplicitno čišćenje nije potrebno.
  static void dispose() {}

  // ──────────────────────────────────────────────────────────────────────────
  /// Agregira pazar iz polasciCache za tekuci dan (0 DB upita, realtime)
  static Map<String, double> _pazarIzPolasciCache(Iterable<Map<String, dynamic>> rows, String today) {
    final Map<String, double> pazar = {};
    double ukupno = 0;
    for (final row in rows) {
      if (row['placen'] != true) continue;
      final datumAkcije = row['datum_akcije']?.toString();
      if (datumAkcije != today) continue;
      final iznos = (row['placen_iznos'] as num?)?.toDouble() ?? 0;
      if (iznos <= 0) continue;
      final vozacIme = row['placen_vozac_ime']?.toString() ?? 'Nepoznat';
      pazar[vozacIme] = (pazar[vozacIme] ?? 0) + iznos;
      ukupno += iznos;
    }
    pazar['_ukupno'] = ukupno;
    return pazar;
  }

  // PAZAR STREAM
  // ──────────────────────────────────────────────────────────────────────────

  /// Pretvori listu redova u mapu {vozacIme: iznos, '_ukupno': ukupno}.
  static Map<String, double> _mapRowsToPazar(Iterable<Map<String, dynamic>> rows) {
    final Map<String, double> pazar = {};
    double ukupno = 0;
    for (final row in rows) {
      final tip = row['tip'] as String?;
      if (tip != 'uplata' && tip != 'uplata_dnevna' && tip != 'uplata_mesecna' && tip != 'placanje') continue;
      final iznos = (row['iznos'] as num?)?.toDouble() ?? 0;
      if (iznos <= 0) continue;
      String vozacIme = (row['vozac_ime'] as String?) ?? '';
      if (vozacIme.isEmpty) {
        final vozacId = row['vozac_id']?.toString() ?? '';
        if (vozacId.isNotEmpty) vozacIme = V2VozacCache.getImeByUuid(vozacId) ?? vozacId;
      }
      if (vozacIme.isEmpty) continue;
      pazar[vozacIme] = (pazar[vozacIme] ?? 0) + iznos;
      ukupno += iznos;
    }
    pazar['_ukupno'] = ukupno;
    return pazar;
  }

  /// Stream pazara direktno iz master cache-a (0 DB upita za današnji dan).
  /// Za ostale datume radi jednokratni DB fetch.
  /// Vraća mapu {vozacIme: iznos, '_ukupno': ukupno}
  static Stream<Map<String, double>> streamPazarIzCachea({
    required String isoDate,
  }) {
    final rm = V2MasterRealtimeManager.instance;
    final controller = StreamController<Map<String, double>>.broadcast();

    Future<void> emit() async {
      if (controller.isClosed) return;
      try {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final Map<String, double> result;
        if (isoDate == today && rm.isInitialized) {
          // Tekuci dan — citaj direktno iz polasciCache (realtime, 0 DB upita)
          result = _pazarIzPolasciCache(rm.polasciCache.values, today);
        } else {
          final rows = await supabase
              .from('v2_statistika_istorija')
              .select('tip, iznos, vozac_id, vozac_ime')
              .eq('datum', isoDate)
              .limit(500);
          result = _mapRowsToPazar(rows);
        }
        if (!controller.isClosed) controller.add(result);
      } catch (e) {
        debugPrint('[V2StatistikaIstorijaService] streamPazar greška: $e');
        if (!controller.isClosed) controller.add({'_ukupno': 0});
      }
    }

    Future.microtask(emit);
    final sub = rm.subscribe('v2_polasci').listen((_) => emit());
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }
}
