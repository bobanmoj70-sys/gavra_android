import 'v2_grad_adresa_validator.dart';

enum V2RegistrovaniStatus { active, canceled, vacation, unknown }

class V2RegistrovaniHelpers {
  V2RegistrovaniHelpers._();

  // Kompajlirano jednom - koristi se u isActiveFromMap
  static final RegExp _isoDateRegExp = RegExp(r'\d{4}-\d{2}-\d{2}');

  // Status mapa - static const da se ne kreira iznova pri svakom pozivu
  static const Map<String, V2RegistrovaniStatus> _statusMap = {
    'otkazano': V2RegistrovaniStatus.canceled,
    'otkazan': V2RegistrovaniStatus.canceled,
    'otkazana': V2RegistrovaniStatus.canceled,
    'otkaz': V2RegistrovaniStatus.canceled,
    'godišnji': V2RegistrovaniStatus.vacation,
    'godisnji': V2RegistrovaniStatus.vacation,
    'godisnji_odmor': V2RegistrovaniStatus.vacation,
    'bolovanje': V2RegistrovaniStatus.vacation,
    'aktivan': V2RegistrovaniStatus.active,
    'active': V2RegistrovaniStatus.active,
    'placeno': V2RegistrovaniStatus.active,
  };

  // Normalize time using V2GradAdresaValidator for consistency across the app
  static String? normalizeTime(String? raw) {
    return V2GradAdresaValidator.normalizeTime(raw);
  }

  // SSOT: Polasci po danu se sada čuvaju ISKLJUČIVO u v2_polasci tabeli.
  // Ove metode su zadržane radi kompatibilnosti interfejsa.

  // Get polazak for a day and place ('bc' or 'vs') from v2_polasci
  // NAPOMENA: [dayKratica] i [isWinter] su zadrzani radi kompatibilnosti interfejsa,
  // ali se trenutno ne koriste (filtriranje po danu je preseljeno na pozivajuci sloj).
  static String? getPolazakForDay(
    Map<String, dynamic> rawMap,
    String dayKratica, // ignore: avoid_unused_parameters
    String place, {
    bool isWinter = false, // ignore: avoid_unused_parameters
  }) {
    if (rawMap.containsKey('zeljeno_vreme') && rawMap['zeljeno_vreme'] != null) {
      final gradRaw = rawMap['grad']?.toString();
      final matches = gradRaw?.toUpperCase() == place.toUpperCase();

      if (matches) {
        return normalizeTime(rawMap['zeljeno_vreme'].toString());
      }
    }
    return null;
  }

  // Is active (soft delete handling)
  static bool isActiveFromMap(Map<String, dynamic>? m) {
    if (m == null) return true;
    final obrisan = m['obrisan'] ?? m['deleted'] ?? m['deleted_at'];
    if (obrisan != null) {
      if (obrisan is bool) return !obrisan;
      final s = obrisan.toString().toLowerCase();
      if (s == 'true' || s == '1' || s == 't') return false;
      if (s.isNotEmpty && _isoDateRegExp.hasMatch(s)) {
        return false;
      }
    }

    final aktivan = m['aktivan'];
    if (aktivan != null) {
      if (aktivan is bool) return aktivan;
      final s = aktivan.toString().toLowerCase();
      if (s == 'false' || s == '0' || s == 'f') return false;
      return true;
    }

    return true;
  }

  // Status converter
  static V2RegistrovaniStatus statusFromString(String? raw) {
    if (raw == null) return V2RegistrovaniStatus.unknown;
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return V2RegistrovaniStatus.unknown;
    // Egzaktan match - contains() bi dao false positive za stringove poput 'bez_otkazivanja'
    return _statusMap[s] ?? V2RegistrovaniStatus.unknown;
  }
}
