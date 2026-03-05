import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/v2_theme_manager.dart';

// GLOBALNO REŠENJE ZA SRPSKU DJAKRITIKU (š, đ, č, ć, ž)
// Unicode normalizacija i font fallback-ovi
// KORIŠĆENJE:
// 1. AUTOMATSKI - Svi Text widget-i u app-u koriste srpsku dijakritiku
// textTheme: createSerbianTextTheme() - već primenjeno u temi
// 2. EXTENSION - Dodavanje dijakritike postojećem TextStyle-u:
// TextStyle().withSerbianSupport()
// FONT FALLBACK-OVI:
// - Inter (primarni)
// - Roboto
// - NotoSans
// - Arial Unicode MS
// - sans-serif (sistemski)
// OVO OSIGURAVA da se srpska slova uvek pravilno prikazuju!

/// Globalni TextStyle sa srpskom dijakritikom
class SerbianTextStyle {
  static const String _primaryFont = 'Inter';
  static const List<String> _fallbackFonts = [
    'Roboto',
    'NotoSans',
    'Arial Unicode MS',
    'sans-serif',
  ];

  /// Kreira TextStyle sa srpskom dijakritikom
  static TextStyle create({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    TextDecoration? decoration,
    double? letterSpacing,
  }) {
    // KORISTIMO GOOGLE FONTS SA latin-ext PODRŠKOM
    return GoogleFonts.getFont(
      _primaryFont,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      decoration: decoration,
      letterSpacing: letterSpacing,
    ).copyWith(
      fontFamilyFallback: _fallbackFonts,
    );
  }

  /// Headline style sa dijakritikom
  static TextStyle headlineLarge({Color? color}) => create(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.2,
      );

  /// Title style sa dijakritikom
  static TextStyle titleLarge({Color? color}) => create(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.3,
      );

  /// Body style sa dijakritikom
  static TextStyle bodyLarge({Color? color}) => create(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Label style sa dijakritikom
  static TextStyle labelLarge({Color? color}) => create(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.4,
      );
}

// Extension za TextStyle sa dijakritikom
extension SerbianTextStyleExtension on TextStyle {
  /// Dodaje srpsku dijakritiku podršku postojećem TextStyle-u
  TextStyle withSerbianSupport() {
    return copyWith(
      fontFamilyFallback: SerbianTextStyle._fallbackFonts,
    );
  }
}

/// Kreira TextTheme sa srpskom dijakritikom podrškom
TextTheme createSerbianTextTheme() {
  final baseTheme = GoogleFonts.interTextTheme();
  return baseTheme.copyWith(
    // Headline stilovi
    headlineLarge: baseTheme.headlineLarge?.withSerbianSupport(),
    headlineMedium: baseTheme.headlineMedium?.withSerbianSupport(),
    headlineSmall: baseTheme.headlineSmall?.withSerbianSupport(),

    // Title stilovi
    titleLarge: baseTheme.titleLarge?.withSerbianSupport(),
    titleMedium: baseTheme.titleMedium?.withSerbianSupport(),
    titleSmall: baseTheme.titleSmall?.withSerbianSupport(),

    // Body stilovi
    bodyLarge: baseTheme.bodyLarge?.withSerbianSupport(),
    bodyMedium: baseTheme.bodyMedium?.withSerbianSupport(),
    bodySmall: baseTheme.bodySmall?.withSerbianSupport(),

    // Label stilovi
    labelLarge: baseTheme.labelLarge?.withSerbianSupport(),
    labelMedium: baseTheme.labelMedium?.withSerbianSupport(),
    labelSmall: baseTheme.labelSmall?.withSerbianSupport(),

    // Display stilovi
    displayLarge: baseTheme.displayLarge?.withSerbianSupport(),
    displayMedium: baseTheme.displayMedium?.withSerbianSupport(),
    displaySmall: baseTheme.displaySmall?.withSerbianSupport(),
  );
}

// Extension za kompatibilnost sa starijim Flutter verzijama

// SAMO TRIPLE BLUE FASHION TEMA!

// TRIPLE BLUE FASHION - Electric + Ice + Neon kombinacija!
const ColorScheme tripleBlueFashionColorScheme = ColorScheme(
  brightness: Brightness.light,
  // Electric Blue Shine kao glavni
  primary: Color(0xFF021B79), // Electric Blue Shine - taman
  onPrimary: Colors.white,
  primaryContainer: Color(0xFF0575E6), // Electric Blue Shine - svetao
  onPrimaryContainer: Colors.white,

  // Blue Ice Metallic kao secondary
  secondary: Color(0xFF1E3A78), // Blue Ice Metallic - početak
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFF4F7CAC), // Blue Ice Metallic - sredina
  onSecondaryContainer: Colors.white,

