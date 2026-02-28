import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import 'v2_realtime_config.dart';
import 'v2_realtime_status.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// V2MasterRealtimeManager — čist, novi singleton za v2_ tabele
///
/// PRAVILA:
///   1. Samo v2_ tabele — nikad stare (registrovani_putnici, voznje_log, itd.)
///   2. Cache ime = tačno ime tabele bez prefiksa: polasci, putnici, vozaci...
///   3. subscribe/unsubscribe ostaje isti pattern kao RealtimeManager
///   4. Inicijalizuje se JEDNOM iz main.dart — ne iz servisa
///
/// CACHE MAPA:
///   polasciCache     ← v2_polasci          (dnevni, filter po danas)
///   statistikaCache  ← v2_statistika_istorija (dnevni, filter po danas)
///   radniciCache     ← v2_radnici           (statički, svi aktivni)
///   uceniciCache     ← v2_ucenici           (statički, svi aktivni)
///   dnevniCache      ← v2_dnevni            (statički, svi aktivni)
///   posiljkeCache    ← v2_posiljke          (statički, sve aktivne)
///   vozaciCache      ← v2_vozaci            (statički)
///   vozilaCache      ← v2_vozila            (statički)
///   kapacitetCache   ← v2_kapacitet_polazaka (statički, aktivni)
///   adreseCache      ← v2_adrese            (statički)
///   rasporedCache    ← v2_vozac_raspored    (statički)
///   vozacPutnikCache ← v2_vozac_putnik      (statički)
///   lokacijeCache    ← v2_vozac_lokacije    (statički, aktivne)
///   troskoviCache    ← v2_finansije_troskovi (statički, aktivni)
///   pumpaCache       ← v2_pumpa_config      (statički)
///   pinCache         ← v2_pin_zahtevi       (statički)
///   settingsCache    ← v2_app_settings      (statički)
/// ════════════════════════════════════════════════════════════════════════════
class V2MasterRealtimeManager {
  V2MasterRealtimeManager._internal();

  static final V2MasterRealtimeManager _instance = V2MasterRealtimeManager._internal();
  static V2MasterRealtimeManager get instance => _instance;

  SupabaseClient get _db => supabase;

  // ──────────────────────────────────────────────────────────────────────────
  // 🗄️  IN-MEMORY CACHE — ključ je uvek 'id' reda
  // ──────────────────────────────────────────────────────────────────────────

  // --- Dnevni (čisti se na novi dan) ---
  /// v2_polasci za tekući dan
  final Map<String, Map<String, dynamic>> polasciCache = {};

  /// v2_statistika_istorija za tekući dan
  final Map<String, Map<String, dynamic>> statistikaCache = {};

  // --- Putnici (svi aktivni, statički) ---
  /// v2_radnici — aktivni radnici
  final Map<String, Map<String, dynamic>> radniciCache = {};

  /// v2_ucenici — aktivni učenici
  final Map<String, Map<String, dynamic>> uceniciCache = {};

  /// v2_dnevni — aktivni dnevni putnici
  final Map<String, Map<String, dynamic>> dnevniCache = {};

  /// v2_posiljke — aktivne pošiljke
  final Map<String, Map<String, dynamic>> posiljkeCache = {};

  // --- Infrastruktura (statički) ---
  /// v2_vozaci
  final Map<String, Map<String, dynamic>> vozaciCache = {};

  /// v2_vozila
  final Map<String, Map<String, dynamic>> vozilaCache = {};

  /// v2_kapacitet_polazaka (samo aktivan=true)
  final Map<String, Map<String, dynamic>> kapacitetCache = {};

  /// v2_adrese
  final Map<String, Map<String, dynamic>> adreseCache = {};

  /// v2_vozac_raspored
  final Map<String, Map<String, dynamic>> rasporedCache = {};

  /// v2_vozac_putnik
  final Map<String, Map<String, dynamic>> vozacPutnikCache = {};

  /// v2_vozac_lokacije (samo aktivan=true)
  final Map<String, Map<String, dynamic>> lokacijeCache = {};

