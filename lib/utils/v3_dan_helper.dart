/// Helper za konverziju DateTime u naziv/kraticu dana i naziva u datume.
class V3DanHelper {
  V3DanHelper._();

  static const int _isoDateLength = 10;

  static const _names = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const _abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  static const _labels = ['Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub', 'Ned'];
  static const _upper = ['PONEDELJAK', 'UTORAK', 'SREDA', 'CETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];

  static String _normalizeDayToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('č', 'c')
        .replaceAll('ć', 'c')
        .replaceAll('š', 's')
        .replaceAll('ž', 'z')
        .replaceAll('đ', 'dj');
  }

  static int _indexForFullDayName(String danPuni) {
    final normalized = _normalizeDayToken(danPuni);
    for (var i = 0; i < _names.length; i++) {
      if (_normalizeDayToken(_names[i]) == normalized) return i;
    }
    return -1;
  }

  static int _indexForDayAbbr(String danAbbr) {
    final normalized = _normalizeDayToken(danAbbr);
    if (normalized.startsWith('pon')) return 0;
    if (normalized.startsWith('uto')) return 1;
    if (normalized.startsWith('sre')) return 2;
    if (normalized.startsWith('cet')) return 3;
    if (normalized.startsWith('pet')) return 4;
    if (normalized.startsWith('sub')) return 5;
    if (normalized.startsWith('ned')) return 6;
    return -1;
  }

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

  /// Danas kao puni naziv.
  static String defaultDay() {
    final w = DateTime.now().weekday;
    return _names[w - 1];
  }

  // ─── Aktivna sedmica za zakazivanje ────────────────────────────

  /// Anchor datum za aktivnu sedmicu zakazivanja.
  ///
  /// Pravilo:
  /// - Ponedeljak–petak: aktivna je tekuća sedmica.
  /// - Subota od 03:00: aktivna je sledeća sedmica.
  /// - Nedelja: aktivna je sledeća sedmica.
  static DateTime schedulingWeekAnchor({DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = dateOnly(current);
    final saturdayUnlock = DateTime(base.year, base.month, base.day, 3, 0);
    final saturdayAfterUnlock = base.weekday == DateTime.saturday && !current.isBefore(saturdayUnlock);

    if (base.weekday == DateTime.sunday || saturdayAfterUnlock) {
      return dateOnly(base.add(const Duration(days: 7)));
    }
    return base;
  }

  /// Sledeći trenutak kada se otvara zakazivanje za novu sedmicu (subota 03:00).
  static DateTime nextSchedulingUnlock({DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = dateOnly(current);
    final saturday = base.add(Duration(days: DateTime.saturday - base.weekday));
    final unlockThisWeek = DateTime(saturday.year, saturday.month, saturday.day, 3, 0);
    if (current.isBefore(unlockThisWeek)) return unlockThisWeek;
    final nextSaturday = saturday.add(const Duration(days: 7));
    return DateTime(nextSaturday.year, nextSaturday.month, nextSaturday.day, 3, 0);
  }

  /// Da li je datum unutar aktivne sedmice zakazivanja.
  static bool isInSchedulingWeek(DateTime datum, {DateTime? now}) {
    final target = dateOnly(datum);
    final anchor = dateOnly(schedulingWeekAnchor(now: now));
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return !target.isBefore(monday) && !target.isAfter(sunday);
  }

  /// Da li je datum unutar aktivne RADNE sedmice zakazivanja (ponedeljak–petak).
  static bool isInSchedulingWorkweek(DateTime datum, {DateTime? now}) {
    if (!isInSchedulingWeek(datum, now: now)) return false;
    final target = dateOnly(datum);
    return target.weekday >= DateTime.monday && target.weekday <= DateTime.friday;
  }

  // ─── naziv/kratica → ISO datum (RAČUNANJE PO SEDMICI) ────────

  /// ISO datum (yyyy-MM-dd) za izabrani dan u TEKUĆOJ sedmici.
  /// Ne gura automatski u sledeću sedmicu ako je dan već prošao.
  static String datumIsoZaDanPuniUTekucojSedmici(String danPuni, {DateTime? anchor}) {
    final base = dateOnly(anchor ?? DateTime.now());
    final targetIndex = _indexForFullDayName(danPuni);
    if (targetIndex == -1) return '';
    final monday = base.subtract(Duration(days: base.weekday - 1));
    final targetDate = monday.add(Duration(days: targetIndex));
    return toIsoDate(targetDate);
  }

  /// DateTime za izabrani dan u TEKUĆOJ sedmici.
  /// Sedmica se računa od [anchor] datuma (ili danas ako nije prosleđen).
  static DateTime datumZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    final base = dateOnly(anchor ?? DateTime.now());
    final targetIndex = _indexForDayAbbr(danAbbr);
    if (targetIndex == -1) return base;
    final monday = base.subtract(Duration(days: base.weekday - 1));
    return monday.add(Duration(days: targetIndex));
  }

  /// ISO datum (yyyy-MM-dd) za izabrani dan u TEKUĆOJ sedmici.
  static String datumIsoZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    return toIsoDate(datumZaDanAbbrUTekucojSedmici(danAbbr, anchor: anchor));
  }

  // ─── parsiranje/formatiranje ───────────────────────────────────

  /// Čisti ISO datum deo (yyyy-MM-dd) iz ISO string-a.
  static String parseIsoDatePart(String isoString) {
    final value = isoString.trim();
    if (value.isEmpty) return '';
    if (value.length < _isoDateLength) return value;
    return value.substring(0, _isoDateLength);
  }

  /// ISO datum string iz DateTime.
  static String toIsoDate(DateTime datum) {
    return dateOnly(datum).toIso8601String().substring(0, _isoDateLength);
  }

  /// Današnji ISO datum (yyyy-MM-dd).
  static String todayIso() => toIsoDate(DateTime.now());

  /// Formatuje vreme iz sati/minuta u "HH:mm".
  static String formatVreme(int sati, int minuti) {
    return '${sati.toString().padLeft(2, '0')}:${minuti.toString().padLeft(2, '0')}';
  }

  /// Formatira datum u DD.MM.YY format.
  static String formatDanMesec(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year.toString().substring(2)}';
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

  /// Generira DateTime sa datumom (god, mes, dan) i vremenom na 00:00:00.
  static DateTime dateOnlyFrom(int godina, int mesec, int dan) {
    return DateTime(godina, mesec, dan);
  }

  /// Formatira datum u dd.MM.yyyy format - alias za formatDatumPuni
  static String formatDatumDdMmYyyy(DateTime datum) {
    return formatDatumPuni(datum);
  }
}
