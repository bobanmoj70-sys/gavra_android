import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Single source of truth for cross-platform app identity and native bridges.
///
/// Store IDs differ by design (Play vs App Store history) — never "unify" them
/// without a coordinated store migration. Dart + Kotlin channel names must match.
class AppPlatform {
  AppPlatform._();

  static const String displayName = 'Gavra 013';

  /// Android applicationId / namespace (Play Store).
  static const String androidApplicationId = 'com.gavra013.gavra_android';

  /// iOS PRODUCT_BUNDLE_IDENTIFIER (App Store).
  static const String iosBundleId = 'com.gavra013.gavra013ios';

  /// Custom URL scheme (Android intent-filter + iOS CFBundleURLTypes).
  static const String urlScheme = 'gavra';

  /// OSM / flutter_map User-Agent — use the running platform's store id.
  static String get mapUserAgentPackageName => !kIsWeb && Platform.isIOS ? iosBundleId : androidApplicationId;

  // ── Native MethodChannels (Android MainActivity only; iOS uses plugins) ──

  static const String wakelockChannel = 'com.gavra013.gavra_android/wakelock';
  static const String pushTokenChannel = 'com.gavra013.gavra_android/push_token';

  static const String methodWakeScreen = 'wakeScreen';
  static const String methodReleaseWakeLock = 'releaseWakeLock';
  static const String methodIsGmsAvailable = 'isGmsAvailable';
  static const String methodGetAndroidId = 'getAndroidId';
}
