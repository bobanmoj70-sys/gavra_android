import 'package:flutter/material.dart';

/// Gavra brand — jedini izvor istine za ikone i brand boje.
///
/// Vizuel: **crna pozadina + cyan/plava slova** (kao store logo).
/// Master fajl: [iconAsset] (`assets/branding/gavra_icon.png`).
/// Ne pokazivati druge logo fajlove u UI / launcher-ima.
class GavraBranding {
  GavraBranding._();

  /// Canonical app icon / logo (crna bg + plava slova).
  static const String iconAsset = 'assets/branding/gavra_icon.png';

  /// Crna pozadina (store / launcher / splash).
  static const Color background = Color(0xFF000000);

  /// Plava slova — mereno sa store asseta (~#60C8F8).
  static const Color letter = Color(0xFF60C8F8);

  /// Tamniji cyan za secondary / senke.
  static const Color letterDeep = Color(0xFF57AACE);

  /// Svetliji cyan highlight.
  static const Color letterBright = Color(0xFF68D0F8);

  /// ARGB int za adaptive icon / native config.
  static const int iconBackgroundArgb = 0xFF000000;

  /// ARGB int brand slova.
  static const int letterArgb = 0xFF60C8F8;
}
