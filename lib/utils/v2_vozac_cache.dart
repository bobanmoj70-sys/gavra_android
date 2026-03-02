import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/v2_vozac.dart';
import '../services/realtime/v2_master_realtime_manager.dart';

/// VozacCache — jedinstven in-memory cache za sve podatke o vozačima.
///
/// Zamjenjuje `VozacBoja` i `VozacMappingService`.
/// Inicijalizuj jednom pri startu: `await VozacCache.initialize()`.
///
/// ## API:
/// - `VozacCache.getColorByUuid(uuid)` — boja po UUID-u, fallback = grey
/// - `VozacCache.getColor(imeIliUuid)` — boja po imenu ili UUID (auto-detect)
/// - `VozacCache.getImeByUuid(uuid)` — ime po UUID-u, null ako ne postoji
/// - `VozacCache.getUuidByIme(ime)` — UUID po imenu, null ako ne postoji
/// - `VozacCache.isValidIme(ime)` — provjera da li je ime registrovan vozač
/// - `VozacCache.vozaci` — lista svih Vozac objekata
/// - `VozacCache.imenaVozaca` — lista svih imena
class VozacCache {
  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNA STANJA
  // ═══════════════════════════════════════════════════════════════════════════

  static List<Vozac> _vozaci = [];

  // Primarni lookup map-ovi
  static Map<String, Color> _imeToColor = {};
  static Map<String, Color> _uuidToColor = {};
  static Map<String, String> _imeToUuid = {};
  static Map<String, String> _uuidToIme = {};

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  // UUID regex za auto-detect
  static final _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // INICIJALIZACIJA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Inicijalizuj cache pri startu (poziva se iz main.dart, jednom).
  static Future<void> initialize() async {
    try {
      await _load();
    } catch (e) {
      _clear();
      if (kDebugMode) debugPrint('❌ [VozacCache] initialize failed: $e');
    }
  }

  /// Osvježi cache iz baze (npr. nakon izmjene vozača).
  static Future<void> refresh() async {
    try {
      await _load();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [VozacCache] refresh failed: $e');
    }
  }

  static Future<void> _load() async {
    final rm = V2MasterRealtimeManager.instance;
    final vozaci = rm.vozaciCache.values.map((r) => Vozac.fromMap(r)).toList();

    final Map<String, Color> imeToColor = {};
    final Map<String, Color> uuidToColor = {};
    final Map<String, String> imeToUuid = {};
    final Map<String, String> uuidToIme = {};

    for (final v in vozaci) {
      imeToUuid[v.ime] = v.id;
      uuidToIme[v.id] = v.ime;

      final color = v.color;
      if (color != null) {
        imeToColor[v.ime] = color;
        uuidToColor[v.id] = color;
      }
    }

    _vozaci = vozaci;
    _imeToColor = Map.unmodifiable(imeToColor);
    _uuidToColor = Map.unmodifiable(uuidToColor);
    _imeToUuid = Map.unmodifiable(imeToUuid);
    _uuidToIme = Map.unmodifiable(uuidToIme);
    _isInitialized = true;

    if (kDebugMode) {
      debugPrint('✅ [VozacCache] Loaded ${vozaci.length} vozača');
    }
  }

