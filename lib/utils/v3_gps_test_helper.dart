import 'package:geolocator/geolocator.dart';

/// Test file za verifikaciju V3 GPS tracking funkcionalnosti
class V3GPSTestHelper {
  /// Simuliraj poziciju vozača za testiranje
  static Position createTestPosition({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: heading ?? 0.0,
      headingAccuracy: 0.0,
      speed: speed ?? 0.0,
      speedAccuracy: 0.0,
    );
  }

  /// Test kontinuirane GPS funkcionalnosti
  static Future<void> testKontinuiraniGPS() async {
    print('🧪 [V3GPSTest] Testiram V3 GPS tracking...');

    // Test 1: Provjera dozvola
    try {
      final permission = await Geolocator.checkPermission();
      print('📍 GPS dozvole: $permission');

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        print('⚠️ GPS dozvole nisu omogućene!');
        return;
      }

      // Test 2: Dobijanje pozicije
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('✅ GPS pozicija: lat=${position.latitude}, lng=${position.longitude}');
      print('🧭 Heading: ${position.heading}°, Brzina: ${(position.speed * 3.6).toStringAsFixed(1)} km/h');
    } catch (e) {
      print('❌ GPS test error: $e');
    }
  }

  /// Test V3VozacLokacija update
  static void logGPSUpdate({
    required String vozacId,
    required double lat,
    required double lng,
    double? brzina,
    required String grad,
    required String vreme,
  }) {
    print('📡 [V3GPS] Šaljem poziciju u v3_vozac_lokacije:');
    print('   vozacId: $vozacId');
    print('   lat: $lat, lng: $lng');
    print('   brzina: ${brzina?.toStringAsFixed(1)} km/h');
    print('   grad: $grad, vreme: $vreme');
    print('   timestamp: ${DateTime.now().toIso8601String()}');
  }
}
