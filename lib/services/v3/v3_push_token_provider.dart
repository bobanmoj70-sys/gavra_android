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
          await _writeTokenSafely(_lastFcmTokenStorageKey, safeToken);
          return V3PushTokenResult(token: safeToken);
        }
      } catch (e) {
        debugPrint('[PushTokenProvider] Android FCM token unavailable (attempt=$attempt): $e');
      }

      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    // Isti fallback kao na iOS-u: ako native poziv ne uspe, koristimo
    // poslednji poznati FCM token iz secure storage-a.
    final fallbackToken = (await _storage.read(key: _lastFcmTokenStorageKey) ?? '').trim();
    if (fallbackToken.isNotEmpty) {
      debugPrint('[PushTokenProvider] Android using last known FCM token fallback.');
      return V3PushTokenResult(token: fallbackToken);
    }

    return null;
  }

  static Future<V3PushTokenResult?> _tryGetFcmTokenIos() async {
    try {
      await _ensureFirebaseInitialized();

      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.setAutoInitEnabled(true);
        // Tražimo dozvolu direktno, u slučaju da već nije dodeljena kroz role permissions.
        var settings = await messaging.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.notDetermined ||
            settings.authorizationStatus == AuthorizationStatus.denied) {
          await messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false, // Bitno: tražimo punu dozvolu kako bi Apple generisao validan token ako već nije.
          );
        }
      } catch (_) {}

      // APNs token je best-effort samo za lokalni debug/log — ne blokiramo
      // (Firebase getToken() interno čeka APNs kada je to potrebno).
      final apnsToken = await messaging.getAPNSToken().timeout(const Duration(seconds: 2), onTimeout: () => null);
      final safeApnsToken = (apnsToken ?? '').trim();
      if (safeApnsToken.isNotEmpty) {
        await _writeTokenSafely(_lastApnsTokenStorageKey, safeApnsToken);
      }

      // Na svežem instalu APNs registracija ume da potraje, zato dajemo
      // getToken() dovoljno vremena (15s) umesto kratkog timeout-a.
      final token = await messaging.getToken().timeout(const Duration(seconds: 15), onTimeout: () => null);
      final safeToken = (token ?? '').trim();
      if (safeToken.isNotEmpty) {
        await _writeTokenSafely(_lastFcmTokenStorageKey, safeToken);
        return V3PushTokenResult(token: safeToken, apnsToken: safeApnsToken);
      }

      final fallbackToken = (await _storage.read(key: _lastFcmTokenStorageKey) ?? '').trim();
      if (fallbackToken.isNotEmpty) {
        debugPrint('[PushTokenProvider] iOS using last known FCM token fallback.');
        return V3PushTokenResult(token: fallbackToken, apnsToken: safeApnsToken);
      }

      return null;
    } catch (e) {
      debugPrint('[PushTokenProvider] iOS FCM token unavailable: $e');
      return null;
    }
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
