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
      return V2Vozac.fromMap(response);
    } catch (e) {
      debugPrint('[V2VozacService] Greška u updateVozac(): $e');
      rethrow;
    }
  }

  /// Realtime stream: dohvata sve vozače u realnom vremenu.
  /// Emituje direktno iz rm cache-a, bez DB fetcha na svaki event.
  Stream<List<V2Vozac>> streamAllVozaci() {
    final controller = StreamController<List<V2Vozac>>.broadcast();
    // Inicijalno emitovanje
    controller.add(getAllVozaci());
    // Svaki rm event → emit iz cache
    final sub = _rm.subscribe('v2_vozaci').listen((_) {
      if (!controller.isClosed) controller.add(getAllVozaci());
    });
    controller.onCancel = () {
      sub.cancel();
      controller.close();
    };
    return controller.stream;
  }
}
