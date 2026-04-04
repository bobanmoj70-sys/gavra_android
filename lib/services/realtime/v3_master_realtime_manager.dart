import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_time_utils.dart';
import '../v3/v3_app_update_service.dart';
import 'repositories/v3_realtime_bootstrap_repository.dart';

/// V3MasterRealtimeManager - Centralized cache and realtime manager for v3 tables.
class V3MasterRealtimeManager {
  V3MasterRealtimeManager._internal();
  static final V3MasterRealtimeManager _instance = V3MasterRealtimeManager._internal();
  static V3MasterRealtimeManager get instance => _instance;
  static final V3RealtimeBootstrapRepository _bootstrapRepository = V3RealtimeBootstrapRepository();

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
  final Map<String, Map<String, dynamic>> pinZahteviCache = {};
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
      final datumIso = V3DanHelper.parseIsoDatePart(trip['datum'] as String? ?? '');
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

      final datumIso = V3DanHelper.parseIsoDatePart(entry['datum'] as String? ?? '');
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
      currentType: row['nav_bar_type'] as String?,
      nextType: row['nav_bar_type_next'] as String?,
      effectiveAt: row['nav_bar_type_effective_at'],
      now: now,
    );
    if (navType != null) {
      navBarTypeNotifier.value = navType;
    }

    _navTypeSwitchTimer?.cancel();
    _navTypeSwitchTimer = null;

    final nextType = (row['nav_bar_type_next'] as String?)?.toLowerCase();
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

    unawaited(V3AppUpdateService.refreshUpdateInfo(appSettingsRow: row));
  }

  final StreamController<void> _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;
  final StreamController<Set<String>> _tableChangeController = StreamController<Set<String>>.broadcast();
  static const Duration _emitDebounceWindow = Duration(milliseconds: 90);
  final Set<String> _pendingTableChanges = <String>{};
  Timer? _emitDebounceTimer;
  Timer? _navTypeSwitchTimer;

  RealtimeChannel? _v3Channel;
  Future<void>? _initInFlight;
  bool _isInitialized = false;

  DateTime? _tryParseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  void _scheduleEmit({Set<String>? tables, bool immediate = false}) {
    if (tables != null && tables.isNotEmpty) {
      if (tables.contains('*')) {
        _pendingTableChanges
          ..clear()
          ..add('*');
      } else if (!_pendingTableChanges.contains('*')) {
        _pendingTableChanges.addAll(tables);
      }
    }

    if (immediate) {
      _emitDebounceTimer?.cancel();
      _emitDebounceTimer = null;
      _flushEmit();
      return;
    }

    if (_emitDebounceTimer != null && _emitDebounceTimer!.isActive) return;
    _emitDebounceTimer = Timer(_emitDebounceWindow, _flushEmit);
  }

  void _flushEmit() {
    _emitDebounceTimer = null;

    if (_pendingTableChanges.isEmpty) return;
    final changed = _pendingTableChanges.contains('*') ? <String>{'*'} : Set<String>.from(_pendingTableChanges);
    _pendingTableChanges.clear();

    _changeController.add(null);
    _tableChangeController.add(changed);
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
      final results = await _bootstrapRepository.fetchInitialData();

      _fillCache(adreseCache, results[0] as List);
      _fillCache(vozaciCache, results[1] as List);
      _fillCache(vozilaCache, results[2] as List);
      _fillCache(putniciCache, results[3] as List);
      _fillCache(zahteviCache, results[4] as List);
      _fillCache(gorivoCache, results[5] as List);
      _fillCache(gorivoPromeneCache, results[6] as List);
      _fillCache(vozacLokacijeCache, results[7] as List);
      _fillCache(troskoviCache, results[8] as List);
      _fillCache(pinZahteviCache, results[9] as List);
      _fillCache(operativnaNedeljaCache, results[10] as List);
      _fillCache(gpsTripStateCache, results[11] as List);
      _fillCache(tripStopsCache, results[12] as List);
      _fillCache(kapacitetSlotsCache, results[13] as List);
      _fillCache(appSettingsCache, results[14] as List);
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

  void _fillCache(Map<String, Map<String, dynamic>> cache, List data) {
    cache.clear();
    for (var item in data) {
      final id = item['id']?.toString();
      if (id != null) cache[id] = item as Map<String, dynamic>;
    }
  }

  Future<void> _setupRealtime() async {
    if (_v3Channel != null) {
      try {
        await supabase.removeChannel(_v3Channel!);
      } catch (_) {}
      _v3Channel = null;
    }

    _v3Channel = supabase.channel('v3_realtime_all');

    _setupTableRealtime('v3_adrese', adreseCache);
    _setupTableRealtime('v3_vozaci', vozaciCache);
    _setupTableRealtime('v3_vozila', vozilaCache);
    _setupTableRealtime('v3_putnici', putniciCache);
    _setupTableRealtime('v3_zahtevi', zahteviCache);
    _setupTableRealtime('v3_gorivo', gorivoCache);
    _setupTableRealtime('v3_gorivo_promene', gorivoPromeneCache, hasActiveKey: false);
    _setupTableRealtime('v3_vozac_lokacije', vozacLokacijeCache, hasActiveKey: false);
    _setupTableRealtime('v3_finansije', troskoviCache);
    _setupTableRealtime('v3_pin_zahtevi', pinZahteviCache);
    _setupTableRealtime('v3_operativna_nedelja', operativnaNedeljaCache, keepInactive: true);
    _setupTableRealtime('v3_gps_trip_state', gpsTripStateCache, hasActiveKey: false);
    _setupTableRealtime('v3_trip_stops', tripStopsCache, hasActiveKey: false);
    _setupTableRealtime('v3_kapacitet_slots', kapacitetSlotsCache);
    _setupTableRealtime('v3_app_settings', appSettingsCache, hasActiveKey: false);

    _v3Channel!.subscribe();
  }

  void _setupTableRealtime(String table, Map<String, Map<String, dynamic>> cache,
      {String activeKey = 'aktivno', bool hasActiveKey = true, bool keepInactive = false}) {
    _v3Channel?.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (payload) {
        final newRecord = payload.newRecord;
        final oldRecord = payload.oldRecord;
        final id = (newRecord['id'] ?? oldRecord['id'])?.toString();

        if (id == null) return;

        bool isActive = true;
        if (hasActiveKey && newRecord.containsKey(activeKey)) {
          isActive = newRecord[activeKey] as bool? ?? true;
        }

        if (payload.eventType == PostgresChangeEvent.delete || (!isActive && !keepInactive)) {
          cache.remove(id);
        } else {
          cache[id] = Map<String, dynamic>.from(newRecord);
        }
        if (table == 'v3_operativna_nedelja' || table == 'v3_gps_trip_state' || table == 'v3_trip_stops') {
          _rebuildGpsCacheFromOperativna();
        }
        if (table == 'v3_app_settings' && id == 'global') {
          _applyAppSettings(newRecord);
        }
        if (table == 'v3_gps_trip_state') {
          _scheduleEmit(tables: {table, 'v3_operativna_nedelja'});
        } else if (table == 'v3_trip_stops') {
          _scheduleEmit(tables: {table, 'v3_operativna_nedelja'});
        } else {
          _scheduleEmit(tables: {table});
        }
      },
    );
  }

  Stream<T> v3StreamFromCache<T>({required List<String> tables, required T Function() build}) {
    final watchedTables = tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();

    return _tableChangeController.stream
        .where((changedTables) {
          if (changedTables.contains('*') || watchedTables.isEmpty) return true;
          for (final table in watchedTables) {
            if (changedTables.contains(table)) return true;
          }
          return false;
        })
        .map((_) => build())
        .asBroadcastStream(
          onListen: (subs) => _tableChangeController.add({'*'}),
        );
  }

  void v3UpsertToCache(String table, Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (id == null) return;

    switch (table) {
      case 'v3_adrese':
        adreseCache[id] = row;
        break;
      case 'v3_vozaci':
        vozaciCache[id] = row;
        break;
      case 'v3_vozila':
        vozilaCache[id] = row;
        break;
      case 'v3_putnici':
        putniciCache[id] = row;
        break;
      case 'v3_zahtevi':
        zahteviCache[id] = row;
        break;
      case 'v3_gorivo':
        gorivoCache[id] = row;
        break;
      case 'v3_gorivo_promene':
        gorivoPromeneCache[id] = row;
        break;
      case 'v3_vozac_lokacije':
        vozacLokacijeCache[id] = row;
        break;
      case 'v3_finansije':
        troskoviCache[id] = row;
        break;
      case 'v3_operativna_nedelja':
        operativnaNedeljaCache[id] = row;
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_gps_trip_state':
        gpsTripStateCache[id] = row;
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_trip_stops':
        tripStopsCache[id] = row;
        _rebuildGpsCacheFromOperativna();
        break;
      case 'v3_kapacitet_slots':
        kapacitetSlotsCache[id] = row;
        break;
      case 'v3_pin_zahtevi':
        if (row['status'] == 'ceka') {
          pinZahteviCache[id] = row;
        } else {
          pinZahteviCache.remove(id);
        }
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
      case 'v3_pin_zahtevi':
        return pinZahteviCache;
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