  /// v2_finansije_troskovi (samo aktivan=true)
  final Map<String, Map<String, dynamic>> troskoviCache = {};

  /// v2_pumpa_config
  final Map<String, Map<String, dynamic>> pumpaCache = {};

  /// v2_pin_zahtevi
  final Map<String, Map<String, dynamic>> pinCache = {};

  /// v2_app_settings
  final Map<String, Map<String, dynamic>> settingsCache = {};

  // ──────────────────────────────────────────────────────────────────────────
  // 📅  State
  // ──────────────────────────────────────────────────────────────────────────

  String? _loadedDate;
  String? get loadedDate => _loadedDate;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ──────────────────────────────────────────────────────────────────────────
  // 🚀  INICIJALIZACIJA — poziva se jednom iz main.dart
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!isSupabaseReady) {
      debugPrint('❌ [V2MasterRealtimeManager] Supabase nije spreman');
      return;
    }
    _loadedDate = _today();
    debugPrint('🚀 [V2MasterRealtimeManager] Inicijalizacija za datum=$_loadedDate ...');

    await Future.wait([
      _loadPolasciCache(),
      _loadStatistikaCache(),
      _loadPutniciCaches(),
      _loadInfraCache(),
    ]);

    _initialized = true;
    debugPrint(
      '✅ [V2MasterRealtimeManager] Inicijalizovano: '
      'polasci=${polasciCache.length}, '
      'statistika=${statistikaCache.length}, '
      'radnici=${radniciCache.length}, '
      'ucenici=${uceniciCache.length}, '
      'dnevni=${dnevniCache.length}, '
      'posiljke=${posiljkeCache.length}, '
      'vozaci=${vozaciCache.length}, '
      'adrese=${adreseCache.length}',
    );
  }

  /// Poziva se iz AppLifecycleObserver kad datum nije isti
  Future<void> refreshForNewDay() async {
    final today = _today();
    if (_loadedDate == today) return;
    debugPrint('🔄 [V2MasterRealtimeManager] Novi dan ($today) — osvežavam dnevne cache-ove...');
    _loadedDate = today;
    polasciCache.clear();
    statistikaCache.clear();
    await Future.wait([_loadPolasciCache(), _loadStatistikaCache()]);
    debugPrint(
      '✅ [V2MasterRealtimeManager] Dnevni cache osvežen: '
      'polasci=${polasciCache.length}, statistika=${statistikaCache.length}',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 📥  LOAD metode — jedna po grupi tabela
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadPolasciCache() async {
    try {
      final dan = _todayKratica();
      final rows = await _db
          .from('v2_polasci')
          .select(
            'id, putnik_id, putnik_tabela, grad, zeljeno_vreme, dodeljeno_vreme, '
            'status, created_at, updated_at, processed_at, broj_mesta, '
            'alternative_vreme_1, alternative_vreme_2, adresa_id, '
            'cancelled_by, approved_by, pokupljeno_by, dan',
          )
          .eq('dan', dan)
          .inFilter('status', [
        'pending',
        'manual',
        'approved',
        'confirmed',
        'otkazano',
        'cancelled',
        'bez_polaska',
        'pokupljen',
      ]);
      for (final row in rows) {
        polasciCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [V2MasterRealtimeManager] polasciCache: ${polasciCache.length} (dan=$dan)');
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadPolasciCache: $e');
    }
  }

  Future<void> _loadStatistikaCache() async {
    try {
      final rows = await _db
          .from('v2_statistika_istorija')
          .select(
            'id, putnik_id, putnik_ime, putnik_tabela, datum, dan, '
            'grad, vreme, tip, iznos, vozac_id, vozac_ime, detalji, created_at',
          )
          .eq('datum', _loadedDate!);
      for (final row in rows) {
        statistikaCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [V2MasterRealtimeManager] statistikaCache: ${statistikaCache.length}');
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadStatistikaCache: $e');
    }
  }

  Future<void> _loadPutniciCaches() async {
    try {
      final results = await Future.wait([
        _db
            .from('v2_radnici')
            .select(
              'id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
              'pin, email, cena_po_danu, broj_mesta, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_ucenici')
            .select(
              'id, ime, status, telefon, telefon_oca, telefon_majke, '
              'adresa_bc_id, adresa_vs_id, pin, email, cena_po_danu, broj_mesta, '
              'created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_dnevni')
            .select(
              'id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
              'cena, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_posiljke')
            .select(
              'id, ime, status, telefon, adresa_bc_id, adresa_vs_id, '
              'cena, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
      ]);

      for (final row in results[0]) {
        radniciCache[row['id'].toString()] = _tagRow(row, 'v2_radnici');
      }
      for (final row in results[1]) {
        uceniciCache[row['id'].toString()] = _tagRow(row, 'v2_ucenici');
      }
      for (final row in results[2]) {
        dnevniCache[row['id'].toString()] = _tagRow(row, 'v2_dnevni');
      }
      for (final row in results[3]) {
        posiljkeCache[row['id'].toString()] = _tagRow(row, 'v2_posiljke');
      }

      debugPrint(
        '📦 [V2MasterRealtimeManager] putnici: '
        'radnici=${radniciCache.length}, '
        'ucenici=${uceniciCache.length}, '
        'dnevni=${dnevniCache.length}, '
        'posiljke=${posiljkeCache.length}',
      );
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadPutniciCaches: $e');
    }
  }

  Future<void> _loadInfraCache() async {
    try {
      final results = await Future.wait([
        _db.from('v2_vozaci').select('id, ime, email, telefon, sifra, boja'),
        _db.from('v2_vozila').select('id, registarski_broj, marka, model, godina_proizvodnje, kilometraza, napomena'),
        _db.from('v2_kapacitet_polazaka').select('id, grad, vreme, max_mesta, aktivan').eq('aktivan', true),
        _db.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng'),
        _db.from('v2_vozac_raspored').select(),
        _db.from('v2_vozac_putnik').select(),
        _db
            .from('v2_finansije_troskovi')
            .select('id, naziv, iznos, tip, aktivan, vozac_id, created_at')
            .eq('aktivan', true),
        _db.from('v2_pumpa_config').select(),
        _db.from('v2_vozac_lokacije').select().eq('aktivan', true),
        _db.from('v2_pin_zahtevi').select(),
        _db.from('v2_app_settings').select(),
      ]);

      _fillCache(vozaciCache, results[0]);
      _fillCache(vozilaCache, results[1]);
      _fillCache(kapacitetCache, results[2]);
      _fillCache(adreseCache, results[3]);
      _fillCache(rasporedCache, results[4]);
      _fillCache(vozacPutnikCache, results[5]);
      _fillCache(troskoviCache, results[6]);
      _fillCache(pumpaCache, results[7]);
      _fillCache(lokacijeCache, results[8]);
      _fillCache(pinCache, results[9]);
      _fillCache(settingsCache, results[10]);

      debugPrint(
        '📦 [V2MasterRealtimeManager] infra: '
        'vozaci=${vozaciCache.length}, '
        'vozila=${vozilaCache.length}, '
        'adrese=${adreseCache.length}, '
        'lokacije=${lokacijeCache.length}',
      );
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadInfraCache: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🔧  CACHE UPDATE — poziva se iz realtime callback-a
  // ──────────────────────────────────────────────────────────────────────────

  /// Ažurira odgovarajući cache na INSERT/UPDATE event
  void upsertToCache(String table, Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;
    final target = _cacheForTable(table);
    if (target != null) {
      target[id] = Map<String, dynamic>.from(record);
    }
  }

  /// Uklanja red iz cache-a na DELETE event
  void removeFromCache(String table, String id) {
    _cacheForTable(table)?.remove(id);
  }

  /// Vraća odgovarajući cache map po imenu tabele
  Map<String, Map<String, dynamic>>? _cacheForTable(String table) {
    switch (table) {
      case 'v2_polasci':
        return polasciCache;
      case 'v2_statistika_istorija':
        return statistikaCache;
      case 'v2_radnici':
        return radniciCache;
      case 'v2_ucenici':
        return uceniciCache;
      case 'v2_dnevni':
        return dnevniCache;
      case 'v2_posiljke':
        return posiljkeCache;
      case 'v2_vozaci':
        return vozaciCache;
      case 'v2_vozila':
        return vozilaCache;
      case 'v2_kapacitet_polazaka':
        return kapacitetCache;
      case 'v2_adrese':
        return adreseCache;
      case 'v2_vozac_raspored':
        return rasporedCache;
      case 'v2_vozac_putnik':
        return vozacPutnikCache;
      case 'v2_vozac_lokacije':
        return lokacijeCache;
      case 'v2_finansije_troskovi':
        return troskoviCache;
      case 'v2_pumpa_config':
        return pumpaCache;
      case 'v2_pin_zahtevi':
        return pinCache;
      case 'v2_app_settings':
        return settingsCache;
      default:
        debugPrint('⚠️ [V2MasterRealtimeManager] Nepoznata tabela za cache: $table');
        return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 📡  CHANNEL MANAGEMENT — subscribe / unsubscribe
  // ──────────────────────────────────────────────────────────────────────────

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<PostgresChangePayload>> _controllers = {};
  final Map<String, int> _listenerCount = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, RealtimeStatus> _statusMap = {};
  final Map<String, Timer?> _reconnectTimers = {};

  final StreamController<Map<String, RealtimeStatus>> _statusController =
      StreamController<Map<String, RealtimeStatus>>.broadcast();

  Stream<Map<String, RealtimeStatus>> get statusStream => _statusController.stream;

  RealtimeStatus getStatus(String table) => _statusMap[table] ?? RealtimeStatus.disconnected;

  /// Pretplati se na promene u tabeli.
  /// Više listenera može deliti isti channel.
  Stream<PostgresChangePayload> subscribe(String table) {
    if (!isSupabaseReady) {
      debugPrint('❌ [V2MasterRealtimeManager] Cannot subscribe "$table": Supabase not ready');
      return const Stream.empty();
    }

    _listenerCount[table] = (_listenerCount[table] ?? 0) + 1;

    if (_controllers.containsKey(table) && !_controllers[table]!.isClosed) {
      return _controllers[table]!.stream;
    }

    _reconnectTimers[table]?.cancel();
    _reconnectTimers[table] = null;

    _controllers[table] = StreamController<PostgresChangePayload>.broadcast();
    _createChannel(table);

    return _controllers[table]!.stream;
  }

  /// Odjavi se sa tabele — channel se zatvara kad nema više listenera
  void unsubscribe(String table) {
    _listenerCount[table] = (_listenerCount[table] ?? 1) - 1;
    if ((_listenerCount[table] ?? 0) <= 0) {
      _closeChannel(table);
    }
  }

  void _createChannel(String table) {
    _updateStatus(table, RealtimeStatus.connecting);

    final channel = _db.channel('v2master:$table');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              final id = payload.oldRecord['id']?.toString();
              if (id != null) removeFromCache(table, id);
            } else {
              final rec = payload.newRecord;
              if (rec.isNotEmpty) upsertToCache(table, rec);
            }

            if (_controllers[table] != null && !_controllers[table]!.isClosed) {
              _controllers[table]!.add(payload);
            }
          },
        )
        .subscribe((status, [error]) => _handleStatus(table, status, error));

    _channels[table] = channel;
  }

  void _closeChannel(String table) {
    _reconnectTimers[table]?.cancel();
    _reconnectTimers[table] = null;
    _channels[table]?.unsubscribe();
    _channels.remove(table);
    _controllers[table]?.close();
    _controllers.remove(table);
    _listenerCount.remove(table);
    _reconnectAttempts.remove(table);
    _updateStatus(table, RealtimeStatus.disconnected);
  }

  void _handleStatus(String table, RealtimeSubscribeStatus status, dynamic error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _reconnectAttempts[table] = 0;
        _updateStatus(table, RealtimeStatus.connected);
        break;

      case RealtimeSubscribeStatus.channelError:
        debugPrint('❌ [V2MasterRealtimeManager] Channel error "$table": $error');
        _scheduleReconnect(table);
        break;

      case RealtimeSubscribeStatus.closed:
        if ((_listenerCount[table] ?? 0) > 0) {
          _scheduleReconnect(table);
        } else {
          _closeChannel(table);
        }
        break;

      case RealtimeSubscribeStatus.timedOut:
        _scheduleReconnect(table);
        break;
    }
  }

  void _scheduleReconnect(String table) {
    _reconnectTimers[table]?.cancel();

    final attempts = _reconnectAttempts[table] ?? 0;
    if (attempts >= RealtimeConfig.maxReconnectAttempts) {
      _updateStatus(table, RealtimeStatus.error);
      _reconnectTimers[table] = null;
      return;
    }

    _updateStatus(table, RealtimeStatus.reconnecting);
    _reconnectAttempts[table] = attempts + 1;

    final delays = [3, 6, 10];
    final delay = delays[attempts.clamp(0, delays.length - 1)];

    _reconnectTimers[table] = Timer(Duration(seconds: delay), () async {
      _reconnectTimers[table] = null;
      if ((_listenerCount[table] ?? 0) <= 0) return;
      if (_channels.containsKey(table)) return;

      final existing = _channels[table];
      if (existing != null) {
        try {
          await _db.removeChannel(existing);
        } catch (_) {}
        _channels.remove(table);
      }

      // Sačekaj da SDK očisti kanal
      int retries = 0;
      final initialCount = _db.getChannels().length;
      while (retries < 20) {
        if (_db.getChannels().length < initialCount) break;
        await Future.delayed(const Duration(milliseconds: 50));
        retries++;
      }

      _createChannel(table);
    });
  }

  void _updateStatus(String table, RealtimeStatus status) {
    _statusMap[table] = status;
    if (!_statusController.isClosed) {
      _statusController.add(Map.from(_statusMap));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🔍  LOOKUP HELPERS — česte operacije iz servisa/screena
  // ──────────────────────────────────────────────────────────────────────────

  /// Vraća ime putnika iz odgovarajućeg cache-a po putnik_tabela + putnik_id
  String? getIme(String putnikTabela, String putnikId) {
    final cache = _cacheForTable(putnikTabela);
    return cache?[putnikId]?['ime'] as String?;
  }

  /// Vraća sve aktivne putnike iz sva 4 cache-a objedinjeno
  List<Map<String, dynamic>> getAllPutnici() {
    return [
      ...radniciCache.values,
      ...uceniciCache.values,
      ...dnevniCache.values,
      ...posiljkeCache.values,
    ];
  }

  /// Vraća putnika po ID-u pretražujući sva 4 cache-a
  Map<String, dynamic>? getPutnikById(String id) {
    return radniciCache[id] ?? uceniciCache[id] ?? dnevniCache[id] ?? posiljkeCache[id];
  }

  /// Vraća ime vozača iz cache-a
  String? getVozacIme(String vozacId) {
    return vozaciCache[vozacId]?['ime'] as String?;
  }

  /// Vraća naziv adrese iz cache-a
  String? getAdresaNaziv(String adresaId) {
    return adreseCache[adresaId]?['naziv'] as String?;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🛠️  PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  static String _todayKratica() {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.now().weekday]!;
  }

  /// Popuni cache mapu iz liste redova
  static void _fillCache(Map<String, Map<String, dynamic>> cache, List rows) {
    for (final row in rows) {
      cache[row['id'].toString()] = Map<String, dynamic>.from(row as Map<String, dynamic>);
    }
  }

  /// Dodaje '_tabela' tag u red (korisno za putnici cache)
  static Map<String, dynamic> _tagRow(Map<String, dynamic> row, String tabela) {
    return {...row, '_tabela': tabela};
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🗑️  DISPOSE
  // ──────────────────────────────────────────────────────────────────────────

  void dispose() {
    for (final t in _reconnectTimers.values) {
      t?.cancel();
    }
    _reconnectTimers.clear();
    for (final ch in _channels.values) {
      ch.unsubscribe();
    }
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
    _channels.clear();
    _controllers.clear();
    _listenerCount.clear();
    _reconnectAttempts.clear();
    _statusMap.clear();
    _statusController.close();
  }
}
