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
///   - lokalizovane nazive meseci
const String kBelgradeTimeZone = 'Europe/Belgrade';

class V3BelgradeTime {
  V3BelgradeTime._();

  static tz.Location? _location;
  static bool _initialized = false;

  static tz.Location get _loc {
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
    return tz.TZDateTime.now(_loc);
  }

  /// Današnji datum (bez vremena) u `Europe/Belgrade` zoni.
  static DateTime today() => dateOnly(now());

  /// Današnji datum kao ISO string `yyyy-MM-dd` u Belgrade zoni.
  static String todayIso() => toIsoDate(today());

  /// Konvertuje bilo koji DateTime (tretiran kao UTC instant) u `Europe/Belgrade`.
  static DateTime fromUtc(DateTime dt) {
    _ensureInitialized();
    return tz.TZDateTime.from(dt.toUtc(), _loc);
  }

  /// DateTime samo sa datumom (year/month/day) u 00:00:00.
  static DateTime dateOnly(DateTime datum) => DateTime(datum.year, datum.month, datum.day);

  /// DateTime sa datumom (god, mes, dan) i vremenom na 00:00:00.
  static DateTime dateOnlyFrom(int godina, int mesec, int dan) => DateTime(godina, mesec, dan);

  /// DateTime → `yyyy-MM-dd` za upis u date kolone.
  static String toIsoDate(DateTime datum) {
    final d = dateOnly(datum);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// DateTime kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String toIsoUtc(DateTime value) => value.toUtc().toIso8601String();

  /// Trenutni trenutak kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String nowIsoUtc() => DateTime.now().toUtc().toIso8601String();

  // ─── Parsiranje iz baze ─────────────────────────────────────────

  /// Parsira timestamptz string iz baze → `Europe/Belgrade` DateTime.
  static DateTime? parseTs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(s.trim());
    return parsed == null ? null : fromUtc(parsed);
  }

  /// Parsira date string iz baze → DateTime (bez timezone konverzije).
  static DateTime? parseDatum(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s.trim());
  }

  /// Vadi `yyyy-MM-dd` deo iz ISO stringa (npr. iz DateTime.toIso8601String()).
  static String parseIsoDatePart(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.length >= 10) return value.substring(0, 10);
    return '';
  }

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

  /// Vadi prvi HH:mm (ili HH:mm:ss) token iz stringa i vraća ga kao HH:mm.
  /// Ako ne nađe validno vreme, vraća `null`.
  static String? extractHHmmToken(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final match = _timeRegex.firstMatch(value);
    if (match == null) return null;

    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return null;

    final hour = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final minute = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$hour:$minute';
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
