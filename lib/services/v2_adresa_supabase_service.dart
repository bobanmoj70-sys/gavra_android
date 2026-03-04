import 'dart:async';

import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_adresa.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_unified_geocoding_service.dart';

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

  /// Stream svih adresa — emituje iz rm.adreseCache, nema DB upita.
  /// Reaktivan: osvježava se kad god upsertToCache/removeFromCache promijeni v2_adrese.
  static Stream<List<V2Adresa>> streamSveAdrese() {
    final rm = V2MasterRealtimeManager.instance;
    final controller = StreamController<List<V2Adresa>>.broadcast();
    void emit() {
      if (!controller.isClosed) controller.add(getSveAdrese());
    }

    Future.microtask(emit);

    final cacheSub = rm.onCacheChanged.where((t) => t == 'v2_adrese').listen((_) => emit());
    controller.onCancel = () {
      cacheSub.cancel();
      controller.close();
    };
    return controller.stream;
  }

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

  /// Pronađi adresu po nazivu i gradu — iz rm.adreseCache
  static V2Adresa? findAdresaByNazivAndGrad(String naziv, String grad) {
    final rm = V2MasterRealtimeManager.instance;
    final row = rm.adreseCache.values.where((r) => r['naziv'] == naziv && r['grad'] == grad).firstOrNull;
    if (row == null) return null;
    return V2Adresa.fromMap(row);
  }

  /// Pronalazi postojeću adresu — ne kreira nove.
  /// Nove adrese može dodati samo admin direktno u bazi.
  static Future<V2Adresa?> createOrGetAdresa({
    required String naziv,
    required String grad,
    double? lat,
    double? lng,
  }) async {
    final postojeca = findAdresaByNazivAndGrad(naziv, grad);
    if (postojeca != null) {
      if (!postojeca.hasValidCoordinates && lat != null && lng != null) {
        final updated = await _geocodeAndUpdateAdresa(postojeca, grad);
        if (updated != null) return updated;
      }
      return postojeca;
    }
    return null;
  }

  /// Geocodira adresu i ažurira koordinate u bazi.
  static Future<V2Adresa?> _geocodeAndUpdateAdresa(V2Adresa adresa, String grad) async {
    try {
      final coordsString = await V2UnifiedGeocodingService.getKoordinateZaAdresu(
        grad,
        adresa.naziv,
      );

      if (coordsString != null) {
        final parts = coordsString.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0]);
          final lng = double.tryParse(parts[1]);

          if (lat != null && lng != null) {
            final response = await supabase
                .from('v2_adrese')
                .update({'gps_lat': lat, 'gps_lng': lng})
                .eq('id', adresa.id)
                .select('id, naziv, grad, gps_lat, gps_lng')
                .single();
            return V2Adresa.fromMap(response);
          }
        }
      }
    } catch (e) {
      debugPrint('[AdresaSupabaseService] getAdresaByVozacIGrad error: $e');
    }
    return null;
  }

  /// Ažurira GPS koordinate za postojeću adresu.
  static Future<bool> updateKoordinate(
    String uuid, {
    required double lat,
    required double lng,
  }) async {
    try {
      await supabase.from('v2_adrese').update({'gps_lat': lat, 'gps_lng': lng}).eq('id', uuid);
      return true;
    } catch (e) {
      return false;
    }
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

    await supabase.from('v2_adrese').insert(insertData);

    // v2_adrese nema Realtime — ručno dohvati novi red i upiši u cache
    final row = await supabase
        .from('v2_adrese')
        .select('id, naziv, grad, gps_lat, gps_lng')
        .eq('naziv', naziv)
        .eq('grad', grad)
        .order('id', ascending: false)
        .limit(1)
        .single();
    V2MasterRealtimeManager.instance.upsertToCache('v2_adrese', row);
    return V2Adresa.fromMap(row);
  }

  /// Ažurira adresu, osvježava cache, vraća ažuriranu adresu.
  static Future<V2Adresa> updateAdresa(
    V2Adresa adresa, {
    required String naziv,
    required String grad,
    double? lat,
    double? lng,
  }) async {
    final updateData = <String, dynamic>{
      'naziv': naziv,
      'grad': grad,
    };
    if (lat != null) updateData['gps_lat'] = lat;
    if (lng != null) updateData['gps_lng'] = lng;

    await supabase.from('v2_adrese').update(updateData).eq('id', adresa.id);

    final updatedRow = <String, dynamic>{
      'id': adresa.id,
      ...updateData,
    };
    V2MasterRealtimeManager.instance.upsertToCache('v2_adrese', updatedRow);
    return V2Adresa.fromMap(updatedRow);
  }

  /// Briše adresu i uklanja je iz cache-a.
  static Future<void> deleteAdresa(V2Adresa adresa) async {
    await supabase.from('v2_adrese').delete().eq('id', adresa.id);
    V2MasterRealtimeManager.instance.removeFromCache('v2_adrese', adresa.id);
  }
}
