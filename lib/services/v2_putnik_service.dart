import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_statistika_istorija_service.dart';

/// Servis za upravljanje putnicima (v2_ šema)
/// Agregira sve 4 V2Putnik tabele: v2_radnici, v2_ucenici, v2_dnevni, v2_posiljke
class V2PutnikService {
  V2PutnikService({SupabaseClient? supabaseClient}) : _supabaseOverride = supabaseClient;
  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? supabase;

  static const _putnikTabele = ['v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke'];

  // ---------------------------------------------
  // CITANJE
  // ---------------------------------------------

  /// Dohvata putnika iz specificne tabele po ID-u
  Future<Map<String, dynamic>?> getPutnikById(String id, String tabela) async {
    final row = await _supabase.from(tabela).select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return {...row, '_tabela': tabela};
  }

  /// Dohvata putnika iz bilo koje od 4 tabele (pretražuje sve dok ne nade)
  Future<Map<String, dynamic>?> findPutnikById(String id) async {
    // Prvo pokušaj iz cache-a
    final cached = V2MasterRealtimeManager.instance.getPutnikById(id);
    if (cached != null) return cached;

    // Fallback: pretraži sve tabele
    for (final tabela in _putnikTabele) {
      final row = await _supabase.from(tabela).select().eq('id', id).maybeSingle();
      if (row != null) return {...row, '_tabela': tabela};
    }
    return null;
  }

  /// Dohvata sve aktivne putnike iz date tabele
  Future<List<Map<String, dynamic>>> getAktivniIzTabele(String tabela) async {
    final rows = await _supabase.from(tabela).select().neq('status', 'neaktivan').order('ime');
    return rows.map((r) => {...r, '_tabela': tabela}).toList();
  }

  /// Dohvata sve aktivne putnike iz svih 4 tabela
  Future<List<Map<String, dynamic>>> getSviAktivni() async {
    final results = <Map<String, dynamic>>[];
    for (final tabela in _putnikTabele) {
      final rows = await getAktivniIzTabele(tabela);
      results.addAll(rows);
    }
    results.sort((a, b) => (a['ime'] as String? ?? '').compareTo(b['ime'] as String? ?? ''));
    return results;
  }

  /// Vraca sve putnike iz cache-a (bez network poziva)
  List<Map<String, dynamic>> getSviIzCachea() {
    return V2MasterRealtimeManager.instance.getAllPutnici();
  }

  /// Dohvata putnika po PIN-u iz date tabele
  Future<Map<String, dynamic>?> getByPin(String pin, String tabela) async {
    final row = await _supabase.from(tabela).select().eq('pin', pin).maybeSingle();
    if (row == null) return null;
    return {...row, '_tabela': tabela};
  }

  /// Dohvata putnika po telefonu (pretražuje sve tabele)
  Future<Map<String, dynamic>?> findByTelefon(String telefon) async {
    if (telefon.isEmpty) return null;
    final normalized = _normalizePhone(telefon);

    for (final tabela in _putnikTabele) {
      final svi = await _supabase.from(tabela).select();
      for (final row in svi) {
        final t = row['telefon'] as String? ?? '';
        final t2 = row['telefon_2'] as String? ?? '';
        if ((t.isNotEmpty && _normalizePhone(t) == normalized) ||
            (t2.isNotEmpty && _normalizePhone(t2) == normalized)) {
          return {...row, '_tabela': tabela};
        }
      }
    }
    return null;
  }

  // ---------------------------------------------
  // KREIRANJE
  // ---------------------------------------------

  /// Kreira novog putnika u datoj tabeli
  Future<Map<String, dynamic>> createPutnik(
    Map<String, dynamic> data,
    String tabela,
  ) async {
    // Provjeri duplikat po telefonu ako postoji
    final telefon = data['telefon'] as String?;
    if (telefon != null && telefon.isNotEmpty) {
      final existing = await findByTelefon(telefon);
      if (existing != null) {
        final ime = existing['ime'] as String? ?? '?';
        final tab = existing['_tabela'] as String? ?? '?';
        throw Exception('V2Putnik sa ovim brojem telefona vec postoji: $ime ($tab)');
      }
    }

    data['created_at'] = DateTime.now().toUtc().toIso8601String();
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final row = await _supabase.from(tabela).insert(data).select().single();
    return {...row, '_tabela': tabela};
  }

  // ---------------------------------------------
  // AŽURIRANJE
  // ---------------------------------------------

  /// Ažurira putnika u datoj tabeli
  Future<Map<String, dynamic>> updatePutnik(
    String id,
    Map<String, dynamic> updates,
    String tabela,
  ) async {
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final row = await _supabase.from(tabela).update(updates).eq('id', id).select().single();
    return {...row, '_tabela': tabela};
  }

