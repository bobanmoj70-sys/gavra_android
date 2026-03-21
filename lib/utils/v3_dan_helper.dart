import 'v3_validation_utils.dart';

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

  // ─── naziv/kratica → ISO datum (uvijek tekuća sedmica) ──────────

  /// ISO datum (yyyy-MM-dd) za dati puni naziv dana u tekućoj nedelji.
  /// Prošli dani vraćaju prošli datum — nema skakanja na sledeću nedelju.
  /// EXCEPTION: Za vikend (subota/nedelja) + 'Ponedeljak' → sledeći ponedeljak.
  static String datumIsoZaDanPuni(String danPuni) {
    final idx = _names
        .indexWhere((d) => V3ValidationUtils.normalizeForSearch(d) == V3ValidationUtils.normalizeForSearch(danPuni));
    if (idx == -1) return _todayIso();

    // Za vikend + ponedeljak → sledeći ponedeljak, ne prošli
    final now = DateTime.now();
    final isWeekend = (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);
    final isPonedeljak = (V3ValidationUtils.normalizeForSearch(danPuni) == 'ponedeljak' && idx == 0);

    if (isWeekend && isPonedeljak) {
      final ponedeljak = now.subtract(Duration(days: now.weekday - 1));
      final sledeciPonedeljak = ponedeljak.add(const Duration(days: 7));
      return sledeciPonedeljak.toIso8601String().split('T')[0];
    }

    return _isoZaIdx(idx);
  }

  /// ISO datum (yyyy-MM-dd) za datu kraticu dana (npr. 'pon').
  static String datumIsoZaDanAbbr(String danAbbr) {
    final idx = _abbrs
        .indexWhere((a) => V3ValidationUtils.normalizeForSearch(a) == V3ValidationUtils.normalizeForSearch(danAbbr));
    if (idx == -1) return _todayIso();

    // Za vikend + ponedeljak → sledeći ponedeljak, ne prošli (kao u datumIsoZaDanPuni)
    final now = DateTime.now();
    final isWeekend = (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);
    final isPonedeljak = (V3ValidationUtils.normalizeForSearch(danAbbr) == 'pon' && idx == 0);

    if (isWeekend && isPonedeljak) {
      final ponedeljak = now.subtract(Duration(days: now.weekday - 1));
      final sledeciPonedeljak = ponedeljak.add(const Duration(days: 7));
      return sledeciPonedeljak.toIso8601String().split('T')[0];
    }

    return _isoZaIdx(idx);
  }

  /// DateTime za datu kraticu dana.
  static DateTime datumZaDanAbbr(String danAbbr) => DateTime.parse(datumIsoZaDanAbbr(danAbbr));

  /// ISO datum string (yyyy-MM-dd) za datu kraticu dana direktno.
  static String datumIsoStringZaDanAbbr(String danAbbr) => toIsoDate(datumZaDanAbbr(danAbbr));

  /// Vraća sve ISO datume (yyyy-MM-dd) relevantne sedmice na osnovu vikend logike.
  /// Za vikend → sledeća sedmica, inače → tekuća sedmica.
  static List<String> relevantnaSedmicaIsoLista() {
    final now = DateTime.now();
    final isWeekend = (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);

    final ponedeljak = now.subtract(Duration(days: now.weekday - 1));
    final bazniPonedeljak = isWeekend ? ponedeljak.add(const Duration(days: 7)) : ponedeljak;

    return List.generate(
        7,
        (i) => DateTime(bazniPonedeljak.year, bazniPonedeljak.month, bazniPonedeljak.day + i)
            .toIso8601String()
            .split('T')[0]);
  }

  // ─── Utility metode za datum konverzije ─────────────────────────

  /// Trenutni datum kao ISO string (yyyy-MM-dd).
  static String todayIso() => DateTime.now().toIso8601String().split('T')[0];

  /// Konvertuje DateTime u ISO datum string format (YYYY-MM-DD)
  static String toIsoDate(DateTime datum) {
    return '${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}';
  }

  /// Parse-uje ISO datum string i vraća samo datum deo (YYYY-MM-DD)
  static String parseIsoDatePart(String isoString) {
    return isoString.split('T')[0];
  }

  /// Formatira vreme u HH:MM format
  static String formatVreme(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Formatira datum u DD.MM format
  static String formatDanMesec(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}';
  }

  /// Formatira datetime u DD.MM.YYYY HH:MM format
  static String formatDatumVreme(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Formatira datetime u DD.MM. HH:MM format (kratko)
  static String formatDatumVremeKratko(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}. '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Formatira datum u DD.MM.YYYY format (puni)
  static String formatDatumPuni(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}';
  }

  /// Kreira DateTime samo sa datumom (bez vremena) - samo year/month/day
  static DateTime dateOnly(DateTime datum) {
    return DateTime(datum.year, datum.month, datum.day);
  }

  /// Kreira DateTime sa specifikovanim year, month, day (bez vremena)
  static DateTime dateOnlyFrom(int year, int month, int day) {
    return DateTime(year, month, day);
  }

  /// Formatira datum u dd.MM.yyyy format koristeći DateFormat
  static String formatDatumDdMmYyyy(DateTime datum) {
    return formatDatumPuni(datum); // Koristi već postojeću metodu
  }

  // ─── interno ────────────────────────────────────────────────────

  static String _todayIso() => todayIso(); // Redirectuj na javnu metodu

  static String _isoZaIdx(int targetIdx) {
    final now = DateTime.now();
    final ponedeljak = now.subtract(Duration(days: now.weekday - 1));
    return toIsoDate(DateTime(ponedeljak.year, ponedeljak.month, ponedeljak.day + targetIdx));
  }
}
