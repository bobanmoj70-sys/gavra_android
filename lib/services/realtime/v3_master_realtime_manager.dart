import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../v3/v3_address_coordinate_service.dart';
import '../v3/v3_app_settings_state.dart';
import '../v3/v3_app_update_service.dart';
import '../v3/v3_operativna_nedelja_service.dart';
import 'engine/v3_bootstrap_loader.dart';
import 'engine/v3_cache_store.dart';
import 'engine/v3_event_bus.dart';
import 'engine/v3_table_registry.dart';
import 'repositories/v3_realtime_bootstrap_repository.dart';

/// V3MasterRealtimeManager - Centralized cache and realtime manager for v3 tables.
class V3MasterRealtimeManager {
  V3MasterRealtimeManager._internal();
  static final V3MasterRealtimeManager _instance = V3MasterRealtimeManager._internal();
  static V3MasterRealtimeManager get instance => _instance;
  static final V3RealtimeBootstrapRepository _bootstrapRepository = V3RealtimeBootstrapRepository();

  final V3CacheStore _cacheStore = V3CacheStore();
  final V3EventBus _eventBus = V3EventBus();
  late final V3BootstrapLoader _bootstrapLoader = V3BootstrapLoader(repository: _bootstrapRepository);
  bool _cacheStoreRegistered = false;

  // --- REALTIME ---
  RealtimeChannel? _channel;
  int _reconnectAttempts = 0;
  bool _isSubscribing = false;
  bool _hasConnectedBefore = false;
  DateTime? _lastSubscribedAt;
  AppLifecycleListener? _lifecycleListener;
  Future<void>? _resumeReconnectInFlight;
  DateTime? _lastResumeReconnectAt;
  static const Duration _resumeReconnectCooldown = Duration(seconds: 3);
  Future<void>? _fullResyncInFlight;
  DateTime? _lastFullResyncAt;
  static const Duration _fullResyncCooldown = Duration(seconds: 20);
  int _deltaResyncFailures = 0;
  static const int _maxDeltaResyncFailuresBeforeFull = 3;

  // --- IN-MEMORY CACHE ---
  final Map<String, Map<String, dynamic>> adreseCache = {};
  final Map<String, Map<String, dynamic>> authCache = {};
  final Map<String, Map<String, dynamic>> vozaciCache = {};
  final Map<String, Map<String, dynamic>> vozilaCache = {};
  final Map<String, Map<String, dynamic>> putniciCache = {};
  final Map<String, Map<String, dynamic>> zahteviCache = {};
  final Map<String, Map<String, dynamic>> gorivoCache = {};
  final Map<String, Map<String, dynamic>> finansijeCache = {};
  final Map<String, Map<String, dynamic>> kreditiCache = {};
  final Map<String, Map<String, dynamic>> racuniCache = {};
  final Map<String, Map<String, dynamic>> uplataPazaraCache = {};
  final Map<String, Map<String, dynamic>> trenutnaDodelaCache = {};
  final Map<String, Map<String, dynamic>> trenutnaDodelaSlotCache = {};
  final Map<String, Map<String, dynamic>> operativnaNedeljaCache = {};
  final Map<String, Map<String, dynamic>> kapacitetSlotsCache = {};
  final Map<String, Map<String, dynamic>> appSettingsCache = {};
  final Map<String, Map<String, dynamic>> operativnaAssignedCache = {};
  final Map<String, Map<String, dynamic>> etaResultsCache = {};
  final Map<String, Map<String, dynamic>> vozacAkcijeCache = {};

