import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/app_platform.dart';
import 'v3_device_identity_service.dart';

class V3PushTokenResult {
  final String token;
  final String? installationId;
  final String? apnsToken;
  final String provider; // 'fcm' ili 'hms'

  const V3PushTokenResult({
    required this.token,
    this.installationId,
    this.apnsToken,
    this.provider = 'fcm',
  });
}

/// Single FCM token source for Android + iOS via [FirebaseMessaging.getToken].
class V3PushTokenProvider {
  V3PushTokenProvider._();

  static const MethodChannel _channel = MethodChannel(AppPlatform.pushTokenChannel);
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const String _lastFcmTokenStorageKey = 'v3_last_known_fcm_token';
  static const String _lastApnsTokenStorageKey = 'v3_last_known_apns_token';
  static const String _lastHmsTokenStorageKey = 'v3_last_known_hms_token';

  static Future<V3PushTokenResult?> getBestToken() async {
    if (!Platform.isAndroid) {
      final result = await _tryGetFcmToken();
      final fcmToken = result?.token ?? '';
      if (fcmToken.isNotEmpty) {
        final installationId = await getInstallationId();
        return V3PushTokenResult(
          token: fcmToken,
          installationId: installationId,
          apnsToken: result?.apnsToken,
          provider: 'fcm',
        );
      }
      return null;
    }

    // Android: prvo pokušaj FCM ako je GMS dostupan
    final gmsAvailable = await _isGmsAvailable();
    if (gmsAvailable) {
      final result = await _tryGetFcmToken();
      final fcmToken = result?.token ?? '';
      if (fcmToken.isNotEmpty) {
        final installationId = await getInstallationId();
        return V3PushTokenResult(
          token: fcmToken,
          installationId: installationId,
          apnsToken: result?.apnsToken,
          provider: 'fcm',
        );
      }
    }

    // Android bez GMS: pokušaj HMS
    final hmsToken = await _tryGetHmsToken();
    if (hmsToken != null && hmsToken.isNotEmpty) {
      final installationId = await getInstallationId();
      return V3PushTokenResult(
        token: hmsToken,
        installationId: installationId,
        provider: 'hms',
      );
    }

    // Fallback na poslednji poznati FCM token
    final result = await _fallbackToken();
    if (result != null) {
      final installationId = await getInstallationId();
      return V3PushTokenResult(
        token: result.token,
        installationId: installationId,
        apnsToken: result.apnsToken,
        provider: 'fcm',
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

    return _fetchFcmToken(isIos: false);
  }

  static Future<bool> _isGmsAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final available = await _channel
          .invokeMethod<bool>(AppPlatform.methodIsGmsAvailable)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      return available == true;
    } catch (e) {
      debugPrint('[PushTokenProvider] isGmsAvailable failed: $e');
      return false;
    }
  }

  static Future<String?> _tryGetHmsToken() async {
    if (!Platform.isAndroid) return null;
    try {
      final token = await _channel
          .invokeMethod<String>('getHmsPushToken')
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      final safeToken = (token ?? '').trim();
      if (safeToken.isNotEmpty) {
        await _writeTokenSafely(_lastHmsTokenStorageKey, safeToken);
        debugPrint('[PushTokenProvider] HMS token obtained: ${safeToken.substring(0, 8)}...');
        return safeToken;
      }
      return null;
    } catch (e) {
      debugPrint('[PushTokenProvider] HMS token unavailable: $e');
      return null;
    }
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
        // Permission UI is owned by V3RolePermissionService — here only token fetch.
        // getToken() na iOS baca ako APNs još nije stigao.
        final resolvedApns = await _waitForApnsToken(messaging);
        if (resolvedApns == null || resolvedApns.isEmpty) {
          debugPrint('[PushTokenProvider] APNs token not ready — skip FCM getToken.');
          return _fallbackToken(isIos: true);
        }
        apnsToken = resolvedApns;
      }

      final tokenTimeout = isIos ? const Duration(seconds: 12) : const Duration(seconds: 8);
      final token = await messaging.getToken().timeout(tokenTimeout, onTimeout: () => null);
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

  static Future<String?> _waitForApnsToken(FirebaseMessaging messaging) async {
    const delaysMs = <int>[0, 300, 500, 800, 1200, 1500, 2000];
    for (final delayMs in delaysMs) {
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      try {
        final rawApns = await messaging.getAPNSToken().timeout(
              const Duration(seconds: 1),
              onTimeout: () => null,
            );
        final safeApns = (rawApns ?? '').trim();
        if (safeApns.isNotEmpty) {
          await _writeTokenSafely(_lastApnsTokenStorageKey, safeApns);
          return safeApns;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<V3PushTokenResult?> _fallbackToken({bool isIos = false}) async {
    // Prvo pokušaj HMS fallback za Android
    if (!isIos && Platform.isAndroid) {
      final hmsFallback = (await _storage.read(key: _lastHmsTokenStorageKey) ?? '').trim();
      if (hmsFallback.isNotEmpty) {
        debugPrint('[PushTokenProvider] Using last known HMS token fallback.');
        return V3PushTokenResult(
          token: hmsFallback,
          provider: 'hms',
        );
      }
    }

    final fallbackToken = (await _storage.read(key: _lastFcmTokenStorageKey) ?? '').trim();
    if (fallbackToken.isEmpty) return null;
    debugPrint('[PushTokenProvider] Using last known FCM token fallback.');
    final apns = isIos ? (await _storage.read(key: _lastApnsTokenStorageKey) ?? '').trim() : '';
    return V3PushTokenResult(
      token: fallbackToken,
      apnsToken: apns.isEmpty ? null : apns,
      provider: 'fcm',
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
