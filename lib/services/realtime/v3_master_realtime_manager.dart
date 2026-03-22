import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';

/// V3MasterRealtimeManager - Centralized cache and realtime manager for v3 tables.
class V3MasterRealtimeManager {
  V3MasterRealtimeManager._internal();
  static final V3MasterRealtimeManager _instance = V3MasterRealtimeManager._internal();
  static V3MasterRealtimeManager get instance => _instance;

  // --- IN-MEMORY CACHE ---
  final Map<String, Map<String, dynamic>> adreseCache = {};
  final Map<String, Map<String, dynamic>> vozaciCache = {};
  final Map<String, Map<String, dynamic>> vozilaCache = {};
  final Map<String, Map<String, dynamic>> putniciCache = {};
  final Map<String, Map<String, dynamic>> zahteviCache = {};
  final Map<String, Map<String, dynamic>> postavkeKapacitetaCache = {};
  final Map<String, Map<String, dynamic>> pumpaStanjeCache = {};
  final Map<String, Map<String, dynamic>> pumpaRezervoarCache = {};
  final Map<String, Map<String, dynamic>> vozacLokacijeCache = {};
  final Map<String, Map<String, dynamic>> troskoviCache = {};
  final Map<String, Map<String, dynamic>> finansijeStanjeCache = {};
  final Map<String, Map<String, dynamic>> pinZahteviCache = {};
  final Map<String, Map<String, dynamic>> operativnaNedeljaCache = {};
  final Map<String, Map<String, dynamic>> kapacitetSlotsCache = {};
  final Map<String, Map<String, dynamic>> gpsActivationScheduleCache = {};
  final Map<String, Map<String, dynamic>> gpsTriggerStatsCache = {};
  final Map<String, Map<String, dynamic>> appSettingsCache = {};
  final Map<String, Map<String, dynamic>> v3GpsRasporedCache = {};

  final StreamController<void> _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  RealtimeChannel? _v3Channel;
  Future<void>? _initInFlight;
  bool _isInitialized = false;

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
      final results = await Future.wait([
        supabase.from('v3_adrese').select().eq('aktivno', true),
        supabase.from('v3_vozaci').select().eq('aktivno', true),
        supabase.from('v3_vozila').select().eq('aktivno', true),
        supabase.from('v3_putnici').select().eq('aktivno', true),
        supabase
            .from('v3_zahtevi')
            .select(
                'id, putnik_id, datum, grad, zeljeno_vreme, broj_mesta, status, napomena, dodeljeno_vreme, koristi_sekundarnu, adresa_id_override, alt_vreme_pre, alt_vreme_posle, alt_napomena, aktivno, created_at, updated_at, created_by, scheduled_at')
            .eq('aktivno', true),
        supabase.from('v3_pumpa_stanje').select().eq('aktivno', true),
        supabase.from('v3_pumpa_rezervoar').select(),
        supabase.from('v3_vozac_lokacije').select(),
        supabase.from('v3_troskovi').select().eq('aktivno', true),
        supabase.from('v3_finansije_stanje').select().eq('aktivno', true),
        supabase.from('v3_operativna_nedelja').select(),
        supabase.from('v3_kapacitet_slots').select().eq('aktivno', true),
        supabase.from('v3_app_settings').select(),
        supabase.from('v3_gps_raspored').select().order('created_at', ascending: false).limit(1000),
      ]);

      _fillCache(adreseCache, results[0] as List);
      _fillCache(vozaciCache, results[1] as List);
      _fillCache(vozilaCache, results[2] as List);
      _fillCache(putniciCache, results[3] as List);
      _fillCache(zahteviCache, results[4] as List);
      _fillCache(pumpaStanjeCache, results[5] as List);
      _fillCache(pumpaRezervoarCache, results[6] as List);
      _fillCache(vozacLokacijeCache, results[7] as List);
      _fillCache(troskoviCache, results[8] as List);
      _fillCache(finansijeStanjeCache, results[9] as List);
      _fillCache(operativnaNedeljaCache, results[10] as List);
      _fillCache(kapacitetSlotsCache, results[11] as List);
      _fillCache(appSettingsCache, results[12] as List);
      _fillCache(v3GpsRasporedCache, results[13] as List);

