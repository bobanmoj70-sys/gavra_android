/// Konfiguracija ruta i rasporeda polazaka za BC i VS pravce.
class V2RouteConfig {
  V2RouteConfig._();

  // 🏙️ BELA CRKVA - Zimski raspored
  static const List<String> _bcVremenaZimski = [
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

  // 🌆 VRŠAC - Zimski raspored
  static const List<String> _vsVremenaZimski = [
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:30',
    '17:00',
  ];

  // 🏙️ BELA CRKVA - Letnji raspored (april-septembar)
  static const List<String> _bcVremenaLetnji = [
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

  // 🌆 VRŠAC - Letnji raspored (april-septembar)
  static const List<String> _vsVremenaLetnji = [
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

  // 🏙️ BELA CRKVA - Praznični raspored
  static const List<String> _bcVremenaPraznici = [
    '05:00',
    '06:00',
    '12:00',
    '13:00',
    '15:00',
  ];

  // 🌆 VRŠAC - Praznični raspored
  static const List<String> _vsVremenaPraznici = [
    '06:00',
    '07:00',
    '13:00',
    '14:00',
    '15:30',
  ];

  // ── Sezonski getteri ──
  static List<String> get bcVremenaZimski => List.unmodifiable(_bcVremenaZimski);
  static List<String> get vsVremenaZimski => List.unmodifiable(_vsVremenaZimski);
  static List<String> get bcVremenaLetnji => List.unmodifiable(_bcVremenaLetnji);
  static List<String> get vsVremenaLetnji => List.unmodifiable(_vsVremenaLetnji);
  static List<String> get bcVremenaPraznici => List.unmodifiable(_bcVremenaPraznici);
  static List<String> get vsVremenaPraznici => List.unmodifiable(_vsVremenaPraznici);

  /// Vraća listu vremena na osnovu smjera i TRUBNOG navType
  static List<String> getVremenaByNavType(String grad, [String? season]) {
    // Ako season nije prosleđen, pokušavamo ga dobiti (u v3_home_screen se season dobija iz navBarTypeNotifier)
    final s = season?.toLowerCase() ?? 'zimski';

    if (grad.toUpperCase() == 'BC') {
      if (s == 'letnji') return bcVremenaLetnji;
      if (s == 'praznici') return bcVremenaPraznici;
      return bcVremenaZimski;
    } else {
      if (s == 'letnji') return vsVremenaLetnji;
      if (s == 'praznici') return vsVremenaPraznici;
      return vsVremenaZimski;
    }
  }
}
