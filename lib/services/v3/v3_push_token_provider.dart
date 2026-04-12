import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum V3PushProvider { hms }

class V3PushTokenResult {
  final String token;
  final V3PushProvider provider;

  const V3PushTokenResult({
    required this.token,
    required this.provider,
  });
}

class V3PushTokenProvider {
  V3PushTokenProvider._();

  static const MethodChannel _channel = MethodChannel('com.gavra013.gavra_android/push_token');

  static Future<V3PushTokenResult?> getBestToken() async {
    final hmsToken = await _tryGetHmsToken();
    if (hmsToken != null) {
      return V3PushTokenResult(token: hmsToken, provider: V3PushProvider.hms);
    }

    return null;
  }

  static Future<String?> _tryGetHmsToken() async {
    if (!Platform.isAndroid) return null;

    try {
      final available = await _channel.invokeMethod<bool>('isHmsAvailable');
      if (available != true) return null;

      final token = await _channel.invokeMethod<String>('getHmsToken');
      final safeToken = (token ?? '').trim();
      return safeToken.isEmpty ? null : safeToken;
    } catch (e) {
      debugPrint('[PushTokenProvider] HMS token unavailable: $e');
      return null;
    }
  }

  static String providerAsString(V3PushProvider provider) {
    switch (provider) {
      case V3PushProvider.hms:
        return 'hms';
    }
  }
}
