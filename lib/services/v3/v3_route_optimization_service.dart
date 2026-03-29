import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service za optimizaciju rute pokupljanja putnika
/// Poziva SQL funkciju fn_v3_optimize_pickup_route
class V3RouteOptimizationService {
  V3RouteOptimizationService._();

  static String _normalizeTime(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final parts = value.trim().split(':');
    if (parts.length < 2) return value.trim();
    final hour = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final minute = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static int? _parseRouteOrder(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

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
      final gradNorm = grad.toUpperCase();
      final vremeNorm = _normalizeTime(vreme);

      final putnici = cache.values
          .where((row) =>
              row['vozac_id'] == vozacId &&
              V3DanHelper.parseIsoDatePart(row['datum']?.toString() ?? '') == datumStr &&
              (row['grad']?.toString().toUpperCase() ?? '') == gradNorm &&
              _normalizeTime(row['vreme']?.toString()) == vremeNorm &&
              row['aktivno'] == true &&
              row['pickup_lat'] != null &&
              row['pickup_lng'] != null)
          .toList();

      // Sortira po route_order ako postoji, inače po pickup_naziv
      putnici.sort((a, b) {
        final orderA = _parseRouteOrder(a['route_order']);
        final orderB = _parseRouteOrder(b['route_order']);

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