  // Neon Blue Glow kao tertiary
  tertiary: Color(0xFF1FA2FF), // Neon Blue Glow - početak
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFF12D8FA), // Neon Blue Glow - sredina
  onTertiaryContainer: Colors.white,

  // Surface colors - svetla pozadina
  surface: Color(0xFFF0F9FF), // Svetla pozadina
  onSurface: Color(0xFF1A1A1A),
  surfaceContainerHighest: Color(0xFFE0F2FE),
  onSurfaceVariant: Color(0xFF4B5563),

  outline: Color(0xFF6B7280),
  outlineVariant: Color(0xFFD1D5DB),

  // Error colors
  error: Color(0xFFEF4444),
  onError: Colors.white,
  errorContainer: Color(0xFFFEF2F2),
  onErrorContainer: Color(0xFF991B1B),
);

// DARK STEEL GREY - Sive boje umesto plavih!
const ColorScheme darkSteelGreyColorScheme = ColorScheme(
  brightness: Brightness.dark,
  // Steel Grey kao glavni - sive boje
  primary: Color(0xFF404040), // Srednja siva
  onPrimary: Colors.white,
  primaryContainer: Color(0xFF6A6A6A), // Svetlija siva
  onPrimaryContainer: Colors.white,

  // Dark Steel Grey kao secondary
  secondary: Color(0xFF2C2C2C), // Tamno siva
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFF8A8A8A), // Najsvetlija siva
  onSecondaryContainer: Colors.white,

  // Metallic Grey kao tertiary
  tertiary: Color(0xFF606060), // Srednje-svetla siva
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFF9A9A9A), // Svetla siva
  onTertiaryContainer: Colors.white,

  // Surface colors - tamne pozadine
  surface: Color(0xFF1A1A1A), // Tamna pozadina
  onSurface: Colors.white,
  surfaceContainerHighest: Color(0xFF2A2A2A),
  onSurfaceVariant: Color(0xFFB4B4B4),

  outline: Color(0xFF6A6A6A),
  outlineVariant: Color(0xFF404040),

  // Error colors - iste kao plava tema
  error: Color(0xFFEF4444),
  onError: Colors.white,
  errorContainer: Color(0xFFFEF2F2),
  onErrorContainer: Color(0xFF991B1B),
);

// CUSTOM COLOR EXTENSIONS za dodatne boje
extension CustomColors on ColorScheme {
  // Success Colors
  Color get successPrimary => const Color(0xFF4CAF50);

  // Danger Colors
  Color get dangerPrimary => const Color(0xFFEF5350);
}

// Triple Blue Fashion Gradient - 5 boja!
const LinearGradient tripleBlueFashionGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF0575E6), // Electric Blue Shine - završetak
    Color(0xFF1E3A78), // Blue Ice Metallic - početak
    Color(0xFF4F7CAC), // Blue Ice Metallic - sredina
    Color(0xFFA8D8E8), // Blue Ice Metallic - završetak
    Color(0xFF12D8FA), // Neon Blue Glow - sredina
  ],
  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
);

