import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../models/v2_polazak.dart';
import '../../models/v2_registrovani_putnik.dart';
import '../../services/v2_app_settings_service.dart';
import '../../utils/v2_dan_utils.dart';
import '../../utils/v2_grad_adresa_validator.dart';
import '../../utils/v2_vozac_cache.dart';

/// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
/// V2MasterRealtimeManager â€” Äist, novi singleton za v2_ tabele
///
/// PRAVILA:
/// 1. Samo v2_ tabele â€” nikad stare (registrovani_putnici, itd.)
/// 2. Cache ime = taÄno ime tabele bez prefiksa: polasci, putnici, vozaci...
/// 3. subscribe/unsubscribe ostaje isti pattern kao RealtimeManager
/// 4. Inicijalizuje se JEDNOM iz main.dart â€” ne iz servisa
///
/// CACHE MAPA:
/// polasciCache     â† v2_polasci          (sedmiÄni, svi aktivni dani)
/// statistikaCache  â† v2_statistika_istorija (dnevni, filter po danas)
/// auditLogCache    â† v2_audit_log           (posljednjih 200 zapisa, realtime feed)
/// radniciCache     â† v2_radnici           (statiÄki, svi aktivni)
/// uceniciCache     â† v2_ucenici           (statiÄki, svi aktivni)
/// dnevniCache      â† v2_dnevni            (statiÄki, svi aktivni)
/// posiljkeCache    â† v2_posiljke          (statiÄki, sve aktivne)
/// vozaciCache      â† v2_vozaci            (statiÄki)
/// vozilaCache      â† v2_vozila            (statiÄki)
/// kapacitetCache   â† v2_kapacitet_polazaka (statiÄki, aktivni)
/// adreseCache      â† v3_adrese            (statiÄki)
/// rasporedCache    â† v2_vozac_raspored    (statiÄki)
/// vozacPutnikCache â† v2_vozac_putnik      (statiÄki)
/// lokacijeCache    â† v2_vozac_lokacije    (statiÄki, aktivne)
/// troskoviCache    â† v2_finansije_troskovi (statiÄki, aktivni)
/// pumpaCache       â† v2_pumpa_config      (statiÄki)
/// pinCache         â† v2_pin_zahtevi       (statiÄki)
/// settingsCache    â† v2_app_settings      (statiÄki)
/// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class V2MasterRealtimeManager {
  V2MasterRealtimeManager._internal();

  static final V2MasterRealtimeManager _instance = V2MasterRealtimeManager._internal();
  static V2MasterRealtimeManager get instance => _instance;

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // IN-MEMORY CACHE â€” kljuÄ je uvek 'id' reda
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // --- Dnevni (Äisti se na novi dan) ---
  /// v2_polasci â€” svi aktivni dani (ponâ€“pet)
  final Map<String, Map<String, dynamic>> polasciCache = {};

  /// v2_statistika_istorija za tekuÄ‡i dan
  final Map<String, Map<String, dynamic>> statistikaCache = {};

  /// v2_audit_log â€” posljednjih N zapisa za tekuÄ‡i dan (realtime feed)
  final Map<String, Map<String, dynamic>> auditLogCache = {};

  // --- Putnici (svi aktivni, statiÄki) ---
  /// v2_radnici â€” aktivni radnici
  final Map<String, Map<String, dynamic>> radniciCache = {};

  /// v2_ucenici â€” aktivni uÄenici
  final Map<String, Map<String, dynamic>> uceniciCache = {};

  /// v2_dnevni â€” aktivni dnevni putnici
  final Map<String, Map<String, dynamic>> dnevniCache = {};

  /// v2_posiljke â€” aktivne poÅ¡iljke
  final Map<String, Map<String, dynamic>> posiljkeCache = {};

  /// v3_putnici â€” svi aktivni putnici (unificirana tabela)
  final Map<String, Map<String, dynamic>> v3PutniciCache = {};

  // --- Infrastruktura (statiÄki) ---
  /// v2_vozaci
  final Map<String, Map<String, dynamic>> vozaciCache = {};

  /// v2_vozila
  final Map<String, Map<String, dynamic>> vozilaCache = {};

  /// v2_kapacitet_polazaka (samo aktivan=true)
  final Map<String, Map<String, dynamic>> kapacitetCache = {};

  /// v3_adrese
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

  /// v2_pumpa_punjenja â€” sva punjenja kuÄ‡ne pumpe, sortirana po datum DESC
  final Map<String, Map<String, dynamic>> punjenjaCache = {};

  /// v2_pumpa_tocenja â€” sva toÄenja po vozilu, sortirana po datum DESC
  final Map<String, Map<String, dynamic>> tocenjaCache = {};

  /// v2_pin_zahtevi
  final Map<String, Map<String, dynamic>> pinCache = {};

  /// v2_app_settings
  final Map<String, Map<String, dynamic>> settingsCache = {};

  /// v2_racuni â€” firma podaci po putnik_id (keyed by putnik_id)
  final Map<String, Map<String, dynamic>> racuniCache = {};

  /// Reverse lookup: racun UUID â†’ putnik_id (za O(1) DELETE handling)
  final Map<String, String> _racuniIdToPutnikId = {};

  // --- V3 GETTERS & LOOKUPS ---
  /// VraÄ‡a vozaÄa po id-u iz cache-a
  Map<String, dynamic>? v2GetVozacById(String id) => vozaciCache[id];

  /// Brza pretraga id-a vozaÄa po imenu â€” O(1)
  String? v2GetVozacIdByIme(String ime) {
    if (ime.isEmpty) return null;
    final lIme = ime.toLowerCase();
    for (final v in vozaciCache.values) {
      if ((v['ime']?.toString() ?? '').toLowerCase() == lIme) return v['id']?.toString();
    }
    return null;
  }

  /// Individualna dodjela (v2_vozac_putnik) â€” O(1)
  String? v3FindIndividualnaDodjela(String putnikId, String dan) {
    if (putnikId.isEmpty || dan.isEmpty) return null;
    final lDan = dan.toLowerCase();
    for (final row in vozacPutnikCache.values) {
      if (row['putnik_id']?.toString() == putnikId && (row['dan']?.toString() ?? '').toLowerCase() == lDan) {
        return row['vozac_id']?.toString();
      }
    }
    return null;
  }

  /// VozaÄ iz rasporeda (v2_vozac_raspored) â€” O(1)
  String? v3GetVozacIzRasporeda(String grad, String dan, String vreme) {
    if (grad.isEmpty || dan.isEmpty || vreme.isEmpty) return null;
    final lDan = dan.toLowerCase();
    final lGrad = grad.toUpperCase();
    final lVreme = vreme.replaceAll(':', '');
    for (final row in rasporedCache.values) {
      if ((row['grad']?.toString() ?? '').toUpperCase() == lGrad &&
          (row['dan']?.toString() ?? '').toLowerCase() == lDan &&
          (row['vreme']?.toString() ?? '').replaceAll(':', '') == lVreme) {
        return row['vozac_id']?.toString();
      }
    }
    return null;
  }

  /// Brzi lookup adresa po gradu â€” O(1)
  Map<String, Map<String, dynamic>>? get v3AdreseGradCache {
    final Map<String, Map<String, Map<String, dynamic>>> cache = {};
    for (final row in adreseCache.values) {
      final grad = (row['grad']?.toString() ?? 'BC').toUpperCase();
      final id = row['id']?.toString();
      if (id != null) {
        cache[grad] ??= {};
        cache[grad]![id] = row;
      }
    }
    return cache.cast<String, Map<String, Map<String, dynamic>>>() as dynamic;
  }

  /// Map: Ime VozaÄa -> ID VozaÄa (O(1))
  Map<String, String> get v3VozaciIme2Id {
    final Map<String, String> map = {};
    for (final v in vozaciCache.values) {
      final ime = v['ime']?.toString();
      final id = v['id']?.toString();
      if (ime != null && id != null) map[ime] = id;
    }
    return map;
  }

  /// Brzi lookup toÄenja po vozilu â€” O(1)
  Map<String, Map<String, Map<String, dynamic>>> get v3TocenjaVoziloCache {
    final Map<String, Map<String, Map<String, dynamic>>> cache = {};
    for (final row in tocenjaCache.values) {
      final vId = row['vozilo_id']?.toString();
      final id = row['id']?.toString();
      if (vId != null && id != null) {
        cache[vId] ??= {};
        cache[vId]![id] = row;
      }
    }
    return cache;
  }

  /// NOVO: Stream zbirnog Home View-a (v2_home) â€” O(1) fetch gotovih podataka iz baze.
  /// Zamjenjuje v3StreamPutniciZaDan procesorski zahtjevno spajanje.
  Stream<List<Map<String, dynamic>>> v2StreamHomeView(String dan) {
    final lDan = dan.toLowerCase();
    // Buduci da je v2_home SQL VIEW, on se ne moze direktno osluskivati preko Realtime-a
    // u nekim verzijama Supabase-a, ali ovdje ga koristimo kao filter nad v2_polasci
    // jer v2_home zapravo cita v2_polasci.
    return v2StreamFromCache<List<Map<String, dynamic>>>(
      tables: const ['v2_polasci'],
      build: () {
        final List<Map<String, dynamic>> results = [];
        // Cita direktno iz polasciCache koji je vec u memoriji
        for (final row in polasciCache.values) {
          if ((row['dan']?.toString() ?? '').toLowerCase() == lDan) {
            results.add(row);
          }
        }
        return results;
      },
    );
  }

  /// Stream polazaka za konkretan dan â€” O(1) filtering
  Stream<List<Map<String, dynamic>>> v3StreamPutniciZaDan(String dan) {
    final lDan = dan.toLowerCase();
    return v2StreamFromCache<List<Map<String, dynamic>>>(
      tables: const ['v2_polasci', ...putnikTabele],
      build: () {
        final List<Map<String, dynamic>> results = [];
        v3PolasciCache.forEach((pId, dani) {
          if (pId == 'svi') return;
          final row = dani[lDan];
          if (row != null) results.add(row);
        });
        return results;
      },
    );
  }

  // --- V3 OPTIMIZACIJA (Index-based caching) ---
  /// v3PolasciCache â€” Key: putnik_id -> Value: Map(Dan, RedPodataka)
  final Map<String, Map<String, Map<String, dynamic>>> v3PolasciCache = {};

  /// v3PolasciModels â€” Instancirani V2Polazak objekti za O(1) streamove
  final Map<String, V2Polazak> v3PolasciModels = {};

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // State
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String? _loadedDate;
  String? get loadedDate => _loadedDate;

  /// Sedmica koja je uÄitana u polasciCache â€” koristi se u v2UpsertToCache
  /// da se izbjegne neslaganje kada pocetakTekuceSedmice() promijeni vrijednost
  /// (npr. app pokrenut u petak, Realtime INSERT dolazi u subotu)
  String? _loadedSedmica;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Subscriptions za statiÄke tabele iz initialize() â€” drÅ¾e _listenerCount >= 1
  /// tako da vanjski unsubscribe() nikad ne moÅ¾e zatvoriti te kanale.
  final List<StreamSubscription<PostgresChangePayload>> _staticSubscriptions = [];

  /// Debounce timeri za derived service reinicijalizacije (vozaci, settings)
  final Map<String, Timer> _debounceTimers = {};

  /// Debounce helper â€” poziva [fn] jednom nakon 300ms tiÅ¡ine za dati [key]
  void _debounceTimer(String key, void Function() fn) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(const Duration(milliseconds: 300), fn);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    if (!isSupabaseReady) {
      debugPrint('âŒ [V2MasterRealtimeManager] Supabase nije spreman');
      return;
    }
    _loadedDate = _today();

    // Pretplati se na sve tabele PRE nego Å¡to poÄne DB fetch â€” eliminise "mrtvu zonu"
    // od ~100-500ms u kojoj Realtime event moÅ¾e stiÄ‡i a kanal joÅ¡ ne postoji.
    const staticTabele = [
      // Putnici
      'v3_putnici',
      'v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke',
      // Polasci â€” glavna dnevna tabela, mora biti permanentno subscribe-ovana
      'v2_polasci',
      // Infrastruktura
      'v2_vozaci', 'v2_vozila', 'v3_adrese',
      'v2_finansije_troskovi', 'v2_pumpa_config', 'v2_app_settings',
      'v2_statistika_istorija',
      // Raspored / putnik mapping / lokacije / kapacitet / pin
      'v2_kapacitet_polazaka', 'v2_vozac_raspored', 'v2_vozac_putnik',
      'v2_vozac_lokacije', 'v2_pin_zahtevi',
      'v2_racuni',
      'v2_audit_log',
      // Gorivo â€” pumpa punjenja i toÄenja (autorefresh za v2_gorivo_screen)
      'v2_pumpa_punjenja', 'v2_pumpa_tocenja',
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
      _loadPumpaGorivoCache(),
    ]).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('âš ï¸ [RM] initialize() timeout â€” nastavlja sa djelimiÄno popunjenim cache-om');
        return [];
      },
    );

    _initialized = true;

    // Obavijesti sve stream-ove koji su Äekali na isInitialized â€” triggera inicijalni emit
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
        'âœ… [RM] polasci=${polasciCache.length} radnici=${radniciCache.length} ucenici=${uceniciCache.length} dnevni=${dnevniCache.length} vozaci=${vozaciCache.length}');
  }

  /// Forsira refresh polasciCache bez promjene dana (npr. nakon ruÄnog dodavanja termina)
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
    auditLogCache.clear();
    await Future.wait([
      _loadPolasciCache(),
      v2LoadStatistikaCache(),
      _loadAuditLogCache(),
    ]);
    if (!_cacheChangeController.isClosed) {
      _cacheChangeController.add('v2_polasci');
      _cacheChangeController.add('v2_statistika_istorija');
      _cacheChangeController.add('v2_audit_log');
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadPolasciCache() async {
    try {
      final sedmica = V2DanUtils.pocetakTekuceSedmice();
      _loadedSedmica = sedmica;
      final rows = await supabase
          .from('v2_polasci')
          .select('id, putnik_id, putnik_tabela, grad, zeljeno_vreme, dodeljeno_vreme, '
              'status, created_at, updated_at, processed_at, broj_mesta, '
              'alternativno_vreme_1, alternativno_vreme_2, adresa_id, '
              'otkazao, odobrio, pokupio, dan, datum_sedmice, '
              'placen, placen_iznos, placen_vozac_id, placen_vozac_ime, pokupljen_datum, datum_akcije, placen_tip')
          .inFilter('status', [
        'obrada',
        'odobreno',
        'otkazano',
        'odbijeno',
        'pokupljen',
      ]).eq('datum_sedmice', sedmica);
      v3PolasciCache.clear();
      for (final row in rows) {
        final normalized = Map<String, dynamic>.from(row);
        if (normalized['datum_sedmice'] != null) {
          normalized['datum_sedmice'] = normalized['datum_sedmice'].toString().split('T').first;
        }
        final pId = normalized['putnik_id']?.toString();
        final dan = normalized['dan']?.toString().toLowerCase();
        if (pId != null && dan != null) {
          v3PolasciCache[pId] ??= {};
          v3PolasciCache[pId]![dan] = normalized;
        }
        polasciCache[normalized['id'].toString()] = normalized;
      }
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] _loadPolasciCache: $e');
    }
  }

  /// Puni/osveÅ¾ava statistikaCache za tekuÄ‡i dan â€” poziva se on-demand (pazar, profil, lista)
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
      debugPrint('âŒ [V2MasterRealtimeManager] _loadStatistikaCache: $e');
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
      debugPrint('âŒ [V2MasterRealtimeManager] _loadPutniciCaches: $e');
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
        supabase.from('v3_adrese').select('id, naziv, grad, gps_lat, gps_lng, created_at, updated_at'),
        supabase.from('v2_vozac_raspored').select('id, dan, grad, vreme, vozac_id, created_at, updated_at'),
        supabase
            .from('v2_vozac_putnik')
            .select('id, putnik_id, putnik_tabela, vozac_id, dan, grad, vreme, datum_sedmice, created_at, updated_at'),
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

      // OsvjeÅ¾i V2VozacCache i AppSettings paralelno â€” oba Äitaju iz veÄ‡ popunjenih cache-ova
      await Future.wait([V2VozacCache.initialize(), V2AppSettingsService.initialize()]);
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] _loadInfraCache: $e');
    }
  }

  /// UÄitava sve v2_racuni zapise u racuniCache (keyed by putnik_id)
  Future<void> _loadRacuniCache() async {
    try {
      final rows = await supabase.from('v2_racuni').select(
          'id, putnik_id, putnik_tabela, firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa, updated_at');
      racuniCache.clear();
      _racuniIdToPutnikId.clear();
      for (final row in rows) {
        final putnikId = row['putnik_id']?.toString();
        final rowId = row['id']?.toString();
        if (putnikId != null) {
          racuniCache[putnikId] = Map<String, dynamic>.from(row);
          if (rowId != null) _racuniIdToPutnikId[rowId] = putnikId;
        }
      }
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] _loadRacuniCache: $e');
    }
  }

  /// UÄitava posljednjih 200 audit log zapisa u auditLogCache (keyed by id).
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
      debugPrint('âŒ [V2MasterRealtimeManager] _loadAuditLogCache: $e');
    }
  }

  /// UÄitava v2_pumpa_punjenja i v2_pumpa_tocenja u cache (gorivo screen autorefresh)
  Future<void> _loadPumpaGorivoCache() async {
    try {
      final results = await Future.wait([
        supabase
            .from('v2_pumpa_punjenja')
            .select('id, datum, litri, cena_po_litru, ukupno_cena, napomena, created_at')
            .order('datum', ascending: false)
            .order('created_at', ascending: false),
        supabase
            .from('v2_pumpa_tocenja')
            .select('id, datum, vozilo_id, litri, km_vozila, napomena, created_at')
            .order('datum', ascending: false)
            .order('created_at', ascending: false),
      ]);
      punjenjaCache.clear();
      for (final row in results[0]) {
        punjenjaCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      tocenjaCache.clear();
      for (final row in results[1]) {
        tocenjaCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] _loadPumpaGorivoCache: $e');
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// AÅ¾urira odgovarajuÄ‡i cache na INSERT/UPDATE event
  void v2UpsertToCache(String table, Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;

    // v3 Index for polasci
    if (table == 'v2_polasci') {
      final pId = record['putnik_id']?.toString();
      final dan = record['dan']?.toString().toLowerCase();
      if (pId != null && dan != null) {
        final existing = v3PolasciCache[pId] ??= {};
        existing[dan] = Map<String, dynamic>.from(record);
      }
    }

    // v2_racuni je keyed by putnik_id (ne id) â€” poseban handling
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

    // statistikaCache je dnevni â€” prihvati samo zapise za _loadedDate
    if (table == 'v2_statistika_istorija') {
      final datum = record['datum']?.toString();
      if (datum != null && datum != _loadedDate) return;
    }

    // polasciCache drÅ¾i samo aktivne statuse za tekuÄ‡u sedmicu â€” ukloni zapis ako status nije aktivan ili je iz druge sedmice
    if (table == 'v2_polasci') {
      const aktivniStatusi = {'obrada', 'odobreno', 'otkazano', 'odbijeno', 'pokupljen'};
      final status = record['status']?.toString();
      if (status != null && !aktivniStatusi.contains(status)) {
        target.remove(id);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
        return;
      }
      // Normalizuj datum_sedmice na yyyy-MM-dd (Realtime Å¡alje ISO sa sekundama)
      if (record['datum_sedmice'] != null) {
        record = {...record, 'datum_sedmice': record['datum_sedmice'].toString().split('T').first};
      }
      // IgnoriÅ¡i zapise koji nisu iz sedmice koja je uÄitana u cache
      // Koristimo _loadedSedmica (snapshot iz _loadPolasciCache) umjesto
      // dinamiÄkog pocetakTekuceSedmice() koji moÅ¾e promijeniti vrijednost
      // ako se sedmica promijeni dok je app otvoren (npr. petakâ†’subota)
      final recordSedmica = record['datum_sedmice']?.toString();
      final targetSedmica = _loadedSedmica ?? V2DanUtils.pocetakTekuceSedmice();
      if (recordSedmica != null && recordSedmica != targetSedmica) {
        target.remove(id);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
        return;
      }
    }

    // pinCache sadrÅ¾i samo zahtjeve sa status='ceka' â€” ako status nije 'ceka', ukloni iz cache-a
    if (table == 'v2_pin_zahtevi') {
      final status = record['status']?.toString();
      if (status != null && status != 'ceka') {
        target.remove(id);
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
        return;
      }
    }

    // SaÄuvaj postojeÄ‡i _tabela tag â€” realtime payload ne sadrÅ¾i _tabela
    final existingTabela = target[id]?['_tabela'] ?? table;
    // Putnik tabele zahtijevaju _tagRow â€” dodaje '_tabela' i 'broj_telefona' alias
    // (vaÅ¾no za Realtime INSERT koji ne prolazi kroz _loadPutniciCaches)
    if (putnikTabele.contains(table)) {
      target[id] = _tagRow({...record, '_tabela': existingTabela}, table);
    } else {
      target[id] = {...record, '_tabela': existingTabela};
    }
    // PoniÅ¡ti cached listu putnika ako se promijenio putnik cache
    if (putnikTabele.contains(table)) _invalidatePutniciCache();
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);

    // OsvjeÅ¾i derived services uz debounce â€” spreÄava viÅ¡estruke reinicijalizacije
    // pri bulk Realtime eventima (npr. 5 vozaÄa UPDATE odjednom)
    if (table == 'v2_app_settings') {
      _debounceTimer('_settings', () => V2AppSettingsService.initialize());
    } else if (table == 'v2_vozaci') {
      _debounceTimer('_vozaci', () => V2VozacCache.initialize());
    }
  }

  /// Uklanja red iz cache-a na DELETE event
  void v2RemoveFromCache(String table, String id) {
    // v3 Index for polasci
    if (table == 'v2_polasci') {
      final existing = polasciCache[id];
      if (existing != null) {
        final pId = existing['putnik_id']?.toString();
        final dan = existing['dan']?.toString().toLowerCase();
        if (pId != null && dan != null) {
          final existing = v3PolasciCache[pId];
          if (existing != null) {
            existing.remove(dan);
            if (existing.isEmpty) v3PolasciCache.remove(pId);
          }
        }
      }
    }

    // v2_racuni: keyed by putnik_id, ali Realtime DELETE payload Å¡alje record 'id' (UUID reda)
    // Trebamo pronaÄ‡i putnik_id koji odgovara tom id-u
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

  /// OptimistiÄki patch â€” aÅ¾urira samo odreÄ‘ena polja postojeÄ‡eg cache reda i odmah emituje onCacheChanged.
  /// Koristi se nakon lokalnog DB write-a da se UI odmah osvjeÅ¾i bez Äekanja WebSocket event-a.
  void v2PatchCache(String table, String id, Map<String, dynamic> fields) {
    final target = _cacheForTable(table);
    if (target == null) return;
    final existing = target[id];
    if (existing == null) return; // red ne postoji u cache-u â€” WebSocket Ä‡e ga dodati
    target[id] = {...existing, ...fields};
    if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
  }

  /// O(1) lookup: ime tabele â†’ odgovarajuÄ‡i cache map
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
    'v3_adrese': adreseCache,
    'v2_vozac_raspored': rasporedCache,
    'v2_vozac_putnik': vozacPutnikCache,
    'v2_vozac_lokacije': lokacijeCache,
    'v2_finansije_troskovi': troskoviCache,
    'v2_pumpa_config': pumpaCache,
    'v2_pumpa_punjenja': punjenjaCache,
    'v2_pumpa_tocenja': tocenjaCache,
    'v2_pin_zahtevi': pinCache,
    'v2_app_settings': settingsCache,
    'v2_audit_log': auditLogCache,
    'v3_putnici': v3PutniciCache,
    // v2_racuni intentionally excluded â€” keyed by putnik_id, handled separately in upsertToCache
  };

  /// VraÄ‡a odgovarajuÄ‡i cache map po imenu tabele â€” O(1)
  Map<String, Map<String, dynamic>>? _cacheForTable(String table) {
    final cache = _tableToCache[table];
    if (cache == null) debugPrint('âš ï¸ [V2MasterRealtimeManager] Nepoznata tabela za cache: $table');
    return cache;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CHANNEL MANAGEMENT â€” subscribe / unsubscribe
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<PostgresChangePayload>> _controllers = {};
  final Map<String, int> _listenerCount = {};
  final Map<String, Timer?> _reconnectTimers = {};

  /// Broadcast stream koji se emituje svaki put kad se cache manuelno promijeni.
  /// Listeneri (streamAktivniPutnici, streamSveAdrese...) reaguju bez Realtime-a.
  final StreamController<String> _cacheChangeController = StreamController<String>.broadcast();
  Stream<String> get onCacheChanged => _cacheChangeController.stream;

  /// Pretplati se na promene u tabeli.
  /// ViÅ¡e listenera moÅ¾e deliti isti channel.
  Stream<PostgresChangePayload> subscribe(String table) {
    if (!isSupabaseReady) {
      debugPrint('âŒ [V2MasterRealtimeManager] Cannot subscribe "$table": Supabase not ready');
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

  /// Odjavi se sa tabele â€” channel se zatvara kad nema viÅ¡e listenera
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

  /// Reload cache za datu tabelu nakon reconnecta â€” pokriva stale podatke iz perioda disconnecta.
  /// Za polasci/statistika koristi posebne load metode; za infra tabele radi direktan DB upit.
  Future<void> _reloadCacheForTable(String table) async {
    try {
      if (table == 'v2_polasci') {
        polasciCache.clear();
        await _loadPolasciCache();
        if (!_cacheChangeController.isClosed) _cacheChangeController.add('v2_polasci');
      } else if (table == 'v2_statistika_istorija') {
        statistikaCache.clear();
        await v2LoadStatistikaCache();
        if (!_cacheChangeController.isClosed) _cacheChangeController.add('v2_statistika_istorija');
      } else if (table == 'v2_racuni') {
        racuniCache.clear();
        await _loadRacuniCache();
        if (!_cacheChangeController.isClosed) _cacheChangeController.add('v2_racuni');
      } else if (table == 'v2_audit_log') {
        await _loadAuditLogCache();
        if (!_cacheChangeController.isClosed) _cacheChangeController.add('v2_audit_log');
      } else if (table == 'v2_pumpa_punjenja' || table == 'v2_pumpa_tocenja') {
        await _loadPumpaGorivoCache();
        if (!_cacheChangeController.isClosed) {
          _cacheChangeController.add('v2_pumpa_punjenja');
          _cacheChangeController.add('v2_pumpa_tocenja');
        }
      } else {
        // GeneriÄki infra reload â€” direktan upit, fill u odgovarajuÄ‡i cache
        final targetCache = _cacheForTable(table);
        if (targetCache == null) return;
        // Primijeni iste filtere kao pri inicijalnom uÄitavanju
        final query = switch (table) {
          'v2_radnici' => supabase
              .from(table)
              .select('id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
                  'pin, email, cena_po_danu, broj_mesta, treba_racun, created_at, updated_at')
              .eq('status', 'aktivan'),
          'v2_ucenici' => supabase
              .from(table)
              .select('id, ime, status, telefon, telefon_oca, telefon_majke, '
                  'adresa_bc_id, adresa_vs_id, pin, email, cena_po_danu, broj_mesta, '
                  'treba_racun, created_at, updated_at')
              .eq('status', 'aktivan'),
          'v2_dnevni' => supabase
              .from(table)
              .select('id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, '
                  'pin, email, cena, broj_mesta, treba_racun, created_at, updated_at')
              .eq('status', 'aktivan'),
          'v2_posiljke' => supabase
              .from(table)
              .select('id, ime, status, telefon, adresa_bc_id, adresa_vs_id, '
                  'pin, email, cena, treba_racun, created_at, updated_at')
              .eq('status', 'aktivan'),
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
            targetCache[row['id'].toString()] = _tagRow(row, table);
          }
        } else {
          _fillCache(targetCache, rows);
        }
        if (!_cacheChangeController.isClosed) _cacheChangeController.add(table);
      }
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] _reloadCacheForTable "$table": $e');
    }
  }

  void _handleStatus(String table, RealtimeSubscribeStatus status, dynamic error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        // Ako je ovo reconnect (ne prvi subscribe), reload cache da popunimo stale podatke
        if ((_reconnectAttempts[table] ?? 0) > 0) {
          _reconnectAttempts.remove(table);
          unawaited(_reloadCacheForTable(table));
        }
        break;

      case RealtimeSubscribeStatus.channelError:
        debugPrint('âŒ [V2MasterRealtimeManager] Channel error "$table": $error');
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

  void _scheduleReconnect(String table, {bool immediate = false}) {
    _reconnectTimers[table]?.cancel();

    // Eksponencijalni backoff: 3, 6, 10, 20, 30, 60s â€” max 60s
    const delays = [3, 6, 10, 20, 30, 60];
    final attempt = (_reconnectAttempts[table] ?? 0).clamp(0, delays.length - 1);
    final delay = immediate ? 0 : delays[attempt];
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

      // Kratka pauza da SDK zavrÅ¡i ÄiÅ¡Ä‡enje kanala
      await Future.delayed(const Duration(milliseconds: 200));

      if ((_listenerCount[table] ?? 0) <= 0) {
        _reconnectAttempts.remove(table);
        return;
      }
      _createChannel(table);
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // LOOKUP HELPERS â€” Äeste operacije iz servisa/screena
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// VraÄ‡a ime putnika iz odgovarajuÄ‡eg cache-a po putnik_tabela + putnik_id
  String? getIme(String putnikTabela, String putnikId) {
    final cache = _cacheForTable(putnikTabela);
    return cache?[putnikId]?['ime'] as String?;
  }

  /// Cached lista svih putnika â€” poniÅ¡tava se samo kad se putnik cache promijeni
  List<Map<String, dynamic>>? _allPutniciCache;

  /// PoniÅ¡ti _allPutniciCache kad se promijeni bilo koji putnik cache.
  /// Poziva se iz upsertToCache i removeFromCache.
  void _invalidatePutniciCache() => _allPutniciCache = null;

  /// VraÄ‡a sve aktivne putnike iz sva 4 cache-a objedinjeno â€” O(1) za ponovljene pozive
  List<Map<String, dynamic>> v2GetAllPutnici() {
    return _allPutniciCache ??= [
      ...radniciCache.values,
      ...uceniciCache.values,
      ...dnevniCache.values,
      ...posiljkeCache.values,
    ];
  }

  /// VraÄ‡a putnika po ID-u pretraÅ¾ujuÄ‡i sva 4 cache-a
  Map<String, dynamic>? v2GetPutnikById(String id) {
    return radniciCache[id] ?? uceniciCache[id] ?? dnevniCache[id] ?? posiljkeCache[id];
  }

  /// Sync Äitanje polasciCache za dati dan (kratica 'pon'/'uto'/...) â€” 0 DB upita.
  /// Enrichuje svaki polazak podacima putnika iz odgovarajuÄ‡eg cache-a.
  /// Koristi se direktno iz StreamBuilder-a u HomeScreen-u.
  List<Map<String, dynamic>> v2GetPutniciZaDan(String dan) {
    final danKey = dan.toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final polazak in polasciCache.values) {
      if (polazak['dan']?.toString() != danKey) continue;
      final putnikId = polazak['putnik_id']?.toString();
      final rp = putnikId != null ? v2GetPutnikById(putnikId) : null;
      result.add({
        ...polazak,
        if (rp != null) 'registrovani_putnici': rp,
        if (rp != null && rp['ime'] != null) 'putnik_ime': rp['ime'],
      });
    }
    return result;
  }

  /// Stream putnika za dati dan â€” reaguje na sve relevantne cache promjene.
  /// Jedan stream po pozivu; koristi v2StreamFromCache pa ne zatvara controller.
  /// HomeScreen kreira JEDAN ovakav stream i mijenja dan kroz setState.
  Stream<List<Map<String, dynamic>>> v2StreamPutniciZaDan(String dan) => v2StreamFromCache<List<Map<String, dynamic>>>(
        tables: const [
          'v2_polasci',
          'v2_radnici',
          'v2_ucenici',
          'v2_dnevni',
          'v2_posiljke',
          'v2_vozac_raspored',
          'v2_vozac_putnik',
        ],
        build: () => v2GetPutniciZaDan(dan),
      );

  /// VraÄ‡a ime vozaÄa iz cache-a
  String? getVozacIme(String vozacId) {
    return vozaciCache[vozacId]?['ime'] as String?;
  }

  /// VraÄ‡a naziv adrese iz cache-a
  String? getAdresaNaziv(String adresaId) {
    return adreseCache[adresaId]?['naziv'] as String?;
  }

  /// VraÄ‡a GPS koordinate adrese iz cache-a (null ako nisu upisane)
  Map<String, double>? getAdresaKoordinate(String adresaId) {
    final row = adreseCache[adresaId];
    if (row == null) return null;
    final lat = double.tryParse(row['gps_lat']?.toString() ?? '');
    final lng = double.tryParse(row['gps_lng']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    return {'lat': lat, 'lng': lng};
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // PRIVATE HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  /// Popuni cache mapu iz liste redova
  static void _fillCache(Map<String, Map<String, dynamic>> cache, List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      cache[row['id'].toString()] = Map<String, dynamic>.from(row);
    }
    // Special case for O(1) index of v2_polasci
    if (cache == instance.polasciCache) {
      instance.v3PolasciCache.clear();
      for (final row in rows) {
        final pId = row['putnik_id']?.toString();
        final dan = row['dan']?.toString().toLowerCase();
        if (pId != null && dan != null) {
          final existing = instance.v3PolasciCache[pId] ??= {};
          existing[dan] = Map<String, dynamic>.from(row);
        }
      }
    }
  }

  /// Dodaje '_tabela' tag i 'broj_telefona' alias u red putnika.
  /// v2_* tabele Äuvaju broj u koloni 'telefon', ali enrichment oÄekuje 'broj_telefona'.
  static Map<String, dynamic> _tagRow(Map<String, dynamic> row, String tabela) {
    return {
      ...row,
      '_tabela': tabela,
      'broj_telefona': row['telefon'], // alias za enrichment
    };
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // WRITE OPERACIJE â€” jedino mesto za direktne upite ka bazi
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static const List<String> putnikTabele = ['v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke'];

  /// AÅ¾urira putnika u datoj tabeli
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

  /// Migrira putnika iz jedne tabele u drugu (isti UUID, novi tip).
  /// ÄŒuva v2_vozac_putnik, v2_polasci i v2_pin_zahtevi â€” samo menja tabelu putnika.
  Future<Map<String, dynamic>> v2MigratePutnikTabela(
    String id,
    Map<String, dynamic> data,
    String staraTabela,
    String novaTabela,
  ) async {
    final d = Map<String, dynamic>.from(data);
    final now = DateTime.now().toUtc().toIso8601String();
    d['id'] = id;
    d['created_at'] = now;
    d['updated_at'] = now;
    d.remove('_tabela');
    d.remove('tip');

    // 1. ObriÅ¡i iz stare tabele (vezane tabele se NE briÅ¡u â€” putnik_id ostaje isti)
    await supabase.from(staraTabela).delete().eq('id', id);
    v2RemoveFromCache(staraTabela, id);

    // 2. Insertuj u novu tabelu sa istim UUID-om
    final row = await supabase.from(novaTabela).insert(d).select().single();
    final result = {...row, '_tabela': novaTabela};
    v2UpsertToCache(novaTabela, result);

    // 3. AÅ¾uriraj putnik_tabela u v2_racuni ako postoji
    try {
      await supabase.from('v2_racuni').update({'putnik_tabela': novaTabela, 'updated_at': now}).eq('putnik_id', id);
      final cached = racuniCache[id];
      if (cached != null) {
        racuniCache[id] = {...cached, 'putnik_tabela': novaTabela};
      }
    } catch (_) {
      // v2_racuni nije obavezan â€” ignoriÅ¡i ako ne postoji
    }

    if (!_cacheChangeController.isClosed) {
      _cacheChangeController.add(staraTabela);
      _cacheChangeController.add(novaTabela);
    }

    return result;
  }

  /// BriÅ¡e putnika i sve vezane podatke (trajno)
  Future<bool> v2DeletePutnik(String id, String tabela) async {
    try {
      // BriÅ¡i vezane podatke paralelno, pa tek onda putnika (FK constraint)
      await Future.wait([
        supabase.from('v2_pin_zahtevi').delete().eq('putnik_id', id),
        supabase.from('v2_polasci').delete().eq('putnik_id', id),
        supabase.from('v2_vozac_putnik').delete().eq('putnik_id', id),
      ]);
      await supabase.from(tabela).delete().eq('id', id);
      // Ukloni putnika iz glavnog cache-a
      v2RemoveFromCache(tabela, id);
      // Odmah oÄisti sve vezane redove iz polasciCache i vozacPutnikCache
      // (Realtime DELETE eventi bi stigli jedan po jedan â€” ovo ih preduhitruje)
      polasciCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      vozacPutnikCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      pinCache.removeWhere((_, v) => v['putnik_id']?.toString() == id);
      // OÄisti i racuniCache â€” keyed by putnik_id, plus reverse map
      final racunId = racuniCache[id]?['id']?.toString();
      racuniCache.remove(id);
      if (racunId != null) _racuniIdToPutnikId.remove(racunId);
      if (!_cacheChangeController.isClosed) {
        _cacheChangeController.add(tabela);
        _cacheChangeController.add('v2_polasci');
        _cacheChangeController.add('v2_vozac_putnik');
        _cacheChangeController.add('v2_pin_zahtevi');
      }
      return true;
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] deletePutnik error: $e');
      return false;
    }
  }

  /// AÅ¾urira PIN putnika
  Future<void> v2UpdatePin(String id, String noviPin, String tabela) async {
    try {
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      await supabase.from(tabela).update({
        'pin': noviPin,
        'updated_at': updatedAt,
      }).eq('id', id);
      // OptimistiÄki aÅ¾uriraj cache bez Äekanja Realtime eventa
      v2PatchCache(tabela, id, {'pin': noviPin, 'updated_at': updatedAt});
    } catch (e) {
      debugPrint('âŒ [V2MasterRealtimeManager] v2UpdatePin greÅ¡ka: $e');
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
        racuniCache[putnikId] = Map<String, dynamic>.from(row);
      }
      return row;
    } catch (e) {
      debugPrint('âŒ [RM] getFirma error: $e');
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
    final data = {
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      'firma_naziv': firmaNaziv,
      'firma_pib': firmaPib,
      'firma_mb': firmaMb,
      'firma_ziro': firmaZiro,
      'firma_adresa': firmaAdresa,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await supabase.from('v2_racuni').upsert(data, onConflict: 'putnik_id');
    // Optimisticki azuriraj racuniCache odmah â€” ne cekaj Realtime event
    final existing = racuniCache[putnikId];
    racuniCache[putnikId] = {...?existing, ...data};
    if (!_cacheChangeController.isClosed) _cacheChangeController.add('v2_racuni');
  }

  /// Dohvata putnika po PIN-u iz date tabele
  Future<Map<String, dynamic>?> v2GetByPin(String pin, String tabela) async {
    try {
      final row = await supabase
          .from(tabela)
          .select(
              'id,ime,status,telefon,telefon_2,adresa_bc_id,adresa_vs_id,pin,email,treba_racun,created_at,updated_at')
          .eq('pin', pin)
          .maybeSingle();
      if (row == null) return null;
      return {...row, '_tabela': tabela};
    } catch (e) {
      debugPrint('âŒ [RM] v2GetByPin error ($tabela, pin=$pin): $e');
      return null;
    }
  }

  /// Dohvata putnika iz bilo koje od 4 tabele â€” prvo cache, pa DB
  Future<Map<String, dynamic>?> v2FindPutnikById(String id) async {
    final cached = v2GetPutnikById(id);
    if (cached != null) return cached;
    // Upitaj sve 4 tabele paralelno â€” uzmi prvi non-null rezultat
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

  /// Dohvata putnika po telefonu (prvo pretraÅ¾uje cache, pa DB ako nije naÄ‘en)
  Future<Map<String, dynamic>?> v2FindByTelefon(String telefon) async {
    if (telefon.isEmpty) return null;
    final normalized = V2GradAdresaValidator.normalizePhone(telefon);

    // Prvo pretraÅ¾i lokalni cache â€” 0 DB upita
    for (final tabela in putnikTabele) {
      final cache = _cacheForTable(tabela);
      if (cache == null) continue;
      for (final row in cache.values) {
        final t = row['telefon'] as String? ?? '';
        final t2 = row['telefon_2'] as String? ?? '';
        if ((t.isNotEmpty && V2GradAdresaValidator.normalizePhone(t) == normalized) ||
            (t2.isNotEmpty && V2GradAdresaValidator.normalizePhone(t2) == normalized)) {
          return {...row, '_tabela': tabela};
        }
      }
    }

    // Fallback: DB upit (cache prazan ili putnik nije aktivan u memoriji)
    for (final tabela in putnikTabele) {
      final svi = await supabase
          .from(tabela)
          .select(
              'id, ime, telefon, telefon_2, adresa_bc_id, adresa_vs_id, status, pin, email, treba_racun, created_at, updated_at')
          .eq('status', 'aktivan')
          .or('telefon.ilike.%${normalized.replaceAll('+', '')},telefon_2.ilike.%${normalized.replaceAll('+', '')}');
      for (final row in svi) {
        final t = row['telefon'] as String? ?? '';
        final t2 = row['telefon_2'] as String? ?? '';
        if ((t.isNotEmpty && V2GradAdresaValidator.normalizePhone(t) == normalized) ||
            (t2.isNotEmpty && V2GradAdresaValidator.normalizePhone(t2) == normalized)) {
          return {...row, '_tabela': tabela};
        }
      }
    }
    return null;
  }

  /// GeneriÄki stream iz cache-a â€” jedna logika za sve tabele.
  ///
  /// [tables] â€” lista tabela Äije promjene aktiviraju osvjeÅ¾avanje.
  /// [build]  â€” sinhron builder koji Äita iz cache-a i vraÄ‡a vrijednost.
  ///
  /// Koristi se u svim servisima umjesto ponovljenog StreamController boilerplatea.
  /// Emituje odmah (Future.microtask) i zatim na svaku promjenu odgovarajuÄ‡ih tabela.
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
        if (sub != null) return; // Guard: ne dodaj novi sub ako vec postoji
        emit();
        sub = onCacheChanged.where(tables.contains).listen((_) => scheduleEmit());
      },
      onCancel: () async {
        // Ne zatvaraj controller â€” broadcast stream moÅ¾e dobiti novog listenera
        debounce?.cancel();
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  /// Stream aktivnih putnika iz cache-a â€” 0 DB upita
  Stream<List<V2RegistrovaniPutnik>> streamAktivniPutnici() => v2StreamFromCache<List<V2RegistrovaniPutnik>>(
        tables: [...putnikTabele, 'v3_adrese'],
        build: () => v2GetAllPutnici().map((row) {
          // Fix #6: Enrichuj adresu iz adreseCache umjesto JOIN-a koji ne postoji u cache-u
          final adresaBcId = row['adresa_bc_id']?.toString();
          final adresaVsId = row['adresa_vs_id']?.toString();
          String? adresaNaziv;
          String? grad;
          if (adresaBcId != null && adreseCache.containsKey(adresaBcId)) {
            adresaNaziv = adreseCache[adresaBcId]!['naziv']?.toString();
            grad = 'BC';
          } else if (adresaVsId != null && adreseCache.containsKey(adresaVsId)) {
            adresaNaziv = adreseCache[adresaVsId]!['naziv']?.toString();
            grad = 'VS';
          }
          return V2RegistrovaniPutnik.fromMap({
            ...row,
            if (adresaNaziv != null) 'adresa_bc': {'naziv': adresaNaziv},
          });
        }).toList()
          ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase())),
      );

  /// Stream audit log zapisa iz cache-a â€” 0 DB upita, sortiran created_at DESC.
  /// Cache drÅ¾i posljednjih 200 zapisa (punjenih pri init i Realtime INSERT).
  Stream<List<Map<String, dynamic>>> streamAuditLog() => v2StreamFromCache<List<Map<String, dynamic>>>(
        tables: ['v2_audit_log'],
        build: () => auditLogCache.values.toList()
          ..sort((a, b) {
            final ca = a['created_at']?.toString() ?? '';
            final cb = b['created_at']?.toString() ?? '';
            return cb.compareTo(ca); // DESC
          }),
      );

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
