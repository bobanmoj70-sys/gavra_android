import 'package:intl/intl.dart';

/// Centralizovano formatiranje brojeva, cena i ostalih numeričkih podataka.
/// Eliminiše duplikate NumberFormat instanci kroz aplikaciju.
class V3FormatUtils {
  V3FormatUtils._();

  // ─── STATIC FORMATTERS ──────────────────────────────────────────────

  /// Standardni broj formatter za srpski locale - #,###
  static final _brojFormatter = NumberFormat('#,###', 'sr');

  /// Novčani formatter za srpski locale sa decimalnim mestima
  static final _novacFormatter = NumberFormat('#,##0.00', 'sr_Latn_RS');

  /// Kratki novčani formatter bez decimala
  static final _novacKratkiFormatter = NumberFormat('#,###', 'sr');

  /// Formatter za gorivo sa jednom decimalom
  static final _gorivoFormatter = NumberFormat('#,##0.0', 'sr');

  // ─── PUBLIC METHODS ──────────────────────────────────────────────────

  /// Formatira broj sa zapetom kao separator hiljada (123,456)
  static String formatBroj(num broj) {
    return _brojFormatter.format(broj);
  }

  /// Formatira novac sa decimalnim mestima (1,234.56)
  static String formatNovac(num iznos) {
    return _novacFormatter.format(iznos);
  }

  /// Formatira novac bez decimala za prikaz u UI (1,234)
  static String formatNovacKratko(num iznos) {
    return _novacKratkiFormatter.format(iznos);
  }

  /// Formatira kilometražu vozila
  static String formatKilometraza(int? km) {
    if (km == null) return '-';
    return '${formatBroj(km)} km';
  }

  /// Formatira cenu po vožnji
  static String formatCenaPoVoznji(double cena) {
    return '${formatNovacKratko(cena)} RSD';
  }

  /// Formatira procenat
  static String formatProcenat(double procenat) {
    return '${procenat.toStringAsFixed(1)}%';
  }

  /// Formatira gorivo sa jednom decimalom
  static String formatGorivo(num litara) {
    return _gorivoFormatter.format(litara);
  }
}
