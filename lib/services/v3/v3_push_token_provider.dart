import 'dart:io';

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
    if (!Platform.isAndroid) return null;

    try {
      final available = await _channel.invokeMethod<bool>('isGmsAvailable');
      if (available != true) return null;

      final token = await _channel.invokeMethod<String>('getFcmToken');
      final safeToken = (token ?? '').trim();
      return safeToken.isEmpty ? null : safeToken;
    } catch (e) {
      debugPrint('[PushTokenProvider] FCM token unavailable: $e');
      return null;
    }
  }
}
