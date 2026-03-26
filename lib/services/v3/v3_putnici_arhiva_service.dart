import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_putnik_arhiva.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3PutniciArhivaService {
  V3PutniciArhivaService._();

  static List<V3PutnikArhiva> getByPutnik(String putnikId) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_putnici_arhiva');
    return cache.values
        .where((row) => row['aktivno'] != false && row['putnik_id']?.toString() == putnikId)
        .map((row) => V3PutnikArhiva.fromJson(row))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  }

  static List<V3PutnikArhiva> getForPeriod({required int mesec, required int godina}) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_putnici_arhiva');
    return cache.values
        .where((row) => row['aktivno'] != false && row['za_mesec'] == mesec && row['za_godinu'] == godina)
        .map((row) => V3PutnikArhiva.fromJson(row))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  }

  static Stream<List<V3PutnikArhiva>> streamByPutnik(String putnikId) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_putnici_arhiva'],
      build: () => getByPutnik(putnikId),
    );
  }

  static Future<void> addZapis(V3PutnikArhiva zapis) async {
    try {
      await supabase.from('v3_putnici_arhiva').insert(zapis.toJson());
    } catch (e) {
      debugPrint('[V3PutniciArhivaService] addZapis error: $e');
      rethrow;
    }
  }
}
