import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../services/v3_locale_manager.dart';

/// JEDINI globalni izvor istine za `Europe/Belgrade` vremensku zonu.
///
/// Sva poslovna logika u aplikaciji radi po Beogradskom vremenu, nezavisno
/// od timezone-a uređaja. Ova klasa sadrži osnovne, čiste helper-e:
///   - trenutno vreme/datum u Belgrade zoni
///   - konverziju UTC instant-a u Belgrade zonu
///   - serijalizaciju u ISO formate
///   - parsiranje timestamp-ova i date-ova iz baze
///   - normalizaciju vremena u HH:mm
///   - formatiranje datuma/vremena za prikaz
const String kBelgradeTimeZone = 'Europe/Belgrade';

class V3BelgradeTime {
  V3BelgradeTime._();

  static tz.Location? _location;
  static bool _initialized = false;

  static tz.Location get location {
    _location ??= tz.getLocation(kBelgradeTimeZone);
    return _location!;
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// Trenutni trenutak u `Europe/Belgrade` zoni (poštuje DST).
  static DateTime now() {
    _ensureInitialized();
    return tz.TZDateTime.now(location);
  }

  /// Trenutni trenutak kao UTC instant.
  static DateTime nowUtc() => now().toUtc();

  /// Današnji datum (bez vremena) u `Europe/Belgrade` zoni.
  static DateTime today() => dateOnly(now());

  /// Današnji datum kao ISO string `yyyy-MM-dd` u Belgrade zoni.
  static String todayIso() => toIsoDate(today());

  /// Konvertuje bilo koji DateTime (tretiran kao UTC instant) u `Europe/Belgrade`.
  static DateTime fromUtc(DateTime dt) {
    _ensureInitialized();
    return tz.TZDateTime.from(dt.toUtc(), location);
  }

  /// DateTime samo sa datumom (year/month/day) u 00:00:00.
  static DateTime dateOnly(DateTime datum) => DateTime(datum.year, datum.month, datum.day);

  /// DateTime sa datumom (god, mes, dan) i vremenom na 00:00:00.
  static DateTime dateOnlyFrom(int godina, int mesec, int dan) => DateTime(godina, mesec, dan);

  /// Kreira DateTime u `Europe/Belgrade` zoni za zadatu godinu/mesec/dan i opciono sat/minut.
  static DateTime dateTime(int godina, int mesec, int dan, [int sat = 0, int minut = 0]) {
    _ensureInitialized();
    return tz.TZDateTime(location, godina, mesec, dan, sat, minut);
  }

  /// DateTime → `yyyy-MM-dd` za upis u date kolone.
  static String toIsoDate(DateTime datum) {
    final d = dateOnly(datum);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Vadi `yyyy-MM-dd` deo iz ISO stringa (npr. iz DateTime.toIso8601String()).
  static String parseIsoDatePart(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.length >= 10) return value.substring(0, 10);
    return '';
  }

  /// DateTime kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String toIsoUtc(DateTime value) => value.toUtc().toIso8601String();

  /// Trenutni trenutak kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String nowIsoUtc() => nowUtc().toIso8601String();

  // ─── Parsiranje iz baze ─────────────────────────────────────────

  static final RegExp _dateOnlyRe = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Timestamptz → Beograd. Čist `yyyy-MM-dd` ide na [parseDatum] (bez TZ pomaka).
  static DateTime? parseTs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final raw = s.trim();
    if (raw.length == 10 && _dateOnlyRe.hasMatch(raw)) return parseDatum(raw);
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : fromUtc(parsed);
  }

  static DateTime parseTsOrNow(String? s) => parseTs(s) ?? now();

  /// DATE kolona → kalendarski dan (Beograd posao). Bez zone telefona.
  static DateTime? parseDatum(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);

    final iso = parseIsoDatePart(value.toString());
    if (!_dateOnlyRe.hasMatch(iso)) return null;
    final y = int.tryParse(iso.substring(0, 4));
    final m = int.tryParse(iso.substring(5, 7));
    final d = int.tryParse(iso.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime parseDatumOrToday(Object? value) => parseDatum(value) ?? today();

  // ─── Normalizacija vremena ──────────────────────────────────────

  static final RegExp _timeRegex = RegExp(
    r'((?:[01]?\d|2[0-3]):[0-5]\d(?:\:[0-5]\d)?)',
  );

  /// Vadi prvi HH:mm (ili HH:mm:ss) token iz stringa i vraća ga kao HH:mm.
  /// Ako ne nađe validno vreme, vraća trimovan original.
  static String normalizeToHHmm(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final match = _timeRegex.firstMatch(value);
    if (match == null) return value.trim();

    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    final hour = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final minute = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Formatira vreme iz sati/minuta u "HH:mm".
  static String formatVreme(int sati, int minuti) {
    return '${sati.toString().padLeft(2, '0')}:${minuti.toString().padLeft(2, '0')}';
  }

  // ─── Formatiranje datuma za prikaz ──────────────────────────────

  /// Formatira datum u DD.MM.YY format.
  static String formatDanMesec(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year.toString().substring(2)}';
  }

  /// Formatira datetime u DD.MM. HH:MM format (kratko).
  static String formatDatumVremeKratko(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}. '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Formatira datum u DD.MM.YYYY format (puni).
  static String formatDatumPuni(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}';
  }

  /// Formatira datum u `ddMMyyyy` (za nazive fajlova).
  static String formatFileDate(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}${datum.month.toString().padLeft(2, '0')}${datum.year}';
  }

  /// Formatira datum u `dd_MM_yyyy` (za nazive fajlova/dokumenata).
  static String formatFileDateUnderscore(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}_${datum.month.toString().padLeft(2, '0')}_${datum.year}';
  }

  // ─── Lokalizovani nazivi meseci ─────────────────────────────────

  static const List<String> _meseciSr = <String>[
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

  static const List<String> _meseciEn = <String>[
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _meseciRu = <String>[
    '',
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _meseciDe = <String>[
    '',
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  static const List<String> _meseciZh = <String>[
    '',
    '一月',
    '二月',
    '三月',
    '四月',
    '五月',
    '六月',
    '七月',
    '八月',
    '九月',
    '十月',
    '十一月',
    '十二月',
  ];

  static String mesecNaziv(int mesec, {String fallback = 'Mesec'}) {
    if (mesec >= 1 && mesec <= 12) {
      final code = V3LocaleManager().currentLocale.languageCode;
      final months = switch (code) {
        'en' => _meseciEn,
        'ru' => _meseciRu,
        'de' => _meseciDe,
        'zh' => _meseciZh,
        _ => _meseciSr,
      };
      return months[mesec];
    }
    return fallback;
  }
}
