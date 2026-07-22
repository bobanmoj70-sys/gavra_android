import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../services/v3_locale_manager.dart';

/// Pomoćne funkcije za parsiranje datuma/vremena iz Supabase baze.
///
/// Supabase timestamptz kolone (created_at, updated_at, vreme_*) dolaze
/// kao ISO string. Parsiramo ih kao instant i eksplicitno konvertujemo
/// u `Europe/Belgrade`, nezavisno od timezone uređaja.
///
/// Kolone tipa `date` (datum) dolaze bez timezone — ne trebaju TZ konverziju.
class V3DateUtils {
  V3DateUtils._();

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

  static const String _belgradeTzName = 'Europe/Belgrade';
  static bool _tzInitialized = false;
  static tz.Location? _belgradeLocation;

  static void _ensureBelgradeTz() {
    if (_tzInitialized && _belgradeLocation != null) return;
    tz_data.initializeTimeZones();
    _belgradeLocation = tz.getLocation(_belgradeTzName);
    _tzInitialized = true;
  }

  static DateTime _toBelgrade(DateTime dt) {
    _ensureBelgradeTz();
    return tz.TZDateTime.from(dt.toUtc(), _belgradeLocation!);
  }

  /// Parsira timestamptz string iz baze → Europe/Belgrade vreme.
  /// Koristiti za: created_at, updated_at, pokupljen_at, placeno_at, itd.
  static DateTime? parseTs(String? s) {
    if (s == null || s.isEmpty) return null;

    final trimmed = s.trim();
    final isDateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed);
    if (isDateOnly) {
      return DateTime.tryParse(trimmed);
    }

    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;

    final hasExplicitOffset = trimmed.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(trimmed);
    if (!hasExplicitOffset) {
      return parsed;
    }

    return _toBelgrade(parsed);
  }

  /// Parsira timestamptz string ili vraća fallback vrednost.
  static DateTime parseTsOr(String? s, DateTime fallback) {
    return parseTs(s) ?? fallback;
  }

  /// Parsira date string iz baze → DateTime (bez timezone konverzije).
  /// Koristiti za: datum kolone ('2026-03-18').
  static DateTime? parseDatum(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Parsira date string ili vraća fallback vrednost.
  static DateTime parseDatumOr(String? s, DateTime fallback) {
    return parseDatum(s) ?? fallback;
  }

  /// Trenutni trenutak kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String nowIsoUtc() {
    return DateTime.now().toUtc().toIso8601String();
  }

  /// DateTime kao ISO-8601 u UTC (`...Z`) za upis u timestamptz.
  static String toIsoUtc(DateTime value) {
    return value.toUtc().toIso8601String();
  }

  static String parseIsoDatePart(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';

    final dateOnlyMatch = RegExp(r'^(\d{4}-\d{2}-\d{2})$').firstMatch(value);
    if (dateOnlyMatch != null) {
      return dateOnlyMatch.group(1) ?? '';
    }

    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final hasExplicitOffset = value.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value);
      final normalized = hasExplicitOffset ? _toBelgrade(parsed) : parsed;
      final y = normalized.year.toString().padLeft(4, '0');
      final m = normalized.month.toString().padLeft(2, '0');
      final d = normalized.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(value);
    return match?.group(1) ?? '';
  }

  static String mesecNaziv(int mesec, {String fallback = 'Mesec'}) {
    if (mesec >= 1 && mesec <= 12) {
      final code = V3LocaleManager().currentLocale.languageCode;
      final months = switch (code) {
        'en' => _meseciEn,
        'ru' => _meseciRu,
        'de' => _meseciDe,
        _ => _meseciSr,
      };
      return months[mesec];
    }
    return fallback;
  }
}
