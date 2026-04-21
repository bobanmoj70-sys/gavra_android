import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class V3PushTokenResult {
  final String token;

  const V3PushTokenResult({
    required this.token,
  });
}

class V3PushTokenProvider {
  V3PushTokenProvider._();

  static const MethodChannel _channel = MethodChannel('com.gavra013.gavra_android/push_token');

  static Future<V3PushTokenResult?> getBestToken() async {
    final fcmToken = await _tryGetFcmToken();
    if (fcmToken != null) {
      return V3PushTokenResult(token: fcmToken);
    }

    return null;
  }

  static Future<String?> _tryGetFcmToken() async {
    if (Platform.isIOS) {
      return _tryGetFcmTokenIos();
    }

    if (!Platform.isAndroid) return null;

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final available = await _channel
            .invokeMethod<bool>('isGmsAvailable')
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (available != true) return null;

        final token = await _channel
            .invokeMethod<String>('getFcmToken')
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
        final safeToken = (token ?? '').trim();
        if (safeToken.isNotEmpty) {
          return safeToken;
        }
      } catch (e) {
        debugPrint('[PushTokenProvider] Android FCM token unavailable (attempt=$attempt): $e');
      }

      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    return null;
  }

  static Future<String?> _tryGetFcmTokenIos() async {
    try {
      await _ensureFirebaseInitialized();

      final messaging = FirebaseMessaging.instance;
      final currentSettings = await messaging.getNotificationSettings().timeout(
            const Duration(seconds: 2),
          );

      NotificationSettings settings = currentSettings;

      if (currentSettings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await messaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(const Duration(seconds: 5));
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[PushTokenProvider] iOS permission denied for push notifications.');
        return null;
      }

      String? apnsToken;
      for (var attempt = 1; attempt <= 3; attempt++) {
        apnsToken = await messaging.getAPNSToken().timeout(const Duration(seconds: 2), onTimeout: () => null);
        if ((apnsToken ?? '').trim().isNotEmpty) break;
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }

      debugPrint('[PushTokenProvider] iOS APNs token present=${(apnsToken ?? '').isNotEmpty}');

      String? token;
      for (var attempt = 1; attempt <= 3; attempt++) {
        token = await messaging.getToken().timeout(const Duration(seconds: 3), onTimeout: () => null);
        final safeToken = (token ?? '').trim();
        if (safeToken.isNotEmpty) {
          return safeToken;
        }
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }

      final safeToken = (token ?? '').trim();
      return safeToken.isEmpty ? null : safeToken;
    } catch (e) {
      debugPrint('[PushTokenProvider] iOS FCM token unavailable: $e');
      return null;
    }
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }
}
