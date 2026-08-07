import 'package:flutter/material.dart';

/// Gavra brand — jedini izvor istine za ikone i brand boje.
///
/// Vizuel: **crna pozadina + cyan/plava cursive „Gavra 013“** (kao Play Store).
/// Master fajl: [iconAsset] (`assets/branding/gavra_icon.png`) — full-bleed kvadrat
/// (Android adaptive / iOS / Play zahtevaju neprozirni kvadrat; OS / UI seče uglove).
///
/// Za UI koristi [GavraBrandIcon] (Play-style zaobljeni uglovi).
/// Ne pokazivati druge logo fajlove u UI / launcher-ima.
class GavraBranding {
  GavraBranding._();

  /// Canonical app icon / logo (crna bg + plava slova), full-bleed 512×512.
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

  /// Play Store–style corner radius as fraction of icon edge (~22%).
  static const double cornerRadiusFactor = 0.22;

  /// Radius for a logo of the given [size] (shortest side).
  static double cornerRadiusFor(double size) => size * cornerRadiusFactor;
}

/// Brand logo with Play-style rounded corners (single UI entry point).
class GavraBrandIcon extends StatelessWidget {
  const GavraBrandIcon({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Override radius; default = Play-style factor on the shorter side.
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    final side = switch ((w, h)) {
      (final double ww, final double hh) => ww < hh ? ww : hh,
      (final double ww, null) => ww,
      (null, final double hh) => hh,
      _ => 48.0,
    };
    final radius = borderRadius ?? GavraBranding.cornerRadiusFor(side);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        GavraBranding.iconAsset,
        width: width,
        height: height,
        fit: fit,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
