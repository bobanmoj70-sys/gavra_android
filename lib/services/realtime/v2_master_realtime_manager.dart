import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../models/v2_registrovani_putnik.dart';
import '../../services/v2_app_settings_service.dart';
import '../../utils/v2_vozac_cache.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// V2MasterRealtimeManager — čist, novi singleton za v2_ tabele
///
/// PRAVILA:
/// 1. Samo v2_ tabele — nikad stare (registrovani_putnici, itd.)
/// 2. Cache ime = tačno ime tabele bez prefiksa: polasci, putnici, vozaci...
/// 3. subscribe/unsubscribe ostaje isti pattern kao RealtimeManager
/// 4. Inicijalizuje se JEDNOM iz main.dart — ne iz servisa
///
/// CACHE MAPA:
/// polasciCache     ← v2_polasci          (sedmični, svi aktivni dani)
/// statistikaCache  ← v2_statistika_istorija (dnevni, filter po danas)
/// radniciCache     ← v2_radnici           (statički, svi aktivni)
/// uceniciCache     ← v2_ucenici           (statički, svi aktivni)
/// dnevniCache      ← v2_dnevni            (statički, svi aktivni)
/// posiljkeCache    ← v2_posiljke          (statički, sve aktivne)
/// vozaciCache      ← v2_vozaci            (statički)
/// vozilaCache      ← v2_vozila            (statički)
/// kapacitetCache   ← v2_kapacitet_polazaka (statički, aktivni)
/// adreseCache      ← v2_adrese            (statički)
/// rasporedCache    ← v2_vozac_raspored    (statički)
/// vozacPutnikCache ← v2_vozac_putnik      (statički)
/// lokacijeCache    ← v2_vozac_lokacije    (statički, aktivne)
/// troskoviCache    ← v2_finansije_troskovi (statički, aktivni)
/// pumpaCache       ← v2_pumpa_config      (statički)
/// pinCache         ← v2_pin_zahtevi       (statički)
/// settingsCache    ← v2_app_settings      (statički)
/// ════════════════════════════════════════════════════════════════════════════
class V2MasterRealtimeManager {
  V2MasterRealtimeManager._internal();

  static final V2MasterRealtimeManager _instance = V2MasterRealtimeManager._internal();
  static V2MasterRealtimeManager get instance => _instance;

  SupabaseClient get _db => supabase;

  // ──────────────────────────────────────────────────────────────────────────
  // IN-MEMORY CACHE — ključ je uvek 'id' reda
  // ──────────────────────────────────────────────────────────────────────────

  // --- Dnevni (čisti se na novi dan) ---
  /// v2_polasci — svi aktivni dani (pon–pet)
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

  /// v2_racuni — firma podaci po putnik_id (keyed by putnik_id)
  final Map<String, Map<String, dynamic>> racuniCache = {};

  // ──────────────────────────────────────────────────────────────────────────
  // State
  // ──────────────────────────────────────────────────────────────────────────

  String? _loadedDate;
  String? get loadedDate => _loadedDate;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Subscriptions za statičke tabele iz initialize() — drže _listenerCount >= 1
  /// tako da vanjski unsubscribe() nikad ne može zatvoriti te kanale.
  final List<StreamSubscription<PostgresChangePayload>> _staticSubscriptions = [];

