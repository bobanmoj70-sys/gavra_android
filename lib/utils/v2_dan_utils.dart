/// Centralizovana logika za rad sa danima u sedmici.
/// Sve konverzije dan kratica ↔ ISO datum ↔ puno ime idu kroz ovaj util.
class V2DanUtils {
  V2DanUtils._();

  static const List<String> kratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  static const List<String> puniNazivi = [
    'Ponedeljak',
    'Utorak',
    'Sreda',
    'Cetvrtak',
    'Petak',
    'Subota',
    'Nedelja',
  ];

  /// DateTime → kratica ('pon', 'uto', ...)
  static String odDatuma(DateTime date) => kratice[date.weekday - 1];

  /// ISO string '2026-03-05' → kratica ('cet')
  static String odIso(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return kratice[dt.weekday - 1];
  }

  /// Puno ime → kratica ('Cetvrtak' → 'cet')
  static String odPunogNaziva(String punNaziv) {
    final i = puniNazivi.indexWhere(
      (n) => n.toLowerCase() == punNaziv.toLowerCase(),
    );
    if (i >= 0) return kratice[i];
    // fallback: prvih 3 slova
    final lower = punNaziv.toLowerCase();
    const map = {
      'ponedeljak': 'pon',
      'utorak': 'uto',
      'sreda': 'sre',
      'cetvrtak': 'cet',
      'četvrtak': 'cet',
      'petak': 'pet',
      'subota': 'sub',
      'nedelja': 'ned',
      'nedjelja': 'ned',
    };
    return map[lower] ?? lower.substring(0, lower.length >= 3 ? 3 : lower.length);
  }

  /// Kratica → puno ime ('cet' → 'Cetvrtak')
  static String puniNaziv(String kratica) {
    final i = kratice.indexOf(kratica.toLowerCase());
    if (i >= 0) return puniNazivi[i];
    return kratica;
  }

  /// Danasnja kratica
  static String danas() => odDatuma(DateTime.now());

  /// ISO datum za selektovani dan u OVOJ sedmici (ponedeljak=baza).
  /// Ako je vikend, koristi sledeću sedmicu.
  static String isoZaDan(String kratica) {
    final now = DateTime.now();
    final int todayWd = now.weekday; // 1=pon ... 7=ned
    final int daysToMonday = (todayWd == 6 || todayWd == 7)
        ? (8 - todayWd) // vikend → sledeći pon
        : (1 - todayWd); // radni dan → ovaj pon
    final monday = now.add(Duration(days: daysToMonday));
    const offsets = {'pon': 0, 'uto': 1, 'sre': 2, 'cet': 3, 'pet': 4, 'sub': 5, 'ned': 6};
    final offset = offsets[kratica.toLowerCase()] ?? 0;
    return monday.add(Duration(days: offset)).toIso8601String().split('T').first;
  }

  /// Proveri da li je dan vikend
  static bool jeVikend(String kratica) => kratica == 'sub' || kratica == 'ned';
}
