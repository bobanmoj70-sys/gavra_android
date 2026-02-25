import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import 'realtime_config.dart';
import 'realtime_status.dart';

/// Centralizovani manager za sve Supabase Realtime konekcije i in-memory cache.
///
/// Singleton koji:
/// 1. Upravlja svim channel-ima (1 channel po tabeli)
/// 2. Drži sve podatke u memoriji (0 DB upita na realtime event)
/// 3. Inicijalizuje se jednom pri startu, reinicijalizuje na novi dan
///
/// Korišćenje:
/// ```dart
/// // Cache podaci
/// final srRows = RealtimeManager.instance.srCache.values.toList();
///
/// // Pretplata na realtime evente
/// final subscription = RealtimeManager.instance
///     .subscribe('vozac_lokacije')
///     .listen((payload) => handleChange(payload));
///
/// // Otkazivanje
/// subscription.cancel();
/// RealtimeManager.instance.unsubscribe('vozac_lokacije');
/// ```
class RealtimeManager {
  RealtimeManager._internal();

  static final RealtimeManager _instance = RealtimeManager._internal();
  static RealtimeManager get instance => _instance;

  SupabaseClient get _supabase => supabase;

  // ---------------------------------------------------------------------------
  // 🗄️ IN-MEMORY CACHE — sve tabele, 0 DB upita na realtime event
  // ---------------------------------------------------------------------------

  /// seat_requests za tekući dan — ključ: id
  final Map<String, Map<String, dynamic>> srCache = {};

  /// voznje_log za tekući dan — ključ: id
  final Map<String, Map<String, dynamic>> vlCache = {};

  /// registrovani_putnici aktivni — ključ: id
  final Map<String, Map<String, dynamic>> rpCache = {};

  /// vozaci — ključ: id
  final Map<String, Map<String, dynamic>> vozaciCache = {};

  /// vozila — ključ: id
  final Map<String, Map<String, dynamic>> vozilaCache = {};

  /// kapacitet_polazaka — ključ: id
  final Map<String, Map<String, dynamic>> kapacitetCache = {};

  /// app_settings — ključ: id
  final Map<String, Map<String, dynamic>> settingsCache = {};

  /// pin_zahtevi — ključ: id
  final Map<String, Map<String, dynamic>> pinCache = {};

  /// vozac_lokacije — ključ: id
  final Map<String, Map<String, dynamic>> lokacijeCache = {};

  /// adrese — ključ: id
  final Map<String, Map<String, dynamic>> adreseCache = {};

  /// vozac_raspored — ključ: id
  final Map<String, Map<String, dynamic>> rasporedCache = {};

  /// vozac_putnik — ključ: id
  final Map<String, Map<String, dynamic>> vozacPutnikCache = {};

  /// finansije_troskovi — ključ: id
  final Map<String, Map<String, dynamic>> troskoviCache = {};

  /// pumpa_config — ključ: id
  final Map<String, Map<String, dynamic>> pumpaConfigCache = {};

  /// Datum za koji su srCache i vlCache učitani (format: 'yyyy-MM-dd')
  String? _loadedDate;

  /// Datum za koji su podaci učitani (read-only pristup za lifecycle observer)
  String? get loadedDate => _loadedDate;

  /// Da li je inicijalizacija završena
  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // 🚀 INICIJALIZACIJA
  // ---------------------------------------------------------------------------

  /// Učitava sve tabele jednom pri startu aplikacije.
  /// Poziva se iz main.dart nakon što je Supabase spreman.
  Future<void> initializeCache() async {
    if (!isSupabaseReady) {
      debugPrint('❌ [RealtimeManager] initializeCache: Supabase not ready');
      return;
    }
    _loadedDate = DateTime.now().toIso8601String().split('T')[0];
    debugPrint('🚀 [RealtimeManager] initializeCache za datum=$_loadedDate ...');

    await Future.wait([
      _loadSrCache(),
      _loadVlCache(),
      _loadRpCache(),
      _loadStaticCaches(),
    ]);

    _initialized = true;
    debugPrint('✅ [RealtimeManager] Cache inicijalizovan: '
        'sr=${srCache.length}, vl=${vlCache.length}, rp=${rpCache.length}, '
        'vozaci=${vozaciCache.length}, adrese=${adreseCache.length}');
  }

