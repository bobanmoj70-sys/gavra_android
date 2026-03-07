import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_dnevni.dart';
import '../models/v2_posiljka.dart';
import '../models/v2_registrovani_putnik.dart';
import '../models/v2_ucenik.dart';
import 'realtime/v2_master_realtime_manager.dart';

// =============================================================================
// v2_putnici_service.dart
// Spoj 4 identična CRUD servisa: radnici, ucenici, dnevni, posiljke.
// Sva 4 klasa su zadržana bez izmene javnog API-ja.
// =============================================================================

// ---------------------------------------------------------------------------
// V2RadniciService
// ---------------------------------------------------------------------------

/// Servis za radnike — jedina klasa koja radi sa v2_radnici tabelom.
class V2RadniciService {
  V2RadniciService._();

  static const String tabela = 'v2_radnici';

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;
  static Map<String, dynamic> get _cache => _rm.radniciCache;

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

  static V2RegistrovaniPutnik? v2GetByPin(String pin) {
    try {
      final row = _cache.values.firstWhere(
        (r) => r['pin'] == pin && r['status'] == 'aktivan',
      );
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (_) {
      return null;
    }
  }

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() =>
      _rm.v2StreamFromCache(tables: [tabela], build: getAktivne);

  static Future<V2RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefon2,
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
            'telefon_2': telefon2,
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
      _rm.v2UpsertToCache(tabela, {...row, '_tabela': tabela});
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (e) {
      debugPrint('[V2RadniciService] create greška: $e');
      return null;
    }
  }

  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _db.from(tabela).update(updates).eq('id', id);
      _rm.v2PatchCache(tabela, id, updates);
      return true;
    } catch (e) {
      debugPrint('[V2RadniciService] update greška: $e');
      return false;
    }
  }

  static Future<bool> setStatus(String id, String status) => update(id, {'status': status});

  static Future<bool> delete(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2RadniciService] delete greška: $e');
      return false;
    }
  }
}
// ---------------------------------------------------------------------------

/// Servis za učenike — jedina klasa koja radi sa v2_ucenici tabelom.
class V2UceniciService {
  V2UceniciService._();

  static const String tabela = 'v2_ucenici';

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;
  static Map<String, dynamic> get _cache => _rm.uceniciCache;

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

  static V2RegistrovaniPutnik? v2GetByPin(String pin) {
    try {
      final row = _cache.values.firstWhere(
        (r) => r['pin'] == pin && r['status'] == 'aktivan',
      );
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (_) {
      return null;
    }
  }

  static V2Ucenik? getUcenikById(String id) {
    final row = _cache[id];
    if (row == null) return null;
    return V2Ucenik.fromJson(Map<String, dynamic>.from(row));
  }

  static List<V2Ucenik> getAktivneKaoModele() {
    return _cache.values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => V2Ucenik.fromJson(Map<String, dynamic>.from(r)))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() =>
      _rm.v2StreamFromCache(tables: [tabela], build: getAktivne);

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
      _rm.v2UpsertToCache(tabela, {...row, '_tabela': tabela});
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (e) {
      debugPrint('[V2UceniciService] create greška: $e');
      return null;
    }
  }

  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _db.from(tabela).update(updates).eq('id', id);
      _rm.v2PatchCache(tabela, id, updates);
      return true;
    } catch (e) {
      debugPrint('[V2UceniciService] update greška: $e');
      return false;
    }
  }

  static Future<bool> setStatus(String id, String status) => update(id, {'status': status});

  static Future<bool> delete(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2UceniciService] delete greška: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// V2DnevniService
// ---------------------------------------------------------------------------

/// Servis za dnevne putnike — jedina klasa koja radi sa v2_dnevni tabelom.
class V2DnevniService {
  V2DnevniService._();

  static const String tabela = 'v2_dnevni';

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;
  static Map<String, dynamic> get _cache => _rm.dnevniCache;

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