  /// Ažurira PIN putnika
  Future<void> updatePin(String id, String noviPin, String tabela) async {
    await _supabase.from(tabela).update({
      'pin': noviPin,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Ažurira email putnika
  Future<void> updateEmail(String id, String email, String tabela) async {
    await _supabase.from(tabela).update({
      'email': email,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Upsert podataka firme u v2_racuni (jedna firma po putniku)
  Future<void> upsertFirma({
    required String putnikId,
    required String putnikTabela,
    required String firmaNaziv,
    String? firmaPib,
    String? firmaMb,
    String? firmaZiro,
    String? firmaAdresa,
  }) async {
    await _supabase.from('v2_racuni').upsert({
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      'firma_naziv': firmaNaziv,
      'firma_pib': firmaPib,
      'firma_mb': firmaMb,
      'firma_ziro': firmaZiro,
      'firma_adresa': firmaAdresa,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'putnik_id');
  }

  // ---------------------------------------------
  // BRISANJE
  // ---------------------------------------------

  /// Briše putnika i sve vezane podatke (trajno)
  Future<bool> deletePutnik(String id, String tabela) async {
    try {
      // Briši vezane podatke
      await _supabase.from('v2_pin_zahtevi').delete().eq('putnik_id', id);
      await _supabase.from('v2_polasci').delete().eq('putnik_id', id);
      await _supabase.from('v2_vozac_putnik').delete().eq('putnik_id', id);
      // Briši putnika
      await _supabase.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2PutnikService] deletePutnik error: $e');
      return false;
    }
  }

  // ---------------------------------------------
  // PLACANJA
  // ---------------------------------------------

  /// Upisuje uplatu u v2_statistika_istorija
  Future<bool> upisPlacanjaULog({
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
    required double iznos,
    required String vozacIme,
    required DateTime datum,
    int? placeniMesec,
    int? placenaGodina,
  }) async {
    try {
      // Resolvi vozac UUID iz cache-a
      String? vozacId;
      if (vozacIme.isNotEmpty) {
        vozacId = VozacCache.getUuidByIme(vozacIme);
        vozacId ??= await VozacCache.getUuidByImeAsync(vozacIme);
      }

      await V2StatistikaIstorijaService.dodajUplatu(
        putnikId: putnikId,
        datum: datum,
        iznos: iznos,
        vozacId: vozacId,
        vozacImeParam: vozacIme,
        placeniMesec: placeniMesec ?? datum.month,
        placenaGodina: placenaGodina ?? datum.year,
        tipUplate: 'uplata_mesecna',
      );
      return true;
    } catch (e) {
      debugPrint('❌ [V2PutnikService] upisPlacanjaULog error: $e');
      rethrow;
    }
  }

  /// Dohvata sva placanja za putnika iz v2_statistika_istorija
  Future<List<Map<String, dynamic>>> dohvatiPlacanja(String putnikId) async {
    try {
      final rows = await _supabase
          .from('v2_statistika_istorija')
          .select()
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']).order('datum', ascending: false);

      return rows
          .map<Map<String, dynamic>>((row) => {
                'iznos': row['iznos'],
                'datum': row['datum'],
                'created_at': row['created_at'],
                'vozac_ime': row['vozac_ime'],
                'placeni_mesec': row['placeni_mesec'],
                'placena_godina': row['placena_godina'],
                'tip': row['tip'],
              })
          .toList();
    } catch (e) {
      debugPrint('❌ [V2PutnikService] dohvatiPlacanja error: $e');
      return [];
    }
  }

  /// Dohvata ukupno placeno za putnika iz v2_statistika_istorija
  Future<double> dohvatiUkupnoPlaceno(String putnikId) async {
    try {
      final rows = await _supabase
          .from('v2_statistika_istorija')
          .select('iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']);

      double ukupno = 0.0;
      for (final row in rows) {
        ukupno += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
      return ukupno;
    } catch (e) {
      return 0.0;
    }
  }

  // ---------------------------------------------
  // STATISTIKE
  // ---------------------------------------------

  /// Broji jedinstvene dane vožnji za putnika
  Future<int> izracunajBrojVoznji(String putnikId) async {
    try {
      final rows =
          await _supabase.from('v2_statistika_istorija').select('datum').eq('putnik_id', putnikId).eq('tip', 'voznja');

      final datumi = <String>{};
      for (final row in rows) {
        if (row['datum'] != null) datumi.add(row['datum'] as String);
      }
      return datumi.length;
    } catch (e) {
      return 0;
    }
  }

  /// Broji jedinstvene dane otkazivanja za putnika
  Future<int> izracunajBrojOtkazivanja(String putnikId) async {
    try {
      final rows = await _supabase
          .from('v2_statistika_istorija')
          .select('datum')
          .eq('putnik_id', putnikId)
          .eq('tip', 'otkazivanje');

      final datumi = <String>{};
      for (final row in rows) {
        if (row['datum'] != null) datumi.add(row['datum'] as String);
      }
      return datumi.length;
    } catch (e) {
      return 0;
    }
  }

  // ---------------------------------------------
  // BACKWARD COMPAT ž za screene koji još nisu migrirani
  // Vraca RegistrovaniPutnik objekat iz v2_ podataka
  // ---------------------------------------------

  /// Dohvata sve aktivne putnike kao RegistrovaniPutnik listu
  /// (za screene koji još koriste stari model)
  Future<List<RegistrovaniPutnik>> getAllAktivniKaoModel() async {
    final svi = await getSviAktivni();
    return svi.map((row) => RegistrovaniPutnik.fromMap(row)).toList();
  }

  /// Stream aktivnih putnika kao RegistrovaniPutnik
  Stream<List<RegistrovaniPutnik>> streamAktivniPutnici() async* {
    final loaded = await getAllAktivniKaoModel();
    yield loaded;
  }

  // ---------------------------------------------
  // HELPERS
  // ---------------------------------------------

  static String _normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }
}
