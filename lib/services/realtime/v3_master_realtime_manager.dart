import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../v3/v3_kapacitet_service.dart';

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
  final Map<String, Map<String, dynamic>> rasporedTerminCache = {};
  final Map<String, Map<String, dynamic>> rasporedPutnikCache = {};
  final Map<String, Map<String, dynamic>> vozacLokacijeCache = {};
  final Map<String, Map<String, dynamic>> troskoviCache = {};
  final Map<String, Map<String, dynamic>> finansijeStanjeCache = {};
  final Map<String, Map<String, dynamic>> pinZahteviCache = {};
  final Map<String, Map<String, dynamic>> operativnaNedeljaCache = {};
  final Map<String, Map<String, dynamic>> appSettingsCache = {};
  final Map<String, Map<String, dynamic>> kapacitetCache = {};

  final StreamController<void> _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  RealtimeChannel? _v3Channel;

  Future<void> initV3() async {
    try {
      final results = await Future.wait([
        supabase.from('v3_adrese').select().eq('aktivno', true),
        supabase.from('v3_vozaci').select().eq('aktivno', true),
        supabase.from('v3_vozila').select().eq('aktivno', true),
        supabase.from('v3_putnici').select().eq('aktivno', true),
        supabase.from('v3_zahtevi').select().eq('aktivno', true),
        supabase.from('v3_pumpa_stanje').select().eq('aktivno', true),
        supabase.from('v3_pumpa_rezervoar').select(),
        supabase.from('v3_raspored_termin').select().order('created_at', ascending: false).limit(200),
        supabase.from('v3_raspored_putnik').select().order('created_at', ascending: false).limit(500),
        supabase.from('v3_vozac_lokacije').select(),
        supabase.from('v3_troskovi').select().eq('aktivno', true),
        supabase.from('v3_finansije_stanje').select().eq('aktivno', true),
        supabase.from('v3_operativna_nedelja').select(),
        supabase.from('v3_app_settings').select(),
        supabase.from('v3_kapacitet').select().eq('aktivno', true),
      ]);

      _fillCache(adreseCache, results[0] as List);
      _fillCache(vozaciCache, results[1] as List);
      _fillCache(vozilaCache, results[2] as List);
      _fillCache(putniciCache, results[3] as List);
      _fillCache(zahteviCache, results[4] as List);
      _fillCache(pumpaStanjeCache, results[5] as List);
      _fillCache(pumpaRezervoarCache, results[6] as List);
      _fillCache(rasporedTerminCache, results[7] as List);
      _fillCache(rasporedPutnikCache, results[8] as List);
      _fillCache(vozacLokacijeCache, results[9] as List);
      _fillCache(troskoviCache, results[10] as List);
      _fillCache(finansijeStanjeCache, results[11] as List);
      _fillCache(operativnaNedeljaCache, results[12] as List);
      _fillCache(appSettingsCache, results[13] as List);
      _fillCache(kapacitetCache, results[14] as List);

      // Kreiraj slotove koji nedostaju u v3_kapacitet (iz trenutnog sezona konfiguracije)
      await V3KapacitetService.syncSlotsFromConfig();

      _setupRealtime();
      debugPrint('[V3MasterRealtimeManager] Initialized successfully');
    } catch (e) {
      debugPrint('[V3MasterRealtimeManager] Initialization error: $e');
    }
  }

  void _fillCache(Map<String, Map<String, dynamic>> cache, List data) {
    cache.clear();
    for (var item in data) {
      final id = item['id']?.toString();
      if (id != null) cache[id] = item as Map<String, dynamic>;
    }
  }

  void _setupRealtime() {
    _v3Channel = supabase.channel('v3_realtime_all');

    _setupTableRealtime('v3_adrese', adreseCache);
    _setupTableRealtime('v3_vozaci', vozaciCache);
    _setupTableRealtime('v3_vozila', vozilaCache);
    _setupTableRealtime('v3_putnici', putniciCache);
    _setupTableRealtime('v3_zahtevi', zahteviCache);
    _setupTableRealtime('v3_pumpa_stanje', pumpaStanjeCache);
    _setupTableRealtime('v3_pumpa_rezervoar', pumpaRezervoarCache, hasActiveKey: false);
    _setupTableRealtime('v3_raspored_termin', rasporedTerminCache, hasActiveKey: false);
    _setupTableRealtime('v3_raspored_putnik', rasporedPutnikCache, hasActiveKey: false);
    _setupTableRealtime('v3_vozac_lokacije', vozacLokacijeCache, hasActiveKey: false);
    _setupTableRealtime('v3_troskovi', troskoviCache);
    _setupTableRealtime('v3_finansije_stanje', finansijeStanjeCache);
    _setupTableRealtime('v3_pin_zahtevi', pinZahteviCache);
    _setupTableRealtime('v3_operativna_nedelja', operativnaNedeljaCache, keepInactive: true);
    _setupTableRealtime('v3_app_settings', appSettingsCache, hasActiveKey: false);
    _setupTableRealtime('v3_kapacitet', kapacitetCache);

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
      case 'v3_raspored_termin':
        rasporedTerminCache[id] = row;
        break;
      case 'v3_raspored_putnik':
        rasporedPutnikCache[id] = row;
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
      case 'v3_kapacitet':
        kapacitetCache[id] = row;
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
      case 'v3_raspored_termin':
        return rasporedTerminCache;
      case 'v3_raspored_putnik':
        return rasporedPutnikCache;
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
      case 'v3_kapacitet':
        return kapacitetCache;
      default:
        return {};
    }
  }
}
