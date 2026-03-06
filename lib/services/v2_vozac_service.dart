import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje vozačima
class V2VozacService {
  V2VozacService._();

  static SupabaseClient get _supabase => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvata sve vozače iz rm cache-a (sync)
  static List<V2Vozac> getAllVozaci() {
    return _rm.vozaciCache.values.map((json) => V2Vozac.fromMap(json)).toList()..sort((a, b) => a.ime.compareTo(b.ime));
  }

  /// Dodaje novog vozača
  static Future<V2Vozac> addVozac(V2Vozac vozac) async {
    try {
      final response = await _supabase.from('v2_vozaci').insert(vozac.toMap()).select().single();
      _rm.v2UpsertToCache('v2_vozaci', response);
      return V2Vozac.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Ažurira postojećeg vozača
  static Future<V2Vozac> updateVozac(V2Vozac vozac) async {
    try {
      final response = await _supabase.from('v2_vozaci').update(vozac.toMap()).eq('id', vozac.id).select().single();
      _rm.v2UpsertToCache('v2_vozaci', response);
      return V2Vozac.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Menja samo šifru vozača (koristi vozač za self-service promenu šifre)
  static Future<void> updateSifra(String vozacId, String novaSifra) async {
    final response = await _supabase.from('v2_vozaci').update({'sifra': novaSifra}).eq('id', vozacId).select().single();
    _rm.v2UpsertToCache('v2_vozaci', response);
  }

  static Stream<List<V2Vozac>> streamAllVozaci() => _rm.v2StreamFromCache(tables: ['v2_vozaci'], build: getAllVozaci);
}
