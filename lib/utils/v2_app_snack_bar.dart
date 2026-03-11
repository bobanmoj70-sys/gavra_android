import 'package:flutter/material.dart';

// ==========================================
// APP SNACK BAR - CENTRALIZOVANE PORUKE
// ==========================================
// NE MIJENJATI - ZACEMENTIRANI STILOVI
// Sve SnackBar poruke u aplikaciji moraju koristiti ovu klasu.
// Zabranjeno je direktno kreiranje SnackBar(...) ili pozivanje
// ScaffoldMessenger.of(context).showSnackBar(...) van ove klase.
// Potvrđeno i zacementirano 21.02.2026.
// TIPOVI PORUKA:
// success  → zelena  (#4CAF50) — uspješna akcija
// error    → crvena  (#F44336) — greška / neuspjeh
// warning  → narandžasta (#FF9800) — upozorenje / blokada
// info     → plava   (#2196F3) — informacija / neutralna poruka
// TRAJANJE:
// kratko  (short)  → 2 sekunde — potvrda akcije
// srednje (medium) → 3 sekunde — default
// dugo    (long)   → 5 sekundi — objašnjenje / blokada
// UPOTREBA:
// V2AppSnackBar.success(context, ' Sačuvano!');
// V2AppSnackBar.error(context, 'Greška: $e');
// V2AppSnackBar.warning(context, '⏳ Zahtev je u obradi...');
// V2AppSnackBar.info(context, 'ℹ Rezervacije su moguće samo za danas i sutra.');
// KRAJ SPECIFIKACIJE

class V2AppSnackBar {
  V2AppSnackBar._(); // Ne instancirati

  // ─── Boje ────────────────────────────────────────────────────
  static const Color _colorSuccess = Color(0xFF4CAF50); // zelena
  static const Color _colorError = Color(0xFFF44336); // crvena
  static const Color _colorWarning = Color(0xFFFF9800); // narandžasta
  static const Color _colorInfo = Color(0xFF2196F3); // plava

  // ─── Trajanja ─────────────────────────────────────────────────
  static const Duration _short = Duration(seconds: 2);
  static const Duration _medium = Duration(seconds: 3);
  static const Duration _long = Duration(seconds: 5);

  // ─── Interni builder ──────────────────────────────────────────
  static void _show(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    Duration duration = _medium,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          action: action,
        ),
      );
  }

  // ─── Javne metode ─────────────────────────────────────────────

  /// Uspješna akcija (zelena, 5s)
  static void success(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorSuccess, duration: _long);

  /// Greška (crvena, 5s)
  static void error(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorError, duration: _long);

  /// Upozorenje / blokada (narandžasta, 5s)
  static void warning(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorWarning, duration: _long);

  /// ℹ Informacija / neutralna poruka (plava, 5s)
  static void info(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorInfo, duration: _long);

  /// ℹ Informacija sa dužim trajanjem (plava, 5s)
  static void infoLong(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorInfo, duration: _long);

  /// ⏳ Blokada sa dužim objašnjenjem (narandžasta, 5s)
  static void blocked(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorWarning, duration: _long);

  /// Plaćanje uspješno (zelena, 5s)
  static void payment(BuildContext context, String message) =>
      _show(context, message, backgroundColor: _colorSuccess, duration: _long);
}
