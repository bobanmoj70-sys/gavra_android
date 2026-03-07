import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Haptic feedback servis za tactile response
class V2HapticService {
  V2HapticService._();

  /// Light impact - za obicne tap-ove
  static void lightImpact() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Medium impact - za vaznije akcije
  static void mediumImpact() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Heavy impact - za kriticne akcije
  static void heavyImpact() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Selection click - za picker wheel i slicno
  static void selectionClick() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Success feedback - dupli light impact (bip-bip)
  static void success() {
    try {
      HapticFeedback.lightImpact();
      unawaited(
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            HapticFeedback.lightImpact();
          } catch (_) {}
        }),
      );
    } catch (_) {}
  }

  /// Error feedback - za greske
  static void error() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Jaca vibracija kad se V2Putnik pokupi — dva kratka pulsa (150ms + 150ms)
  static Future<void> putnikPokupljen() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Dva kratka pulsa - "bip-bip" efekat
        await Vibration.vibrate(pattern: [0, 150, 100, 150], intensities: [0, 255, 0, 255]);
      } else {
        // Fallback na haptic feedback
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      // Fallback
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }
}

/// Elevated button sa haptic feedback-om
class V2HapticElevatedButton extends StatelessWidget {
  const V2HapticElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.hapticType = HapticType.light,
    this.style,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final HapticType hapticType;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: style,
      onPressed: onPressed == null
          ? null
          : () {
              switch (hapticType) {
                case HapticType.light:
                  V2HapticService.lightImpact();
                case HapticType.medium:
                  V2HapticService.mediumImpact();
                case HapticType.heavy:
                  V2HapticService.heavyImpact();
                case HapticType.selection:
                  V2HapticService.selectionClick();
                case HapticType.success:
                  V2HapticService.success();
                case HapticType.error:
                  V2HapticService.error();
              }
              onPressed!();
            },
      child: child,
    );
  }
}

/// Tipovi haptic feedback-a
enum HapticType {
  light,
  medium,
  heavy,
  selection,
  success,
  error,
}
