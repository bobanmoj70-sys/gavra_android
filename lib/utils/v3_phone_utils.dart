/// Centralna normalizacija telefonskih brojeva.
/// Sve metode konvertuju u format +381XXXXXXXXX
class V3PhoneUtils {
  V3PhoneUtils._();

  /// Normalizuje broj u +381 format.
  /// Prihvata: 0641234567, +381641234567, 381641234567, 064 123 4567, itd.
  /// Vraća: +381641234567
  static String normalize(String phone) {
    // Ukloni razmake, crtice, zagrade
    var p = phone.replaceAll(RegExp(r'[\s\-\(\).]'), '').trim();
    if (p.isEmpty) return p;

    if (p.startsWith('+381')) return p; // već +381
    if (p.startsWith('00381')) return '+381${p.substring(5)}'; // 00381...
    if (p.startsWith('381')) return '+${p}'; // 381 bez +
    if (p.startsWith('0')) return '+381${p.substring(1)}'; // 06x / 07x
    return p; // nepoznat format — vrati kakav jeste
  }

  /// Normalizuje ili vraća null ako je prazan string
  static String? normalizeOrNull(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    return normalize(phone.trim());
  }

  /// Validacija — mora biti +381 + 8 ili 9 cifara
  static bool isValid(String phone) {
    final n = normalize(phone);
    return RegExp(r'^\+381[0-9]{8,9}$').hasMatch(n);
  }
}
