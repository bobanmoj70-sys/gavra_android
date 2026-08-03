import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Cross-platform haptic / vibration helpers.
class V3HapticService {
  V3HapticService._();

  static bool? _hasVibrator;

  static void lightImpact() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static void mediumImpact() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static void heavyImpact() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static void selectionClick() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  static void success() {
    try {
      unawaited(HapticFeedback.lightImpact());
      unawaited(
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            HapticFeedback.lightImpact();
          } catch (_) {}
        }),
      );
    } catch (_) {}
  }

  static void error() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Stronger pulse when a passenger is picked up.
  static Future<void> putnikPokupljen() async {
    try {
      _hasVibrator ??= await Vibration.hasVibrator();
      if (_hasVibrator == true) {
        await Vibration.vibrate(
          pattern: [0, 150, 100, 150],
          intensities: [0, 255, 0, 255],
        );
      } else {
        unawaited(HapticFeedback.heavyImpact());
      }
    } catch (_) {
      try {
        unawaited(HapticFeedback.heavyImpact());
      } catch (_) {}
    }
  }
}
