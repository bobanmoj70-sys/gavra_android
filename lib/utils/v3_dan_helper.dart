import '../l10n/app_translations.dart';
import '../services/v3_locale_manager.dart';
import 'v3_belgrade_time.dart';
import 'v3_string_utils.dart';

/// Dani + sedmica zakazivanja. Vreme uvek preko [V3BelgradeTime] (Beograd).
/// Zakazivanje = samo pon–pet.
class V3DanHelper {
  V3DanHelper._();

  static final Map<String, Map<String, String>> _t = AppTranslations.ns('danHelper');

  static const Map<String, String> _translationKeys = {
    'ponedeljak': 'ponedeljak',
    'utorak': 'utorak',
    'sreda': 'sreda',
    'cetvrtak': 'cetvrtak',
    'četvrtak': 'cetvrtak',
    'petak': 'petak',
    'subota': 'subota',
    'nedelja': 'nedelja',
  };

  static String trFullName(String danPuni) {
    final key = _translationKeys[danPuni.trim().toLowerCase()];
    if (key == null) return danPuni;
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? danPuni;
  }

  static String trAbbr(String danPuni) {
    final translated = trFullName(danPuni);
    final code = V3LocaleManager().currentLocale.languageCode;
    if (code == 'zh') return translated;
    final len = translated.length < 3 ? translated.length : 3;
    return translated.substring(0, len);
  }

  static const _names = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const _abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  static const _labels = ['Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub', 'Ned'];

  static const List<String> workdayNames = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak'];
  static const List<String> workdayAbbrs = ['pon', 'uto', 'sre', 'cet', 'pet'];

  static int _indexForFullDayName(String danPuni) {
    final normalized = V3StringUtils.forSearch(danPuni);
    for (var i = 0; i < _names.length; i++) {
      if (V3StringUtils.forSearch(_names[i]) == normalized) return i;
    }
    return -1;
  }

  /// 0–4 = pon–pet, inače -1 (vikend nije radni dan).
  static int _workdayIndexFromAbbr(String danAbbr) {
    final n = V3StringUtils.forSearch(danAbbr);
    if (n.startsWith('pon')) return 0;
    if (n.startsWith('uto')) return 1;
    if (n.startsWith('sre')) return 2;
    if (n.startsWith('cet')) return 3;
    if (n.startsWith('pet')) return 4;
    return -1;
  }

  static String fullName(DateTime datum) => _names[datum.weekday - 1];
  static String label(DateTime datum) => _labels[datum.weekday - 1];

  static String defaultWorkdayFullName({DateTime? now}) {
    final base = dateOnly(now ?? V3BelgradeTime.now());
    if (base.weekday >= DateTime.monday && base.weekday <= DateTime.friday) {
      return fullName(base);
    }
    return 'Ponedeljak';
  }

  static DateTime defaultWorkdayDate({DateTime? now}) {
    final base = dateOnly(now ?? V3BelgradeTime.now());
    if (base.weekday >= DateTime.monday && base.weekday <= DateTime.friday) {
      return base;
    }
    return schedulingWeekAnchor(now: now);
  }

  static String normalizeToWorkdayFull(String dayFullName) {
    final index = _indexForFullDayName(dayFullName);
    if (index >= 0 && index <= 4) return _names[index];
    return '';
  }

  static String workdayAbbrFromFullName(String dayFullName) {
    final index = _indexForFullDayName(dayFullName);
    if (index >= 0 && index <= 4) return _abbrs[index];
    return '';
  }

  static String fullNameFromWorkdayAbbr(String danAbbr) {
    final index = _workdayIndexFromAbbr(danAbbr);
    return index < 0 ? '' : _names[index];
  }

  /// Ponedeljak aktivne sedmice iz baze (ili tekući pon, Beograd).
  static DateTime? Function()? getGlobalOperativnaNedeljaStart;

  static DateTime schedulingWeekAnchor({DateTime? now}) {
    final fromDb = getGlobalOperativnaNedeljaStart?.call();
    final d = dateOnly(fromDb ?? now ?? V3BelgradeTime.now());
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Pon–pet aktivne sedmice.
  static ({DateTime start, DateTime end}) schedulingWeekRange({DateTime? now}) {
    final start = schedulingWeekAnchor(now: now);
    return (start: start, end: start.add(const Duration(days: 4)));
  }

  /// Subota 03:00 Beograd — otvaranje nove sedmice.
  static DateTime nextSchedulingUnlock({DateTime? now}) {
    final current = now ?? V3BelgradeTime.now();
    final base = dateOnly(current);
    final saturday = base.add(Duration(days: DateTime.saturday - base.weekday));
    final unlock = V3BelgradeTime.dateTime(saturday.year, saturday.month, saturday.day, 3, 0);
    if (current.isBefore(unlock)) return unlock;
    final next = saturday.add(const Duration(days: 7));
    return V3BelgradeTime.dateTime(next.year, next.month, next.day, 3, 0);
  }

  static bool isInSchedulingWeek(DateTime datum, {DateTime? now}) {
    return isInSchedulingWorkweek(datum, now: now);
  }

  static bool isInSchedulingWorkweek(DateTime datum, {DateTime? now}) {
    final target = dateOnly(datum);
    if (target.weekday < DateTime.monday || target.weekday > DateTime.friday) return false;
    final range = schedulingWeekRange(now: now);
    return !target.isBefore(range.start) && !target.isAfter(range.end);
  }

  static String datumIsoZaDanPuniUTekucojSedmici(String danPuni, {DateTime? anchor}) {
    final i = _indexForFullDayName(danPuni);
    if (i < 0 || i > 4) return '';
    return toIsoDate(schedulingWeekAnchor(now: anchor).add(Duration(days: i)));
  }

  static DateTime datumZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    final i = _workdayIndexFromAbbr(danAbbr);
    if (i < 0) {
      throw ArgumentError.value(danAbbr, 'danAbbr', 'Samo pon-pet');
    }
    return schedulingWeekAnchor(now: anchor).add(Duration(days: i));
  }

  static String datumIsoZaDanAbbrUTekucojSedmici(String danAbbr, {DateTime? anchor}) {
    return toIsoDate(datumZaDanAbbrUTekucojSedmici(danAbbr, anchor: anchor));
  }

  static String formatVreme(int sati, int minuti) => V3BelgradeTime.formatVreme(sati, minuti);
  static String toIsoDate(DateTime datum) => V3BelgradeTime.toIsoDate(datum);
  static String todayIso() => V3BelgradeTime.todayIso();
  static String formatDanMesec(DateTime datum) => V3BelgradeTime.formatDanMesec(datum);
  static String formatDatumVremeKratko(DateTime dt) => V3BelgradeTime.formatDatumVremeKratko(dt);
  static String formatDatumPuni(DateTime datum) => V3BelgradeTime.formatDatumPuni(datum);
  static DateTime dateOnly(DateTime datum) => V3BelgradeTime.dateOnly(datum);
  static DateTime dateOnlyFrom(int godina, int mesec, int dan) => V3BelgradeTime.dateOnlyFrom(godina, mesec, dan);
}