      await _setupRealtime();
      _isInitialized = true;
      _changeController.add(null);
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
    _setupTableRealtime('v3_pumpa_stanje', pumpaStanjeCache);
    _setupTableRealtime('v3_pumpa_rezervoar', pumpaRezervoarCache, hasActiveKey: false);
    _setupTableRealtime('v3_vozac_lokacije', vozacLokacijeCache, hasActiveKey: false);
    _setupTableRealtime('v3_troskovi', troskoviCache);
    _setupTableRealtime('v3_finansije_stanje', finansijeStanjeCache);
    _setupTableRealtime('v3_pin_zahtevi', pinZahteviCache);
    _setupTableRealtime('v3_operativna_nedelja', operativnaNedeljaCache, keepInactive: true);
    _setupTableRealtime('v3_kapacitet_slots', kapacitetSlotsCache);
    _setupTableRealtime('v3_app_settings', appSettingsCache, hasActiveKey: false);
    _setupTableRealtime('v3_gps_raspored', v3GpsRasporedCache, hasActiveKey: false);

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
        _changeController.add(null);
      },
    );
  }

  Stream<T> v3StreamFromCache<T>({required List<String> tables, required T Function() build}) {
    return _changeController.stream.map((_) => build()).asBroadcastStream(
          onListen: (subs) => _changeController.add(null),
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
      case 'v3_pumpa_stanje':
        pumpaStanjeCache[id] = row;
        break;
      case 'v3_pumpa_rezervoar':
        pumpaRezervoarCache[id] = row;
        break;
      case 'v3_vozac_lokacije':
        vozacLokacijeCache[id] = row;
        break;
      case 'v3_troskovi':
        troskoviCache[id] = row;
        break;
      case 'v3_finansije_stanje':
        finansijeStanjeCache[id] = row;
        break;
      case 'v3_operativna_nedelja':
        operativnaNedeljaCache[id] = row;
        break;
      case 'v3_kapacitet_slots':
        kapacitetSlotsCache[id] = row;
        break;
      case 'v3_gps_raspored':
        v3GpsRasporedCache[id] = row;
        break;
      case 'v3_pin_zahtevi':
        if (row['status'] == 'ceka') {
          pinZahteviCache[id] = row;
        } else {
          pinZahteviCache.remove(id);
        }
        break;
    }

    _changeController.add(null);
  }

  /// Osvži v3_gps_raspored cache nakon izmena
  Future<void> refreshV3GpsRaspored() async {
    try {
      final result = await supabase.from('v3_gps_raspored').select().order('created_at', ascending: false).limit(1000);
      _fillCache(v3GpsRasporedCache, result);
      _changeController.add(null);
      debugPrint('[V3MasterRealtimeManager] v3_gps_raspored cache refreshed: ${v3GpsRasporedCache.length} records');
    } catch (e) {
      debugPrint('[V3MasterRealtimeManager] Error refreshing v3_gps_raspored: $e');
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
      case 'v3_pumpa_stanje':
        return pumpaStanjeCache;
      case 'v3_pumpa_rezervoar':
        return pumpaRezervoarCache;
      case 'v3_vozac_lokacije':
        return vozacLokacijeCache;
      case 'v3_troskovi':
        return troskoviCache;
      case 'v3_finansije_stanje':
        return finansijeStanjeCache;
      case 'v3_pin_zahtevi':
        return pinZahteviCache;
      case 'v3_operativna_nedelja':
        return operativnaNedeljaCache;
      case 'v3_kapacitet_slots':
        return kapacitetSlotsCache;
      case 'v3_app_settings':
        return appSettingsCache;
      case 'v3_gps_raspored':
        return v3GpsRasporedCache;
      default:
        return {};
    }
  }
}
