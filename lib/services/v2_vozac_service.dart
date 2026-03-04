import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje vozačima
class V2VozacService {
  // Singleton pattern
  static final V2VozacService _instance = V2VozacService._internal();

  factory V2VozacService() {
    return _instance;
  }

  V2VozacService._internal();

  SupabaseClient get _supabase => supabase;

  V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvata sve vozače iz rm cache-a (sync)
  List<V2Vozac> getAllVozaci() {
    return _rm.vozaciCache.values.map((json) => V2Vozac.fromMap(json)).toList()..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dodaje novog vozača
  Future<V2Vozac> addVozac(V2Vozac vozac) async {
    try {
      final response = await _supabase.from('v2_vozaci').insert(vozac.toMap()).select().single();
      _rm.upsertToCache('v2_vozaci', response);
      return V2Vozac.fromMap(response);
    } catch (e) {
      debugPrint('[V2VozacService] Greška u addVozac(): $e');
      rethrow;
    }
  }

  /// Ažurira postojećeg vozača
  Future<V2Vozac> updateVozac(V2Vozac vozac) async {
    try {
      final response = await _supabase.from('v2_vozaci').update(vozac.toMap()).eq('id', vozac.id).select().single();
      _rm.upsertToCache('v2_vozaci', response);
      return V2Vozac.fromMap(response);
    } catch (e) {
      debugPrint('[V2VozacService] Greška u updateVozac(): $e');
      rethrow;
    }
  }

  /// Realtime stream: dohvata sve vozače u realnom vremenu.
  /// Reaktivan: osvježava se kad god addVozac/updateVozac/delete promijeni cache.
  Stream<List<V2Vozac>> streamAllVozaci() {
    final controller = StreamController<List<V2Vozac>>.broadcast();
    void emit() {
      if (!controller.isClosed) controller.add(getAllVozaci());
    }

    Future.microtask(emit);

    final cacheSub = _rm.onCacheChanged.where((t) => t == 'v2_vozaci').listen((_) => emit());
    controller.onCancel = () {
      cacheSub.cancel();
      controller.close();
    };
    return controller.stream;
  }
}
