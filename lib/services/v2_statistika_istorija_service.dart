import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_statistika_istorija.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';

/// Servis za upravljanje istorijom vožnji
/// MINIMALNA tabela: putnik_id, datum, tip (voznja/otkazivanje/uplata), iznos, vozac_id
/// ? TRAJNO REŠENJE: Sve statistike se citaju iz ove tabele
class V2StatistikaIstorijaService {
  static SupabaseClient get _supabase => supabase;

  /// ?? STATISTIKE ZA POPIS - Broj vožnji, otkazivanja i uplata po vozacu za odredeni datum
  /// Vraca mapu: {voznje: X, otkazivanja: X, uplate: X, pazar: X.X}
  static Future<Map<String, dynamic>> getStatistikePoVozacu({required String vozacIme, required DateTime datum}) async {
    int voznje = 0;
    int otkazivanja = 0;
    int naplaceniDnevni = 0;
    int naplaceniMesecni = 0;
    double pazar = 0.0;

    try {
      // Dohvati UUID vozaca
      final vozacUuid = VozacCache.getUuidByIme(vozacIme);
      if (vozacUuid == null || vozacUuid.isEmpty) {
        return {'voznje': 0, 'otkazivanja': 0, 'uplate': 0, 'mesecne': 0, 'pazar': 0.0};
      }

      final datumStr = datum.toIso8601String().split('T')[0];

      final response = await _supabase
          .from('v2_statistika_istorija')
          .select('tip, iznos')
          .eq('vozac_id', vozacUuid)
          .eq('datum', datumStr)
          .limit(100);

      for (final record in response) {
        final tip = record['tip'] as String?;
        final iznos = (record['iznos'] as num?)?.toDouble() ?? 0;

        switch (tip) {
          case 'voznja':
            voznje++;
            break;
          case 'otkazivanje':
            otkazivanja++;
            break;
          case 'uplata':
            // STARI TIP PRE MIGRACIJE (sada više ne bi trebao da postoji, ali za svaki slucaj)
            // Pretpostavljamo da je 'uplata' bila dnevna ako je iznos manji od np. 2000?
            // Ili ga brojimo u dnevne.
            naplaceniDnevni++;
            pazar += iznos;
            break;
          case 'uplata_dnevna':
            naplaceniDnevni++;
            pazar += iznos;
            break;
          case 'uplata_mesecna':
            naplaceniMesecni++;
            pazar += iznos;
            break;
        }
      }
    } catch (e) {
      // Greška - vrati prazne statistike
    }

    return {
      'voznje': voznje,
      'otkazivanja': otkazivanja,
      'uplate': naplaceniDnevni, // Dnevne naplate
      'mesecne': naplaceniMesecni, // Mesecne naplate
      'pazar': pazar,
    };
  }

