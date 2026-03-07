import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_putnik.dart';
import '../models/v2_registrovani_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_audit_log_service.dart';
import 'v2_putnici_service.dart';

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
      return null;
    }
  }

  /// Dodaj uplatu za putnika
  static Future<void> dodajUplatu({
    required String putnikId,
    required DateTime datum,
    required double iznos,
    String? putnikIme,
    String? putnikTabela,
    String? vozacId,
    String? vozacImeParam, // direktan fallback ako UUID lookup ne uspe
    int? placeniMesec,
    int? placenaGodina,
    String tipUplate = 'uplata',
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
      // Ako nije u VozacCache-u, pokušaj iz rm.vozaciCache — 0 DB querija
      if (vozacIme == null || vozacIme.isEmpty) {
        vozacIme = V2MasterRealtimeManager.instance.vozaciCache[vozacId]?['ime'] as String?;
        if (vozacIme != null) debugPrint('[dodajUplatu] vozacId=$vozacId -> vozac_ime=$vozacIme (iz rm.vozaciCache)');
      }
      // Poslednji fallback: direktno prosledeno ime
      if ((vozacIme == null || vozacIme.isEmpty) && vozacImeParam != null && vozacImeParam.isNotEmpty) {
        vozacIme = vozacImeParam;
      }
    } else if (vozacImeParam != null && vozacImeParam.isNotEmpty) {
      vozacIme = vozacImeParam;
    } else {}

    await _supabase.from('v2_statistika_istorija').insert({
      'putnik_id': putnikId,
      'putnik_ime': putnikIme,
      'putnik_tabela': putnikTabela,
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

    // Audit log — uplata dodana
    V2AuditLogService.log(
      tip: 'uplata_dodana',
      aktorId: vozacId,
      aktorIme: vozacIme,
      aktorTip: 'vozac',
      putnikId: putnikId,
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
      grad: gradKod,
      vreme: vremeNormalizovano,
      novo: {'iznos': iznos, 'tip': tipUplate},
      detalji: 'Uplata: ${iznos.toStringAsFixed(0)} RSD${vozacIme != null ? " od: $vozacIme" : ""}',
    );
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
      if (datumParsed == null) {}
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
    } catch (e) {}
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
      // placen može biti bool true ili string 'true' (Supabase realtime vs REST)
      final placen = row['placen'];
      if (placen != true && placen.toString() != 'true') continue;
      final datumAkcije = row['datum_akcije']?.toString();
      // datum_akcije moze doci kao "2026-03-04" ili "2026-03-04T00:00:00.000Z" — uzmi samo datum
      if (datumAkcije == null || !datumAkcije.startsWith(today)) continue;
      final iznos =
          (row['placen_iznos'] as num?)?.toDouble() ?? (double.tryParse(row['placen_iznos']?.toString() ?? '') ?? 0);
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
      if (tip != 'uplata' && tip != 'placanje') continue; // backward compat
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
        if (!controller.isClosed) controller.add({'_ukupno': 0});
      }
    }

    Future.microtask(emit);
    // Prati i polasci (pokupljen/plaćen flag) i statistika (nova uplata)
    // Debounce 150ms — skuplja brze uzastopne evente u jedan emit
    Timer? debounce;
    final sub = rm.onCacheChanged.where((t) => t == 'v2_polasci' || t == 'v2_statistika_istorija').listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 150), emit);
    });
    controller.onCancel = () {
      debounce?.cancel();
      sub.cancel();
      controller.close();
    };
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // BATCH QUERY — za prikaz stanja plaćanja za listu putnika (v2_putnici_screen)
  // ---------------------------------------------------------------------------

  /// Dohvata istorijska plaćanja za batch putnika iz tekuće godine.
  /// Vraća listu redova sa kolonama: putnik_id, iznos, placeni_mesec, placena_godina.
  static Future<List<Map<String, dynamic>>> getPlacanjaBatch({
    required List<String> putnikIds,
    required String thisYear,
  }) async {
    try {
      final rows = await _supabase
          .from('v2_statistika_istorija')
          .select('putnik_id, iznos, placeni_mesec, placena_godina')
          .inFilter('putnik_id', putnikIds)
          .inFilter('tip', ['uplata'])
          .not('placeni_mesec', 'is', null)
          .not('placena_godina', 'is', null)
          .gte('datum', '$thisYear-01-01')
          .order('datum', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // SINGLE PUTNIK — svi zapisi od početka godine (v2_putnik_profil_screen)
  // ---------------------------------------------------------------------------

  /// Dohvata sve zapise za jednog putnika od početka date godine.
  /// Vraća listu redova sa kolonama: datum, tip, iznos, placeni_mesec, placena_godina, created_at.
  static Future<List<Map<String, dynamic>>> getSveZapisiGodina({
    required String putnikId,
    required String pocetakGodineIso,
  }) async {
    try {
      final rows = await _supabase
          .from('v2_statistika_istorija')
          .select('datum, tip, iznos, placeni_mesec, placena_godina, created_at')
          .eq('putnik_id', putnikId)
          .gte('datum', pocetakGodineIso)
          .order('datum', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // LOOKUP — pretražuje sva 4 cache-a (preseljeno iz V2StatistikaService)
  // ---------------------------------------------------------------------------

  /// Vraca sve aktivne putnike iz sva 4 cache-a (radnici + ucenici + dnevni + posiljke)
  static List<V2RegistrovaniPutnik> getAllAktivniKaoModel() {
    return [
      ...V2RadniciService.getAktivne(),
      ...V2UceniciService.getAktivne(),
      ...V2DnevniService.getAktivne(),
      ...V2PosiljkeService.getAktivne(),
    ]..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Traži putnika po ID-u kroz sva 4 cache-a, sa DB fallback-om
  static Future<Map<String, dynamic>?> v2FindPutnikById(String id) async {
    final rm = V2MasterRealtimeManager.instance;
    final row = rm.v2GetPutnikById(id);
    if (row != null) return row;
    for (final tabela in [
      V2RadniciService.tabela,
      V2UceniciService.tabela,
      V2DnevniService.tabela,
      V2PosiljkeService.tabela,
    ]) {
      try {
        final res = await _supabase.from(tabela).select().eq('id', id).maybeSingle();
        if (res != null) return {...res, '_tabela': tabela};
      } catch (e) {}
    }
    return null;
  }

  /// Dohvata sva plaćanja (tip='uplata') za putnika
  static Future<List<Map<String, dynamic>>> dohvatiPlacanja(String putnikId) async {
    try {
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select(
              'id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme, created_at, placeni_mesec, placena_godina')
          .eq('putnik_id', putnikId)
          .eq('tip', 'uplata')
          .order('datum', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }

  /// Dohvata ukupno plaćeno za putnika (suma svih uplata)
  static Future<double> dohvatiUkupnoPlaceno(String putnikId) async {
    try {
      final rows =
          await _supabase.from('v2_statistika_istorija').select('iznos').eq('putnik_id', putnikId).eq('tip', 'uplata');
      double ukupno = 0.0;
      for (final row in rows) {
        ukupno += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
      return ukupno;
    } catch (e) {
      return 0.0;
    }
  }

  /// Broji vožnje (tip='voznja') za putnika u zadatom ili tekućem mesecu
  static Future<int> izracunajBrojVoznji(String putnikId, {int? mesec, int? godina}) async {
    try {
      final now = DateTime.now();
      final m = mesec ?? now.month;
      final g = godina ?? now.year;
      final mesecStart = '$g-${m.toString().padLeft(2, '0')}-01';
      final mesecEnd = DateTime(g, m + 1, 1).toIso8601String().split('T')[0];
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'voznja')
          .gte('datum', mesecStart)
          .lt('datum', mesecEnd);
      return res.length;
    } catch (e) {
      return 0;
    }
  }

  /// Broji otkazivanja (tip='otkazivanje') za putnika u zadatom ili tekućem mesecu
  static Future<int> izracunajBrojOtkazivanja(String putnikId, {int? mesec, int? godina}) async {
    try {
      final now = DateTime.now();
      final m = mesec ?? now.month;
      final g = godina ?? now.year;
      final mesecStart = '$g-${m.toString().padLeft(2, '0')}-01';
      final mesecEnd = DateTime(g, m + 1, 1).toIso8601String().split('T')[0];
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'otkazivanje')
          .gte('datum', mesecStart)
          .lt('datum', mesecEnd);
      return res.length;
    } catch (e) {
      return 0;
    }
  }

  /// Upisuje mesečno plaćanje u v2_statistika_istorija i ažurira v2_polasci
  static Future<bool> upisPlacanjaULog({
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    double? iznos,
    String? vozacIme,
    DateTime? datum,
    int? placeniMesec,
    int? placenaGodina,
  }) async {
    if (putnikId == null || iznos == null) return false;
    try {
      final rm = V2MasterRealtimeManager.instance;
      final now = datum ?? DateTime.now();
      final datumStr = now.toIso8601String().split('T')[0];
      String? vozacId;
      if (vozacIme != null) {
        vozacId = rm.vozaciCache.values.where((v) => v['ime']?.toString() == vozacIme).firstOrNull?['id']?.toString();
      }
      final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
      if (srRow != null) {
        await _supabase.from('v2_polasci').update({
          'placen': true,
          'placen_iznos': iznos,
          if (vozacId != null) 'placen_vozac_id': vozacId,
          if (vozacIme != null) 'placen_vozac_ime': vozacIme,
          'datum_akcije': datumStr,
          'placen_tip': V2Putnik.tipIzTabele(putnikTabela) ?? 'radnik',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', srRow['id'].toString());
      }
      await _supabase.from('v2_statistika_istorija').insert({
        'putnik_id': putnikId,
        'putnik_ime': putnikIme,
        'putnik_tabela': putnikTabela,
        'tip': 'uplata',
        'iznos': iznos,
        'vozac_id': vozacId,
        'vozac_ime': vozacIme,
        'datum': datumStr,
        'placeni_mesec': placeniMesec ?? now.month,
        'placena_godina': placenaGodina ?? now.year,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Audit log — uplata dodana
      V2AuditLogService.log(
        tip: 'uplata_dodana',
        aktorId: vozacId,
        aktorIme: vozacIme,
        aktorTip: 'vozac',
        putnikId: putnikId,
        putnikIme: putnikIme,
        putnikTabela: putnikTabela,
        novo: {'iznos': iznos, 'tip': 'uplata'},
        detalji: 'Uplata: ${iznos.toStringAsFixed(0)} RSD${vozacIme != null ? " od: $vozacIme" : ""}',
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
