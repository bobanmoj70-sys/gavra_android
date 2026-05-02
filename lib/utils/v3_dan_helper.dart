import 'v3_string_utils.dart';

/// Helper za konverziju DateTime u naziv/kraticu dana i naziva u datume.
class V3DanHelper {
  V3DanHelper._();

  static const int _isoDateLength = 10;

  static const _names = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const _abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  static const _labels = ['Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub', 'Ned'];

  static int _indexForFullDayName(String danPuni) {
    final normalized = V3StringUtils.forSearch(danPuni);
    for (var i = 0; i < _names.length; i++) {
      if (V3StringUtils.forSearch(_names[i]) == normalized) return i;
    }
    return -1;
  }

  static int _indexForDayAbbr(String danAbbr) {
    final normalized = V3StringUtils.forSearch(danAbbr);
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

  /// Kratki UI label (npr. 'Pon').
  static String label(DateTime datum) => _labels[datum.weekday - 1];

  // ─── Lista dana za UI (dropdown/chip) ───────────────────────────

  /// Radni dani (ponedeljak–petak) — puni nazivi.
  static const List<String> workdayNames = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak'];

  /// Radni dani (ponedeljak–petak) — kratice.
  static const List<String> workdayAbbrs = ['pon', 'uto', 'sre', 'cet', 'pet'];

  // ─── Inicijalizacija tekućeg dana ───────────────────────────────

  /// Danas kao puni naziv RADNOG dana.
  /// - Ako je danas ponedeljak–petak: vraća današnji radni dan.
  /// - Ako je vikend: vraća ponedeljak aktivne sedmice zakazivanja.
  static String defaultWorkdayFullName({DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = dateOnly(current);
    if (base.weekday >= DateTime.monday && base.weekday <= DateTime.friday) {
      return fullName(base);
    }
    return fullName(schedulingWeekRange(now: current).start);
  }

  /// Podrazumevani datum radnog dana.
  /// - Ako je danas ponedeljak–petak: vraća današnji datum.
  /// - Ako je vikend: vraća ponedeljak aktivne sedmice zakazivanja.
  static DateTime defaultWorkdayDate({DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = dateOnly(current);
    if (base.weekday >= DateTime.monday && base.weekday <= DateTime.friday) {
      return base;
    }
    return schedulingWeekRange(now: current).start;
  }

  /// Normalizuje puni naziv dana na radni dan.
  /// Vraća prazan string za vikend/invalid.
  static String normalizeToWorkdayFull(String dayFullName) {
    final index = _indexForFullDayName(dayFullName);
    if (index >= 0 && index <= 4) return _names[index];
    return '';
  }

  /// Kratica radnog dana iz punog naziva dana.
  /// Vraća prazan string za vikend/invalid.
  static String workdayAbbrFromFullName(String dayFullName) {
    final index = _indexForFullDayName(dayFullName);
    if (index >= 0 && index <= 4) return _abbrs[index];
    return '';
  }

  // ─── Aktivna sedmica za zakazivanje ────────────────────────────

  /// Funkcija koja dobavlja globalni override za početak aktivne sedmice (kako je podešeno u bazi).
  /// Koristimo callback da izbegnemo kružne importe sa globals.dart.
  static DateTime? Function()? getGlobalActiveWeekStart;
  static DateTime? Function()? getGlobalActiveWeekEnd;

  /// Anchor datum za aktivnu sedmicu zakazivanja.
  static DateTime schedulingWeekAnchor({DateTime? now}) {
    if (getGlobalActiveWeekStart != null) {
      final overrideStart = getGlobalActiveWeekStart!();
      if (overrideStart != null) {
        return dateOnly(overrideStart);
      }
    }

    return dateOnly(now ?? DateTime.now());
  }

  /// Početak i kraj aktivne sedmice zakazivanja.
  /// Zahteva globalni override iz app settings (`aktivnaSedmicaStart/End`).
  static ({DateTime start, DateTime end}) schedulingWeekRange({DateTime? now}) {
    final overrideStart = getGlobalActiveWeekStart?.call();
    if (overrideStart == null) {
      throw StateError(
        'Aktivna sedmica nije podešena (app settings active week start je null).',
      );
    }

    final start = dateOnly(overrideStart);
    final overrideEnd = getGlobalActiveWeekEnd?.call();
    final end = (overrideEnd != null && !dateOnly(overrideEnd).isBefore(start))
        ? dateOnly(overrideEnd)
        : start.add(const Duration(days: 6));
    return (start: start, end: end);
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
    final range = schedulingWeekRange(now: now);
    return !target.isBefore(range.start) && !target.isAfter(range.end);
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
    final targetIndex = _indexForFullDayName(danPuni);
    if (targetIndex == -1) return '';
    final range = schedulingWeekRange(now: anchor ?? DateTime.now());
    final targetDate = range.start.add(Duration(days: targetIndex));
    return toIsoDate(targetDate);
  }

  /// DateTime za izabrani dan u TEKUĆOJ sedmici.
  /// Sedmica se računa od [anchor] datuma (ili danas ako nije prosleđen).
  static DateTime datumZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    final targetIndex = _indexForDayAbbr(danAbbr);
    final range = schedulingWeekRange(now: anchor ?? DateTime.now());
    if (targetIndex == -1) {
      throw ArgumentError.value(danAbbr, 'danAbbr', 'Nevažeća kratica dana');
    }
    return range.start.add(Duration(days: targetIndex));
  }

  /// ISO datum (yyyy-MM-dd) za izabrani dan u TEKUĆOJ sedmici.
  static String datumIsoZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    return toIsoDate(datumZaDanAbbrUTekucojSedmici(danAbbr, anchor: anchor));
  }

  // ─── parsiranje/formatiranje ───────────────────────────────────

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
}
