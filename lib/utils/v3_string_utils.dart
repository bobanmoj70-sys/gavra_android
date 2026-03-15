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
  };

  /// Uklanja dijakritike — č→c, š→s, ž→z, ć→c, đ→d
  static String stripDiacritics(String s) => s.splitMapJoin('', onNonMatch: (ch) => _diacritics[ch] ?? ch);

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
}
