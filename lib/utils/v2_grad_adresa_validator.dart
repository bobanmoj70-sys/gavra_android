/// Validator i normalizer za grad/adresa/vreme podatke.
class V2GradAdresaValidator {
  V2GradAdresaValidator._();

  /// Normalizuje format vremena u 'HH:mm'.
  /// Primjeri: '5:00' → '05:00', '15:30' → '15:30', '7' → '07:00', '18:00:00' → '18:00'
  static String normalizeTime(String vreme) {
    if (vreme.isEmpty) return '';

    final trimmed = vreme.trim();

    // HH:mm:ss format (iz baze) → uzmi samo HH:mm
    final withSecondsMatch = RegExp(r'^(\d{1,2}):(\d{2}):\d{2}$').firstMatch(trimmed);
    if (withSecondsMatch != null) {
      final h = int.parse(withSecondsMatch.group(1)!).toString().padLeft(2, '0');
      final m = withSecondsMatch.group(2)!;
      return '$h:$m';
    }

    // Već u ispravnom formatu HH:mm
    final fullMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
    if (fullMatch != null) {
      final h = int.parse(fullMatch.group(1)!).toString().padLeft(2, '0');
      final m = fullMatch.group(2)!;
      return '$h:$m';
    }

    // Samo sati bez minuta
    final hourOnly = RegExp(r'^(\d{1,2})$').firstMatch(trimmed);
    if (hourOnly != null) {
      final h = int.parse(hourOnly.group(1)!).toString().padLeft(2, '0');
      return '$h:00';
    }

    return trimmed;
  }

  /// Normalizuje naziv grada u uppercase kraticu ('BC' ili 'VS')
  static String normalizeGrad(String grad) {
    final upper = grad.trim().toUpperCase();
    if (upper == 'BC' || upper == 'BANJA LUKA' || upper == 'BANJALUKA') return 'BC';
    if (upper == 'VS' || upper == 'ČELINAC' || upper == 'CELINAC') return 'VS';
    return upper;
  }
}