// Dark Steel Grey Gradient - SAMO GRADIJENT!
const LinearGradient darkSteelGreyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF4A4A4A), // Srednja siva - početak svetliji
    Color(0xFF1A1A1A), // Tamna siva
    Color(0xFF3A3A3A), // Srednja siva
    Color(0xFF6A6A6A), // Svetlija siva
    Color(0xFF9A9A9A), // Najsvetlija siva - neon efekat
  ],
  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
);

// PASSIONATE ROSE GRADIENT - Electric Red + Ruby + Crimson + Pink Ice + Neon Rose!
const LinearGradient passionateRoseGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFDC143C), // Crimson - početak svetliji
    Color(0xFF8B0000), // Dark Red
    Color(0xFFB22222), // Ruby Metallic
    Color(0xFFFF69B4), // Pink Ice Glow
    Color(0xFFFFC0CB), // Neon Rose Shine
  ],
  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
);

// DARK PINK GRADIENT - Tamna sa neon pink akcentima!
const LinearGradient darkPinkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF8B2F6B), // Rich pink - početak svetliji
    Color(0xFF1A0A14), // Skoro crna sa pink undertone
    Color(0xFF4A1942), // Deep magenta
    Color(0xFF9B4F8B), // Lighter pink
    Color(0xFFE91E8C), // Neon pink akcent
  ],
  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
);

// PASSIONATE ROSE COLOR SCHEME
const ColorScheme passionateRoseColorScheme = ColorScheme(
  brightness: Brightness.light,

  // Crimson kao glavni
  primary: Color(0xFFDC143C), // Crimson
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFFF69B4), // Pink Ice Glow
  onPrimaryContainer: Colors.white,

  // Dark Red kao secondary
  secondary: Color(0xFF8B0000), // Dark Red
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFB22222), // Ruby Metallic
  onSecondaryContainer: Colors.white,

  // Light pink kao tertiary
  tertiary: Color(0xFFFFC0CB), // Light pink
  onTertiary: Color(0xFF8B0000),
  tertiaryContainer: Color(0xFFFFE4E1), // Misty Rose
  onTertiaryContainer: Color(0xFF8B0000),

  // Svetle površine
  surface: Color(0xFFFFF8F9), // Skoro bela sa pink odsjajem
  onSurface: Color(0xFF1A1A1A),
  surfaceContainerHighest: Color(0xFFFFE4E1), // Misty Rose
  onSurfaceVariant: Color(0xFF8B5A5A),

  outline: Color(0xFFDC143C),
  outlineVariant: Color(0xFFFFB6C1), // Light Pink

  error: Color(0xFFEF4444),
  onError: Colors.white,
  errorContainer: Color(0xFFFEF2F2),
  onErrorContainer: Color(0xFF991B1B),
);

// DARK PINK COLOR SCHEME
const ColorScheme darkPinkColorScheme = ColorScheme(
  brightness: Brightness.dark,

  // Neon Pink kao glavni
  primary: Color(0xFFE91E8C), // Neon pink
  onPrimary: Colors.white,
  primaryContainer: Color(0xFF8B2F6B), // Deep pink
  onPrimaryContainer: Colors.white,

  // Magenta kao secondary
  secondary: Color(0xFF4A1942), // Deep magenta
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFFF69B4), // Hot pink
  onSecondaryContainer: Color(0xFF1A0A14),

  // Light pink kao tertiary
  tertiary: Color(0xFFFFC0CB), // Light pink
  onTertiary: Color(0xFF1A0A14),
  tertiaryContainer: Color(0xFFFFB6C1), // Baby pink
  onTertiaryContainer: Color(0xFF1A0A14),

  // Tamne površine
  surface: Color(0xFF1A0A14), // Skoro crna
  onSurface: Colors.white,
  surfaceContainerHighest: Color(0xFF2D1F2D),
  onSurfaceVariant: Color(0xFFE8B4D0), // Svetlo pink tekst

  outline: Color(0xFF8B2F6B),
  outlineVariant: Color(0xFF4A1942),

  error: Color(0xFFFF4444),
  onError: Colors.white,
  errorContainer: Color(0xFF3D0A0A),
  onErrorContainer: Color(0xFFFF8888),
);

