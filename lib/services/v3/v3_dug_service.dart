import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_dug.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// V3DugService - Upravljanje dugovima/naplatama iz v3_dnevne_operacije.
/// Tabela v3_dugovi ne postoji - dugovi se prate kroz naplata_status u v3_dnevne_operacije.
class V3DugService {
  V3DugService._();

  /// Vraca sve nenaplacene operacije kao listu dugova
  static List<V3Dug> getDugovi() {
    final cache = V3MasterRealtimeManager.instance.dnevneOperacijeCache;
    final dugovi = <V3Dug>[];
    for (final row in cache.values) {
      final naplataSt = row['naplata_status'] as String? ?? 'nije_placeno';
      if (naplataSt == 'nije_placeno' || naplataSt == 'ceka') {
        try {
          dugovi.add(V3Dug.fromOperacija(row));
        } catch (_) {}
      }
    }
    dugovi.sort((a, b) => b.datum.compareTo(a.datum));
    return dugovi;
  }

  static Stream<List<V3Dug>> streamDugovi() =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(tables: ['v3_dnevne_operacije'], build: () => getDugovi());

  static Future<void> markAsPaid(String operacijaId) async {
    try {
      final row = await supabase
          .from('v3_dnevne_operacije')
          .update({
            'naplata_status': 'placeno',
            'vreme_placen': DateTime.now().toIso8601String(),
          })
          .eq('id', operacijaId)
          .select()
          .single();
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_dnevne_operacije', row);
    } catch (e) {
      debugPrint('[V3DugService] markAsPaid error: $e');
      rethrow;
    }
  }
}
