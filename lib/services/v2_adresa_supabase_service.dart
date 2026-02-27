import 'dart:async';

import '../globals.dart';
import '../models/adresa.dart';
import 'geocoding_service.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za rad sa normalizovanim adresama iz Supabase tabele
/// 🎯 KORISTI UUID REFERENCE umesto TEXT polja
class V2AdresaSupabaseService {
  static StreamSubscription? _adreseSubscription;
  static final StreamController<List<Adresa>> _adreseController = StreamController<List<Adresa>>.broadcast();
  static List<Adresa> _cachedAdrese = []; // 🚀 Cache za brže učitavanje

  /// Dobija adresu po UUID-u
  static Future<Adresa?> getAdresaByUuid(String uuid) async {
    try {
      final response =
          await supabase.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng').eq('id', uuid).single();

      final adresa = Adresa.fromMap(response);
      return adresa;
    } catch (e) {
      return null;
    }
  }

  /// Dobija naziv adrese po UUID-u (optimizovano za UI)
  static Future<String?> getNazivAdreseByUuid(String? uuid) async {
    if (uuid == null || uuid.isEmpty) return null;

    final adresa = await getAdresaByUuid(uuid);
    return adresa?.naziv;
  }

  /// Dobija sve adrese za određeni grad
  static Future<List<Adresa>> getAdreseZaGrad(String grad) async {
    try {
      final response =
          await supabase.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng').eq('grad', grad).order('naziv');

      return response.map((json) => Adresa.fromMap(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Dobija sve adrese
  static Future<List<Adresa>> getSveAdrese() async {
    try {
      final response =
          await supabase.from('v2_adrese').select('id, naziv, grad, gps_lat, gps_lng').order('grad').order('naziv');
      return response.map((json) => Adresa.fromMap(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 🛰️ REALTIME STREAM: Prati promene u tabeli 'v2_adrese'
  static Stream<List<Adresa>> streamSveAdrese() {
    if (_adreseSubscription == null) {
      // Učitaj prvi put (ako nema cache)
      if (_cachedAdrese.isEmpty) {
        _refreshAdreseStream();
      } else {
        // Emituj iz cache-a odmah
        if (!_adreseController.isClosed) {
          _adreseController.add(_cachedAdrese);
        }
      }

      _adreseSubscription = V2MasterRealtimeManager.instance.subscribe('v2_adrese').listen((payload) {
        _refreshAdreseStream(); // Ažuriraj samo na promenu
      });
    }
    return _adreseController.stream;
  }

  static void _refreshAdreseStream() async {
    final adrese = await getSveAdrese();
    _cachedAdrese = adrese; // 💾 Čuva se u memoriji
    if (!_adreseController.isClosed) {
      _adreseController.add(adrese);
    }
  }

  /// Pronađi adresu po nazivu i gradu
  static Future<Adresa?> findAdresaByNazivAndGrad(String naziv, String grad) async {
    try {
      final response = await supabase
          .from('v2_adrese')
          .select('id, naziv, grad, ulica, broj, gps_lat, gps_lng')
          .eq('naziv', naziv)
          .eq('grad', grad)
          .maybeSingle();
      if (response != null) {
        final adresa = Adresa.fromMap(response);
        return adresa;
      }
      return null;
    } catch (e) {
      return null;
    }
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
    try {
      final postojeca = await findAdresaByNazivAndGrad(naziv, grad);
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
    } catch (_) {
      // 🔇 Ignore
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
                .select('id, naziv, grad, ulica, broj, gps_lat, gps_lng')
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

  /// Batch učitavanje adresa
  static Future<Map<String, Adresa>> getAdreseByUuids(List<String> uuids) async {
    final Map<String, Adresa> result = {};

    for (final uuid in uuids) {
      final adresa = await getAdresaByUuid(uuid);
      if (adresa != null) {
        result[uuid] = adresa;
      }
    }

    return result;
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

  /// 🧹 Čisti realtime subscription
  static void dispose() {
    _adreseSubscription?.cancel();
    _adreseSubscription = null;
    _adreseController.close();
  }
}
