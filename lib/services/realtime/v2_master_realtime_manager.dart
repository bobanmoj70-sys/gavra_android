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
/// auditLogCache    ← v2_audit_log           (posljednjih 200 zapisa, realtime feed)
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

  // ──────────────────────────────────────────────────────────────────────────
  // IN-MEMORY CACHE — ključ je uvek 'id' reda
  // ──────────────────────────────────────────────────────────────────────────

  // --- Dnevni (čisti se na novi dan) ---
  /// v2_polasci — svi aktivni dani (pon–pet)
  final Map<String, Map<String, dynamic>> polasciCache = {};

  /// v2_statistika_istorija za tekući dan
  final Map<String, Map<String, dynamic>> statistikaCache = {};

  /// v2_audit_log — posljednjih N zapisa za tekući dan (realtime feed)
  final Map<String, Map<String, dynamic>> auditLogCache = {};

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

  /// Reverse lookup: racun UUID → putnik_id (za O(1) DELETE handling)
  final Map<String, String> _racuniIdToPutnikId = {};

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

  /// Debounce timeri za derived service reinicijalizacije (vozaci, settings)
  final Map<String, Timer> _debounceTimers = {};

  /// Debounce helper — poziva [fn] jednom nakon 300ms tišine za dati [key]
  void _debounceTimer(String key, void Function() fn) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(const Duration(milliseconds: 300), fn);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    if (!isSupabaseReady) {
      debugPrint('❌ [V2MasterRealtimeManager] Supabase nije spreman');
      return;
    }
    _loadedDate = _today();

    // Pretplati se na sve tabele PRE nego što počne DB fetch — eliminise "mrtvu zonu"
    // od ~100-500ms u kojoj Realtime event može stići a kanal još ne postoji.
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
      'v2_audit_log',
    ];
    for (final tabela in staticTabele) {
      _staticSubscriptions.add(subscribe(tabela).listen((_) {}));
    }

    await Future.wait([
      _loadPolasciCache(),
      v2LoadStatistikaCache(),
      _loadPutniciCaches(),
      _loadInfraCache(),
      _loadRacuniCache(),
      _loadAuditLogCache(),
    ]).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('⚠️ [RM] initialize() timeout — nastavlja sa djelimično popunjenim cache-om');
        return [];
      },
    );

    _initialized = true;

    // Obavijesti sve stream-ove koji su čekali na isInitialized — triggera inicijalni emit
    if (!_cacheChangeController.isClosed) {
      for (final table in const [
        'v2_polasci',
        'v2_radnici',
        'v2_ucenici',
        'v2_dnevni',
        'v2_posiljke',
        'v2_vozac_raspored',
        'v2_vozac_putnik',
        'v2_statistika_istorija',
      ]) {
        _cacheChangeController.add(table);
      }
    }

    debugPrint(
        '✅ [RM] polasci=${polasciCache.length} radnici=${radniciCache.length} ucenici=${uceniciCache.length} dnevni=${dnevniCache.length} vozaci=${vozaciCache.length}');
  }

  /// Forsira refresh polasciCache bez promjene dana (npr. nakon ručnog dodavanja termina)
  Future<void> v2RefreshPolasciCache() async {
    polasciCache.clear();
    await _loadPolasciCache();
    if (!_cacheChangeController.isClosed) {
      _cacheChangeController.add('v2_polasci');
    }
  }

  /// Poziva se iz AppLifecycleObserver kad datum nije isti
  Future<void> v2RefreshForNewDay() async {
    final today = _today();
    if (_loadedDate == today) return;
    _loadedDate = today;
    polasciCache.clear();
    statistikaCache.clear();
    await Future.wait([
      _loadPolasciCache(),
      v2LoadStatistikaCache(),
    ]);
    if (!_cacheChangeController.isClosed) {
      _cacheChangeController.add('v2_polasci');
      _cacheChangeController.add('v2_statistika_istorija');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadPolasciCache() async {
    try {
      final rows = await supabase
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
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadPolasciCache: $e');
    }
  }

  /// Puni/osvežava statistikaCache za tekući dan — poziva se on-demand (pazar, profil, lista)
  Future<void> v2LoadStatistikaCache() async {
    try {
      final rows = await supabase
          .from('v2_statistika_istorija')
          .select(
            'id, putnik_id, putnik_ime, putnik_tabela, datum, dan, '
            'grad, vreme, tip, iznos, vozac_id, vozac_ime, detalji, created_at, '
            'placeni_mesec, placena_godina',
          )
          .eq('datum', _loadedDate!);
      statistikaCache.clear();
      for (final row in rows) {
        statistikaCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadStatistikaCache: $e');
    }
  }

  Future<void> _loadPutniciCaches() async {
    try {
      final results = await Future.wait([
        supabase
            .from('v2_radnici')
            .select(
              'id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
              'pin, email, cena_po_danu, broj_mesta, treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        supabase
            .from('v2_ucenici')
            .select(
              'id, ime, status, telefon, telefon_oca, telefon_majke, '
              'adresa_bc_id, adresa_vs_id, pin, email, cena_po_danu, broj_mesta, '
              'treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        supabase
            .from('v2_dnevni')
            .select(
              'id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
              'pin, email, cena, broj_mesta, treba_racun, created_at, updated_at',
            )
            .eq('status', 'aktivan'),
        supabase
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
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadPutniciCaches: $e');
    }
  }

  Future<void> _loadInfraCache() async {
    try {
      final results = await Future.wait([
        supabase.from('v2_vozaci').select('id, ime, email, telefon, sifra, boja'),
        supabase
            .from('v2_vozila')
            .select('id, registarski_broj, marka, model, godina_proizvodnje, kilometraza, napomena, '
                'broj_sasije, registracija_vazi_do, '
                'mali_servis_datum, mali_servis_km, veliki_servis_datum, veliki_servis_km, '
                'alternator_datum, alternator_km, akumulator_datum, akumulator_km, '
                'gume_datum, gume_opis, gume_prednje_datum, gume_prednje_opis, gume_prednje_km, '
                'gume_zadnje_datum, gume_zadnje_opis, gume_zadnje_km, '
                'plocice_datum, plocice_km, plocice_prednje_datum, plocice_prednje_km, '
                'plocice_zadnje_datum, plocice_zadnje_km, trap_datum, trap_km, radio'),
        supabase.from('v2_kapacitet_polazaka').select('id, grad, vreme, max_mesta, aktivan').eq('aktivan', true),
        supabase.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng, created_at, updated_at'),
        supabase.from('v2_vozac_raspored').select('id, dan, grad, vreme, vozac_id, created_at, updated_at'),
        supabase
            .from('v2_vozac_putnik')
            .select('id, putnik_id, putnik_tabela, vozac_id, dan, grad, vreme, created_at, updated_at'),
        supabase
            .from('v2_finansije_troskovi')
            .select('id, naziv, iznos, tip, aktivan, mesecno, vozac_id, mesec, godina, created_at')
            .eq('aktivan', true),
        supabase.from('v2_pumpa_config').select('id, kapacitet_litri, alarm_nivo, pocetno_stanje, updated_at'),
        supabase
            .from('v2_vozac_lokacije')
            .select('id, vozac_id, lat, lng, grad, vreme_polaska, smer, putnici_eta, aktivan, updated_at')
            .eq('aktivan', true),
        supabase
            .from('v2_pin_zahtevi')
            .select('id, putnik_id, putnik_tabela, email, telefon, status, created_at, updated_at')
            .eq('status', 'ceka'),
        supabase.from('v2_app_settings').select(
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

      // Osvježi V2VozacCache i AppSettings paralelno — oba čitaju iz već popunjenih cache-ova
      await Future.wait([V2VozacCache.initialize(), V2AppSettingsService.initialize()]);
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadInfraCache: $e');
    }
  }

  /// Učitava sve v2_racuni zapise u racuniCache (keyed by putnik_id)
  Future<void> _loadRacuniCache() async {
    try {
      final rows = await supabase.from('v2_racuni').select(
          'id, putnik_id, putnik_tabela, firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa, updated_at');
      racuniCache.clear();
      _racuniIdToPutnikId.clear();
      for (final row in (rows as List)) {
        final putnikId = row['putnik_id']?.toString();
        final rowId = row['id']?.toString();
        if (putnikId != null) {
          racuniCache[putnikId] = Map<String, dynamic>.from(row as Map);
          if (rowId != null) _racuniIdToPutnikId[rowId] = putnikId;
        }
      }
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadRacuniCache: $e');
    }
  }

  /// Učitava posljednjih 200 audit log zapisa u auditLogCache (keyed by id).
  Future<void> _loadAuditLogCache() async {
    try {
      final rows = await supabase
          .from('v2_audit_log')
          .select('id, tip, aktor_id, aktor_ime, aktor_tip, putnik_id, putnik_ime, putnik_tabela, '
              'dan, grad, vreme, polazak_id, detalji, created_at')
          .order('created_at', ascending: false)
          .limit(200);
      auditLogCache.clear();
      for (final row in rows) {
        auditLogCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] _loadAuditLogCache: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────

  /// Ažurira odgovarajući cache na INSERT/UPDATE event
  void v2UpsertToCache(String table, Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;

    // v2_racuni je keyed by putnik_id (ne id) — poseban handling
    if (table == 'v2_racuni') {
      final putnikId = record['putnik_id']?.toString();
      if (putnikId != null) {
        racuniCache[putnikId] = Map<String, dynamic>.from(record);
        if (id.isNotEmpty) _racuniIdToPutnikId[id] = putnikId;
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
    // Poništi cached listu putnika ako se promijenio putnik cache
    if (putnikTabele.contains(table)) _invalidatePutniciCache();
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);

    // Osvježi derived services uz debounce — sprečava višestruke reinicijalizacije
    // pri bulk Realtime eventima (npr. 5 vozača UPDATE odjednom)
    if (table == 'v2_app_settings') {
      _debounceTimer('_settings', () => V2AppSettingsService.initialize());
    } else if (table == 'v2_vozaci') {
      _debounceTimer('_vozaci', () => V2VozacCache.initialize());
    }
  }

  /// Uklanja red iz cache-a na DELETE event
  void v2RemoveFromCache(String table, String id) {
    // v2_racuni: keyed by putnik_id, ali Realtime DELETE payload šalje record 'id' (UUID reda)
    // Trebamo pronaći putnik_id koji odgovara tom id-u
    if (table == 'v2_racuni') {
      final putnikId = _racuniIdToPutnikId.remove(id);
      if (putnikId != null) {
        racuniCache.remove(putnikId);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
      }
      return;
    }
    _cacheForTable(table)?.remove(id);
    if (putnikTabele.contains(table)) _invalidatePutniciCache();
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
  }

  /// Optimistički patch — ažurira samo određena polja postojećeg cache reda i odmah emituje onCacheChanged.
  /// Koristi se nakon lokalnog DB write-a da se UI odmah osvježi bez čekanja WebSocket event-a.
  void v2PatchCache(String table, String id, Map<String, dynamic> fields) {
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
    'v2_audit_log': auditLogCache,
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
    final channel = supabase.channel('v2master:$table');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              final id = payload.oldRecord['id']?.toString();
              if (id != null) v2RemoveFromCache(table, id);
            } else {
              final rec = payload.newRecord;
              if (rec.isNotEmpty) v2UpsertToCache(table, rec);
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
        await v2LoadStatistikaCache();
        _cacheChangeController.add('v2_statistika_istorija');
      } else if (table == 'v2_racuni') {
        racuniCache.clear();
        await _loadRacuniCache();
        _cacheChangeController.add('v2_racuni');
      } else if (table == 'v2_audit_log') {
        await _loadAuditLogCache();
        _cacheChangeController.add('v2_audit_log');
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
            supabase.from(table).select().eq('status', 'aktivan'),
          'v2_kapacitet_polazaka' => supabase.from(table).select().eq('aktivan', true),
          'v2_vozac_lokacije' => supabase.from(table).select().eq('aktivan', true),
          'v2_finansije_troskovi' => supabase.from(table).select().eq('aktivan', true),
          'v2_pin_zahtevi' => supabase.from(table).select().eq('status', 'ceka'),
          _ => supabase.from(table).select(),
        };
        final rows = await query;
        targetCache.clear();
        // Putnik tabele zahtijevaju _tagRow (dodaje _tabela i broj_telefona alias)
        const putnikTabelaSet = {'v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke'};
        if (putnikTabelaSet.contains(table)) {
          for (final row in rows) {
            final r = row;
            targetCache[r['id'].toString()] = _tagRow(r, table);
          }
        } else {
          _fillCache(targetCache, rows);
        }
        _cacheChangeController.add(table);
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

    // Eksponencijalni backoff: 3, 6, 10, 20, 30, 60s — max 60s
    const delays = [3, 6, 10, 20, 30, 60];
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
          await supabase.removeChannel(existing);
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

  /// Cached lista svih putnika — poništava se samo kad se putnik cache promijeni
  List<Map<String, dynamic>>? _allPutniciCache;

  /// Poništi _allPutniciCache kad se promijeni bilo koji putnik cache.
  /// Poziva se iz upsertToCache i removeFromCache.
  void _invalidatePutniciCache() => _allPutniciCache = null;

  /// Vraća sve aktivne putnike iz sva 4 cache-a objedinjeno — O(1) za ponovljene pozive
  List<Map<String, dynamic>> v2GetAllPutnici() {
    return _allPutniciCache ??= [
      ...radniciCache.values,
      ...uceniciCache.values,
      ...dnevniCache.values,
      ...posiljkeCache.values,
    ];
  }

  /// Vraća putnika po ID-u pretražujući sva 4 cache-a
  Map<String, dynamic>? v2GetPutnikById(String id) {
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
  Future<Map<String, dynamic>> v2UpdatePutnik(
    String id,
    Map<String, dynamic> updates,
    String tabela,
  ) async {
    final data = Map<String, dynamic>.from(updates);
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    data.remove('_tabela');
    data.remove('tip');
    final row = await supabase.from(tabela).update(data).eq('id', id).select().single();
    final result = {...row, '_tabela': tabela};
    v2UpsertToCache(tabela, result);
    return result;
  }

  /// Kreira novog putnika u datoj tabeli
  Future<Map<String, dynamic>> v2CreatePutnik(
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
    final row = await supabase.from(tabela).insert(d).select().single();
    final result = {...row, '_tabela': tabela};
    v2UpsertToCache(tabela, result);
    return result;
  }

  /// Briše putnika i sve vezane podatke (trajno)
  Future<bool> v2DeletePutnik(String id, String tabela) async {
    try {
      // Briši vezane podatke paralelno, pa tek onda putnika (FK constraint)
      await Future.wait([
        supabase.from('v2_pin_zahtevi').delete().eq('putnik_id', id),
        supabase.from('v2_polasci').delete().eq('putnik_id', id),
        supabase.from('v2_vozac_putnik').delete().eq('putnik_id', id),
      ]);
      await supabase.from(tabela).delete().eq('id', id);
      // Ukloni putnika iz glavnog cache-a
      v2RemoveFromCache(tabela, id);
      // Odmah očisti sve vezane redove iz polasciCache i vozacPutnikCache
      // (Realtime DELETE eventi bi stigli jedan po jedan — ovo ih preduhitruje)
      polasciCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      vozacPutnikCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      pinCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      // Očisti i racuniCache — keyed by putnik_id, plus reverse map
      final racunId = racuniCache[id]?['id']?.toString();
      racuniCache.remove(id);
      if (racunId != null) _racuniIdToPutnikId.remove(racunId);
      if (!_cacheChangeController.isClosed) {
        _cacheChangeController.add('v2_polasci');
        _cacheChangeController.add('v2_vozac_putnik');
      }
      return true;
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] deletePutnik error: $e');
      return false;
    }
  }

  /// Ažurira PIN putnika
  Future<void> v2UpdatePin(String id, String noviPin, String tabela) async {
    try {
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      await supabase.from(tabela).update({
        'pin': noviPin,
        'updated_at': updatedAt,
      }).eq('id', id);
      // Optimistički ažuriraj cache bez čekanja Realtime eventa
      v2PatchCache(tabela, id, {'pin': noviPin, 'updated_at': updatedAt});
    } catch (e) {
      debugPrint('❌ [V2MasterRealtimeManager] v2UpdatePin greška: $e');
      rethrow;
    }
  }

  /// Dohvata podatke firme iz v2_racuni po putnik_id
  /// Prvo provjeri cache, pa udari DB samo ako nema
  Future<Map<String, dynamic>?> v2GetFirma(String putnikId) async {
    final cached = racuniCache[putnikId];
    if (cached != null) return cached;
    try {
      final row = await supabase
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
  Future<void> v2UpsertFirma({
    required String putnikId,
    required String putnikTabela,
    required String firmaNaziv,
    String? firmaPib,
    String? firmaMb,
    String? firmaZiro,
    String? firmaAdresa,
  }) async {
    await supabase.from('v2_racuni').upsert({
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
  Future<Map<String, dynamic>?> v2GetByPin(String pin, String tabela) async {
    final row = await supabase
        .from(tabela)
        .select('id,ime,status,telefon,adresa_bc_id,adresa_vs_id,pin,email,treba_racun,created_at,updated_at')
        .eq('pin', pin)
        .maybeSingle();
    if (row == null) return null;
    return {...row, '_tabela': tabela};
  }

  /// Dohvata putnika iz bilo koje od 4 tabele — prvo cache, pa DB
  Future<Map<String, dynamic>?> v2FindPutnikById(String id) async {
    final cached = v2GetPutnikById(id);
    if (cached != null) return cached;
    // Upitaj sve 4 tabele paralelno — uzmi prvi non-null rezultat
    const cols =
        'id,ime,status,telefon,adresa_bc_id,adresa_vs_id,pin,email,treba_racun,cena,cena_po_danu,created_at,updated_at';
    final results = await Future.wait(
      putnikTabele.map((tabela) => supabase.from(tabela).select(cols).eq('id', id).maybeSingle()),
    );
    for (int i = 0; i < results.length; i++) {
      final row = results[i];
      if (row != null) return {...row, '_tabela': putnikTabele[i]};
    }
    return null;
  }

  /// Dohvata putnika po telefonu (prvo pretražuje cache, pa DB ako nije nađen)
  Future<Map<String, dynamic>?> v2FindByTelefon(String telefon) async {
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
      final svi = await supabase
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
  Stream<T> v2StreamFromCache<T>({
    required List<String> tables,
    required T Function() build,
  }) {
    StreamSubscription<String>? sub;
    Timer? debounce;
    late StreamController<T> controller;

    void emit() {
      if (!controller.isClosed) controller.add(build());
    }

    void scheduleEmit() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 150), emit);
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        emit();
        sub = onCacheChanged.where(tables.contains).listen((_) => scheduleEmit());
      },
      onCancel: () async {
        // Ne zatvaraj controller — broadcast stream može dobiti novog listenera
        debounce?.cancel();
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  /// Stream aktivnih putnika iz cache-a — 0 DB upita
  Stream<List<V2RegistrovaniPutnik>> streamAktivniPutnici() => v2StreamFromCache<List<V2RegistrovaniPutnik>>(
        tables: putnikTabele,
        build: () => v2GetAllPutnici().map((row) => V2RegistrovaniPutnik.fromMap(row)).toList()
          ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase())),
      );

  /// Stream audit log zapisa iz cache-a — 0 DB upita, sortiran created_at DESC.
  /// Cache drži posljednjih 200 zapisa (punjenih pri init i Realtime INSERT).
  Stream<List<Map<String, dynamic>>> streamAuditLog() => v2StreamFromCache<List<Map<String, dynamic>>>(
        tables: ['v2_audit_log'],
        build: () => auditLogCache.values.toList()
          ..sort((a, b) {
            final ca = a['created_at']?.toString() ?? '';
            final cb = b['created_at']?.toString() ?? '';
            return cb.compareTo(ca); // DESC
          }),
      );

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
  // ──────────────────────────────────────────────────────────────────────────

  void dispose() {
    for (final sub in _staticSubscriptions) {
      sub.cancel();
    }
    _staticSubscriptions.clear();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    _allPutniciCache = null;
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
