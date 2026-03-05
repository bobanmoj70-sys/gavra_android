import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_putnici_service.dart';

/// Servis za statistiku, plaćanja i lookup putnika kroz sve tabele.
class V2StatistikaService {
  V2StatistikaService._();

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  // ---------------------------------------------------------------------------
  // LOOKUP — pretražuje sva 4 cache-a
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
  static Future<Map<String, dynamic>?> findPutnikById(String id) async {
    final row = _rm.getPutnikById(id);
    if (row != null) return row;
    // Fallback: direktan DB upit ako nije u cache-u
    for (final tabela in [
      V2RadniciService.tabela,
      V2UceniciService.tabela,
      V2DnevniService.tabela,
      V2PosiljkeService.tabela,
    ]) {
      try {
        final res = await _db.from(tabela).select().eq('id', id).maybeSingle();
        if (res != null) return {...res, '_tabela': tabela};
      } catch (e) {
        debugPrint('[V2StatistikaService] findPutnikById fallback ($tabela) error: $e');
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PLACANJA — čita iz v2_statistika_istorija
  // ---------------------------------------------------------------------------

  /// Dohvata sva plaćanja (tip='uplata') za putnika
  static Future<List<Map<String, dynamic>>> dohvatiPlacanja(String putnikId) async {
    try {
      // Pokušaj iz cache-a prvo
      final izCache = _rm.statistikaCache.values
          .where((r) => r['putnik_id']?.toString() == putnikId && r['tip'] == 'uplata')
          .toList();
      if (izCache.isNotEmpty) return izCache;
      // Fallback: DB upit
      final res = await _db
          .from('v2_statistika_istorija')
          .select(
              'id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme, created_at, placeni_mesec, placena_godina')
          .eq('putnik_id', putnikId)
          .eq('tip', 'uplata')
          .order('datum', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[V2StatistikaService] dohvatiPlacanja error: $e');
      return [];
    }
  }

  /// Broji vožnje (tip='voznja') za putnika u tekućem mjesecu
  static Future<int> izracunajBrojVoznji(String putnikId) async {
    try {
      final now = DateTime.now();
      final mesecStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final res = await _db
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'voznja')
          .gte('datum', mesecStart);
      return res.length;
    } catch (e) {
      debugPrint('[V2StatistikaService] izracunajBrojVoznji error: $e');
      return 0;
    }
  }

  /// Broji otkazivanja (tip='otkazivanje') za putnika u tekućem mjesecu
  static Future<int> izracunajBrojOtkazivanja(String putnikId) async {
    try {
      final now = DateTime.now();
      final mesecStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final res = await _db
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'otkazivanje')
          .gte('datum', mesecStart);
      return res.length;
    } catch (e) {
      debugPrint('[V2StatistikaService] izracunajBrojOtkazivanja error: $e');
      return 0;
    }
  }

  /// Upisuje mesečno plaćanje u v2_statistika_istorija
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
      final now = datum ?? DateTime.now();
      final datumStr = now.toIso8601String().split('T')[0];
      // Pronađi vozac_id po imenu ako je dato
      String? vozacId;
      if (vozacIme != null) {
        vozacId = _rm.vozaciCache.values.where((v) => v['ime']?.toString() == vozacIme).firstOrNull?['id']?.toString();
      }
      // Ažuriraj v2_polasci ako postoji polazak za ovog putnika
      final srRow = _rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
      if (srRow != null) {
        await _db.from('v2_polasci').update({
          'placen': true,
          'placen_iznos': iznos,
          if (vozacId != null) 'placen_vozac_id': vozacId,
          if (vozacIme != null) 'placen_vozac_ime': vozacIme,
          'datum_akcije': datumStr,
          'placen_tip': const {
                'v2_radnici': 'radnik',
                'v2_ucenici': 'ucenik',
                'v2_dnevni': 'dnevni',
                'v2_posiljke': 'posiljka',
              }[putnikTabela] ??
              'radnik',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', srRow['id'].toString());
      }

      // Upiši u v2_statistika_istorija (arhiva)
      await _db.from('v2_statistika_istorija').insert({
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
      return true;
    } catch (e) {
      debugPrint('[V2StatistikaService] upisPlacanjaULog error: $e');
      return false;
    }
  }
}