// TEMA EKSTENZIJA - dodaje gradijent pozadinu
extension ThemeGradients on ThemeData {
  LinearGradient get backgroundGradient => V2ThemeManager().currentGradient;

  // Glassmorphism kontejner boje
  Color get glassContainer => Colors.transparent;
  Color get glassBorder => Colors.white.withOpacity(0.13);
}

// Triple Blue Fashion Theme
final ThemeData tripleBlueFashionTheme = ThemeData(
  colorScheme: tripleBlueFashionColorScheme,
  useMaterial3: true,
  fontFamily: 'Inter', // Primarni font sa podrškom za latin-ext
  textTheme: createSerbianTextTheme(), // SRPSKA DJAKRITIKA PODRŠKA
  scaffoldBackgroundColor: const Color(0xFFF0F9FF),
  appBarTheme: AppBarTheme(
    elevation: 0,
    backgroundColor: const Color(0xFF021B79), // Originalna tamna Electric Blue boja
    foregroundColor: Colors.white,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: SerbianTextStyle.create(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
);

// Triple Blue Fashion Styles - OSVETLJENI!
class TripleBlueFashionStyles {
  static BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      width: 2,
      color: const Color(0xFF1FA2FF).withOpacity(0.4),
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF021B79).withOpacity(0.3),
        blurRadius: 32,
        offset: const Offset(0, 12),
        spreadRadius: 4,
      ),
      BoxShadow(
        color: const Color(0xFF4F7CAC).withOpacity(0.2),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: const Color(0xFFE91E63).withOpacity(0.4),
        blurRadius: 36,
        offset: const Offset(0, 16),
        spreadRadius: 6,
      ),
    ],
  );

  static BoxDecoration gradientBackground = const BoxDecoration(
    gradient: tripleBlueFashionGradient,
  );

  static BoxDecoration gradientButton = BoxDecoration(
    gradient: tripleBlueFashionGradient,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      width: 1.5,
      color: const Color(0xFF1FA2FF).withOpacity(0.6),
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF021B79).withOpacity(0.4),
        blurRadius: 24,
        offset: const Offset(0, 12),
        spreadRadius: 2,
      ),
    ],
  );

  static BoxDecoration dropdownDecoration = BoxDecoration(
    color: const Color(0xFFF0F9FF), // Svetla pozadina
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: const Color(0xFF1FA2FF).withOpacity(0.4), // Plavi border
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF021B79).withOpacity(0.2), // Plava senka
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration popupDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: const Color(0xFF1FA2FF).withOpacity(0.5), // Plavi border
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF021B79).withOpacity(0.3), // Plava senka
        blurRadius: 36,
        offset: const Offset(0, 16),
        spreadRadius: 8,
      ),
    ],
  );
}

// Dark Steel Grey Styles - BEZ SHADOW-A!
class DarkSteelGreyStyles {
  static BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      width: 2,
      color: Colors.grey.withOpacity(0.4), // Siva boja umesto plave
    ),
    // BEZ SHADOW-A!
  );

  static BoxDecoration gradientBackground = const BoxDecoration(
    gradient: darkSteelGreyGradient,
  );

  static BoxDecoration gradientButton = BoxDecoration(
    gradient: darkSteelGreyGradient,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      width: 1.5,
      color: Colors.grey.withOpacity(0.6), // Siva boja umesto plave
    ),
    // BEZ SHADOW-A!
  );

  static BoxDecoration dropdownDecoration = BoxDecoration(
    color: Colors.grey[800], // Tamno siva pozadina
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: Colors.grey.withOpacity(0.4), // Siva boja umesto plave
      width: 1.5,
    ),
    // BEZ SHADOW-A!
  );

  static BoxDecoration popupDecoration = BoxDecoration(
    color: Colors.grey[900], // Tamno siva pozadina
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Colors.grey.withOpacity(0.5), // Siva boja umesto plave
      width: 2,
    ),
    // BEZ SHADOW-A!
  );
}

