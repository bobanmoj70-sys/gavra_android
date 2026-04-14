/// Centralizovane validation i parsing utility funkcije.
/// Eliminiše duplikate string/number validacije kroz aplikaciju.
class V3ValidationUtils {
  V3ValidationUtils._();

  // ─── GRAD NORMALIZACIJA ──────────────────────────────────────────────

  /// Normalizuje naziv grada u uppercase kraticu ('BC' ili 'VS')
  static String normalizeGrad(String grad) {
    final upper = grad.trim().toUpperCase();
    if (upper == 'BC' || upper == 'BANJA LUKA' || upper == 'BANJALUKA') return 'BC';
    if (upper == 'VS' || upper == 'ČELINAC' || upper == 'CELINAC') return 'VS';
    return upper;
  }

  /// Proverava da li je grad valjan (BC ili VS)
  static bool isValidGrad(String grad) {
    final normalized = normalizeGrad(grad);
    return normalized == 'BC' || normalized == 'VS';
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
