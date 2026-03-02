/// Centralizovani servis za upravljanje admin privilegijama.
class AdminSecurityService {
  AdminSecurityService._();

  static const Set<String> _adminUsers = {
    'Bojan',
  };

  /// Nemodifiable lista admin korisnika. Koristiti umesto lokalnih hardcode listi.
  static List<String> get adminUsers => List.unmodifiable(_adminUsers);

  /// Proveri da li je vozač admin.
  static bool isAdmin(String? driverName) {
    if (driverName == null || driverName.isEmpty) return false;
    return _adminUsers.contains(driverName);
  }

  /// Filtrira pazar podatke na osnovu privilegija vozača.
  static Map<String, double> filterPazarByPrivileges(
    String currentDriver,
    Map<String, double> pazarData,
  ) {
    if (currentDriver.isEmpty) {
      return {};
    }

    // Admin vidi sve vozače
    if (isAdmin(currentDriver)) {
      return Map.from(pazarData);
    }

    // Vozač vidi samo svoj pazar
    return {
      if (pazarData.containsKey(currentDriver)) currentDriver: pazarData[currentDriver]!,
    };
  }

  /// Vraća listu vozača vidljivih trenutnom korisniku na osnovu privilegija.
  static List<String> getVisibleDrivers(
    String currentDriver,
    List<String> allDrivers,
  ) {
    if (currentDriver.isEmpty) {
      return [];
    }

    // Admin vidi sve vozače
    if (isAdmin(currentDriver)) {
      return List.from(allDrivers);
    }

    // Vozač vidi samo sebe
    return allDrivers.where((driver) => driver == currentDriver).toList();
  }
}
