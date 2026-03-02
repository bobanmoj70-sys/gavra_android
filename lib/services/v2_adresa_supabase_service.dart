import 'dart:async';

import '../globals.dart';
import '../models/v2_adresa.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_geocoding_service.dart';

/// Servis za rad sa normalizovanim adresama iz Supabase tabele.
/// Read metode čitaju iz rm.adreseCache — nema DB upita.
class V2AdresaSupabaseService {
  /// Dobija adresu po UUID-u — iz rm.adreseCache
  static Adresa? getAdresaByUuid(String uuid) {
    final row = V2MasterRealtimeManager.instance.adreseCache[uuid];
    if (row == null) return null;
    return Adresa.fromMap(row);
  }

  /// Dobija naziv adrese po UUID-u
  static String? getNazivAdreseByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    return V2MasterRealtimeManager.instance.adreseCache[uuid]?['naziv'] as String?;
  }

  /// Dobija sve adrese za određeni grad — iz rm.adreseCache
  static List<Adresa> getAdreseZaGrad(String grad) {
    final rm = V2MasterRealtimeManager.instance;
    return rm.adreseCache.values.where((r) => r['grad'] == grad).map((r) => Adresa.fromMap(r)).toList()
      ..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  /// Dobija sve adrese — iz rm.adreseCache
  static List<Adresa> getSveAdrese() {
    final rm = V2MasterRealtimeManager.instance;
    return rm.adreseCache.values.map((r) => Adresa.fromMap(r)).toList()
      ..sort((a, b) {
        final g = (a.grad ?? '').compareTo(b.grad ?? '');
        return g != 0 ? g : a.naziv.compareTo(b.naziv);
      });
  }

  /// Stream svih adresa — emituje iz rm.adreseCache, nema DB upita
  static Stream<List<Adresa>> streamSveAdrese() {
    final controller = StreamController<List<Adresa>>.broadcast();
    final rm = V2MasterRealtimeManager.instance;

    void emit() {
      if (!controller.isClosed) controller.add(getSveAdrese());
    }

    emit();
    final sub = rm.subscribe('v2_adrese').listen((_) => emit());
    controller.onCancel = () {
      sub.cancel();
      rm.unsubscribe('v2_adrese');
    };
    return controller.stream;
  }

  /// Batch učitavanje adresa po UUID-ovima — iz rm.adreseCache
  static Map<String, Adresa> getAdreseByUuids(List<String> uuids) {
    final rm = V2MasterRealtimeManager.instance;
    final result = <String, Adresa>{};
    for (final uuid in uuids) {
      final row = rm.adreseCache[uuid];
      if (row != null) result[uuid] = Adresa.fromMap(row);
    }
    return result;
  }

  /// Pronađi adresu po nazivu i gradu — iz rm.adreseCache
  static Adresa? findAdresaByNazivAndGrad(String naziv, String grad) {
    final rm = V2MasterRealtimeManager.instance;
    final row = rm.adreseCache.values.where((r) => r['naziv'] == naziv && r['grad'] == grad).firstOrNull;
    if (row == null) return null;
    return Adresa.fromMap(row);
  }

  /// Pronalazi postojeću adresu - NE KREIRA NOVE
  /// 🚫 ZAKLJUČANO: Nove adrese može dodati samo admin direktno u bazi
  static Future<Adresa?> createOrGetAdresa({
    required String naziv,
    required String grad,
    String? ulica,
    String? broj,
    double? lat,
    double? lng,
  }) async {
    // 🔒 Samo pronađi postojeću adresu - NE KREIRAJ NOVU
    final postojeca = findAdresaByNazivAndGrad(naziv, grad);
    if (postojeca != null) {
      // Ako postojeća adresa NEMA koordinate ali imamo ih, ažuriraj
      if (!postojeca.hasValidCoordinates && lat != null && lng != null) {
        final updatedAdresa = await _geocodeAndUpdateAdresa(postojeca, grad);
        if (updatedAdresa != null) {
          return updatedAdresa;
        }
      }
      return postojeca;
    }

    // 🚫 NE KREIRAJ NOVU ADRESU - vrati null
    // Nove adrese može dodati samo admin direktno u Supabase
    return null;
  }

  /// 🌍 Geocodira adresu i ažurira u bazi
  static Future<Adresa?> _geocodeAndUpdateAdresa(Adresa adresa, String grad) async {
    try {
      final coordsString = await GeocodingService.getKoordinateZaAdresu(
        grad,
        adresa.naziv,
      );

      if (coordsString != null) {
        final parts = coordsString.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0]);
          final lng = double.tryParse(parts[1]);

          if (lat != null && lng != null) {
            // Ažuriraj u bazi
            final response = await supabase
                .from('v2_adrese')
                .update({
                  'gps_lat': lat, // Direct column
                  'gps_lng': lng, // Direct column
                })
                .eq('id', adresa.id)
                .select('id, naziv, grad, gps_lat, gps_lng')
                .single();

            final updatedAdresa = Adresa.fromMap(response);
            return updatedAdresa;
          }
        }
      }
    } catch (_) {
      // 🔇 Ignore
    }
    return null;
  }

  /// 🎯 NOVO: Ažuriraj koordinate za postojeću adresu
  /// Koristi se kada Nominatim pronađe koordinate za adresu koja ih nema u bazi
  static Future<bool> updateKoordinate(
    String uuid, {
    required double lat,
    required double lng,
  }) async {
    try {
      await supabase.from('v2_adrese').update({
        'gps_lat': lat, // Direct column
        'gps_lng': lng, // Direct column
      }).eq('id', uuid);

      return true;
    } catch (e) {
      return false;
    }
  }
}
