import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Jedinstveni servis za sve 4 putničke tabele profila:
/// v2_radnici, v2_ucenici, v2_dnevni, v2_posiljke
///
/// Zajednički CRUD i stream metode primaju [tabela] kao parametar.
/// Specifični create metodi za svaku tabelu enkapsuliraju različite kolone.
class V2ProfilService {
  V2ProfilService._();

  static SupabaseClient get _supabase => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  static Map<String, dynamic> _cacheForTabela(String tabela) {
    switch (tabela) {
      case 'v2_radnici':
        return _rm.radniciCache;
      case 'v2_ucenici':
        return _rm.uceniciCache;
      case 'v2_dnevni':
        return _rm.dnevniCache;
      case 'v2_posiljke':
        return _rm.posiljkeCache;
      default:
        throw ArgumentError('Nepoznata tabela: $tabela');
    }
  }

  // ---------------------------------------------------------------------------
  // CITANJE — iz RM cache-a (sync, 0 DB upita)
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne putnike iz date tabele
  static List<V2RegistrovaniPutnik> getAktivne(String tabela) {
    return _cacheForTabela(tabela)
        .values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => _fromRow(r, tabela))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dohvata sve putnike iz date tabele (uključujući neaktivne)
  static List<V2RegistrovaniPutnik> getSve(String tabela) {
    return _cacheForTabela(tabela).values.map((r) => _fromRow(r, tabela)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dohvata putnika po ID-u iz date tabele
  static V2RegistrovaniPutnik? getById(String id, String tabela) {
    final row = _cacheForTabela(tabela)[id];
    if (row == null) return null;
    return _fromRow(row, tabela);
  }

  /// Dohvata ime putnika po ID-u iz date tabele
  static String? getImeById(String id, String tabela) {
    return _cacheForTabela(tabela)[id]?['ime']?.toString();
  }

  /// Pronalazi putnika po PIN-u (za autentifikaciju)
  static V2RegistrovaniPutnik? getByPin(String pin, String tabela) {
    try {
      final row = _cacheForTabela(tabela).values.firstWhere(
            (r) => r['pin'] == pin && r['status'] == 'aktivan',
          );
      return _fromRow(row, tabela);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // AZURIRANJE / BRISANJE — genericke metode za sve tabele
  // ---------------------------------------------------------------------------

  /// Ažurira putnika u datoj tabeli
  static Future<bool> update(String id, String tabela, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from(tabela).update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2ProfilService] update ($tabela) error: $e');
      return false;
    }
  }

  /// Menja status putnika (aktivan/neaktivan/bolovanje/godisnji)
  static Future<bool> setStatus(String id, String tabela, String status) async {
    return update(id, tabela, {'status': status});
  }

  /// Brise putnika iz date tabele (trajno)
  static Future<bool> delete(String id, String tabela) async {
    try {
      await _supabase.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2ProfilService] delete ($tabela) error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // STREAM — emituje direktno iz RM cache-a
  // ---------------------------------------------------------------------------

  /// Stream aktivnih putnika iz date tabele (realtime, 0 DB upita)
  static Stream<List<V2RegistrovaniPutnik>> streamAktivne(String tabela) {
    final controller = StreamController<List<V2RegistrovaniPutnik>>.broadcast();

    void emit() {
      if (!controller.isClosed) controller.add(getAktivne(tabela));
    }

    Future.microtask(emit);
    // tabela je statička — kanal je uvijek otvoren, onCacheChanged je dovoljan
    final cacheSub = _rm.onCacheChanged.where((t) => t == tabela).listen((_) => emit());
    controller.onCancel = () {
      cacheSub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // CREATE — specificne metode po tabeli (razlicite kolone)
  // ---------------------------------------------------------------------------

  /// Kreira novog radnika (v2_radnici)
  static Future<V2RegistrovaniPutnik?> createRadnik({
    required String ime,
    String? telefon,
    String? telefon2,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cenaPosDanu,
    int? brojMesta,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_radnici')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_2': telefon2,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'pin': pin,
            'email': email,
            'cena_po_danu': cenaPosDanu,
            'broj_mesta': brojMesta,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row, 'v2_radnici');
    } catch (e) {
      debugPrint('[V2ProfilService] createRadnik error: $e');
      return null;
    }
  }

  /// Kreira novog ucenika (v2_ucenici)
  static Future<V2RegistrovaniPutnik?> createUcenik({
    required String ime,
    String? telefon,
    String? telefonOca,
    String? telefonMajke,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cenaPosDanu,
    int? brojMesta,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_ucenici')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_oca': telefonOca,
            'telefon_majke': telefonMajke,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'pin': pin,
            'email': email,
            'cena_po_danu': cenaPosDanu,
            'broj_mesta': brojMesta,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row, 'v2_ucenici');
    } catch (e) {
      debugPrint('[V2ProfilService] createUcenik error: $e');
      return null;
    }
  }

  /// Kreira novog dnevnog putnika (v2_dnevni)
  static Future<V2RegistrovaniPutnik?> createDnevni({
    required String ime,
    String? telefon,
    String? telefon2,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_dnevni')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_2': telefon2,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'cena': cena,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row, 'v2_dnevni');
    } catch (e) {
      debugPrint('[V2ProfilService] createDnevni error: $e');
      return null;
    }
  }

  /// Kreira novu posiljku (v2_posiljke)
  static Future<V2RegistrovaniPutnik?> createPosiljka({
    required String ime,
    String? telefon,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_posiljke')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'cena': cena,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row, 'v2_posiljke');
    } catch (e) {
      debugPrint('[V2ProfilService] createPosiljka error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HELPER
  // ---------------------------------------------------------------------------

  static V2RegistrovaniPutnik _fromRow(Map<String, dynamic> r, String tabela) {
    return V2RegistrovaniPutnik.fromMap({...r, '_tabela': tabela});
  }

  // ---------------------------------------------------------------------------
  // LOOKUP — svi cache-ovi objedinjeno
  // ---------------------------------------------------------------------------

  /// Vraca sve aktivne putnike iz sva 4 cache-a kao modele (0 DB upita)
  static List<V2RegistrovaniPutnik> getAllAktivniKaoModel() {
    return _rm
        .getAllPutnici()
        .where((r) => r['status'] == 'aktivan')
        .map((r) => _fromRow(r, r['_tabela']?.toString() ?? 'v2_radnici'))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Trazi putnika po ID-u kroz sva 4 cache-a, vraca raw Map (za V2RegistrovaniPutnik.fromMap)
  static Future<Map<String, dynamic>?> findPutnikById(String id) async {
    final row = _rm.getPutnikById(id);
    if (row != null) return row;
    // Fallback: direktan DB upit ako nije u cache-u
    for (final tabela in ['v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke']) {
      try {
        final res = await _supabase.from(tabela).select().eq('id', id).maybeSingle();
        if (res != null) return {...res, '_tabela': tabela};
      } catch (e) {
        debugPrint('[V2ProfilService] findPutnikById fallback ($tabela) error: $e');
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // STATISTIKA — cita iz v2_statistika_istorija
  // ---------------------------------------------------------------------------

  /// Dohvata sva placanja (tip='uplata') za putnika
  static Future<List<Map<String, dynamic>>> dohvatiPlacanja(String putnikId) async {
    try {
      // Pokusaj iz cache-a prvo
      final izCache = _rm.statistikaCache.values
          .where((r) => r['putnik_id']?.toString() == putnikId && r['tip'] == 'uplata')
          .toList();
      if (izCache.isNotEmpty) return izCache;
      // Fallback: DB upit za sve datume
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select(
              'id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme, created_at, placeni_mesec, placena_godina')
          .eq('putnik_id', putnikId)
          .eq('tip', 'uplata')
          .order('datum', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[V2ProfilService] dohvatiPlacanja error: $e');
      return [];
    }
  }

  /// Broji vožnje (tip='voznja') za putnika u tekućem mjesecu
  static Future<int> izracunajBrojVoznji(String putnikId) async {
    try {
      final now = DateTime.now();
      final mesecStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'voznja')
          .gte('datum', mesecStart);
      return res.length;
    } catch (e) {
      debugPrint('[V2ProfilService] izracunajBrojVoznji error: $e');
      return 0;
    }
  }

  /// Broji otkazivanja (tip='otkazivanje') za putnika u tekucem mjesecu
  static Future<int> izracunajBrojOtkazivanja(String putnikId) async {
    try {
      final now = DateTime.now();
      final mesecStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final res = await _supabase
          .from('v2_statistika_istorija')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('tip', 'otkazivanje')
          .gte('datum', mesecStart);
      return res.length;
    } catch (e) {
      debugPrint('[V2ProfilService] izracunajBrojOtkazivanja error: $e');
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
      // Upisi u v2_polasci (operativna — opcionalno, samo ako postoji polazak danas)
      final srRow = _rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
      if (srRow != null) {
        await _supabase.from('v2_polasci').update({
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

      // Upisi u v2_statistika_istorija (arhiva — uvijek, i retroaktivna plaćanja)
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
      return true;
    } catch (e) {
      debugPrint('[V2ProfilService] upisPlacanjaULog error: $e');
      return false;
    }
  }
}
