/// Pomoćne funkcije za parsiranje datuma/vremena iz Supabase baze.
///
/// Supabase timestamptz kolone (created_at, updated_at, vreme_*) dolaze
/// kao UTC string sa 'Z' sufiksom. Dart ih parsira kao UTC DateTime.
/// Uvijek pozivamo .toLocal() da dobijemo lokalno vrijeme (Europe/Belgrade).
///
/// Kolone tipa `date` (datum) dolaze bez timezone — ne trebaju .toLocal().
class V3DateUtils {
  V3DateUtils._();

  /// Parsira timestamptz string iz baze → lokalno vrijeme uređaja.
  /// Koristiti za: created_at, updated_at, vreme_pokupljen, vreme_placen, itd.
  static DateTime? parseTs(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
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
}
