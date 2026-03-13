import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_finansije.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3FinansijeService {
  V3FinansijeService._();

  static List<V3FinansijskiUnos> _filterUnosi(DateTime start, DateTime end) {
    final cache = V3MasterRealtimeManager.instance.finansijeCache.values;
    return cache
        .map((r) => V3FinansijskiUnos.fromJson(r))
        .where((u) => u.datum.isAfter(start) && u.datum.isBefore(end))
        .toList()
      ..sort((a, b) => b.datum.compareTo(a.datum));
  }

  static Stream<V3FinansijskiIzvestaj> streamIzvestaj() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_finansije'],
        build: () {
          final now = DateTime.now();
          final startDanas = DateTime(now.year, now.month, now.day);
          final endDanas = startDanas.add(const Duration(days: 1));
          final startMesec = DateTime(now.year, now.month, 1);
          final endMesec = DateTime(now.year, now.month + 1, 1);

          final unosiMesec = _filterUnosi(startMesec, endMesec);
          final unosiDanas =
              unosiMesec.where((u) => u.datum.isAfter(startDanas) && u.datum.isBefore(endDanas)).toList();

          double prihodDanas = 0;
          double trosakDanas = 0;
          for (final u in unosiDanas) {
            if (u.tip == 'prihod')
              prihodDanas += u.iznos;
            else
              trosakDanas += u.iznos;
          }

          double prihodMesec = 0;
          double trosakMesec = 0;
          final Map<String, double> poKategoriji = {};
          for (final u in unosiMesec) {
            if (u.tip == 'prihod') {
              prihodMesec += u.iznos;
            } else {
              trosakMesec += u.iznos;
              poKategoriji[u.kategorija] = (poKategoriji[u.kategorija] ?? 0) + u.iznos;
            }
          }

          return V3FinansijskiIzvestaj(
            prihodDanas: prihodDanas,
            trosakDanas: trosakDanas,
            prihodMesec: prihodMesec,
            trosakMesec: trosakMesec,
            troskoviPoKategoriji: poKategoriji,
          );
        });
  }

  static Future<void> addUnos(V3FinansijskiUnos unos) async {
    try {
      final data = unos.toJson();
      final row = await supabase.from('v3_finansije').insert(data).select().single();
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } catch (e) {
      debugPrint('[V3FinansijeService] addUnos error: $e');
      rethrow;
    }
  }

  static Future<void> deleteUnos(String id) async {
    try {
      await supabase.from('v3_finansije').delete().eq('id', id);
      V3MasterRealtimeManager.instance.finansijeCache.remove(id);
    } catch (e) {
      debugPrint('[V3FinansijeService] deleteUnos error: $e');
      rethrow;
    }
  }
}
