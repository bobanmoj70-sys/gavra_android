import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_adresa.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za rad sa normalizovanim adresama iz Supabase tabele.
/// Read metode čitaju iz rm.adreseCache — nema DB upita.
class V2AdresaSupabaseService {
  V2AdresaSupabaseService._();

  /// Dobija adresu po UUID-u — iz rm.adreseCache
  static V2Adresa? getAdresaByUuid(String uuid) {
    final row = V2MasterRealtimeManager.instance.adreseCache[uuid];
    if (row == null) return null;
    return V2Adresa.fromMap(row);
  }

  /// Dobija naziv adrese po UUID-u
  static String? getNazivAdreseByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    return V2MasterRealtimeManager.instance.adreseCache[uuid]?['naziv'] as String?;
  }

  /// Dobija sve adrese za određeni grad — iz rm.adreseCache
  static List<V2Adresa> getAdreseZaGrad(String grad) {
    final rm = V2MasterRealtimeManager.instance;
    return rm.adreseCache.values.where((r) => r['grad'] == grad).map((r) => V2Adresa.fromMap(r)).toList()
      ..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  /// Dobija sve adrese — iz rm.adreseCache
  static List<V2Adresa> getSveAdrese() {
    final rm = V2MasterRealtimeManager.instance;
    return rm.adreseCache.values.map((r) => V2Adresa.fromMap(r)).toList()
      ..sort((a, b) {
        final g = (a.grad ?? '').compareTo(b.grad ?? '');
        return g != 0 ? g : a.naziv.compareTo(b.naziv);
      });
  }

  static Stream<List<V2Adresa>> streamSveAdrese() =>
      V2MasterRealtimeManager.instance.v2StreamFromCache(tables: ['v2_adrese'], build: getSveAdrese);

  /// Batch učitavanje adresa po UUID-ovima — iz rm.adreseCache
  static Map<String, V2Adresa> getAdreseByUuids(List<String> uuids) {
    final rm = V2MasterRealtimeManager.instance;
    final result = <String, V2Adresa>{};
    for (final uuid in uuids) {
      final row = rm.adreseCache[uuid];
      if (row != null) result[uuid] = V2Adresa.fromMap(row);
    }
    return result;
  }

  /// Dodaje novu adresu, osvježava cache, vraća kreiranu adresu.
  static Future<V2Adresa> addAdresa({
    required String naziv,
    required String grad,
    double? lat,
    double? lng,
  }) async {
    final insertData = <String, dynamic>{
      'naziv': naziv,
      'grad': grad,
    };
    if (lat != null) insertData['gps_lat'] = lat;
    if (lng != null) insertData['gps_lng'] = lng;

    try {
      final row = await supabase
          .from('v2_adrese')
          .insert(insertData)
          .select('id, naziv, grad, gps_lat, gps_lng, created_at, updated_at')
          .single();
      V2MasterRealtimeManager.instance.v2UpsertToCache('v2_adrese', row);
      return V2Adresa.fromMap(row);
    } catch (e) {
      debugPrint('[V2AdresaSupabaseService] addAdresa greška: $e');
      rethrow;
    }
  }

  /// Ažurira adresu, osvježava cache, vraća ažuriranu adresu.
  static Future<V2Adresa> updateAdresa(
    V2Adresa adresa, {
    required String naziv,
    required String grad,
    double? lat,
    double? lng,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final updateData = <String, dynamic>{
      'naziv': naziv,
      'grad': grad,
      'updated_at': now,
    };
    if (lat != null) updateData['gps_lat'] = lat;
    if (lng != null) updateData['gps_lng'] = lng;

    try {
      await supabase.from('v2_adrese').update(updateData).eq('id', adresa.id);
    } catch (e) {
      debugPrint('[V2AdresaSupabaseService] updateAdresa greška: $e');
      rethrow;
    }

    // Spreada stari cache red pa override sa novim — ne gube se gps_lat/gps_lng ni created_at
    final rm = V2MasterRealtimeManager.instance;
    final existing = rm.adreseCache[adresa.id] ?? {};
    final updatedRow = <String, dynamic>{
      ...existing,
      ...updateData,
      'id': adresa.id,
    };
    rm.v2UpsertToCache('v2_adrese', updatedRow);
    return V2Adresa.fromMap(updatedRow);
  }

  /// Briše adresu i uklanja je iz cache-a.
  static Future<void> deleteAdresa(V2Adresa adresa) async {
    try {
      await supabase.from('v2_adrese').delete().eq('id', adresa.id);
      V2MasterRealtimeManager.instance.v2RemoveFromCache('v2_adrese', adresa.id);
    } catch (e) {
      debugPrint('[V2AdresaSupabaseService] deleteAdresa greška: $e');
      rethrow;
    }
  }
}
