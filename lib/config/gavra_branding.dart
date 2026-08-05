/// Gavra brand assets — single source of truth.
///
/// Master file: [iconAsset] (`assets/branding/gavra_icon.png`)
/// black background + blue letters. Do not point UI/launchers at other logos.
class GavraBranding {
  GavraBranding._();

  /// Canonical app icon / logo (black bg + blue letters).
  static const String iconAsset = 'assets/branding/gavra_icon.png';

  /// Solid black used for adaptive icon / splash backgrounds.
  static const int iconBackgroundArgb = 0xFF000000;
}
