/// 🔐 ADMIN SECURITY SERVICE
/// Centralizovani servis za upravljanje admin privilegijama
/// Zamenjuje hard-coded admin logiku sa sigurnijim pristupom
class AdminSecurityService {
  // 🔐 SECURE ADMIN LIST - trebalo bi da bude iz backend-a ili encrypted config
  static const Set<String> _adminUsers = {
    'Bojan',
  };

  /// Javna lista admin korisnika (nemodifiable). Koristiti umesto lokalnih hardcode listi.
  static List<String> get adminUsers => _adminUsers.toList();

  /// 🔍 Proveri da li je vozač admin
  static bool isAdmin(String? driverName) {
    if (driverName == null || driverName.isEmpty) {
      return false;
    }

    final isAdminUser = _adminUsers.contains(driverName);
    return isAdminUser;
  }

  /// 🔒 Filtriraj pazar podatke na osnovu privilegija
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

  /// 🎯 Dobij vozače koji treba da se prikažu na osnovu privilegija
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
