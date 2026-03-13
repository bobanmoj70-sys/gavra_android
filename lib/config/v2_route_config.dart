/// Konfiguracija ruta i rasporeda polazaka za BC i VS pravce.
class V2RouteConfig {
  V2RouteConfig._();

  /// Vremena polazaka za BC (Banja Luka → Čelinac pravac)
  static const List<String> _bcVremena = [
    '05:00',
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '15:30',
    '16:00',
    '17:00',
    '18:00',
    '19:00',
    '20:00',
  ];

  /// Vremena polazaka za VS (Čelinac → Banja Luka pravac)
  static const List<String> _vsVremena = [
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '15:30',
    '16:00',
    '17:00',
    '18:00',
    '19:00',
    '20:00',
    '21:00',
  ];

  /// Vraća listu vremena na osnovu smjera ('BC' ili 'VS')
  static List<String> getVremenaByNavType(String navType) {
    switch (navType.toUpperCase()) {
      case 'BC':
        return List.unmodifiable(_bcVremena);
      case 'VS':
        return List.unmodifiable(_vsVremena);
      default:
        return List.unmodifiable([..._bcVremena, ..._vsVremena]..sort());
    }
  }
}
