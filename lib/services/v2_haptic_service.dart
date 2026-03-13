import 'package:flutter/services.dart';

/// Wrapper oko Flutter HapticFeedback za taktilne povratne informacije.
class V2HapticService {
  V2HapticService._();

  /// Laki klik — za selekciju, tap
  static void selectionClick() {
    HapticFeedback.selectionClick();
  }

  /// Srednji udar — za potvrdu akcije
  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }

  /// Jaki udar — za greške, upozorenja
  static void heavyImpact() {
    HapticFeedback.heavyImpact();
  }

  /// Laki udar — za manje akcije
  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  /// Vibracija — za notifikacije
  static void vibrate() {
    HapticFeedback.vibrate();
  }
}
