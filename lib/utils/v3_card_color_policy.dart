import 'package:flutter/material.dart';

class V3CardColorPolicy {
  V3CardColorPolicy._();

  static Color? tryParseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse('FF$clean', radix: 16);
      return value != null ? Color(value) : null;
    }
    if (clean.length == 8) {
      final value = int.tryParse(clean, radix: 16);
      return value != null ? Color(value) : null;
    }
    return null;
  }

  static Color parseHexColor(
    String? hex, {
    required Color fallback,
  }) {
    return tryParseHexColor(hex) ?? fallback;
  }

  static Color vozacColorOr(
    String? hex, {
    Color fallback = Colors.blueAccent,
  }) {
    return parseHexColor(hex, fallback: fallback);
  }

  static Color tintedCardBackground(
    Color vozacBoja, {
    double amount = 0.20,
  }) {
    return Color.lerp(Colors.white, vozacBoja, amount) ?? Colors.white;
  }

  static Color slotButtonBackgroundFromVozac(
    Color vozacBoja, {
    double alpha = 0.10,
  }) {
    return vozacBoja.withValues(alpha: alpha);
  }

  static Color slotButtonBorderFromVozac(
    Color vozacBoja, {
    double alpha = 0.30,
  }) {
    return vozacBoja.withValues(alpha: alpha);
  }

  static Color slotNavBackgroundFromVozac(
    Color vozacBoja, {
    double alpha = 0.16,
  }) {
    return vozacBoja.withValues(alpha: alpha);
  }

  static Color slotNavBorderFromVozac(
    Color vozacBoja, {
    double alpha = 0.75,
  }) {
    return vozacBoja.withValues(alpha: alpha);
  }
}
