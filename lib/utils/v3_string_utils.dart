/// Centralni string utilities — normalizacija za pretragu i sortiranje.
/// Podržava srpska latinična slova: č→c, š→s, ž→z, ć→c, đ→d
class V3StringUtils {
  V3StringUtils._();

  static const _diacritics = {
    'č': 'c',
    'š': 's',
    'ž': 'z',
    'ć': 'c',
    'đ': 'd',
    'Č': 'C',
    'Š': 'S',
    'Ž': 'Z',
    'Ć': 'C',
    'Đ': 'D',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ñ': 'N',
  };

  /// Uklanja dijakritike — č→c, š→s, ž→z, ć→c, đ→d
  static String stripDiacritics(String s) {
    if (s.isEmpty) return s;
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_diacritics[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Normalizuje string za pretragu: lowercase + strip dijakritika
  /// Npr. "Šaban Čolović" → "saban colovic"
  /// Korisnik može kucati "sab" ili "šab" i oba će pronaći "Šaban"
  static String forSearch(String s) => stripDiacritics(s.toLowerCase());

  /// Poredi dva stringa za sortiranje uz podršku srpskih slova
  static int compareForSort(String a, String b) => forSearch(a).compareTo(forSearch(b));

  /// Da li [haystack] sadrži [needle] — case-insensitive + bez dijakritika
  static bool containsSearch(String haystack, String needle) {
    if (needle.isEmpty) return true;
    return forSearch(haystack).contains(forSearch(needle));
  }

  // ─── VREME TRIMMING UTILITIES ──────────────────────────────────────────

  /// Trimuje vreme string sa HH:mm:ss na HH:mm format
  /// Primer: "15:30:00" → "15:30", "09:15" → "09:15"
  static String trimTimeToHhMm(String time) {
    final trimmed = time.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})(?::\d{1,2})?$').firstMatch(trimmed);
    if (match != null) {
      final hours = int.tryParse(match.group(1)!);
      final minutes = int.tryParse(match.group(2)!);
      if (hours != null && minutes != null && hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      }
    }
    if (trimmed.length >= 5) {
      return trimmed.substring(0, 5);
    }
    return trimmed;
  }

  /// Normalizuje alternativno vreme za prikaz (null-safe)
  /// Koristi se za z.altVremePre?.toString().substring(0,5) patterne
  static String formatAlternativeTime(Object? altTime) {
    if (altTime == null) return '';
    final timeStr = altTime.toString();
    return trimTimeToHhMm(timeStr);
  }
}
