import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import '../models/v2_ucenik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za učenike — jedina klasa koja radi sa v2_ucenici tabelom.
class V2UceniciService {
  V2UceniciService._();

  static const String tabela = 'v2_ucenici';

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;
  static Map<String, dynamic> get _cache => _rm.uceniciCache;

  // ---------------------------------------------------------------------------
  // CITANJE — iz RM cache-a (sync, 0 DB upita)
  // ---------------------------------------------------------------------------

  static List<V2RegistrovaniPutnik> getAktivne() {
    return _cache.values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => V2RegistrovaniPutnik.fromMap({...r, '_tabela': tabela}))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static List<V2RegistrovaniPutnik> getSve() {
    return _cache.values.map((r) => V2RegistrovaniPutnik.fromMap({...r, '_tabela': tabela})).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static V2RegistrovaniPutnik? getById(String id) {
    final row = _cache[id];
    if (row == null) return null;
    return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
  }

  static String? getImeById(String id) => _cache[id]?['ime']?.toString();

  static V2RegistrovaniPutnik? getByPin(String pin) {
    try {
      final row = _cache.values.firstWhere(
        (r) => r['pin'] == pin && r['status'] == 'aktivan',
      );
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (_) {
      return null;
    }
  }

  /// Typed model iz cache-a
  static V2Ucenik? getUcenikById(String id) {
    final row = _cache[id];
    if (row == null) return null;
    return V2Ucenik.fromJson(Map<String, dynamic>.from(row));
  }

  /// Sve aktivne kao typed modeli
  static List<V2Ucenik> getAktivneKaoModele() {
    return _cache.values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => V2Ucenik.fromJson(Map<String, dynamic>.from(r)))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() => _rm.streamFromCache(tables: [tabela], build: getAktivne);

  // ---------------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------------

  static Future<V2RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefonOca,
    String? telefonMajke,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cenaPoDanu,
    int? brojMesta,
    bool trebaRacun = false,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _db
          .from(tabela)
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_oca': telefonOca,
            'telefon_majke': telefonMajke,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'pin': pin,
            'email': email,
            'cena_po_danu': cenaPoDanu,
            'broj_mesta': brojMesta,
            'treba_racun': trebaRacun,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (e) {
      debugPrint('[V2UceniciService] create error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // UPDATE / DELETE
  // ---------------------------------------------------------------------------

  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _db.from(tabela).update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2UceniciService] update error: $e');
      return false;
    }
  }

  static Future<bool> setStatus(String id, String status) => update(id, {'status': status});

  static Future<bool> delete(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2UceniciService] delete error: $e');
      return false;
    }
  }
}