  /// ?? DETALJI O AKTIVNOSTIMAG ZA PROVERU
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
        // ? NOVO: Koristi dedicirane kolone umesto meta JSONB
        final gradKey = GradAdresaValidator.normalizeGrad(grad);
        query = query.eq('grad', gradKey);
      }
      if (vreme != null) {
        final normVreme = GradAdresaValidator.normalizeTime(vreme);
        query = query.eq('vreme', normVreme);
      }

      return await query.maybeSingle();
    } catch (e) {
      return null;
    }
  }

  /// Dodaj uplatu za putnika
  static Future<void> dodajUplatu({
    required String putnikId,
    required DateTime datum,
    required double iznos,
    String? vozacId,
    String? vozacImeParam, // ? direktan fallback ako UUID lookup ne uspe
    int? placeniMesec,
    int? placenaGodina,
    String tipUplate = 'uplata',
    String? tipPlacanja,
    String? status,
    String? grad,
    String? vreme,
  }) async {
    // ? NOVO: Koristimo dedicirane kolone umesto meta JSONB
    final String? gradKod = grad != null ? GradAdresaValidator.normalizeGrad(grad) : null;
    final String? vremeNormalizovano = vreme != null ? GradAdresaValidator.normalizeTime(vreme) : null;

    // Dohvati vozac_ime direktno iz baze (garantovano)
    String? vozacIme;
    if (vozacId != null && vozacId.isNotEmpty) {
      // Prvo pokušaj iz lokalnog cache-a (brže, bez mrežnog zahteva)
      vozacIme = VozacCache.getImeByUuid(vozacId);
      // Ako nije u cache-u, dohvati iz baze
      if (vozacIme == null || vozacIme.isEmpty) {
        try {
          final vozacData = await _supabase.from('v2_vozaci').select('ime').eq('id', vozacId).maybeSingle();
          vozacIme = vozacData?['ime'] as String?;
          debugPrint('🔍 [dodajUplatu] vozacId=$vozacId → vozac_ime=$vozacIme');
        } catch (e) {
          debugPrint('❌ Greška pri dohvatanju vozac_ime: $e');
        }
      }
      // ? Poslednji fallback: direktno prosledeno ime
      if ((vozacIme == null || vozacIme.isEmpty) && vozacImeParam != null && vozacImeParam.isNotEmpty) {
        vozacIme = vozacImeParam;
      }
    } else if (vozacImeParam != null && vozacImeParam.isNotEmpty) {
      vozacIme = vozacImeParam;
      debugPrint('ℹ️ [dodajUplatu] vozacId NULL, koristim vozacImeParam=$vozacIme');
    } else {
      debugPrint('⚠️ [dodajUplatu] vozacId je NULL ili prazan!');
    }

    final datumObj = datum;
    await _supabase.from('v2_statistika_istorija').insert({
      'putnik_id': putnikId,
      'datum': datumObj.toIso8601String().split('T')[0],
      'tip': tipUplate,
      'iznos': iznos,
      'vozac_id': vozacId,
      'vozac_ime': vozacIme,
      'grad': gradKod,
      'vreme': vremeNormalizovano,
      'placeni_mesec': placeniMesec ?? datumObj.month,
      'placena_godina': placenaGodina ?? datumObj.year,
    });
  }

  /// ? TRAJNO REŠENJE: Stream pazara po vozacima (realtime)
  static Stream<Map<String, double>> streamPazarPoVozacima({required DateTime from, required DateTime to}) {
    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];

    // ? FIX: Filtriraj stream UVEK po datumu - koristi filter za range
    Stream<List<Map<String, dynamic>>> query;
    if (fromStr == toStr) {
      // Isti dan - koristi eq filter
      query = _supabase.from('v2_statistika_istorija').stream(primaryKey: ['id']).eq('datum', fromStr).limit(500);
    } else {
      // Razliciti dani - ucitaj sve i filtriraj u kodu
      // NOTE: Supabase stream ne podržava gte/lte, trebajmo filter u map()
      query = _supabase
          .from('v2_statistika_istorija')
          .stream(primaryKey: ['id'])
          .order('datum', ascending: false)
          .limit(500);
    }

    return query.map((records) {
      final Map<String, double> pazar = {};
      double ukupno = 0;

      for (final record in records) {
        final log = V2StatistikaIstorija.fromJson(record);

        // Filtriraj po tipu i datumu
        if (log.tip != 'uplata' && log.tip != 'uplata_mesecna' && log.tip != 'uplata_dnevna' && log.tip != 'placanje') {
          continue;
        }

        final logDatumStr = log.datum?.toIso8601String().split('T')[0];
        if (logDatumStr == null) continue;
        if (logDatumStr.compareTo(fromStr) < 0 || logDatumStr.compareTo(toStr) > 0) continue;

        final vozacId = log.vozacId;
        final iznos = log.iznos;

        if (iznos <= 0) continue;

        // Konvertuj UUID u ime vozaca - PRVO iz vozac_ime kolone, pa iz cache-a
        // ? FIX: nikad ne preskacemo uplatu ako postoji vozac_id ž koristimo UUID kao fallback kljuc
        String vozacIme = record['vozac_ime'] as String? ?? '';
        if (vozacIme.isEmpty && vozacId != null && vozacId.isNotEmpty) {
          vozacIme = VozacCache.getImeByUuid(vozacId) ?? vozacId;
        }
        if (vozacIme.isEmpty) continue;

        pazar[vozacIme] = (pazar[vozacIme] ?? 0) + iznos;
        ukupno += iznos;
      }

      pazar['_ukupno'] = ukupno;
      return pazar;
    });
  }

  /// ?? LOGOVANJE GENERICKE AKCIJE
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

      // ? Koristimo dedicirane kolone umesto meta JSONB
      final String? gradKod = grad != null ? GradAdresaValidator.normalizeGrad(grad) : null;
      final String? vremeNormalizovano = vreme != null ? GradAdresaValidator.normalizeTime(vreme) : null;

      // Dohvati vozac_ime iz cache-a (bez async DB query)
      // Fallback: DB trigger sync_vozac_ime_on_log ce popuniti ako ostane null
      String? vozacIme = vozacImeOverride;
      if (vozacIme == null && vozacId != null && vozacId.isNotEmpty) {
        vozacIme = VozacCache.getImeByUuid(vozacId);
      }

      final datumParsed = DateTime.tryParse(datumStr);
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
      debugPrint('❌ Greška pri logovanju akcije ($tip): $e\n$stack');
    }
  }

  /// ?? LOGOVANJE POTVRDE ZAHTEVA (Kada sistem ili admin potvrdi pending zahtev)
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

  /// ? LOGOVANJE GREŠKE PRI OBRADI ZAHTEVA
  static Future<void> logGreska({
    String? putnikId, // ?? Može biti null za nove putnike koji nisu još sacuvani
    required String greska,
  }) async {
    return logGeneric(tip: 'greska_aplikacije', putnikId: putnikId, detalji: 'Greška: $greska');
  }

  /// ?? Cisti realtime subscription
  static void dispose() {}
}