  static void _clear() {
    _vozaci = [];
    _imeToColor = {};
    _uuidToColor = {};
    _imeToUuid = {};
    _uuidToIme = {};
    _isInitialized = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOJA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vraća boju po UUID-u. Nikad ne baca exception.
  static Color getColorByUuid(String? uuid, {Color fallback = Colors.grey}) {
    if (uuid == null || uuid.isEmpty) return fallback;
    return _uuidToColor[uuid] ?? fallback;
  }

  /// Vraća boju po imenu ILI UUID-u (auto-detect). Nikad ne baca exception.
  /// Ovo zamjenjuje VozacBoja.getSync().
  static Color getColor(String? imeIliUuid, {Color fallback = Colors.grey}) {
    if (imeIliUuid == null || imeIliUuid.isEmpty) return fallback;
    if (_uuidRegex.hasMatch(imeIliUuid)) {
      return _uuidToColor[imeIliUuid] ?? fallback;
    }
    return _imeToColor[imeIliUuid] ?? fallback;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IME ↔ UUID
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vraća ime vozača za dati UUID. Null ako ne postoji.
  static String? getImeByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    return _uuidToIme[uuid];
  }

  /// Vraća UUID vozača za dato ime. Null ako ne postoji.
  static String? getUuidByIme(String? ime) {
    if (ime == null || ime.isEmpty) return null;
    return _imeToUuid[ime];
  }

  /// Ako je input UUID, vrati ime. Ako je ime, vrati ime. Null ako prazno.
  static String? resolveIme(String? imeIliUuid) {
    if (imeIliUuid == null || imeIliUuid.isEmpty) return null;
    if (_uuidRegex.hasMatch(imeIliUuid)) {
      return _uuidToIme[imeIliUuid] ?? imeIliUuid;
    }
    return imeIliUuid;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVJERE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Provjera da li je ime registrovan vozač.
  static bool isValidIme(String? ime) {
    if (ime == null || ime.isEmpty) return false;
    return _imeToUuid.containsKey(ime);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LISTE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Svi Vozac objekti.
  static List<Vozac> get vozaci => _vozaci;

  /// Sva registrovana imena.
  static List<String> get imenaVozaca => _imeToUuid.keys.toList();

  /// Mapa ime → Color (za backwards compat s VozacBoja.bojeSync).
  static Map<String, Color> get bojeSync => _imeToColor;

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METODE (email, telefon — zamjena za VozacBoja helpers)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vraća Vozac objekat za dato ime.
  static Vozac? getVozacByIme(String? ime) {
    if (ime == null || ime.isEmpty) return null;
    try {
      return _vozaci.firstWhere((v) => v.ime == ime);
    } catch (_) {
      return null;
    }
  }

  /// Centralizovana odluka da li određeni vozač treba da koristi `VozacScreen`.
  ///
  /// Trenutno sadrži samo istorijsku specijalnu proveru za vozača "Voja",
  /// ali je mesto gde se ta logika treba menjati (umesto širenja hardcode provera).
  static bool prefersVozacScreen(String? ime) {
    if (ime == null || ime.isEmpty) return false;
    return ime.toLowerCase() == 'voja';
  }

  /// Vrati ikonu koja predstavlja vozača u UI.
  /// Mapiranje je najmanje privilegovano mesto za hardcode koje centralizuje
  /// sve specijalne slučajeve (može se proširiti iz baze kasnije).
  static IconData getIconForDriver(String? ime) {
    if (ime == null || ime.isEmpty) return Icons.person;
    switch (ime.toLowerCase()) {
      case 'bruda':
        return Icons.local_taxi;
      case 'bilevski':
        return Icons.directions_car;
      case 'bojan':
        return Icons.airport_shuttle;
      default:
        return Icons.person;
    }
  }

  /// Vraća ime vozača za dati email (case-insensitive).
  static String? getImeByEmail(String? email) {
    if (email == null || email.isEmpty) return null;
    try {
      return _vozaci.firstWhere((v) => v.email?.toLowerCase() == email.toLowerCase()).ime;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASYNC API (direktno iz baze, za rijetke slučajeve)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Dohvati UUID vozača po imenu async (direktno iz baze ako nije u cache-u).
  static Future<String?> getUuidByImeAsync(String? ime) async {
    if (ime == null || ime.isEmpty) return null;
    final fromCache = _imeToUuid[ime];
    if (fromCache != null) return fromCache;
    try {
      final rm = V2MasterRealtimeManager.instance;
      final vozaci = rm.vozaciCache.values.map((r) => Vozac.fromMap(r)).toList();
      return vozaci.firstWhere((v) => v.ime == ime).id;
    } catch (_) {
      return null;
    }
  }
}
