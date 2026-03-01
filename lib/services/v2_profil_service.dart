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
  // 📖 ČITANJE — iz RM cache-a (sync, 0 DB upita)
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne putnike iz date tabele
  static List<RegistrovaniPutnik> getAktivne(String tabela) {
    return _cacheForTabela(tabela)
        .values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => _fromRow(r, tabela))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dohvata sve putnike iz date tabele (uključujući neaktivne)
  static List<RegistrovaniPutnik> getSve(String tabela) {
    return _cacheForTabela(tabela).values.map((r) => _fromRow(r, tabela)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dohvata putnika po ID-u iz date tabele
  static RegistrovaniPutnik? getById(String id, String tabela) {
    final row = _cacheForTabela(tabela)[id];
    if (row == null) return null;
    return _fromRow(row, tabela);
  }

  /// Dohvata ime putnika po ID-u iz date tabele
  static String? getImeById(String id, String tabela) {
    return _cacheForTabela(tabela)[id]?['ime'] as String?;
  }

  /// Pronalazi putnika po PIN-u (za autentifikaciju)
  static RegistrovaniPutnik? getByPin(String pin, String tabela) {
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
  // ✏️ AŽURIRANJE / BRISANJE — generičke metode za sve tabele
  // ---------------------------------------------------------------------------

  /// Ažurira putnika u datoj tabeli
  static Future<bool> update(String id, String tabela, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from(tabela).update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2ProfilService] update ($tabela) error: $e');
      return false;
    }
  }

  /// Menja status putnika (aktivan/neaktivan/bolovanje/godisnji)
  static Future<bool> setStatus(String id, String tabela, String status) async {
    return update(id, tabela, {'status': status});
  }

  /// Briše putnika iz date tabele (trajno)
  static Future<bool> delete(String id, String tabela) async {
    try {
      await _supabase.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2ProfilService] delete ($tabela) error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 📡 STREAM — emituje direktno iz RM cache-a
  // ---------------------------------------------------------------------------

  /// Stream aktivnih putnika iz date tabele (realtime, 0 DB upita)
  static Stream<List<RegistrovaniPutnik>> streamAktivne(String tabela) {
    final controller = StreamController<List<RegistrovaniPutnik>>.broadcast();

    void emit() {
      if (!controller.isClosed) controller.add(getAktivne(tabela));
    }

    emit();
    final sub = _rm.subscribe(tabela).listen((_) => emit());
    controller.onCancel = () {
      sub.cancel();
      _rm.unsubscribe(tabela);
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // 🏗️ CREATE — specifične metode po tabeli (različite kolone)
  // ---------------------------------------------------------------------------

  /// Kreira novog radnika (v2_radnici)
  static Future<RegistrovaniPutnik?> createRadnik({
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
      debugPrint('❌ [V2ProfilService] createRadnik error: $e');
      return null;
    }
  }

  /// Kreira novog učenika (v2_ucenici)
  static Future<RegistrovaniPutnik?> createUcenik({
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
      debugPrint('❌ [V2ProfilService] createUcenik error: $e');
      return null;
    }
  }

  /// Kreira novog dnevnog putnika (v2_dnevni)
  static Future<RegistrovaniPutnik?> createDnevni({
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
      debugPrint('❌ [V2ProfilService] createDnevni error: $e');
      return null;
    }
  }

  /// Kreira novu pošiljku (v2_posiljke)
  static Future<RegistrovaniPutnik?> createPosiljka({
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
      debugPrint('❌ [V2ProfilService] createPosiljka error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔧 HELPER
  // ---------------------------------------------------------------------------

  static RegistrovaniPutnik _fromRow(Map<String, dynamic> r, String tabela) {
    return RegistrovaniPutnik.fromMap({...r, '_tabela': tabela});
  }
}
