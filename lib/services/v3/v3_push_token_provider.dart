import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

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
  static const String _installationStorageKey = 'installation_device_id';
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
    final stored = (await _storage.read(key: _installationStorageKey) ?? '').trim();
    if (stored.isNotEmpty) return stored;

    final generated = const Uuid().v4();
    await _storage.write(key: _installationStorageKey, value: generated);
    return generated;
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
          return V3PushTokenResult(token: safeToken);
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

      // Ne gubimo puno vremena na APNs, ako postoji učita ga
      String? apnsToken;
      for (var attempt = 1; attempt <= 3; attempt++) {
        apnsToken = await messaging.getAPNSToken().timeout(const Duration(seconds: 2), onTimeout: () => null);
        if ((apnsToken ?? '').trim().isNotEmpty) break;
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      final safeApnsToken = (apnsToken ?? '').trim();
      if (safeApnsToken.isNotEmpty) {
        await _writeTokenSafely(_lastApnsTokenStorageKey, safeApnsToken);
      }

      // Prelazimo na dobavljanje Firebase tokena.
      // Ignorišemo greške APNs-a kakve god bile i probamo generisanje Firebase tokena
      String? token;
      for (var attempt = 1; attempt <= 3; attempt++) {
        token = await messaging.getToken().timeout(const Duration(seconds: 4), onTimeout: () => null);
        final safeToken = (token ?? '').trim();
        if (safeToken.isNotEmpty) {
          await _writeTokenSafely(_lastFcmTokenStorageKey, safeToken);
          return V3PushTokenResult(token: safeToken, apnsToken: safeApnsToken);
        }
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
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
