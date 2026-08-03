import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'v3_device_identity_service.dart';

class V3PushTokenResult {
  final String token;
  final String? installationId;
  final String? apnsToken;

  const V3PushTokenResult({
    required this.token,
    this.installationId,
    this.apnsToken,
  });
}

/// Single FCM token source for Android + iOS via [FirebaseMessaging.getToken].
class V3PushTokenProvider {
  V3PushTokenProvider._();

  static const MethodChannel _channel = MethodChannel('com.gavra013.gavra_android/push_token');
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const String _lastFcmTokenStorageKey = 'v3_last_known_fcm_token';
  static const String _lastApnsTokenStorageKey = 'v3_last_known_apns_token';

  static Future<V3PushTokenResult?> getBestToken() async {
    final result = await _tryGetFcmToken();
    final fcmToken = result?.token ?? '';
    if (fcmToken.isNotEmpty) {
      final installationId = await getInstallationId();
      return V3PushTokenResult(
        token: fcmToken,
        installationId: installationId,
        apnsToken: result?.apnsToken,
      );
    }

    return null;
  }

  static Future<String?> getInstallationId() async {
    try {
      return await V3DeviceIdentityService.getStableDeviceId();
    } catch (e) {
      debugPrint('[V3PushTokenProvider] getInstallationId error: $e');
      return null;
    }
  }

  static Future<V3PushTokenResult?> _tryGetFcmToken() async {
    if (Platform.isIOS) {
      return _fetchFcmToken(isIos: true);
    }
    if (!Platform.isAndroid) return null;

    // Android without GMS cannot use FCM.
    try {
      final available = await _channel
          .invokeMethod<bool>('isGmsAvailable')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (available != true) {
        debugPrint('[PushTokenProvider] GMS unavailable — skip FCM token.');
        return _fallbackToken();
      }
    } catch (e) {
      debugPrint('[PushTokenProvider] isGmsAvailable failed: $e');
    }

    return _fetchFcmToken(isIos: false);
  }

  static Future<V3PushTokenResult?> _fetchFcmToken({required bool isIos}) async {
    try {
      await _ensureFirebaseInitialized();
      final messaging = FirebaseMessaging.instance;

      try {
        await messaging.setAutoInitEnabled(true);
      } catch (_) {}

      String? apnsToken;
      if (isIos) {
        try {
          var settings = await messaging.getNotificationSettings();
          if (settings.authorizationStatus == AuthorizationStatus.notDetermined ||
              settings.authorizationStatus == AuthorizationStatus.denied) {
            await messaging.requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );
          }
        } catch (_) {}

        final rawApns = await messaging.getAPNSToken().timeout(
              const Duration(seconds: 2),
              onTimeout: () => null,
            );
        final safeApns = (rawApns ?? '').trim();
        if (safeApns.isNotEmpty) {
          await _writeTokenSafely(_lastApnsTokenStorageKey, safeApns);
          apnsToken = safeApns;
        }
      }

      final timeout = isIos ? const Duration(seconds: 15) : const Duration(seconds: 8);
      final token = await messaging.getToken().timeout(timeout, onTimeout: () => null);
      final safeToken = (token ?? '').trim();
      if (safeToken.isNotEmpty) {
        await _writeTokenSafely(_lastFcmTokenStorageKey, safeToken);
        return V3PushTokenResult(token: safeToken, apnsToken: apnsToken);
      }

      return _fallbackToken(isIos: isIos);
    } catch (e) {
      debugPrint('[PushTokenProvider] FCM token unavailable (${isIos ? 'iOS' : 'Android'}): $e');
      return _fallbackToken(isIos: isIos);
    }
  }

  static Future<V3PushTokenResult?> _fallbackToken({bool isIos = false}) async {
    final fallbackToken = (await _storage.read(key: _lastFcmTokenStorageKey) ?? '').trim();
    if (fallbackToken.isEmpty) return null;
    debugPrint('[PushTokenProvider] Using last known FCM token fallback.');
    final apns = isIos ? (await _storage.read(key: _lastApnsTokenStorageKey) ?? '').trim() : '';
    return V3PushTokenResult(
      token: fallbackToken,
      apnsToken: apns.isEmpty ? null : apns,
    );
  }

  static Future<void> _writeTokenSafely(String key, String value) async {
    final safeValue = value.trim();
    if (safeValue.isEmpty) return;
    try {
      await _storage.write(key: key, value: safeValue);
    } catch (_) {}
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }
}
