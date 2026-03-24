import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_adresa.dart';
import '../../utils/v3_validation_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for interacting with universal V3 addresses.
class V3AdresaService {
  V3AdresaService._();

  static List<V3Adresa> getSortedAdrese() {
    final cache = V3MasterRealtimeManager.instance.adreseCache.values;
    final list = cache.map((r) => V3Adresa.fromJson(r)).toList();
    list.sort((a, b) {
      final g = (a.grad ?? '').compareTo(b.grad ?? '');
      return g != 0 ? g : a.naziv.compareTo(b.naziv);
    });
    return list;
  }

  static Stream<List<V3Adresa>> streamAdrese() =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(tables: ['v3_adrese'], build: getSortedAdrese);

  static V3Adresa? getAdresaById(String? id) {
    if (id == null || id.isEmpty) return null;
    final data = V3MasterRealtimeManager.instance.adreseCache[id];
    return data != null ? V3Adresa.fromJson(data) : null;
  }

  static String? getNazivAdreseById(String? id) {
    if (id == null || id.isEmpty) return null;
    return V3MasterRealtimeManager.instance.adreseCache[id]?['naziv'] as String?;
  }

  static List<V3Adresa> getAdreseZaGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.adreseCache.values;
    final normalizedGrad = V3ValidationUtils.normalizeGrad(grad);
    if (normalizedGrad.isEmpty) return [];
    return cache
        .where((r) => V3ValidationUtils.normalizeGrad(r['grad'] as String? ?? '') == normalizedGrad)
        .map((r) => V3Adresa.fromJson(r))
        .toList()
      ..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  static Future<void> addUpdateAdresa({
    String? id,
    required String naziv,
    required String grad,
    double? lat,
    double? lng,
  }) async {
    try {
      final normalizedGrad = V3ValidationUtils.normalizeGrad(grad);
      final data = <String, dynamic>{
        if (id != null) 'id': id,
        'naziv': naziv,
        'grad': normalizedGrad,
        'gps_lat': lat,
        'gps_lng': lng,
      };

      await supabase.from('v3_adrese').upsert(data);
    } catch (e) {
      debugPrint('[V3AdresaService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deleteAdresa(String id) async {
    try {
      await supabase.from('v3_adrese').update({'aktivno': false}).eq('id', id);
    } catch (e) {
      debugPrint('[V3AdresaService] Delete error: $e');
      rethrow;
    }
  }

  static Future<void> updateAdresaCoordinates({
    required String id,
    required double lat,
    required double lng,
  }) async {
    try {
      await supabase.from('v3_adrese').update({
        'gps_lat': lat,
        'gps_lng': lng,
      }).eq('id', id);
    } catch (e) {
      debugPrint('[V3AdresaService] updateAdresaCoordinates error: $e');
      rethrow;
    }
  }
}