  // ──────────────────────────────────────────────────────────────────────────
  // INICIJALIZACIJA — poziva se jednom iz main.dart
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
      loadStatistikaCache(),
      _loadPutniciCaches(),
      _loadInfraCache(),
      _loadRacuniCache(),
    ]);

    _initialized = true;

    // Trajna Realtime pretplata na sve statičke tabele — WebSocket only, 0 DB querija.
    // Svaka promena u bazi → Realtime event → upsertToCache → onCacheChanged → svi ekrani se osvežavaju.
    const staticTabele = [
      // Putnici
      'v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke',
      // Polasci — glavna dnevna tabela, mora biti permanentno subscribe-ovana
      'v2_polasci',
      // Infrastruktura
      'v2_vozaci', 'v2_vozila', 'v2_adrese',
      'v2_finansije_troskovi', 'v2_pumpa_config', 'v2_app_settings',
      'v2_statistika_istorija',
      // Raspored / putnik mapping / lokacije / kapacitet / pin
      'v2_kapacitet_polazaka', 'v2_vozac_raspored', 'v2_vozac_putnik',
      'v2_vozac_lokacije', 'v2_pin_zahtevi',
      'v2_racuni',
    ];
    for (final tabela in staticTabele) {
      _staticSubscriptions.add(subscribe(tabela).listen((_) {}));
    }

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

  /// Forsira refresh polasciCache bez promjene dana (npr. nakon ručnog dodavanja termina)
  Future<void> refreshPolasciCache() async {
    polasciCache.clear();
    await _loadPolasciCache();
    debugPrint('🔄 [V2MasterRealtimeManager] polasciCache osvežen: ${polasciCache.length}');
  }

  /// Poziva se iz AppLifecycleObserver kad datum nije isti
  Future<void> refreshForNewDay() async {
    final today = _today();
    if (_loadedDate == today) return;
    debugPrint('🔄 [V2MasterRealtimeManager] Novi dan ($today) — osvežavam dnevne cache-ove...');
    _loadedDate = today;
    polasciCache.clear();
    statistikaCache.clear();
    await Future.wait([
      _loadPolasciCache(),
      loadStatistikaCache(),
    ]);
    debugPrint(
      '✅ [V2MasterRealtimeManager] Dnevni cache osvežen: polasci=${polasciCache.length}, statistika=${statistikaCache.length}',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOAD metode — jedna po grupi tabela
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadPolasciCache() async {
    try {
      final rows = await _db
          .from('v2_polasci')
          .select('id, putnik_id, putnik_tabela, grad, zeljeno_vreme, dodeljeno_vreme, '
              'status, created_at, updated_at, processed_at, broj_mesta, '
              'alternativno_vreme_1, alternativno_vreme_2, adresa_id, '
              'otkazao, odobrio, pokupio, dan, '
              'placen, placen_iznos, placen_vozac_id, placen_vozac_ime, pokupljen_datum, datum_akcije, placen_tip')
          .inFilter('status', [
        'obrada',
        'odobreno',
        'otkazano',
        'odbijeno',
        'bez_polaska',
        'pokupljen',
      ]);
      for (final row in rows) {
        polasciCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [V2MasterRealtimeManager] polasciCache: ${polasciCache.length} (svi dani)');
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadPolasciCache: $e');
    }
  }

  /// Puni/osvežava statistikaCache za tekući dan — poziva se on-demand (pazar, profil, lista)
  Future<void> loadStatistikaCache() async {
    try {
      final rows = await _db
          .from('v2_statistika_istorija')
          .select(
            'id, putnik_id, putnik_ime, putnik_tabela, datum, dan, '
            'grad, vreme, tip, iznos, vozac_id, vozac_ime, detalji, created_at, '
            'placeni_mesec, placena_godina',
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
              'pin, email, cena_po_danu, broj_mesta, treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_ucenici')
            .select(
              'id, ime, status, telefon, telefon_oca, telefon_majke, '
              'adresa_bc_id, adresa_vs_id, pin, email, cena_po_danu, broj_mesta, '
              'treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_dnevni')
            .select(
              'id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
              'pin, email, cena, broj_mesta, treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        _db
            .from('v2_posiljke')
            .select(
              'id, ime, status, telefon, adresa_bc_id, adresa_vs_id, '
              'pin, email, cena, treba_racun, created_at, updated_at',
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
        _db.from('v2_vozila').select('id, registarski_broj, marka, model, godina_proizvodnje, kilometraza, napomena, '
            'broj_sasije, registracija_vazi_do, '
            'mali_servis_datum, mali_servis_km, veliki_servis_datum, veliki_servis_km, '
            'alternator_datum, alternator_km, akumulator_datum, akumulator_km, '
            'gume_datum, gume_opis, gume_prednje_datum, gume_prednje_opis, gume_prednje_km, '
            'gume_zadnje_datum, gume_zadnje_opis, gume_zadnje_km, '
            'plocice_datum, plocice_km, plocice_prednje_datum, plocice_prednje_km, '
            'plocice_zadnje_datum, plocice_zadnje_km, trap_datum, trap_km, radio'),
        _db.from('v2_kapacitet_polazaka').select('id, grad, vreme, max_mesta, aktivan').eq('aktivan', true),
        _db.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng, created_at, updated_at'),
        _db.from('v2_vozac_raspored').select('id, dan, grad, vreme, vozac_id, created_at, updated_at'),
        _db
            .from('v2_vozac_putnik')
            .select('id, putnik_id, putnik_tabela, vozac_id, dan, grad, vreme, created_at, updated_at'),
        _db
            .from('v2_finansije_troskovi')
            .select('id, naziv, iznos, tip, aktivan, mesecno, vozac_id, mesec, godina, created_at')
            .eq('aktivan', true),
        _db.from('v2_pumpa_config').select('id, kapacitet_litri, alarm_nivo, pocetno_stanje, updated_at'),
        _db
            .from('v2_vozac_lokacije')
            .select('id, vozac_id, lat, lng, grad, vreme_polaska, smer, putnici_eta, aktivan, updated_at')
            .eq('aktivan', true),
        _db
            .from('v2_pin_zahtevi')
            .select('id, putnik_id, putnik_tabela, email, telefon, status, created_at, updated_at')
            .eq('status', 'ceka'),
        _db.from('v2_app_settings').select(
            'id, min_version, latest_version, store_url_android, store_url_huawei, store_url_ios, nav_bar_type, updated_at'),
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

      // Osvježi V2VozacCache i AppSettings nakon što su SVI cache-ovi popunjeni
      await V2VozacCache.initialize();
      await V2AppSettingsService.initialize();

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

  /// Učitava sve v2_racuni zapise u racuniCache (keyed by putnik_id)
  Future<void> _loadRacuniCache() async {
    try {
      final rows = await _db.from('v2_racuni').select(
          'id, putnik_id, putnik_tabela, firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa, updated_at');
      racuniCache.clear();
      for (final row in (rows as List)) {
        final putnikId = row['putnik_id']?.toString();
        if (putnikId != null) racuniCache[putnikId] = Map<String, dynamic>.from(row as Map);
      }
      debugPrint('📦 [V2MasterRealtimeManager] racuniCache=${racuniCache.length}');
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadRacuniCache: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CACHE UPDATE — poziva se iz realtime callback-a
  // ──────────────────────────────────────────────────────────────────────────

  /// Ažurira odgovarajući cache na INSERT/UPDATE event
  void upsertToCache(String table, Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;

    // v2_racuni je keyed by putnik_id (ne id) — poseban handling
    if (table == 'v2_racuni') {
      final putnikId = record['putnik_id']?.toString();
      if (putnikId != null) {
        racuniCache[putnikId] = Map<String, dynamic>.from(record);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
      }
      return;
    }

    final target = _cacheForTable(table);
    if (target == null) return;

    // statistikaCache je dnevni — prihvati samo zapise za _loadedDate
    if (table == 'v2_statistika_istorija') {
      final datum = record['datum']?.toString();
      if (datum != null && datum != _loadedDate) return;
    }

    // polasciCache drži samo aktivne statuse — ukloni zapis ako dobijemo status koji nije u inicijalnoj listi
    if (table == 'v2_polasci') {
      const aktivniStatusi = {'obrada', 'odobreno', 'otkazano', 'odbijeno', 'bez_polaska', 'pokupljen'};
      final status = record['status']?.toString();
      if (status != null && !aktivniStatusi.contains(status)) {
        target.remove(id);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
        return;
      }
    }

    // pinCache sadrži samo zahtjeve sa status='ceka' — ako status nije 'ceka', ukloni iz cache-a
    if (table == 'v2_pin_zahtevi') {
      final status = record['status']?.toString();
      if (status != null && status != 'ceka') {
        target.remove(id);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
        return;
      }
    }

    // Sačuvaj postojeći _tabela tag — realtime payload ne sadrži _tabela
    final existingTabela = target[id]?['_tabela'] ?? table;
    target[id] = {...record, '_tabela': existingTabela};
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);

    // Osvježi derived services kada se promjene njihove tabele
    if (table == 'v2_app_settings') {
      V2AppSettingsService.initialize();
    } else if (table == 'v2_vozaci') {
      V2VozacCache.initialize();
    }
  }

  /// Uklanja red iz cache-a na DELETE event
  void removeFromCache(String table, String id) {
    // v2_racuni: keyed by putnik_id, ali Realtime DELETE payload šalje record 'id' (UUID reda)
    // Trebamo pronaći putnik_id koji odgovara tom id-u
    if (table == 'v2_racuni') {
      final key = racuniCache.entries
          .firstWhere(
            (e) => e.value['id']?.toString() == id,
            orElse: () => const MapEntry('', {}),
          )
          .key;
      if (key.isNotEmpty) {
        racuniCache.remove(key);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
      }
      return;
    }
    _cacheForTable(table)?.remove(id);
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
  }

  /// Optimistički patch — ažurira samo određena polja postojećeg cache reda i odmah emituje onCacheChanged.
  /// Koristi se nakon lokalnog DB write-a da se UI odmah osvježi bez čekanja WebSocket event-a.
  void patchCache(String table, String id, Map<String, dynamic> fields) {
    final target = _cacheForTable(table);
    if (target == null) return;
    final existing = target[id];
    if (existing == null) return; // red ne postoji u cache-u — WebSocket će ga dodati
    target[id] = {...existing, ...fields};
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
  }

  /// O(1) lookup: ime tabele → odgovarajući cache map
  late final Map<String, Map<String, Map<String, dynamic>>> _tableToCache = {
    'v2_polasci': polasciCache,
    'v2_statistika_istorija': statistikaCache,
    'v2_radnici': radniciCache,
    'v2_ucenici': uceniciCache,
    'v2_dnevni': dnevniCache,
    'v2_posiljke': posiljkeCache,
    'v2_vozaci': vozaciCache,
    'v2_vozila': vozilaCache,
    'v2_kapacitet_polazaka': kapacitetCache,
    'v2_adrese': adreseCache,
    'v2_vozac_raspored': rasporedCache,
    'v2_vozac_putnik': vozacPutnikCache,
    'v2_vozac_lokacije': lokacijeCache,
    'v2_finansije_troskovi': troskoviCache,
    'v2_pumpa_config': pumpaCache,
    'v2_pin_zahtevi': pinCache,
    'v2_app_settings': settingsCache,
    // v2_racuni intentionally excluded — keyed by putnik_id, handled separately in upsertToCache
  };

  /// Vraća odgovarajući cache map po imenu tabele — O(1)
  Map<String, Map<String, dynamic>>? _cacheForTable(String table) {
    final cache = _tableToCache[table];
    if (cache == null) debugPrint('⚠️ [V2MasterRealtimeManager] Nepoznata tabela za cache: $table');
    return cache;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CHANNEL MANAGEMENT — subscribe / unsubscribe
  // ──────────────────────────────────────────────────────────────────────────

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<PostgresChangePayload>> _controllers = {};
  final Map<String, int> _listenerCount = {};
  final Map<String, Timer?> _reconnectTimers = {};

  /// Broadcast stream koji se emituje svaki put kad se cache manuelno promijeni.
  /// Listeneri (streamAktivniPutnici, streamSveAdrese...) reaguju bez Realtime-a.
  final StreamController<String> _cacheChangeController = StreamController<String>.broadcast();
  Stream<String> get _onCacheChanged => _cacheChangeController.stream;
  Stream<String> get onCacheChanged => _cacheChangeController.stream;

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
    _reconnectAttempts.remove(table);
    _channels[table]?.unsubscribe();
    _channels.remove(table);
    _controllers[table]?.close();
    _controllers.remove(table);
    _listenerCount.remove(table);
  }

  /// Reload cache za datu tabelu nakon reconnecta — pokriva stale podatke iz perioda disconnecta.
  /// Za polasci/statistika koristi posebne load metode; za infra tabele radi direktan DB upit.
  Future<void> _reloadCacheForTable(String table) async {
    try {
      if (table == 'v2_polasci') {
        polasciCache.clear();
        await _loadPolasciCache();
        _cacheChangeController.add('v2_polasci');
      } else if (table == 'v2_statistika_istorija') {
        statistikaCache.clear();
        await loadStatistikaCache();
        _cacheChangeController.add('v2_statistika_istorija');
      } else {
        // Generički infra reload — direktan upit, fill u odgovarajući cache
        final targetCache = _cacheForTable(table);
        if (targetCache == null) return;
        // Primijeni iste filtere kao pri inicijalnom učitavanju
        final query = switch (table) {
          'v2_radnici' ||
          'v2_ucenici' ||
          'v2_dnevni' ||
          'v2_posiljke' =>
            _db.from(table).select().eq('status', 'aktivan'),
          'v2_kapacitet_polazaka' => _db.from(table).select().eq('aktivan', true),
          'v2_vozac_lokacije' => _db.from(table).select().eq('aktivan', true),
          'v2_finansije_troskovi' => _db.from(table).select().eq('aktivan', true),
          'v2_pin_zahtevi' => _db.from(table).select().eq('status', 'ceka'),
          _ => _db.from(table).select(),
        };
        final rows = await query;
        targetCache.clear();
        _fillCache(targetCache, rows);
        _cacheChangeController.add(table);
        debugPrint('✅ [V2MasterRealtimeManager] Reconnect reload "$table": ${targetCache.length} redova');
      }
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _reloadCacheForTable "$table": $e');
    }
  }

  void _handleStatus(String table, RealtimeSubscribeStatus status, dynamic error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        // Ako je ovo reconnect (ne prvi subscribe), reload cache da popunimo stale podatke
        if ((_reconnectAttempts[table] ?? 0) > 0) {
          _reconnectAttempts.remove(table);
          debugPrint('🔄 [V2MasterRealtimeManager] Reconnect "$table" — osvježavam cache...');
          _reloadCacheForTable(table);
        }
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

  final Map<String, int> _reconnectAttempts = {};

  void _scheduleReconnect(String table) {
    _reconnectTimers[table]?.cancel();

    final delays = [3, 6, 10];
    final attempt = (_reconnectAttempts[table] ?? 0).clamp(0, delays.length - 1);
    final delay = delays[attempt];
    _reconnectAttempts[table] = (_reconnectAttempts[table] ?? 0) + 1;

    _reconnectTimers[table] = Timer(Duration(seconds: delay), () async {
      _reconnectTimers[table] = null;
      if ((_listenerCount[table] ?? 0) <= 0) {
        _reconnectAttempts.remove(table);
        return;
      }

      final existing = _channels[table];
      if (existing != null) {
        try {
          await _db.removeChannel(existing);
        } catch (_) {}
        _channels.remove(table);
      }

      // Kratka pauza da SDK završi čišćenje kanala
      await Future.delayed(const Duration(milliseconds: 200));

      if ((_listenerCount[table] ?? 0) <= 0) {
        _reconnectAttempts.remove(table);
        return;
      }
      _createChannel(table);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOOKUP HELPERS — česte operacije iz servisa/screena
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
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  /// Popuni cache mapu iz liste redova
  static void _fillCache(Map<String, Map<String, dynamic>> cache, List rows) {
    for (final row in rows) {
      cache[row['id'].toString()] = Map<String, dynamic>.from(row as Map<String, dynamic>);
    }
  }

  /// Dodaje '_tabela' tag i 'broj_telefona' alias u red putnika.
  /// v2_* tabele čuvaju broj u koloni 'telefon', ali enrichment očekuje 'broj_telefona'.
  static Map<String, dynamic> _tagRow(Map<String, dynamic> row, String tabela) {
    return {
      ...row,
      '_tabela': tabela,
      'broj_telefona': row['telefon'], // alias za enrichment
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WRITE OPERACIJE — jedino mesto za direktne upite ka bazi
  // ──────────────────────────────────────────────────────────────────────────

  static const List<String> putnikTabele = ['v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke'];

  /// Ažurira putnika u datoj tabeli
  Future<Map<String, dynamic>> updatePutnik(
    String id,
    Map<String, dynamic> updates,
    String tabela,
  ) async {
    final data = Map<String, dynamic>.from(updates);
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    data.remove('_tabela');
    data.remove('tip');
    final row = await _db.from(tabela).update(data).eq('id', id).select().single();
    final result = {...row, '_tabela': tabela};
    upsertToCache(tabela, result);
    return result;
  }

  /// Kreira novog putnika u datoj tabeli
  Future<Map<String, dynamic>> createPutnik(
    Map<String, dynamic> data,
    String tabela,
  ) async {
    final d = Map<String, dynamic>.from(data);
    final now = DateTime.now().toUtc().toIso8601String();
    d['created_at'] = now;
    d['updated_at'] = now;
    d.remove('_tabela');
    d.remove('tip');
    if (d['id'] == null) d.remove('id');
    final row = await _db.from(tabela).insert(d).select().single();
    final result = {...row, '_tabela': tabela};
    upsertToCache(tabela, result);
    return result;
  }

  /// Briše putnika i sve vezane podatke (trajno)
  Future<bool> deletePutnik(String id, String tabela) async {
    try {
      await _db.from('v2_pin_zahtevi').delete().eq('putnik_id', id);
      await _db.from('v2_polasci').delete().eq('putnik_id', id);
      await _db.from('v2_vozac_putnik').delete().eq('putnik_id', id);
      await _db.from(tabela).delete().eq('id', id);
      removeFromCache(tabela, id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] deletePutnik error: $e');
      return false;
    }
  }

  /// Ažurira PIN putnika
  Future<void> updatePin(String id, String noviPin, String tabela) async {
    await _db.from(tabela).update({
      'pin': noviPin,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Dohvata podatke firme iz v2_racuni po putnik_id
  /// Prvo provjeri cache, pa udari DB samo ako nema
  Future<Map<String, dynamic>?> getFirma(String putnikId) async {
    final cached = racuniCache[putnikId];
    if (cached != null) return cached;
    try {
      final row = await _db
          .from('v2_racuni')
          .select('firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa')
          .eq('putnik_id', putnikId)
          .maybeSingle();
      if (row != null) {
        racuniCache[putnikId] = Map<String, dynamic>.from(row as Map);
      }
      return row;
    } catch (e) {
      debugPrint('❌ [RM] getFirma error: $e');
      return null;
    }
  }

  /// Upsert podataka firme u v2_racuni
  Future<void> upsertFirma({
    required String putnikId,
    required String putnikTabela,
    required String firmaNaziv,
    String? firmaPib,
    String? firmaMb,
    String? firmaZiro,
    String? firmaAdresa,
  }) async {
    await _db.from('v2_racuni').upsert({
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

  /// Dohvata putnika po PIN-u iz date tabele
  Future<Map<String, dynamic>?> getByPin(String pin, String tabela) async {
    final row = await _db
        .from(tabela)
        .select('id,ime,status,telefon,adresa_bc_id,adresa_vs_id,pin,email,treba_racun,created_at,updated_at')
        .eq('pin', pin)
        .maybeSingle();
    if (row == null) return null;
    return {...row, '_tabela': tabela};
  }

  /// Dohvata putnika iz bilo koje od 4 tabele — prvo cache, pa DB
  Future<Map<String, dynamic>?> findPutnikById(String id) async {
    final cached = getPutnikById(id);
    if (cached != null) return cached;
    for (final tabela in putnikTabele) {
      final row = await _db
          .from(tabela)
          .select('id,ime,status,telefon,adresa_bc_id,adresa_vs_id,pin,email,treba_racun,created_at,updated_at')
          .eq('id', id)
          .maybeSingle();
      if (row != null) return {...row, '_tabela': tabela};
    }
    return null;
  }

  /// Dohvata putnika po telefonu (prvo pretražuje cache, pa DB ako nije nađen)
  Future<Map<String, dynamic>?> findByTelefon(String telefon) async {
    if (telefon.isEmpty) return null;
    final normalized = _normalizePhone(telefon);

    // Prvo pretraži lokalni cache — 0 DB upita
    for (final tabela in putnikTabele) {
      final cache = _cacheForTable(tabela);
      if (cache == null) continue;
      for (final row in cache.values) {
        final t = row['telefon'] as String? ?? '';
        final t2 = row['telefon_2'] as String? ?? '';
        if ((t.isNotEmpty && _normalizePhone(t) == normalized) ||
            (t2.isNotEmpty && _normalizePhone(t2) == normalized)) {
          return {...row, '_tabela': tabela};
        }
      }
    }

    // Fallback: DB upit (cache prazan ili putnik neaktivan)
    for (final tabela in putnikTabele) {
      final svi = await _db
          .from(tabela)
          .select(
              'id, ime, telefon, telefon_2, adresa_bc_id, adresa_vs_id, status, pin, email, treba_racun, created_at, updated_at')
          .or('telefon.ilike.%${normalized.replaceAll('+', '')},telefon_2.ilike.%${normalized.replaceAll('+', '')}');
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

  /// Generički stream iz cache-a — jedna logika za sve tabele.
  ///
  /// [tables] — lista tabela čije promjene aktiviraju osvježavanje.
  /// [build]  — sinhron builder koji čita iz cache-a i vraća vrijednost.
  ///
  /// Koristi se u svim servisima umjesto ponovljenog StreamController boilerplatea.
  /// Emituje odmah (Future.microtask) i zatim na svaku promjenu odgovarajućih tabela.
  Stream<T> streamFromCache<T>({
    required List<String> tables,
    required T Function() build,
  }) {
    StreamSubscription<String>? sub;
    late StreamController<T> controller;

    void emit() {
      if (!controller.isClosed) controller.add(build());
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        emit();
        sub = onCacheChanged.where(tables.contains).listen((_) => emit());
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
        controller.close();
      },
    );

    return controller.stream;
  }

  /// Stream aktivnih putnika iz cache-a — 0 DB upita
  Stream<List<V2RegistrovaniPutnik>> streamAktivniPutnici() {
    StreamSubscription<String>? cacheSub;
    late StreamController<List<V2RegistrovaniPutnik>> controller;

    void emit() {
      if (controller.isClosed) return;
      final putnici = getAllPutnici().map((row) => V2RegistrovaniPutnik.fromMap(row)).toList()
        ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase()));
      controller.add(putnici);
    }

    controller = StreamController<List<V2RegistrovaniPutnik>>.broadcast(
      onListen: () {
        emit();
        cacheSub = _onCacheChanged.where((t) => putnikTabele.contains(t)).listen((_) => emit());
      },
      onCancel: () {
        cacheSub?.cancel();
        cacheSub = null;
        controller.close();
      },
    );
    return controller.stream;
  }

  static String _normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ──────────────────────────────────────────────────────────────────────────

  void dispose() {
    for (final sub in _staticSubscriptions) {
      sub.cancel();
    }
    _staticSubscriptions.clear();
    for (final t in _reconnectTimers.values) {
      t?.cancel();
    }
    _reconnectTimers.clear();
    _reconnectAttempts.clear();
    for (final ch in _channels.values) {
      ch.unsubscribe();
    }
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
    _channels.clear();
    _controllers.clear();
    _listenerCount.clear();
    _cacheChangeController.close();
  }
}
