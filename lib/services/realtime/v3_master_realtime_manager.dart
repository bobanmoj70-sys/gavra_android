import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_time_utils.dart';
import '../v3/v3_app_update_service.dart';
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
  final bool _realtimeDisposed = false;
  bool _isSubscribing = false;

  // --- IN-MEMORY CACHE ---
  final Map<String, Map<String, dynamic>> adreseCache = {};
  final Map<String, Map<String, dynamic>> vozaciCache = {};
  final Map<String, Map<String, dynamic>> vozilaCache = {};
  final Map<String, Map<String, dynamic>> putniciCache = {};
  final Map<String, Map<String, dynamic>> zahteviCache = {};
  final Map<String, Map<String, dynamic>> postavkeKapacitetaCache = {};
  final Map<String, Map<String, dynamic>> gorivoCache = {};
  final Map<String, Map<String, dynamic>> gorivoPromeneCache = {};
  final Map<String, Map<String, dynamic>> vozacLokacijeCache = {};
  final Map<String, Map<String, dynamic>> troskoviCache = {};
  final Map<String, Map<String, dynamic>> racuniCache = {};
  final Map<String, Map<String, dynamic>> racuniArhivaCache = {};
  final Map<String, Map<String, dynamic>> operativnaNedeljaCache = {};
  final Map<String, Map<String, dynamic>> gpsTripStateCache = {};
  final Map<String, Map<String, dynamic>> tripStopsCache = {};
  final Map<String, Map<String, dynamic>> kapacitetSlotsCache = {};
  final Map<String, Map<String, dynamic>> gpsActivationScheduleCache = {};
  final Map<String, Map<String, dynamic>> gpsTriggerStatsCache = {};
  final Map<String, Map<String, dynamic>> appSettingsCache = {};
  // Legacy naziv: istorijski se zove "v3GpsRasporedCache", ali izvor podataka je
  // isključivo v3_operativna_nedelja (nema DB tabele v3_gps_raspored).
  final Map<String, Map<String, dynamic>> v3GpsRasporedCache = {};

  // Preferirani alias za novi kod (isti objekat kao legacy naziv).
  Map<String, Map<String, dynamic>> get operativnaAssignedCache => v3GpsRasporedCache;

  String? _extractTimeToken(String? value) {
    return V3TimeUtils.extractHHmmToken(value);
  }

  String _asString(dynamic value) {
    return value?.toString() ?? '';
  }

  String _gpsTripKey({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String polazakTime,
  }) {
    return '${vozacId.trim()}|${datumIso.trim()}|${grad.trim().toUpperCase()}|${polazakTime.trim()}';
  }

  void _rebuildGpsCacheFromOperativna() {
    final gpsTripByKey = <String, Map<String, dynamic>>{};
    final routeOrderByOperativnaId = <String, int?>{};

    for (final stop in tripStopsCache.values) {
      final operativnaId = stop['operativna_id']?.toString();
      if (operativnaId == null || operativnaId.isEmpty) continue;

      final rawOrder = stop['stop_order'];
      int? parsedOrder;
      if (rawOrder is int) {
        parsedOrder = rawOrder;
      } else if (rawOrder is num) {
        parsedOrder = rawOrder.toInt();
      } else {
        parsedOrder = int.tryParse(rawOrder?.toString() ?? '');
      }

      routeOrderByOperativnaId[operativnaId] = parsedOrder;
    }

    for (final trip in gpsTripStateCache.values) {
      final vozacId = (trip['vozac_id']?.toString() ?? '').trim();
      final datumIso = V3DanHelper.parseIsoDatePart(_asString(trip['datum']));
      final grad = (trip['grad']?.toString() ?? '').trim().toUpperCase();
      final polazakTime = _extractTimeToken(trip['polazak_vreme']?.toString()) ?? '';

      if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || polazakTime.isEmpty) {
        continue;
      }

      final key = _gpsTripKey(
        vozacId: vozacId,
        datumIso: datumIso,
        grad: grad,
        polazakTime: polazakTime,
      );
      gpsTripByKey[key] = trip;
    }

    v3GpsRasporedCache.clear();
    for (final entry in operativnaNedeljaCache.values) {
      final id = entry['id']?.toString();
      final vozacId = (entry['vozac_id']?.toString() ?? '').trim();
      if (id == null || vozacId.isEmpty) continue;

      final datumIso = V3DanHelper.parseIsoDatePart(_asString(entry['datum']));
      final grad = (entry['grad']?.toString() ?? '').trim().toUpperCase();
      final polazakTime = _extractTimeToken(entry['dodeljeno_vreme']?.toString()) ??
          _extractTimeToken(entry['zeljeno_vreme']?.toString()) ??
          '';

      final tripKey = polazakTime.isEmpty
          ? null
          : _gpsTripKey(
              vozacId: vozacId,
              datumIso: datumIso,
              grad: grad,
              polazakTime: polazakTime,
            );
      final trip = tripKey != null ? gpsTripByKey[tripKey] : null;

      final row = Map<String, dynamic>.from(entry);
      row['vreme'] = row['vreme'] ?? row['dodeljeno_vreme'] ?? row['zeljeno_vreme'];
      row['polazak_vreme'] = trip?['polazak_vreme'];
      row['nav_bar_type'] = trip?['nav_bar_type'] ?? row['nav_bar_type'] ?? 'zimski';
      row['gps_status'] = trip?['gps_status'] ?? 'pending';
      row['notification_sent'] = trip?['notification_sent'] ?? false;
      row['route_order'] = routeOrderByOperativnaId[id];
      v3GpsRasporedCache[id] = row;
    }
  }

  /// Primenjuje vrednosti iz v3_app_settings na globalne notifiere
  void _applyAppSettings(Map<String, dynamic> row) {
    final now = DateTime.now();

    // nav_bar_type (sa podrškom za zakazani prelaz)
    final navType = resolveEffectiveNavBarType(
      currentType: row['nav_bar_type']?.toString(),
      nextType: row['nav_bar_type_next']?.toString(),
      effectiveAt: row['nav_bar_type_effective_at'],
      now: now,
    );
    if (navType != null) {
      navBarTypeNotifier.value = navType;
    }

    _navTypeSwitchTimer?.cancel();
    _navTypeSwitchTimer = null;

    final nextType = row['nav_bar_type_next']?.toString().toLowerCase();
    final effectiveAt = _tryParseDateTime(row['nav_bar_type_effective_at']);
    if (nextType != null && ['zimski', 'letnji', 'praznici', 'custom'].contains(nextType) && effectiveAt != null) {
      final delay = effectiveAt.difference(now);
      if (!delay.isNegative && delay > Duration.zero) {
        _navTypeSwitchTimer = Timer(delay, () {
          navBarTypeNotifier.value = nextType;
        });
      }
    }

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
        final normalizedDay = V3DanHelper.normalizeToWorkdayFull(entry.key.toString(), fallback: '');
        if (normalizedDay.isEmpty) continue;
        result[normalizedDay] = _toList(entry.value);
      }

      return result;
    }

    List<String> _flattenByDay(Map<String, List<String>> byDay) {
      final merged = <String>{};
      for (final day in V3DanHelper.workdayNames) {
        merged.addAll(byDay[day] ?? const <String>[]);
      }
      final out = merged.toList();
      out.sort();
      return out;
    }

    final updated = Map<String, List<String>>.from(rasporedNotifier.value);
    bool changed = false;

    for (final key in [
      'bc_zimski',
      'vs_zimski',
      'bc_letnji',
      'vs_letnji',
      'bc_praznici',
      'vs_praznici',
      'bc_custom',
      'vs_custom',
    ]) {
      if (row.containsKey(key)) {
        updated[key] = _toList(row[key]);
        changed = true;
      }
    }

    if (changed) rasporedNotifier.value = updated;

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

      updated['bc_custom'] = _flattenByDay(customByDayUpdated['bc'] ?? const <String, List<String>>{});
      updated['vs_custom'] = _flattenByDay(customByDayUpdated['vs'] ?? const <String, List<String>>{});
      changed = true;
    }

    if (row.containsKey('neradni_dani')) {
      applyNeradniDaniFromSettings(row['neradni_dani']);
    }

    unawaited(
      V3AppUpdateService.refreshUpdateInfo(appSettingsRow: row)
          .catchError((Object e) => debugPrint('[V3MasterRealtimeManager] app update info error: $e')),
    );
  }

  Stream<void> get onChange => _eventBus.onChange;
  Stream<Map<String, int>> get onRevisions => _eventBus.onRevisions;
  Timer? _navTypeSwitchTimer;

  Future<void>? _initInFlight;
  bool _isInitialized = false;

  DateTime? _tryParseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  void _scheduleEmit({Set<String>? tables, bool immediate = false}) => _eventBus.scheduleEmit(
        tables: tables,
        immediate: immediate,
        revisions: _cacheStore.revisionsSnapshot(),
      );

  void _registerCacheStoreIfNeeded() {
    if (_cacheStoreRegistered) return;

    _cacheStore.registerTable('v3_adrese', adreseCache);
    _cacheStore.registerTable('v3_vozaci', vozaciCache);
    _cacheStore.registerTable('v3_vozila', vozilaCache);
    _cacheStore.registerTable('v3_putnici', putniciCache);
    _cacheStore.registerTable('v3_zahtevi', zahteviCache);
    _cacheStore.registerTable('v3_gorivo', gorivoCache);
    _cacheStore.registerTable('v3_gorivo_promene', gorivoPromeneCache);
    _cacheStore.registerTable('v3_vozac_lokacije', vozacLokacijeCache);
    _cacheStore.registerTable('v3_finansije', troskoviCache);
    _cacheStore.registerTable('v3_racuni', racuniCache);
    _cacheStore.registerTable('v3_racuni_arhiva', racuniArhivaCache);
    _cacheStore.registerTable('v3_operativna_nedelja', operativnaNedeljaCache);
    _cacheStore.registerTable('v3_gps_trip_state', gpsTripStateCache);
    _cacheStore.registerTable('v3_trip_stops', tripStopsCache);
    _cacheStore.registerTable('v3_kapacitet_slots', kapacitetSlotsCache);
    _cacheStore.registerTable('v3_app_settings', appSettingsCache);
    _cacheStore.registerTable('v3_gps_raspored', v3GpsRasporedCache);

    _cacheStoreRegistered = true;
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
    try {
      _registerCacheStoreIfNeeded();
      final results = await _bootstrapLoader.loadFull();

      for (final table in V3RealtimeTableRegistry.defaults) {
        _cacheStore.replaceAll(table.name, results[table.name] ?? const <dynamic>[]);
      }

      _rebuildGpsCacheFromOperativna();
      // Primeni app_settings na notifiere odmah pri inicijalizaciji
      final globalSettings = appSettingsCache['global'];
      if (globalSettings != null) _applyAppSettings(globalSettings);

      await _setupRealtime();
      _isInitialized = true;
      _scheduleEmit(tables: {'*'}, immediate: true);
      debugPrint('[V3MasterRealtimeManager] Initialized successfully');
    } catch (e) {
      debugPrint('[V3MasterRealtimeManager] Initialization error: $e');
      rethrow;
    }
  }

  Future<void> _setupRealtime() async {
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

    _syncRealtimeAuth();

    final channel = supabase.channel('v3_realtime_all');
    for (final config in V3RealtimeTableRegistry.defaults) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: config.name,
        callback: (payload) => _onTablePayload(config: config, payload: payload),
      );
    }

    _channel = channel;
    _isSubscribing = true;

    channel.subscribe((status, [error]) {
      _isSubscribing = false;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _reconnectAttempts = 0;
          debugPrint('[RT] subscribed');
          _scheduleEmit(tables: {'*'}, immediate: true);
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
          break;
      }
    });
  }

  void _syncRealtimeAuth() {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      supabase.realtime.setAuth(token);
    } catch (e) {
      debugPrint('[RT] setAuth warning: $e');
    }
  }

  Future<void> _scheduleReconnect() async {
    if (_realtimeDisposed || _isSubscribing) return;
    _reconnectAttempts += 1;
    final cappedAttempt = _reconnectAttempts > 6 ? 6 : _reconnectAttempts;
    final baseMs = 500 * (1 << cappedAttempt);
    final jitter = Random().nextInt(250);
    await Future<void>.delayed(Duration(milliseconds: (baseMs + jitter).toInt()));
    if (_realtimeDisposed) return;
    try {
      await _setupRealtime();
    } catch (e) {
      debugPrint('[RT] reconnect error: $e');
    }
  }

  void _onTablePayload({
    required V3RealtimeTableConfig config,
    required PostgresChangePayload payload,
  }) {
    final changed = _cacheStore.applyRealtimeMutation(
      table: config.name,
      newRecord: payload.newRecord,
      oldRecord: payload.oldRecord,
      isDelete: payload.eventType == PostgresChangeEvent.delete,
      activeKey: config.activeKey,
      hasActiveKey: config.hasActiveKey,
      keepInactive: config.keepInactive,
    );

    if (!changed) return;

    final id = (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString();

    for (final hook in config.hooks) {
      switch (hook) {
        case V3RealtimeHook.rebuildGpsCache:
          _rebuildGpsCacheFromOperativna();
          break;
        case V3RealtimeHook.applyGlobalAppSettings:
          if (id == 'global') {
            _applyAppSettings(payload.newRecord);
          }
          break;
      }
    }

    final affected = <String>{config.name, ...config.dependsOn};
    _scheduleEmit(tables: affected);
  }

  Stream<T> v3StreamFromCache<T>({required List<String> tables, required T Function() build}) {
    return v3StreamFromRevisions(tables: tables, build: build);
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

  int tableRevision(String table) => _cacheStore.revision(table);

  Stream<int> tableRevisionStream(String table) {
    final normalized = table.trim();
    return onRevisions.map((snapshot) => snapshot[normalized] ?? _cacheStore.revision(normalized)).distinct();
  }

  Stream<int> tablesRevisionStream(List<String> tables) {
    final normalized = tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(growable: false);
    if (normalized.isEmpty) {
      return onRevisions.map((_) => 0).distinct();
    }

    return onRevisions.map((snapshot) {
      var hash = 17;
      for (final table in normalized) {
        final revision = snapshot[table] ?? _cacheStore.revision(table);
        hash = (hash * 31) ^ revision;
      }
      return hash;
    }).distinct();
  }

  void v3UpsertToCache(String table, Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (id == null) return;

    _cacheStore.upsert(table, row);

    switch (table) {
      case 'v3_adrese':
        break;
      case 'v3_vozaci':
        break;
      case 'v3_vozila':
        break;
      case 'v3_putnici':
        break;
      case 'v3_zahtevi':
        break;
      case 'v3_gorivo':
        break;
      case 'v3_gorivo_promene':
        break;
      case 'v3_vozac_lokacije':
        break;
      case 'v3_finansije':
        break;
      case 'v3_racuni':
        break;
      case 'v3_racuni_arhiva':
        break;
      case 'v3_operativna_nedelja':
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_gps_trip_state':
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_trip_stops':
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_kapacitet_slots':
        break;
    }

    _scheduleEmit(tables: {table});
  }

  /// Osvježi v3GpsRasporedCache - gradi se lokalno iz v3_operativna_nedelja (WHERE vozac_id IS NOT NULL)
  Future<void> refreshV3GpsRaspored() async {
    try {
      _rebuildGpsCacheFromOperativna();
      _scheduleEmit(tables: {'v3_operativna_nedelja'});
      debugPrint(
          '[V3MasterRealtimeManager] v3GpsRasporedCache rebuilt: ${v3GpsRasporedCache.length} records from operativna_nedelja');
    } catch (e) {
      debugPrint('[V3MasterRealtimeManager] Error refreshing assigned operativna cache: $e');
    }
  }

  Map<String, dynamic>? getVozac(String id) => vozaciCache[id];
  Map<String, dynamic>? getPutnik(String id) => putniciCache[id];
  Map<String, dynamic>? getVozilo(String id) => vozilaCache[id];
  Map<String, dynamic>? getAdresa(String id) => adreseCache[id];

  Map<String, Map<String, dynamic>> getCache(String table) {
    switch (table) {
      case 'v3_adrese':
        return adreseCache;
      case 'v3_vozaci':
        return vozaciCache;
      case 'v3_vozila':
        return vozilaCache;
      case 'v3_putnici':
        return putniciCache;
      case 'v3_zahtevi':
        return zahteviCache;
      case 'v3_gorivo':
        return gorivoCache;
      case 'v3_gorivo_promene':
        return gorivoPromeneCache;
      case 'v3_vozac_lokacije':
        return vozacLokacijeCache;
      case 'v3_finansije':
        return troskoviCache;
      case 'v3_racuni':
        return racuniCache;
      case 'v3_racuni_arhiva':
        return racuniArhivaCache;
      case 'v3_operativna_nedelja':
        return operativnaNedeljaCache;
      case 'v3_kapacitet_slots':
        return kapacitetSlotsCache;
      case 'v3_gps_trip_state':
        return gpsTripStateCache;
      case 'v3_trip_stops':
        return tripStopsCache;
      case 'v3_app_settings':
        return appSettingsCache;
      case 'v3_gps_raspored':
        // Backward compatibility key: nema DB tabele, cache se gradi iz v3_operativna_nedelja.
        return v3GpsRasporedCache;
      default:
        return {};
    }
  }
}