  static V2RegistrovaniPutnik? v2GetByPin(String pin) {
    try {
      final row = _cache.values.firstWhere(
        (r) => r['pin'] == pin && r['status'] == 'aktivan',
      );
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (_) {
      return null;
    }
  }

  static V2Dnevni? getDnevniById(String id) {
    final row = _cache[id];
    if (row == null) return null;
    return V2Dnevni.fromJson(Map<String, dynamic>.from(row));
  }

  static List<V2Dnevni> getAktivneKaoModele() {
    return _cache.values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => V2Dnevni.fromJson(Map<String, dynamic>.from(r)))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() =>
      _rm.v2StreamFromCache(tables: [tabela], build: getAktivne);

  static Future<V2RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefon2,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    bool trebaRacun = false,
    String? pin,
    String? email,
    int? brojMesta,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _db
          .from(tabela)
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_2': telefon2,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'cena': cena,
            'treba_racun': trebaRacun,
            'pin': pin,
            'email': email,
            'broj_mesta': brojMesta,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      _rm.v2UpsertToCache(tabela, {...row, '_tabela': tabela});
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (e) {
      debugPrint('[V2DnevniService] create greška: $e');
      return null;
    }
  }

  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _db.from(tabela).update(updates).eq('id', id);
      _rm.v2PatchCache(tabela, id, updates);
      return true;
    } catch (e) {
      debugPrint('[V2DnevniService] update greška: $e');
      return false;
    }
  }

  static Future<bool> setStatus(String id, String status) => update(id, {'status': status});

  static Future<bool> delete(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2DnevniService] delete greška: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// V2PosiljkeService
// ---------------------------------------------------------------------------

/// Servis za pošiljke — jedina klasa koja radi sa v2_posiljke tabelom.
class V2PosiljkeService {
  V2PosiljkeService._();

  static const String tabela = 'v2_posiljke';

  static SupabaseClient get _db => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;
  static Map<String, dynamic> get _cache => _rm.posiljkeCache;

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

  static V2RegistrovaniPutnik? v2GetByPin(String pin) {
    try {
      final row = _cache.values.firstWhere(
        (r) => r['pin'] == pin && r['status'] == 'aktivan',
      );
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (_) {
      return null;
    }
  }

  static V2Posiljka? getPosiljkaById(String id) {
    final row = _cache[id];
    if (row == null) return null;
    return V2Posiljka.fromJson(Map<String, dynamic>.from(row));
  }

  static List<V2Posiljka> getAktivneKaoModele() {
    return _cache.values
        .where((r) => r['status'] == 'aktivan')
        .map((r) => V2Posiljka.fromJson(Map<String, dynamic>.from(r)))
        .toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() =>
      _rm.v2StreamFromCache(tables: [tabela], build: getAktivne);

  static Future<V2RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    bool trebaRacun = false,
    String? pin,
    String? email,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _db
          .from(tabela)
          .insert({
            'ime': ime,
            'telefon': telefon,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'cena': cena,
            'treba_racun': trebaRacun,
            'pin': pin,
            'email': email,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      _rm.v2UpsertToCache(tabela, {...row, '_tabela': tabela});
      return V2RegistrovaniPutnik.fromMap({...row, '_tabela': tabela});
    } catch (e) {
      debugPrint('[V2PosiljkeService] create greška: $e');
      return null;
    }
  }

  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _db.from(tabela).update(updates).eq('id', id);
      _rm.v2PatchCache(tabela, id, updates);
      return true;
    } catch (e) {
      debugPrint('[V2PosiljkeService] update greška: $e');
      return false;
    }
  }

  static Future<bool> setStatus(String id, String status) => update(id, {'status': status});

  static Future<bool> delete(String id) async {
    try {
      await _db.from(tabela).delete().eq('id', id);
      _rm.v2RemoveFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('[V2PosiljkeService] delete greška: $e');
      return false;
    }
  }
}
