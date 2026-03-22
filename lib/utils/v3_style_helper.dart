import 'package:flutter/material.dart';

/// 🎖️💥 V3STYLEHELPER - MASOVNI DUPLIKATE ELIMINATOR! 💥🎖️
/// Konsoliduje sve BorderRadius, Colors, BoxDecoration duplikate
/// u jedinstvenu centralizovanu utility klasu
class V3StyleHelper {
  V3StyleHelper._();

  // ─── BORDER RADIUS KONSTANTE ───────────────────────────────────────────────

  static const BorderRadius radius4 = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radius8 = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radius10 = BorderRadius.all(Radius.circular(10));
  static const BorderRadius radius12 = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radius16 = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radius20 = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radius21 = BorderRadius.all(Radius.circular(21));
  static const BorderRadius radius24 = BorderRadius.all(Radius.circular(24));

  // ─── COLORS KONSTANTE ──────────────────────────────────────────────────────

  static Color get whiteAlpha05 => Colors.white.withValues(alpha: 0.05);
  static Color get whiteAlpha06 => Colors.white.withValues(alpha: 0.06);
  static Color get whiteAlpha07 => Colors.white.withValues(alpha: 0.07);
  static Color get whiteAlpha1 => Colors.white.withValues(alpha: 0.1);
  static Color get whiteAlpha13 => Colors.white.withValues(alpha: 0.13);
  static Color get whiteAlpha15 => Colors.white.withValues(alpha: 0.15);
  static Color get whiteAlpha2 => Colors.white.withValues(alpha: 0.2);
  static Color get whiteAlpha22 => Colors.white.withValues(alpha: 0.22);
  static Color get whiteAlpha25 => Colors.white.withValues(alpha: 0.25);
  static Color get whiteAlpha3 => Colors.white.withValues(alpha: 0.3);
  static Color get whiteAlpha4 => Colors.white.withValues(alpha: 0.4);
  static Color get whiteAlpha45 => Colors.white.withValues(alpha: 0.45);
  static Color get whiteAlpha5 => Colors.white.withValues(alpha: 0.5);
  static Color get whiteAlpha6 => Colors.white.withValues(alpha: 0.6);
  static Color get whiteAlpha65 => Colors.white.withValues(alpha: 0.65);
  static Color get whiteAlpha7 => Colors.white.withValues(alpha: 0.7);
  static Color get whiteAlpha75 => Colors.white.withValues(alpha: 0.75);
  static Color get whiteAlpha8 => Colors.white.withValues(alpha: 0.8);
  static Color get whiteAlpha9 => Colors.white.withValues(alpha: 0.9);

  // ─── COMMON BORDERS ────────────────────────────────────────────────────────

  static Border get whiteAlpha13Border => Border.all(color: whiteAlpha13);
  static Border get whiteAlpha15Border => Border.all(color: whiteAlpha15, width: 1.2);
  static Border get whiteAlpha2Border => Border.all(color: whiteAlpha2);
  static Border get whiteAlpha3Border => Border.all(color: whiteAlpha3, width: 1.2);
  static Border get whiteAlpha5Border => Border.all(color: whiteAlpha5, width: 1.5);

  // ─── COMMON BOXSHADOWS ─────────────────────────────────────────────────────

  static List<BoxShadow> get lightGlowShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get mediumGlowShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ];

  static List<BoxShadow> get heavyGlowShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          blurRadius: 16,
          spreadRadius: 1,
        ),
      ];

  // ─── PREDEFINED BOXDECORATIONS ─────────────────────────────────────────────

  /// Glassmorphism container decoration
  static BoxDecoration glassmorphismContainer({
    Color? backgroundColor,
    BorderRadius? borderRadius,
    Border? border,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? whiteAlpha06,
      borderRadius: borderRadius ?? radius20,
      border: border ?? whiteAlpha13Border,
      boxShadow: mediumGlowShadow,
    );
  }

  /// Standardna kartica decoration
  static BoxDecoration standardCard({
    Color? backgroundColor,
    BorderRadius? borderRadius,
    Border? border,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? Colors.white,
      borderRadius: borderRadius ?? radius16,
      border: border ?? Border.all(color: const Color(0xFFE0E0E0), width: 0.8),
      boxShadow: boxShadow ?? lightGlowShadow,
    );
  }

  /// Putnik kartica decoration - različiti statusi
  static BoxDecoration putnikCard({
    required String status,
    bool isPokupljen = false,
    bool isPlacen = false,
    Color? vozacBoja,
  }) {
    if (status == 'otkazano') {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFCDD2), Color(0xFFEF9A9A)],
        ),
        borderRadius: radius10,
        border: Border.all(color: const Color(0xFFE57373), width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }

    if (isPokupljen) {
      if (isPlacen) {
        return BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
          ),
          borderRadius: radius10,
          border: Border.all(color: const Color(0xFF81C784), width: 0.6),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        );
      }
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
        ),
        borderRadius: radius10,
        border: Border.all(color: const Color(0xFF64B5F6), width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }

    // Default - bijela kartica sa opcional vozac bojom
    if (vozacBoja != null) {
      final blendedColor = Color.lerp(Colors.white, vozacBoja, 0.20)!;
      return BoxDecoration(
        color: blendedColor,
        borderRadius: radius10,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.8),
        boxShadow: lightGlowShadow,
      );
    }

    return standardCard(borderRadius: radius10);
  }

  /// Admin raspored button decoration
  static BoxDecoration adminRasporedButton({
    required bool isSelected,
    required Color color,
  }) {
    return BoxDecoration(
      color: isSelected ? color.withValues(alpha: 0.25) : whiteAlpha07,
      borderRadius: radius12,
      border: Border.all(
        color: isSelected ? color : whiteAlpha15,
        width: 1.5,
      ),
    );
  }

  /// Update banner decoration
  static BoxDecoration updateBanner({
    bool isForced = false,
    List<Color>? gradientColors,
  }) {
    if (isForced) {
      return BoxDecoration(
        color: whiteAlpha06,
        borderRadius: radius24,
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.25),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      );
    }

    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors ??
            [
              const Color(0xFF1565C0),
              const Color(0xFF6A1B9A),
            ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: radius16,
      border: whiteAlpha15Border,
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1565C0).withValues(alpha: 0.5),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  /// Navigation bar time slot decoration
  static BoxDecoration timeSlotButton({
    required bool isSelected,
    required String currentThemeId,
    Color? vozacBoja,
  }) {
    Color backgroundColor;
    Color borderColor;

    if (isSelected) {
      switch (currentThemeId) {
        case 'dark_steel_grey':
          backgroundColor = const Color(0xFF4A4A4A);
          borderColor = const Color(0xFF4A4A4A);
          break;
        case 'passionate_rose':
          backgroundColor = const Color(0xFFDC143C);
          borderColor = const Color(0xFFDC143C);
          break;
        case 'dark_pink':
          backgroundColor = const Color(0xFFE91E8C);
          borderColor = const Color(0xFFE91E8C);
          break;
        default:
          backgroundColor = Colors.blue;
          borderColor = Colors.blue;
      }
    } else {
      backgroundColor = vozacBoja?.withValues(alpha: 0.1) ?? whiteAlpha15;
      borderColor = vozacBoja?.withValues(alpha: 0.3) ?? whiteAlpha3;
    }

    return BoxDecoration(
      color: backgroundColor,
      borderRadius: radius8,
      border: Border.all(color: borderColor),
    );
  }
}
