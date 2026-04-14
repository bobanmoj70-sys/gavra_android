import 'v3_string_utils.dart';

/// Centralizovane validation i parsing utility funkcije.
/// Eliminiše duplikate string/number validacije kroz aplikaciju.
class V3ValidationUtils {
  V3ValidationUtils._();

  // ─── GRAD NORMALIZACIJA ──────────────────────────────────────────────

  /// Normalizuje naziv grada u uppercase kraticu ('BC' ili 'VS')
  static String normalizeGrad(String grad) {
    final upper = grad.trim().toUpperCase();
    if (upper == 'BC' || upper == 'BANJA LUKA' || upper == 'BANJALUKA')
      return 'BC';
    if (upper == 'VS' || upper == 'ČELINAC' || upper == 'CELINAC') return 'VS';
    return upper;
  }

  /// Proverava da li je grad valjan (BC ili VS)
  static bool isValidGrad(String grad) {
    final normalized = normalizeGrad(grad);
    return normalized == 'BC' || normalized == 'VS';
  }

  // ─── TELEFON NORMALIZACIJA ────────────────────────────────────────────

  /// Normalizuje telefon broj - uklanja razmake, crtice, zagrade
  static String normalizePhone(String phone) {
    var p = phone.replaceAll(RegExp(r'[\s\-\(\).]'), '').trim();

    // Standardizuj srpske prefikse
    if (p.startsWith('00381')) p = p.substring(5);
    if (p.startsWith('+381')) p = p.substring(4);
    if (p.startsWith('381')) p = p.substring(3);
    if (p.startsWith('0')) p = p.substring(1);

    return p;
  }

  /// Vraća normalizovan telefon ili null ako je prazan
  static String? normalizePhoneOrNull(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final normalized = normalizePhone(phone.trim());
    return normalized.isEmpty ? null : normalized;
  }

  // ─── VREME NORMALIZACIJA ──────────────────────────────────────────────

  /// Normalizuje vreme string u HH:mm format
  static String normalizeVreme(String vreme) {
    final trimmed = vreme.trim();

    // HH:mm:ss → HH:mm
    final withSecondsMatch =
        RegExp(r'^(\d{1,2}):(\d{2}):\d{2}$').firstMatch(trimmed);
    if (withSecondsMatch != null) {
      final h = int.parse(withSecondsMatch.group(1)!);
      final m = int.parse(withSecondsMatch.group(2)!);
      if (!_isValidHourMinute(h, m)) return trimmed;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    // Već u ispravnom formatu HH:mm
    final fullMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
    if (fullMatch != null) {
      final h = int.parse(fullMatch.group(1)!);
      final m = int.parse(fullMatch.group(2)!);
      if (!_isValidHourMinute(h, m)) return trimmed;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    // Samo sati bez minuta
    final hourOnly = RegExp(r'^(\d{1,2})$').firstMatch(trimmed);
    if (hourOnly != null) {
      final h = int.parse(hourOnly.group(1)!);
      if (h < 0 || h > 23) return trimmed;
      return '${h.toString().padLeft(2, '0')}:00';
    }

    return trimmed;
  }

  static bool _isValidHourMinute(int hour, int minute) {
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  }

  // ─── NUMBER PARSING ───────────────────────────────────────────────────

  /// Sigurno parsira int sa default vrednošću
  static int safeParseInt(String? value, {int defaultValue = 0}) {
    if (value == null || value.trim().isEmpty) return defaultValue;
    return int.tryParse(value.trim()) ?? defaultValue;
  }

  /// Sigurno parsira double sa default vrednošću
  static double safeParseDouble(String? value, {double defaultValue = 0.0}) {
    if (value == null || value.trim().isEmpty) return defaultValue;
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? defaultValue;
  }

  // ─── STRING CLEANING ──────────────────────────────────────────────────

  /// Standardno čišćenje stringa - trim + handle null
  static String cleanString(String? input) {
    if (input == null) return '';
    return input.trim();
  }

  /// Čisti string sa default vrednošću ako je prazan
  static String cleanStringWithDefault(String? input, String defaultValue) {
    final clean = cleanString(input);
    return clean.isEmpty ? defaultValue : clean;
  }

  /// Normalizuje string za search (lowercase + bez dijakritika)
  static String normalizeForSearch(String input) {
    return V3StringUtils.forSearch(input.trim());
  }

  // ─── VALIDATION CHECKS ────────────────────────────────────────────────

  /// Proverava da li string nije null ili prazan
  static bool isNotEmpty(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  /// Proverava da li je string prazan ili null
  static bool isEmpty(String? value) {
    return !isNotEmpty(value);
  }

  /// Proverava da li je number valjan (nije null i > 0)
  static bool isValidNumber(num? value) {
    return value != null && value > 0;
  }

  /// Proverava da li je ID string valjan
  static bool isValidId(String? id) {
    return isNotEmpty(id);
  }
}