// Dark Pink Styles - Tamna sa neon pink akcentima!
class DarkPinkStyles {
  static BoxDecoration cardDecoration = BoxDecoration(
    color: const Color(0xFF2D1F2D), // Tamno ljubičasta pozadina
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      width: 2,
      color: const Color(0xFFE91E8C).withOpacity(0.5), // Neon pink border
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFE91E8C).withOpacity(0.3), // Pink glow
        blurRadius: 24,
        offset: const Offset(0, 8),
        spreadRadius: 2,
      ),
    ],
  );

  static BoxDecoration gradientBackground = const BoxDecoration(
    gradient: darkPinkGradient,
  );

  static BoxDecoration gradientButton = BoxDecoration(
    gradient: darkPinkGradient,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      width: 1.5,
      color: const Color(0xFFE91E8C).withOpacity(0.6), // Neon pink border
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFE91E8C).withOpacity(0.4), // Pink glow
        blurRadius: 20,
        offset: const Offset(0, 8),
        spreadRadius: 2,
      ),
    ],
  );

  static BoxDecoration dropdownDecoration = BoxDecoration(
    color: const Color(0xFF2D1F2D), // Tamno ljubičasta pozadina
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: const Color(0xFFE91E8C).withOpacity(0.4), // Pink border
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFE91E8C).withOpacity(0.2), // Pink glow
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration popupDecoration = BoxDecoration(
    color: const Color(0xFF1A0A14), // Skoro crna pozadina
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: const Color(0xFFE91E8C).withOpacity(0.5), // Pink border
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFE91E8C).withOpacity(0.3), // Pink glow
        blurRadius: 32,
        offset: const Offset(0, 12),
        spreadRadius: 4,
      ),
    ],
  );
}

// PASSIONATE ROSE Styles - Crvena/ružičasta sa klasičnim sjajom!
class PassionateRoseStyles {
  static BoxDecoration cardDecoration = BoxDecoration(
    color: const Color(0xFFFFF8F9), // Skoro bela sa pink odsjajem
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      width: 2,
      color: const Color(0xFFDC143C).withOpacity(0.4), // Crimson border
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFDC143C).withOpacity(0.3), // Crimson glow
        blurRadius: 32,
        offset: const Offset(0, 12),
        spreadRadius: 4,
      ),
      BoxShadow(
        color: const Color(0xFFFF69B4).withOpacity(0.2), // Pink glow
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration gradientBackground = const BoxDecoration(
    gradient: passionateRoseGradient,
  );

  static BoxDecoration gradientButton = BoxDecoration(
    gradient: passionateRoseGradient,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      width: 1.5,
      color: const Color(0xFFDC143C).withOpacity(0.6), // Crimson border
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFDC143C).withOpacity(0.4), // Crimson glow
        blurRadius: 24,
        offset: const Offset(0, 12),
        spreadRadius: 2,
      ),
    ],
  );

  static BoxDecoration dropdownDecoration = BoxDecoration(
    color: const Color(0xFFFFF8F9), // Skoro bela pozadina
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: const Color(0xFFDC143C).withOpacity(0.4), // Crimson border
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFDC143C).withOpacity(0.2), // Crimson glow
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration popupDecoration = BoxDecoration(
    color: Colors.white, // Bela pozadina
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: const Color(0xFFDC143C).withOpacity(0.5), // Crimson border
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFDC143C).withOpacity(0.3), // Crimson glow
        blurRadius: 36,
        offset: const Offset(0, 16),
        spreadRadius: 8,
      ),
    ],
  );
}
