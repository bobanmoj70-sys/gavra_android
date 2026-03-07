/// Route Configuration
///
/// Vremena polazaka za različite rute i sezone.
/// Koristi se u kapacitet servisu i navigacionim bar-ovima.
library;

import '../globals.dart';

class V2RouteConfig {
  V2RouteConfig._();

  // BELA CRKVA - Zimski raspored (oktobar-mart)
  static const List<String> bcVremenaZimski = [
    '05:00',
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:30',
    '18:00',
  ];

  // BELA CRKVA - Letnji raspored (april-septembar)
  static const List<String> bcVremenaLetnji = [
    '05:00',
    '06:00',
    '07:00',
    '08:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:30',
    '18:00',
  ];

  // BELA CRKVA - Praznički raspored
  static const List<String> bcVremenaPraznici = [
    '05:00',
    '06:00',
    '12:00',
    '13:00',
    '15:00',
  ];

  // VRŠAC - Zimski raspored (oktobar-mart)
  static const List<String> vsVremenaZimski = [
    '06:00',
    '07:00',
    '08:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:30',
    '17:00',
    '19:00',
  ];

  // VRŠAC - Letnji raspored (april-septembar)
  static const List<String> vsVremenaLetnji = [
    '06:00',
    '07:00',
    '08:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:30',
    '18:00',
  ];

  // VRŠAC - Praznički raspored
  static const List<String> vsVremenaPraznici = [
    '06:00',
    '07:00',
    '13:00',
    '14:00',
    '15:30',
  ];

  // GEOGRAFSKE KOORDINATE
  static const double belaCrkvaLat = 44.8989;
  static const double belaCrkvaLng = 21.4181;
  static const double vrsacLat = 45.1167;
  static const double vrsacLng = 21.3036;

  // OSRM (OpenStreetMap Routing Machine) KONFIGURACIJA
  static const String osrmBaseUrl = 'https://router.project-osrm.org';
  static const int osrmMaxRetries = 3;
  static const Duration osrmTimeout = Duration(seconds: 30);

  // GEOCODING KONFIGURACIJA
  static const Duration nominatimBatchDelay = Duration(milliseconds: 1000);

  /// ⏱ Dobija delay za retry pokušaj (exponential backoff)
  static Duration getRetryDelay(int attempt) {
    // 1s, 2s, 4s, 8s... max 30s
    final clamped = attempt.clamp(1, 5); // 2^(5-1) = 16s, 2^4 = 16s
    return Duration(seconds: 1 << (clamped - 1));
  }

  /// Vraća listu vremena polazaka za grad i sezonu
  static List<String> getVremenaPolazaka({
    required String grad,
    required String sezona,
  }) {
    final isBc = grad == 'BC';
    if (sezona == 'praznici') {
      return isBc ? bcVremenaPraznici : vsVremenaPraznici;
    } else if (sezona == 'zimski') {
      return isBc ? bcVremenaZimski : vsVremenaZimski;
    } else {
      return isBc ? bcVremenaLetnji : vsVremenaLetnji;
    }
  }

  /// Vraća listu vremena polazaka za grad prema aktivnoj sezoni (čita navBarTypeNotifier).
  /// Grad: 'BC' ili 'VS'
  static List<String> getVremenaByNavType(String grad) {
    return getVremenaPolazaka(
      grad: grad,
      sezona: navBarTypeNotifier.value,
    );
  }
}
