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
  final Map<String, Map<String, dynamic>> dugoviCache = {};
  final Map<String, Map<String, dynamic>> finansijeCache = {};
  final Map<String, Map<String, dynamic>> gorivoStanjeCache = {};
  final Map<String, Map<String, dynamic>> gorivoPunjenjaCache = {};
  final Map<String, Map<String, dynamic>> gorivoTocenjaCache = {};

  final StreamController<void> _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  RealtimeChannel? _v3Channel;

  /// Initializes all v3 caches from the database.
  Future<void> initV3() async {
    try {
      final results = await Future.wait([
        supabase.from('v3_adrese').select().eq('aktivno', true),
        supabase.from('v3_vozaci').select().eq('aktivno', true),
        supabase.from('v3_vozila').select().eq('aktivno', true),
        supabase.from('v3_putnici').select().eq('aktivna', true),
        supabase.from('v3_zahtevi').select().eq('aktivno', true),
        supabase.from('v3_dugovi').select().eq('placeno', false),
        supabase.from('v3_finansije').select().order('datum', ascending: false).limit(500),
        supabase.from('v3_gorivo_stanje').select(),
        supabase.from('v3_gorivo_punjenja').select().order('datum', ascending: false).limit(200),
        supabase.from('v3_gorivo_tocenja').select().order('datum', ascending: false).limit(500),
      ]);

      _fillCache(adreseCache, results[0] as List);
      _fillCache(vozaciCache, results[1] as List);
      _fillCache(vozilaCache, results[2] as List);
      _fillCache(putniciCache, results[3] as List);
      _fillCache(zahteviCache, results[4] as List);
      _fillCache(dugoviCache, results[5] as List);
      _fillCache(finansijeCache, results[6] as List);
      _fillCache(gorivoStanjeCache, results[7] as List);
      _fillCache(gorivoPunjenjaCache, results[8] as List);
      _fillCache(gorivoTocenjaCache, results[9] as List);

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
    _setupTableRealtime('v3_putnici', putniciCache, activeKey: 'aktivna');
    _setupTableRealtime('v3_zahtevi', zahteviCache);
    _setupTableRealtime('v3_dugovi', dugoviCache, activeKey: 'placeno', invertActive: true);
    _setupTableRealtime('v3_finansije', finansijeCache);
    _setupTableRealtime('v3_gorivo_stanje', gorivoStanjeCache);
    _setupTableRealtime('v3_gorivo_punjenja', gorivoPunjenjaCache);
    _setupTableRealtime('v3_gorivo_tocenja', gorivoTocenjaCache);

    _v3Channel?.subscribe();
  }

  void _setupTableRealtime(String table, Map<String, Map<String, dynamic>> cache,
      {String activeKey = 'aktivno', bool invertActive = false}) {
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
        if (newRecord.containsKey(activeKey)) {
          isActive = newRecord[activeKey] as bool;
          if (invertActive) isActive = !isActive;
        }

        if (payload.eventType == PostgresChangeEvent.delete || !isActive) {
          cache.remove(id);
        } else {
          cache[id] = Map<String, dynamic>.from(newRecord);
        }
        _changeController.add(null);
      },
    );
  }

  /// Helper to stream data from cache for specific tables.
  Stream<T> v3StreamFromCache<T>({required List<String> tables, required T Function() build}) {
    // For V3, the simple broadcast is enough as it triggers on ANY v3 update.
    return _changeController.stream.map((_) => build()).asBroadcastStream(
          onListen: (subs) => _changeController.add(null),
        );
  }

  void v3UpsertToCache(String table, Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (id == null) return;

    // Simple routing based on table name
    if (table == 'v3_adrese')
      adreseCache[id] = row;
    else if (table == 'v3_vozaci')
      vozaciCache[id] = row;
    else if (table == 'v3_vozila')
      vozilaCache[id] = row;
    else if (table == 'v3_putnici')
      putniciCache[id] = row;
    else if (table == 'v3_zahtevi')
      zahteviCache[id] = row;
    else if (table == 'v3_dugovi')
      dugoviCache[id] = row;
    else if (table == 'v3_finansije') finansijeCache[id] = row;

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
      case 'v3_dugovi':
        return dugoviCache;
      case 'v3_finansije':
        return finansijeCache;
      case 'v3_gorivo_stanje':
        return gorivoStanjeCache;
      case 'v3_gorivo_punjenja':
        return gorivoPunjenjaCache;
      case 'v3_gorivo_tocenja':
        return gorivoTocenjaCache;
      default:
        return {};
    }
  }
}
