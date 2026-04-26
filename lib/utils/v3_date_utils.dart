import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pomoćne funkcije za parsiranje datuma/vremena iz Supabase baze.
///
/// Supabase timestamptz kolone (created_at, updated_at, vreme_*) dolaze
/// kao ISO string. Parsiramo ih kao instant i eksplicitno konvertujemo
/// u `Europe/Belgrade`, nezavisno od timezone uređaja.
///
/// Kolone tipa `date` (datum) dolaze bez timezone — ne trebaju TZ konverziju.
class V3DateUtils {
  V3DateUtils._();

  static const List<String> _meseci = [
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

  /// Parsira timestamptz string iz baze → Europe/Belgrade vrijeme.
  /// Koristiti za: created_at, updated_at, pokupljen_at, placeno_at, itd.
  static DateTime? parseTs(String? s) {
    if (s == null || s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return _toBelgrade(parsed);
  }

  /// Parsira timestamptz string ili vraća fallback vrijednost.
  static DateTime parseTsOr(String? s, DateTime fallback) {
    return parseTs(s) ?? fallback;
  }

  /// Parsira date string iz baze → DateTime (bez timezone konverzije).
  /// Koristiti za: datum kolone ('2026-03-18').
  static DateTime? parseDatum(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Parsira date string ili vraća fallback vrijednost.
  static DateTime parseDatumOr(String? s, DateTime fallback) {
    return parseDatum(s) ?? fallback;
  }

  static String parseIsoDatePart(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';

    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(value);
    return match?.group(1) ?? '';
  }

  static String mesecNaziv(int mesec, {String fallback = 'Mesec'}) {
    if (mesec >= 1 && mesec <= 12) return _meseci[mesec];
    return fallback;
  }
}
