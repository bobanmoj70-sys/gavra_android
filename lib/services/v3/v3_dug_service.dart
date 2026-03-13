import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_dug.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3DugService {
  V3DugService._();

  static List<V3Dug> getDugovi() {
    final cache = V3MasterRealtimeManager.instance.dugoviCache.values;
    return cache.where((r) => r['placeno'] == false).map((r) => V3Dug.fromJson(r)).toList()
      ..sort((a, b) => b.datum.compareTo(a.datum));
  }

  static Stream<List<V3Dug>> streamDugovi() =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(tables: ['v3_dugovi'], build: () => getDugovi());

  static Future<void> markAsPaid(String id) async {
    try {
      await supabase.from('v3_dugovi').update({'placeno': true}).eq('id', id);
      V3MasterRealtimeManager.instance.dugoviCache.remove(id);
    } catch (e) {
      debugPrint('[V3DugService] Mark as paid error: $e');
      rethrow;
    }
  }

  static Future<void> addDug(V3Dug dug) async {
    try {
      final row = await supabase.from('v3_dugovi').insert(dug.toJson()).select().single();
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_dugovi', row);
    } catch (e) {
      debugPrint('[V3DugService] Add dug error: $e');
      rethrow;
    }
  }
}
