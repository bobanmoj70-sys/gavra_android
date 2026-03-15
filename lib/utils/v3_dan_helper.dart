/// Helper za konverziju DateTime u naziv/kraticu dana i naziva u datume.
class V3DanHelper {
  V3DanHelper._();

  static const _names = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const _abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  static const _labels = ['Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub', 'Ned'];
  static const _upper = ['PONEDELJAK', 'UTORAK', 'SREDA', 'CETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];

  // ─── DateTime → naziv ───────────────────────────────────────────

  /// Puni naziv dana (npr. 'Ponedeljak').
  static String fullName(DateTime datum) => _names[datum.weekday - 1];

  /// Kratica dana (npr. 'pon').
  static String abbr(DateTime datum) => _abbrs[datum.weekday - 1];

  /// Kratki UI label (npr. 'Pon').
  static String label(DateTime datum) => _labels[datum.weekday - 1];

  /// Puni naziv velikim slovima (npr. 'PONEDELJAK').
  static String fullNameUpper(DateTime datum) => _upper[datum.weekday - 1];

  // ─── Lista dana za UI (dropdown/chip) ───────────────────────────

  /// Svi puni nazivi dana — za dropdown/chip liste.
  static const List<String> dayNames = _names;

  /// Sve kratice dana.
  static const List<String> dayAbbrs = _abbrs;

  // ─── Inicijalizacija tekućeg dana ───────────────────────────────

  /// Danas kao puni naziv; vikend → 'Ponedeljak'.
  static String defaultDay() {
    final w = DateTime.now().weekday;
    if (w == DateTime.saturday || w == DateTime.sunday) return 'Ponedeljak';
    return _names[w - 1];
  }

  // ─── naziv/kratica → ISO datum (tekuća/sljedeća sedmica) ────────

  /// ISO datum (yyyy-MM-dd) za dati puni naziv dana.
  /// Ako je dan prošao u tekućoj sedmici, skače u sljedeću.
  static String datumIsoZaDanPuni(String danPuni) {
    final idx = _names.indexWhere((d) => d.toLowerCase() == danPuni.toLowerCase());
    if (idx == -1) return _todayIso();
    return _isoZaIdx(idx);
  }

  /// ISO datum (yyyy-MM-dd) za datu kraticu dana (npr. 'pon').
  static String datumIsoZaDanAbbr(String danAbbr) {
    final idx = _abbrs.indexWhere((a) => a.toLowerCase() == danAbbr.toLowerCase());
    if (idx == -1) return _todayIso();
    return _isoZaIdx(idx);
  }

  /// DateTime za datu kraticu dana.
  static DateTime datumZaDanAbbr(String danAbbr) => DateTime.parse(datumIsoZaDanAbbr(danAbbr));

  // ─── interno ────────────────────────────────────────────────────

  static String _todayIso() => DateTime.now().toIso8601String().split('T')[0];

  static String _isoZaIdx(int targetIdx) {
    final now = DateTime.now();
    int d = targetIdx - (now.weekday - 1);
    if (d < 0) d += 7;
    return now.add(Duration(days: d)).toIso8601String().split('T')[0];
  }
}