  /// Reinicijalizuje dnevne cache-ove (seat_requests + voznje_log) za novi dan.
  /// Poziva se iz AppLifecycleObserver kada datum nije isti kao _loadedDate.
  Future<void> reinitializeForNewDay() async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (_loadedDate == today) return; // već aktualan
    debugPrint('🔄 [RealtimeManager] Novi dan ($today) — reinitializeForNewDay...');
    _loadedDate = today;
    srCache.clear();
    vlCache.clear();
    await Future.wait([_loadSrCache(), _loadVlCache()]);
    debugPrint('✅ [RealtimeManager] Dnevni cache osvježen: sr=${srCache.length}, vl=${vlCache.length}');
  }

  Future<void> _loadSrCache() async {
    try {
      final dan = _todayKratica();
      final rows = await _supabase
          .from('seat_requests')
          .select('id, putnik_id, grad, zeljeno_vreme, dodeljeno_vreme, status, '
              'created_at, updated_at, processed_at, priority, broj_mesta, '
              'custom_adresa_id, alternative_vreme_1, alternative_vreme_2, '
              'cancelled_by, pokupljeno_by, dan, tip_putnika')
          .eq('dan', dan)
          .inFilter('status',
              ['pending', 'manual', 'approved', 'confirmed', 'otkazano', 'cancelled', 'bez_polaska', 'pokupljen']);
      for (final row in rows) {
        srCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [RealtimeManager] srCache: ${srCache.length} redova (dan=$dan)');
    } catch (e) {
      debugPrint('❌ [RealtimeManager] _loadSrCache error: $e');
    }
  }

  Future<void> _loadVlCache() async {
    try {
      final rows = await _supabase
          .from('voznje_log')
          .select('id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, '
              'grad, vreme_polaska, tip_putnika, created_at, status')
          .eq('datum', _loadedDate!);
      for (final row in rows) {
        vlCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [RealtimeManager] vlCache: ${vlCache.length} redova');
    } catch (e) {
      debugPrint('❌ [RealtimeManager] _loadVlCache error: $e');
    }
  }

  Future<void> _loadRpCache() async {
    try {
      final rows = await _supabase
          .from('registrovani_putnici')
          .select('id, putnik_ime, broj_telefona, broj_telefona_2, broj_telefona_oca, '
              'broj_telefona_majke, tip, tip_skole, adresa_bela_crkva_id, adresa_vrsac_id, '
              'datum_pocetka_meseca, datum_kraja_meseca, created_at, updated_at, '
              'aktivan, status, obrisan, is_duplicate, tip_prikazivanja, '
              'pin, email, cena_po_danu, treba_racun, '
              'firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa, broj_mesta')
          .eq('aktivan', true)
          .eq('obrisan', false);
      for (final row in rows) {
        rpCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      debugPrint('📦 [RealtimeManager] rpCache: ${rpCache.length} redova');
    } catch (e) {
      debugPrint('❌ [RealtimeManager] _loadRpCache error: $e');
    }
  }

  Future<void> _loadStaticCaches() async {
    try {
      final results = await Future.wait([
        _supabase.from('vozaci').select('id, ime, email, telefon, sifra, boja'),
        _supabase.from('vozila').select('id, registarski_broj, marka, model, naziv, broj_mesta'),
        _supabase.from('kapacitet_polazaka').select('id, grad, vreme, max_mesta, aktivan').eq('aktivan', true),
        _supabase.from('app_settings').select(),
        _supabase.from('adrese').select('id, naziv, grad, gps_lat, gps_lng'),
        _supabase.from('vozac_raspored').select(),
        _supabase.from('vozac_putnik').select(),
        _supabase
            .from('finansije_troskovi')
            .select('id, naziv, iznos, tip, aktivan, vozac_id, created_at')
            .eq('aktivan', true),
        _supabase.from('pumpa_config').select(),
      ]);
      for (final row in results[0] as List) {
        vozaciCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[1] as List) {
        vozilaCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[2] as List) {
        kapacitetCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[3] as List) {
        settingsCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[4] as List) {
        adreseCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[5] as List) {
        rasporedCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[6] as List) {
        vozacPutnikCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[7] as List) {
        troskoviCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
      for (final row in results[8] as List) {
        pumpaConfigCache[row['id'].toString()] = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('❌ [RealtimeManager] _loadStaticCaches error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 🔧 CACHE UPDATE — poziva se iz realtime listenera
  // ---------------------------------------------------------------------------

  void updateSrCache(Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id != null) srCache[id] = Map<String, dynamic>.from(record);
  }

  void updateVlCache(Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id != null) vlCache[id] = Map<String, dynamic>.from(record);
  }

  void updateRpCache(Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id != null) rpCache[id] = Map<String, dynamic>.from(record);
  }

  void updateGenericCache(String table, Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;
    switch (table) {
      case 'vozaci':
        vozaciCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'vozila':
        vozilaCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'kapacitet_polazaka':
        kapacitetCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'app_settings':
        settingsCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'vozac_lokacije':
        lokacijeCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'pin_zahtevi':
        pinCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'adrese':
        adreseCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'vozac_raspored':
        rasporedCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'vozac_putnik':
        vozacPutnikCache[id] = Map<String, dynamic>.from(record);
        break;
      case 'finansije_troskovi':
        troskoviCache[id] = Map<String, dynamic>.from(record);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 🛠️ HELPERS
  // ---------------------------------------------------------------------------

  static String _todayKratica() {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.now().weekday]!;
  }

  // ---------------------------------------------------------------------------
  // CHANNEL MANAGEMENT (nepromenjen)
  // ---------------------------------------------------------------------------

  /// Jedan channel po tabeli
  final Map<String, RealtimeChannel> _channels = {};

  /// Stream controlleri za broadcast
  final Map<String, StreamController<PostgresChangePayload>> _controllers = {};

  /// Broj listenera po tabeli (za cleanup)
  final Map<String, int> _listenerCount = {};

  /// Broj reconnect pokušaja po tabeli
  final Map<String, int> _reconnectAttempts = {};

  /// Status po tabeli
  final Map<String, RealtimeStatus> _statusMap = {};

  /// Pending reconnect timeri (debounce)
  final Map<String, Timer?> _reconnectTimers = {};

  /// Globalni status stream
  final StreamController<Map<String, RealtimeStatus>> _statusController =
      StreamController<Map<String, RealtimeStatus>>.broadcast();

  /// Stream za praćenje statusa svih tabela
  Stream<Map<String, RealtimeStatus>> get statusStream => _statusController.stream;

  /// Trenutni status za tabelu
  RealtimeStatus getStatus(String table) => _statusMap[table] ?? RealtimeStatus.disconnected;

  /// Pretplati se na promene u tabeli
  ///
  /// Vraća Stream koji emituje PostgresChangePayload pri svakoj promeni.
  /// Više listenera može slušati isti stream - deli se isti channel.
  Stream<PostgresChangePayload> subscribe(String table) {
    // 🛡️ Provera pre pretplate
    if (!isSupabaseReady) {
      if (kDebugMode) {
        debugPrint('❌ [RealtimeManager] Cannot subscribe to $table: Supabase not ready');
      }
      return const Stream.empty();
    }

    _listenerCount[table] = (_listenerCount[table] ?? 0) + 1;
    debugPrint('📊 [RealtimeManager] Subscribe na "$table" - listenera: ${_listenerCount[table]}');

    // ✅ GUARD: Ako channel već postoji i aktivan je, samo vrati stream
    if (_controllers.containsKey(table) && !_controllers[table]!.isClosed) {
      debugPrint('♻️ [RealtimeManager] Reusing postojeći channel za "$table"');
      return _controllers[table]!.stream;
    }

    // ✅ GUARD: Otkaži pending reconnect ako postoji (novi subscribe preuzima kontrolu)
    _reconnectTimers[table]?.cancel();
    _reconnectTimers[table] = null;

    // Kreiraj novi controller i channel
    _controllers[table] = StreamController<PostgresChangePayload>.broadcast();
    _createChannel(table);

    return _controllers[table]!.stream;
  }

  /// Odjavi se sa tabele
  ///
  /// Channel se zatvara samo kad nema više listenera.
  void unsubscribe(String table) {
    _listenerCount[table] = (_listenerCount[table] ?? 1) - 1;

    // Ugasi channel samo ako nema više listenera
    if (_listenerCount[table] != null && _listenerCount[table]! <= 0) {
      _closeChannel(table);
    }
  }

  /// Zatvori channel za tabelu
  void _closeChannel(String table) {
    // Otkaži pending reconnect
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

  /// Kreiraj channel za tabelu
  void _createChannel(String table) {
    _updateStatus(table, RealtimeStatus.connecting);

    // 📝 SUPABASE PRAVILO: Channel name NE SME počinjati sa 'realtime'
    // https://supabase.com/docs/guides/realtime/postgres-changes
    // "The channel name can be any string except 'realtime'."
    final channelName = 'db-changes:$table';

    final channel = _supabase.channel(channelName);

    channel
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (payload) {
        // Handle DELETE: ukloni iz cache-a i emituj signal
        if (payload.eventType == PostgresChangeEvent.delete) {
          final oldRecord = payload.oldRecord;
          final id = oldRecord['id']?.toString();
          if (id != null) {
            switch (table) {
              case 'vozac_raspored':
                rasporedCache.remove(id);
                break;
              case 'vozac_putnik':
                vozacPutnikCache.remove(id);
                break;
              default:
                break; // ostale tabele ignorišu DELETE
            }
          }
          // Emituj event da subscriber-i mogu reagovati (npr. vozac_screen)
          if (_controllers.containsKey(table) && !_controllers[table]!.isClosed) {
            _controllers[table]!.add(payload);
          }
          return;
        }

        debugPrint('🔄 [RealtimeManager] EVENT na tabeli "$table": ${payload.eventType}');
        if (_controllers.containsKey(table) && !_controllers[table]!.isClosed) {
          _controllers[table]!.add(payload);
          debugPrint('✅ [RealtimeManager] Payload emitovan za tabelu "$table"');
        } else {
          debugPrint('⚠️ [RealtimeManager] Controller zatvoren ili ne postoji za tabelu "$table"');
        }
      },
    )
        .subscribe((status, [error]) {
      debugPrint(
          '📡 [RealtimeManager] Subscribe status za "$table": $status${error != null ? " (Error: $error)" : ""}');
      _handleSubscribeStatus(table, status, error);
    });

    _channels[table] = channel;
    debugPrint('🔗 [RealtimeManager] Channel kreiran za tabelu "$table"');
  }

  /// Handle status promene od Supabase
  void _handleSubscribeStatus(String table, RealtimeSubscribeStatus status, dynamic error) {
    debugPrint('🔍 [RealtimeManager] Status handler za "$table": $status (listenera: ${_listenerCount[table] ?? 0})');

    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _reconnectAttempts[table] = 0;
        _updateStatus(table, RealtimeStatus.connected);
        debugPrint('✅ [RealtimeManager] "$table" uspešno konektovan');
        break;

      case RealtimeSubscribeStatus.channelError:
        debugPrint('❌ [RealtimeManager] Channel error za "$table": $error');
        _scheduleReconnect(table);
        break;

      case RealtimeSubscribeStatus.closed:
        debugPrint('🔴 [RealtimeManager] Channel zatvoren za "$table" (listenera: ${_listenerCount[table] ?? 0})');
        // ✅ FIKSUJ: Ne pokušavaj reconnect ako nema aktivnih listenera
        if (_listenerCount[table] != null && _listenerCount[table]! > 0) {
          debugPrint('🔄 [RealtimeManager] Zakazujem reconnect za "$table"');
          _scheduleReconnect(table);
        } else {
          debugPrint('⏹️ [RealtimeManager] Zatvaranjem kanala za "$table" - nema listenera');
          // Nema listenera, samo zatvori
          _closeChannel(table);
        }
        break;

      case RealtimeSubscribeStatus.timedOut:
        debugPrint('⏱️ [RealtimeManager] Timeout za "$table"');
        _scheduleReconnect(table);
        break;
    }
  }

  /// Zakaži reconnect sa exponential backoff
  void _scheduleReconnect(String table) {
    // ✅ DEBOUNCE: Otkaži prethodni pending reconnect
    _reconnectTimers[table]?.cancel();

    final attempts = _reconnectAttempts[table] ?? 0;

    if (attempts >= RealtimeConfig.maxReconnectAttempts) {
      _updateStatus(table, RealtimeStatus.error);
      _reconnectTimers[table] = null;
      return;
    }

    _updateStatus(table, RealtimeStatus.reconnecting);
    _reconnectAttempts[table] = attempts + 1;

    // Exponential backoff: 3s, 6s, 10s (brži recovery nego prethodno 10s, 20s, 30s)
    // https://supabase.com/docs/guides/realtime/troubleshooting - preporučuje kraće intervale
    final delays = [3, 6, 10]; // sekunde za attempt 0, 1, 2
    final delay = delays[attempts.clamp(0, delays.length - 1)];

    _reconnectTimers[table] = Timer(Duration(seconds: delay), () async {
      _reconnectTimers[table] = null;

      // ✅ GUARD: Proveri da li još uvek ima listenera
      if (_listenerCount[table] == null || _listenerCount[table]! <= 0) {
        debugPrint('⏭️ [RealtimeManager] Preskačem reconnect za "$table" - nema aktivnih listenera');
        return;
      }

      // ✅ GUARD: Proveri da li već postoji aktivan channel
      if (_channels.containsKey(table)) {
        debugPrint('⏭️ [RealtimeManager] Preskačem reconnect za "$table" - channel već postoji');
        return;
      }

      // ВАЖНО: Морамо потпуно уклонити канал из SDK пре креирања новог!
      // Supabase SDK има leaveOpenTopic() који затвара канале са истим именом
      // што изазива race condition ако се нови канал направи пре него што
      // је стари потпуно уклоњен.
      final existingChannel = _channels[table];
      if (existingChannel != null) {
        try {
          // ✅ Користи removeChannel() уместо unsubscribe()
          // SDK метода: SupabaseClient.removeChannel(RealtimeChannel)
          // https://pub.dev/documentation/supabase_flutter/latest/supabase_flutter/SupabaseClient/removeChannel.html
          // Ово потпуно уклања канал из SDK и спречава race conditions
          await _supabase.removeChannel(existingChannel);
        } catch (e) {
          debugPrint('⚠️ Error removing realtime channel: $e');
        }
        _channels.remove(table);
      }

      // 🔁 RETRY LOOP: Сачекај да SDK стварно очисти канал
      int retries = 0;
      const maxRetries = 20; // 20 x 50ms = 1 sekунда max
      final initialChannelCount = _supabase.getChannels().length;

      while (retries < maxRetries) {
        final currentChannelCount = _supabase.getChannels().length;

        // Ako se broj kanala smanjio, SDK je očistio kanal
        if (currentChannelCount < initialChannelCount) {
          break;
        }

        await Future.delayed(const Duration(milliseconds: 50));
        retries++;
      }

      // Сада безбедно креирај нови канал
      _createChannel(table);
    });
  }

  /// Ažuriraj status i emituj
  void _updateStatus(String table, RealtimeStatus status) {
    _statusMap[table] = status;
    if (!_statusController.isClosed) {
      _statusController.add(Map.from(_statusMap));
    }
  }

  /// Inicijalizuj sve važne tabele za realtime praćenje i učitaj cache.
  /// Poziva se jednom pri startu aplikacije.
  Future<void> initializeAll() async {
    if (!isSupabaseReady) {
      debugPrint('❌ [RealtimeManager] Cannot initialize: Supabase not ready');
      return;
    }
    // Učitaj sve podatke u memoriju
    await initializeCache();
    debugPrint('🚀 [RealtimeManager] initializeAll završen — kanali se kreiraju on-demand');
  }

  /// Ugasi sve channel-e i očisti resurse
  void dispose() {
    // Otkaži sve pending reconnect timere
    for (final timer in _reconnectTimers.values) {
      timer?.cancel();
    }
    _reconnectTimers.clear();

    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    for (final controller in _controllers.values) {
      controller.close();
    }
    _channels.clear();
    _controllers.clear();
    _listenerCount.clear();
    _reconnectAttempts.clear();
    _statusMap.clear();
    _statusController.close();
  }
}
