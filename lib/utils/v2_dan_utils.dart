/// Centralizovana logika za rad sa danima u sedmici.
/// Sve konverzije dan kratica ↔ ISO datum ↔ puno ime idu kroz ovaj util.
class V2DanUtils {
  V2DanUtils._();

  static const List<String> kratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  static const Map<String, int> _kraticeOffsets = {
    'pon': 0,
    'uto': 1,
    'sre': 2,
    'cet': 3,
    'pet': 4,
    'sub': 5,
    'ned': 6,
  };

  static const List<String> puniNazivi = [
    'Ponedeljak',
    'Utorak',
    'Sreda',
    'Cetvrtak',
    'Petak',
    'Subota',
    'Nedelja',
  ];

  /// Srpski nazivi meseci (index 0 je prazan, index 1=Januar ... 12=Decembar)
  static const List<String> mesecNazivi = [
    '',
    'Januar',
    'Februar',
    'Mart',
    'April',
    'Maj',
    'Jun',
    'Jul',
    'Avgust',
    'Septembar',
    'Oktobar',
    'Novembar',
    'Decembar',
  ];

  /// Broj meseca → srpski naziv (1 → 'Januar')
  static String mesecNaziv(int month) => month >= 1 && month <= 12 ? mesecNazivi[month] : '';

  /// Srpski naziv → broj meseca ('Januar' → 1), 0 ako nije nađen
  static int mesecBroj(String naziv) => mesecNazivi.indexOf(naziv).clamp(0, 12);

  /// DateTime → kratica ('pon', 'uto', ...)
  static String odDatuma(DateTime date) => kratice[date.weekday - 1];

  /// ISO string '2026-03-05' → kratica ('cet')
  static String odIso(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      assert(false, '[V2DanUtils.odIso] Neispravan ISO datum: "$iso"');
      return '';
    }
    return kratice[dt.weekday - 1];
  }

  /// Puno ime → kratica ('Cetvrtak' → 'cet')
  static String odPunogNaziva(String punNaziv) {
    final i = puniNazivi.indexWhere(
      (n) => n.toLowerCase() == punNaziv.toLowerCase(),
    );
    if (i >= 0) return kratice[i];
    // fallback: mapa za alternativne oblike koji nisu u puniNazivi
    // (puniNazivi.indexWhere + toLowerCase vec pokriva standardne oblike)
    final lower = punNaziv.toLowerCase();
    const altMap = {
      'četvrtak': 'cet', // sa č umjesto c
      'nedjelja': 'ned', // ijekavski oblik
    };
    return altMap[lower] ?? lower.substring(0, lower.length >= 3 ? 3 : lower.length);
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
    // Radimo samo sa datumom (bez sata) da izbjegnemo DST greške
    final today = DateTime(now.year, now.month, now.day);
    final int todayWd = today.weekday; // 1=pon ... 7=ned
    final int daysToMonday = (todayWd == 6 || todayWd == 7)
        ? (8 - todayWd) // vikend → sledeći pon
        : (1 - todayWd); // radni dan → ovaj pon
    final monday = today.add(Duration(days: daysToMonday));
    final offset = _kraticeOffsets[kratica.toLowerCase()] ?? 0;
    return monday.add(Duration(days: offset)).toIso8601String().split('T').first;
  }

  /// Proveri da li je dan vikend
  static bool jeVikend(String kratica) => kratica == 'sub' || kratica == 'ned';

  /// Datum ponedeljka tekuće sedmice u formatu 'yyyy-MM-dd'.
  /// Koristi se kao ključ za sedmično opseg v2_vozac_putnik dodjela.
  static String pocetakTekuceSedmice() {
    final now = DateTime.now();
    final ponedeljak = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return '${ponedeljak.year}-${ponedeljak.month.toString().padLeft(2, '0')}-${ponedeljak.day.toString().padLeft(2, '0')}';
  }
}