  void _rebuildAssignedCacheFromOperativna() {
    operativnaAssignedCache.clear();
    for (final entry in operativnaNedeljaCache.values) {
      final id = entry['id']?.toString();
      if (id == null) continue;

      final row = Map<String, dynamic>.from(entry);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];
      row['polazak_vreme'] = row['polazak_at'];
      operativnaAssignedCache[id] = row;
    }
  }

  /// Primenjuje vrednosti iz v3_app_settings na globalne notifiere
  void _applyAppSettings(Map<String, dynamic> row) {
    // rasporedi polazaka
    List<String> _toList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val.map((e) => e.toString()).toList();
      return [];
    }

    Map<String, List<String>> _toCustomByDay(dynamic val) {
      final result = {
        for (final day in V3DanHelper.workdayNames) day: <String>[],
      };
      if (val is! Map) return result;

      for (final entry in val.entries) {
        final normalizedDay = V3DanHelper.normalizeToWorkdayFull(entry.key.toString());
        if (normalizedDay.isEmpty) continue;
        result[normalizedDay] = _toList(entry.value);
      }

      return result;
    }

    final customByDayUpdated = {
      'bc': Map<String, List<String>>.from(customRasporedByDayNotifier.value['bc'] ?? {}),
      'vs': Map<String, List<String>>.from(customRasporedByDayNotifier.value['vs'] ?? {}),
    };
    bool customByDayChanged = false;

    if (row.containsKey('bc_custom_by_day')) {
      customByDayUpdated['bc'] = _toCustomByDay(row['bc_custom_by_day']);
      customByDayChanged = true;
    }
    if (row.containsKey('vs_custom_by_day')) {
      customByDayUpdated['vs'] = _toCustomByDay(row['vs_custom_by_day']);
      customByDayChanged = true;
    }

    if (customByDayChanged) {
      customRasporedByDayNotifier.value = customByDayUpdated;
    }

    if (row.containsKey('neradni_dani')) {
      applyNeradniDaniFromSettings(row['neradni_dani']);
    }

    if (row.containsKey('info_banner')) {
      applyInfoBannerFromSettings(row['info_banner']);
    }

    if (row.containsKey('active_week_start')) {
      final awsParsed = _tryParseDateTime(row['active_week_start']);
      if (awsParsed != null) {
        V3AppSettingsState.instance.setActiveWeekStart(
          DateTime(awsParsed.year, awsParsed.month, awsParsed.day),
        );
      } else {
        debugPrint('[V3MasterRealtimeManager] active_week_start je nevažeći, zadržavam postojeću vrednost.');
      }
    }

    if (row.containsKey('active_week_end')) {
      final aweParsed = _tryParseDateTime(row['active_week_end']);
      if (aweParsed != null) {
        V3AppSettingsState.instance.setActiveWeekEnd(
          DateTime(aweParsed.year, aweParsed.month, aweParsed.day),
        );
      } else {
        debugPrint('[V3MasterRealtimeManager] active_week_end je nevažeći, zadržavam postojeću vrednost.');
      }
    }

    unawaited(
      V3AppUpdateService.refreshUpdateInfo(appSettingsRow: row)
          .catchError((Object e) => debugPrint('[V3MasterRealtimeManager] app update info error: $e')),
    );
  }

  Stream<Map<String, int>> get onRevisions => _eventBus.onRevisions;

  Future<void>? _initInFlight;
  bool _isInitialized = false;

  DateTime? _tryParseDateTime(dynamic value) => V3CacheStore.parseDateTime(value);

  // Alias maintained for readability; delegates to shared CacheStore utility.

  void _scheduleEmit({Set<String>? tables, bool immediate = false}) => _eventBus.scheduleEmit(
        tables: tables,
        immediate: immediate,
        revisions: _cacheStore.revisionsSnapshot(),
      );

  void _registerCacheStoreIfNeeded() {
    if (_cacheStoreRegistered) return;

    _cacheStore.registerTable('v3_adrese', adreseCache);
    _cacheStore.registerTable('v3_auth', authCache);
    _cacheStore.registerTable('v3_vozila', vozilaCache);
    _cacheStore.registerTable('v3_zahtevi', zahteviCache);
    _cacheStore.registerTable('v3_gorivo', gorivoCache);
    _cacheStore.registerTable('v3_finansije', finansijeCache);
    _cacheStore.registerTable('v3_krediti', kreditiCache);
    _cacheStore.registerTable('v3_uplata_pazara', uplataPazaraCache);
    _cacheStore.registerTable('v3_racuni', racuniCache);
    _cacheStore.registerTable('v3_trenutna_dodela', trenutnaDodelaCache);
    _cacheStore.registerTable('v3_trenutna_dodela_slot', trenutnaDodelaSlotCache);
    _cacheStore.registerTable('v3_operativna_nedelja', operativnaNedeljaCache);
    _cacheStore.registerTable('v3_kapacitet_slots', kapacitetSlotsCache);
    _cacheStore.registerTable('v3_app_settings', appSettingsCache);
    _cacheStore.registerTable('v3_operativna_assigned', operativnaAssignedCache);
    _cacheStore.registerTable('v3_eta_results', etaResultsCache);

    _cacheStoreRegistered = true;
  }

  void _rebuildRoleCachesFromAuth() {
    vozaciCache
      ..clear()
      ..addAll(
        {
          for (final row in authCache.values)
            if ((row['tip']?.toString().trim().toLowerCase() ?? '') == 'vozac')
              (row['id']?.toString() ?? ''): <String, dynamic>{
                'id': row['id'],
                'ime_prezime': row['ime'],
                'telefon_1': row['telefon'],
                'telefon_2': row['telefon_2'],
                'boja': row['boja'],
                'push_token': row['push_token'],
                'push_token_2': row['push_token_2'],
                'pin_hash': row['pin_hash'],
                'created_at': row['created_at'],
                'updated_at': row['updated_at'],
              }
        }..removeWhere((key, value) => key.isEmpty),
      );

    putniciCache
      ..clear()
      ..addAll(
        {
          for (final row in authCache.values)
            if ((row['tip']?.toString().trim().toLowerCase() ?? '').isNotEmpty &&
                (row['tip']?.toString().trim().toLowerCase() ?? '') != 'vozac')
              (row['id']?.toString() ?? ''): <String, dynamic>{
                'id': row['id'],
                'ime_prezime': row['ime'],
                'telefon_1': row['telefon'],
                'telefon_2': row['telefon_2'],
                'tip_putnika': row['tip'],
                'adresa_bc_id': row['adresa_primary_bc_id'],
                'adresa_vs_id': row['adresa_primary_vs_id'],
                'adresa_bc_id_2': row['adresa_secondary_bc_id'],
                'adresa_vs_id_2': row['adresa_secondary_vs_id'],
                'cena_po_danu': row['cena_po_danu'],
                'cena_po_pokupljenju': row['cena_po_pokupljenju'],
                'push_token': row['push_token'],
                'push_token_2': row['push_token_2'],
                'pin_hash': row['pin_hash'],
                'created_at': row['created_at'],
                'updated_at': row['updated_at'],
                'last_seen_at': row['last_seen_at'],
                'last_seen_at_2': row['last_seen_at_2'],
              }
        }..removeWhere((key, value) => key.isEmpty),
      );
  }

  Future<void> initV3() async {
    if (_isInitialized) return;
    if (_initInFlight != null) {
      await _initInFlight;
      return;
    }

    _initInFlight = _initV3Internal();
    try {
      await _initInFlight;
    } finally {
      _initInFlight = null;
    }
  }

  Future<void> _initV3Internal() async {
    debugPrint('[V3MasterRealtimeManager] ⚡ STARTED initV3()');
    if (!isSupabaseReady) {
      debugPrint('[V3MasterRealtimeManager] Supabase nije spreman, preskačem initV3.');
      return;
    }
    try {
      _lifecycleListener ??= AppLifecycleListener(
        onResume: () {
          unawaited(_handleAppResume());
        },
      );

      _registerCacheStoreIfNeeded();
      await _loadInitialCachesWithRetry();
      _lastFullResyncAt = DateTime.now();

      await _setupRealtime();
      _isInitialized = true;
      _scheduleEmit(tables: {'*'}, immediate: true);
      // Pre-geocodiramo koordinate gradova u pozadini — bez blokiranja bootstrapa.
      // Time se izbjegava Nominatim poziv pri prvom kliku na Start/Mapa.
      unawaited(
        V3AddressCoordinateService.instance
            .warmUpCities()
            .catchError((Object e) => debugPrint('[V3MasterRealtimeManager] warmUpCities error: $e')),
      );
      debugPrint('[V3MasterRealtimeManager] Initialized successfully');
    } catch (e) {
      debugPrint('[V3MasterRealtimeManager] Initialization error: $e');
      rethrow;
    }
  }

  Future<void> _setupRealtime() async {
    if (!isSupabaseReady) {
      debugPrint('[RT] Supabase nije spreman, preskačem setupRealtime.');
      return;
    }

    if (_isSubscribing) {
      debugPrint('[RT] setupRealtime već u toku, preskačem paralelni poziv.');
      return;
    }

    _registerCacheStoreIfNeeded();

    final existing = _channel;
    _channel = null;
    if (existing != null) {
      try {
        await supabase.removeChannel(existing);
      } catch (e) {
        debugPrint('[RT] removeChannel warning: $e');
      }
    }

    final channel = supabase.channel('v3_realtime_all');
    for (final config in V3RealtimeTableRegistry.defaults) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: config.name,
        callback: (payload) {
          _onTablePayload(config: config, payload: payload);
        },
      );
    }

    _channel = channel;
    _isSubscribing = true;

    channel.subscribe((status, [error]) {
      if (_channel != channel) {
        return;
      }
      _isSubscribing = false;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _lastSubscribedAt = DateTime.now();
          final isFirstSubscribe = !_hasConnectedBefore;
          _reconnectAttempts = 0;
          debugPrint('[RT] subscribed (hasConnectedBefore=$_hasConnectedBefore)');
          if (isFirstSubscribe) {
            _hasConnectedBefore = true;
            _scheduleEmit(tables: {'*'}, immediate: true);
            unawaited(_applyMissedDelta().then((_) {}));
          } else {
            unawaited(_resyncCachesAfterReconnectSmart());
          }
          break;
        case RealtimeSubscribeStatus.channelError:
          debugPrint('[RT] channelError: $error');
          unawaited(_scheduleReconnect());
          break;
        case RealtimeSubscribeStatus.timedOut:
          debugPrint('[RT] timedOut');
          unawaited(_scheduleReconnect());
          break;
        case RealtimeSubscribeStatus.closed:
          debugPrint('[RT] closed');
          unawaited(_scheduleReconnect());
          break;
      }
    });
  }

  Future<void> _resyncCachesAfterReconnectSmart() async {
    final deltaOk = await _applyMissedDelta();
    if (deltaOk) {
      _deltaResyncFailures = 0;
      return;
    }

    _deltaResyncFailures += 1;
    debugPrint('[RT] reconnect → delta sync failed ($_deltaResyncFailures/$_maxDeltaResyncFailuresBeforeFull)');

    if (_deltaResyncFailures < _maxDeltaResyncFailuresBeforeFull) {
      return;
    }

    final inFlight = _fullResyncInFlight;
    if (inFlight != null) {
      debugPrint('[RT] reconnect full-resync već u toku, preskačem dupli poziv');
      return;
    }

    final now = DateTime.now();
    final lastRun = _lastFullResyncAt;
    final canRunFullResync = lastRun == null || now.difference(lastRun) >= _fullResyncCooldown;
    if (!canRunFullResync) {
      debugPrint('[RT] reconnect full-resync cooldown aktivan, preskačem fallback.');
      return;
    }

    final operation = _resyncCachesAfterReconnect();
    _fullResyncInFlight = operation;
    try {
      await operation;
      _lastFullResyncAt = DateTime.now();
      _deltaResyncFailures = 0;
    } finally {
      if (identical(_fullResyncInFlight, operation)) {
        _fullResyncInFlight = null;
      }
    }
  }

  Future<void> _handleAppResume() async {
    if (!isSupabaseReady) return;

    if (!_isInitialized) {
      debugPrint('[RT] app resumed → initV3 retry (not initialized yet)');
      await initV3();
      return;
    }

    final now = DateTime.now();
    final lastRun = _lastResumeReconnectAt;
    if (lastRun != null && now.difference(lastRun) < _resumeReconnectCooldown) {
      debugPrint('[RT] app resumed → reconnect cooldown aktivan, preskačem.');
      return;
    }

    final inFlight = _resumeReconnectInFlight;
    if (inFlight != null) {
      debugPrint('[RT] app resumed → reconnect već u toku, preskačem.');
      return;
    }

    _lastResumeReconnectAt = now;
    final operation = _setupRealtime();
    _resumeReconnectInFlight = operation;
    debugPrint('[RT] app resumed → reconnect + missed delta');

    try {
      await operation;
    } finally {
      if (identical(_resumeReconnectInFlight, operation)) {
        _resumeReconnectInFlight = null;
      }
    }
  }

  Future<void> _resyncCachesAfterReconnect() async {
    debugPrint('[RT] reconnect → full cache resync');
    try {
      final results = await _bootstrapLoader.loadFull();
      _applyBootstrapResults(results);
      _scheduleEmit(tables: {'*'}, immediate: true);
      debugPrint('[RT] reconnect resync → completed');
    } catch (e) {
      debugPrint('[RT] reconnect resync error: $e');
      await _applyMissedDelta();
    }
  }

  Future<void> _loadInitialCachesWithRetry({int maxAttempts = 3}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final results = await _bootstrapLoader.loadFull();
        _applyBootstrapResults(results);
        return;
      } catch (e) {
        lastError = e;
        if (attempt >= maxAttempts) break;
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    throw StateError('Bootstrap init failed after $maxAttempts attempts: $lastError');
  }

  void _applyBootstrapResults(Map<String, List<dynamic>> results) {
    for (final table in V3RealtimeTableRegistry.defaults) {
      final rawRows = results[table.name] ?? const <dynamic>[];
      final normalizedRows = _normalizeRowsForTable(table.name, rawRows);
      _cacheStore.replaceAll(table.name, normalizedRows);
    }

    _rebuildRoleCachesFromAuth();
    _rebuildAssignedCacheFromOperativna();

    final globalSettings = appSettingsCache['global'];
    if (globalSettings != null) _applyAppSettings(globalSettings);
  }

  bool _isScheduleReconnectRunning = false;

  Future<void> _scheduleReconnect() async {
    if (_isSubscribing || _isScheduleReconnectRunning) return;
    _isScheduleReconnectRunning = true;
    final scheduledAt = DateTime.now();
    try {
      _reconnectAttempts += 1;
      final cappedAttempt = _reconnectAttempts > 6 ? 6 : _reconnectAttempts;
      final baseMs = 500 * (1 << cappedAttempt);
      final jitter = Random().nextInt(250);
      await Future<void>.delayed(Duration(milliseconds: (baseMs + jitter).toInt()));

      if (_isSubscribing) return;

      final recoveredAt = _lastSubscribedAt;
      if (recoveredAt != null && recoveredAt.isAfter(scheduledAt)) {
        debugPrint('[RT] reconnect skipped (already recovered)');
        return;
      }

      try {
        await _setupRealtime();
      } catch (e) {
        debugPrint('[RT] reconnect error: $e');
      }
    } finally {
      _isScheduleReconnectRunning = false;
    }
  }

  Future<bool> _applyMissedDelta() async {
    debugPrint('[RT] _applyMissedDelta → pulling missed rows...');
    try {
      final watermarks = {
        for (final t in V3RealtimeTableRegistry.defaults) t.name: _cacheStore.watermark(t.name),
      };
      final deltas = await _bootstrapLoader.loadDeltaAll(watermarks);
      if (deltas.isEmpty) {
        debugPrint('[RT] _applyMissedDelta → nema izmena');
        return true;
      }
      for (final entry in deltas.entries) {
        final config = V3RealtimeTableRegistry.defaults.firstWhere((t) => t.name == entry.key);
        for (final row in entry.value) {
          final normalized = _normalizeRowForTable(entry.key, row);
          _cacheStore.applyDeltaRow(
            table: entry.key,
            row: normalized,
          );
        }
        for (final hook in config.hooks) {
          switch (hook) {
            case V3RealtimeHook.rebuildAssignedCache:
              _rebuildAssignedCacheFromOperativna();
              break;
            case V3RealtimeHook.applyGlobalAppSettings:
              final globalRow = appSettingsCache['global'];
              if (globalRow != null) _applyAppSettings(globalRow);
              break;
          }
        }
        if (config.name == 'v3_auth') _rebuildRoleCachesFromAuth();
      }
      debugPrint('[RT] _applyMissedDelta → applied ${deltas.length} tabela');
      _scheduleEmit(tables: {'*'}, immediate: true);
      return true;
    } catch (e) {
      debugPrint('[RT] _applyMissedDelta error: $e');
      return false;
    }
  }

  void _onTablePayload({
    required V3RealtimeTableConfig config,
    required PostgresChangePayload payload,
  }) {
    final normalizedNew = _normalizeRowForTable(config.name, payload.newRecord);
    final normalizedOld = _normalizeRowForTable(config.name, payload.oldRecord);

    final changed = _cacheStore.applyRealtimeMutation(
      table: config.name,
      newRecord: normalizedNew,
      oldRecord: normalizedOld,
      isDelete: payload.eventType == PostgresChangeEvent.delete,
    );

    if (!changed) return;

    final id = (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString();

    for (final hook in config.hooks) {
      switch (hook) {
        case V3RealtimeHook.rebuildAssignedCache:
          _rebuildAssignedCacheFromOperativna();
          break;
        case V3RealtimeHook.applyGlobalAppSettings:
          if (id == 'global') {
            _applyAppSettings(payload.newRecord);
          }
          break;
      }
    }

    if (config.name == 'v3_auth') {
      _rebuildRoleCachesFromAuth();
    }

    if (config.name == 'v3_operativna_nedelja' &&
        payload.eventType != PostgresChangeEvent.delete &&
        payload.newRecord.isNotEmpty) {
      unawaited(
        V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRow(
          operativnaRow: normalizedNew,
        ).catchError(
          (Object e) => debugPrint('[RT] syncTerminDodela error: $e'),
        ),
      );
    }

    final affected = <String>{config.name, ...config.dependsOn};
    _scheduleEmit(tables: affected);
  }

  Stream<T> v3StreamFromRevisions<T>({required List<String> tables, required T Function() build}) {
    final normalized = tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(growable: false);

    return Stream<T>.multi(
      (controller) {
        controller.add(build());
        final sub = tablesRevisionStream(normalized).listen(
          (_) => controller.add(build()),
          onError: controller.addError,
        );
        controller.onCancel = sub.cancel;
      },
      isBroadcast: true,
    );
  }

  Stream<int> tableRevisionStream(String table) {
    final normalized = table.trim();
    return Stream<int>.multi(
      (controller) {
        controller.add(_cacheStore.revision(normalized));
        final sub =
            onRevisions.map((snapshot) => snapshot[normalized] ?? _cacheStore.revision(normalized)).distinct().listen(
                  controller.add,
                  onError: controller.addError,
                );
        controller.onCancel = sub.cancel;
      },
      isBroadcast: true,
    ).distinct();
  }

  Stream<int> tablesRevisionStream(List<String> tables) {
    final normalized = tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(growable: false);
    if (normalized.isEmpty) {
      return onRevisions.map((_) => 0).distinct();
    }

    int buildHashFromSnapshot(Map<String, int>? snapshot) {
      var hash = 17;
      for (final table in normalized) {
        final revision = snapshot?[table] ?? _cacheStore.revision(table);
        hash = (hash * 31) ^ revision;
      }
      return hash;
    }

    return Stream<int>.multi(
      (controller) {
        controller.add(buildHashFromSnapshot(null));
        final sub = onRevisions.map(buildHashFromSnapshot).distinct().listen(
              controller.add,
              onError: controller.addError,
            );
        controller.onCancel = sub.cancel;
      },
      isBroadcast: true,
    ).distinct();
  }

  void v3UpsertToCache(String table, Map<String, dynamic> row) {
    final normalizedRow = _normalizeRowForTable(table, row);

    // v3_eta_results koristi kompozitni ključ slot_id:putnik_id — nema 'id' kolonu
    if (table != 'v3_eta_results') {
      final id = normalizedRow['id']?.toString();
      if (id == null) return;
    }

    _cacheStore.upsert(table, normalizedRow);

    switch (table) {
      case 'v3_auth':
        _rebuildRoleCachesFromAuth();
        break;
      case 'v3_operativna_nedelja':
        _rebuildAssignedCacheFromOperativna();
        break;
      case 'v3_app_settings':
        if (normalizedRow['id']?.toString() == 'global') {
          _applyAppSettings(normalizedRow);
        }
        break;
    }

    _scheduleEmit(tables: {table});
  }

  void v3RemoveFromCache(String table, String id) {
    if (id.isEmpty) return;
    _cacheStore.remove(table, id);

    if (table == 'v3_auth') {
      _rebuildRoleCachesFromAuth();
    }

    _scheduleEmit(tables: {table});
  }

  Map<String, dynamic> _normalizeRowForTable(String table, Map<String, dynamic> row) {
    if (row.isEmpty) return row;
    final normalized = Map<String, dynamic>.from(row);

    if (table == 'v3_trenutna_dodela') {
      final fallbackId = normalized['termin_id']?.toString();
      final currentId = normalized['id']?.toString();
      if ((currentId == null || currentId.isEmpty) && fallbackId != null && fallbackId.isNotEmpty) {
        normalized['id'] = fallbackId;
      }
    }

    return normalized;
  }

  List<dynamic> _normalizeRowsForTable(String table, List<dynamic> rows) {
    if (rows.isEmpty) return rows;
    return rows.map((row) {
      if (row is Map<String, dynamic>) {
        return _normalizeRowForTable(table, row);
      }
      return row;
    }).toList(growable: false);
  }

  Map<String, dynamic>? getPutnik(String id) => putniciCache[id];

  Map<String, Map<String, dynamic>> getCache(String table) {
    switch (table) {
      case 'v3_adrese':
        return adreseCache;
      case 'v3_auth':
        return authCache;
      case 'v3_vozila':
        return vozilaCache;
      case 'v3_zahtevi':
        return zahteviCache;
      case 'v3_gorivo':
        return gorivoCache;
      case 'v3_finansije':
        return finansijeCache;
      case 'v3_krediti':
        return kreditiCache;
      case 'v3_racuni':
        return racuniCache;
      case 'v3_trenutna_dodela':
        return trenutnaDodelaCache;
      case 'v3_trenutna_dodela_slot':
        return trenutnaDodelaSlotCache;
      case 'v3_operativna_nedelja':
        return operativnaNedeljaCache;
      case 'v3_kapacitet_slots':
        return kapacitetSlotsCache;
      case 'v3_app_settings':
        return appSettingsCache;
      case 'v3_operativna_assigned':
        return operativnaAssignedCache;
      case 'v3_eta_results':
        return etaResultsCache;
      default:
        return {};
    }
  }
}
