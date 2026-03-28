import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service za optimizaciju rute pokupljanja putnika
/// Poziva SQL funkciju fn_v3_optimize_pickup_route
class V3RouteOptimizationService {
  V3RouteOptimizationService._();

  /// Optimizuje rutu za specifičnog vozača na određeni datum/vreme/grad
  static Future<Map<String, dynamic>?> optimizePickupRoute({
    required String vozacId,
    required DateTime datum,
    required String grad,
    required String vreme,
  }) async {
    try {
      final response = await supabase.rpc('fn_v3_optimize_pickup_route', params: {
        'p_vozac_id': vozacId,
        'p_datum': V3DanHelper.toIsoDate(datum), // YYYY-MM-DD format
        'p_grad': grad,
        'p_vreme': vreme,
      });

      if (response != null && response['success'] == true) {
        debugPrint('[RouteOpt] Optimizovano za vozača $vozacId: ${response['putnik_count']} putnika');
        return response as Map<String, dynamic>;
      } else {
        debugPrint('[RouteOpt] Greška: ${response?['error'] ?? 'Unknown error'}');
        return null;
      }
    } catch (e) {
      debugPrint('[RouteOpt] Exception: $e');
      return null;
    }
  }

  /// Dobija optimizovane putnici sa pickup koordinatama i route_order
  static List<Map<String, dynamic>> getOptimizedPutnici({
    required String vozacId,
    required DateTime datum,
    required String grad,
    required String vreme,
  }) {
    try {
      // Dobija podatke iz legacy v3GpsRasporedCache (izvor: v3_operativna_nedelja)
      final cache = V3MasterRealtimeManager.instance.v3GpsRasporedCache;
      final datumStr = V3DanHelper.toIsoDate(datum);

      final putnici = cache.values
          .where((row) =>
              row['vozac_id'] == vozacId &&
              V3DanHelper.parseIsoDatePart(row['datum']?.toString() ?? '') == datumStr &&
              row['grad'] == grad &&
              row['vreme'] == vreme &&
              row['aktivno'] == true &&
              row['pickup_lat'] != null &&
              row['pickup_lng'] != null)
          .toList();

      // Sortira po route_order ako postoji, inače po pickup_naziv
      putnici.sort((a, b) {
        final orderA = a['route_order'] as int?;
        final orderB = b['route_order'] as int?;

        if (orderA != null && orderB != null) {
          return orderA.compareTo(orderB);
        }

        // Fallback na pickup_naziv
        final nazivA = a['pickup_naziv']?.toString() ?? '';
        final nazivB = b['pickup_naziv']?.toString() ?? '';
        return nazivA.compareTo(nazivB);
      });

      debugPrint('[RouteOpt] Našao ${putnici.length} optimizovanih putnika za $vozacId');
      return putnici;
    } catch (e) {
      debugPrint('[RouteOpt] Greška pri čitanju optimizovanih putnika: $e');
      return [];
    }
  }
}
