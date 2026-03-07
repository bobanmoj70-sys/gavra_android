import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:huawei_push/huawei_push.dart';

import '../utils/v2_vozac_cache.dart';
import 'v2_auth_manager.dart';
import 'v2_local_notification_service.dart';
import 'v2_push_token_service.dart';
import 'v2_realtime_notification_service.dart';

/// Lightweight wrapper around the `huawei_push` plugin.
///
/// Responsibilities:
/// - initialize HMS runtime hooks
/// - obtain device token (HMS) and register it with the backend (via Supabase function)
/// - listen for incoming push messages and display local notifications
class V2HuaweiPushService {
  static final V2HuaweiPushService _instance = V2HuaweiPushService._internal();
  factory V2HuaweiPushService() => _instance;
  V2HuaweiPushService._internal();

  StreamSubscription<String?>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  bool _messageListenerRegistered = false;
  String? _currentToken;

  // Zastita od visestrukog pozivanja
  bool _initialized = false;
  bool _initializing = false;

  /// Dohvati trenutni HMS token ako postoji
  Future<String?> getHMSToken() async {
    if (_currentToken != null && _currentToken!.isNotEmpty) {
      return _currentToken;
    }
    // Ako nemamo token, pokušaj ponovo inicijalizaciju (koja vraca token ako ga dobije brzo)
    return await initialize();
  }

  /// Initialize and request token. This method is safe to call even when
  /// HMS is not available on the device — it will simply return null.
  Future<String?> initialize() async {
    // iOS ne podrzava Huawei Push - preskoci
    if (Platform.isIOS) {
      return null;
    }

    // Provera da li je HMS dostupan (zastita od HMSSDK logova na non-Huawei uredajima)
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final manufacturer = androidInfo.manufacturer.toLowerCase();
        final brand = androidInfo.brand.toLowerCase();

        // Ako nije Huawei/Honor, preskacemo HMS inicijalizaciju
        if (!manufacturer.contains('huawei') &&
            !brand.contains('huawei') &&
            !manufacturer.contains('honor') &&
            !brand.contains('honor')) {
          _initialized = true;
          return null;
        }
      }
    } catch (e) {
      debugPrint('[V2HuaweiPushService] initialize deviceInfo greška: $e');
    }

    // Ako je vec inicijalizovan, vrati null
    if (_initialized) {
      return null;
    }

    // Ako je inicijalizacija u toku, sacekaj
    if (_initializing) {
      // Cekaj do 5 sekundi da se zavrsi tekuca inicijalizacija
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_initialized) return null;
      }
      return null;
    }

    _initializing = true;

    try {
      // a successful registration with Huawei HMS. The plugin APIs vary across
      // versions, so the stream-based approach is resilient.
      _tokenSub?.cancel();
      _tokenSub = Push.getTokenStream.listen(
        (String? newToken) async {
          if (newToken != null && newToken.isNotEmpty) {
            _currentToken = newToken;
            await _registerTokenWithServer(newToken);
          }
        },
        onError: (dynamic error) {
          // Token istekao ili nevazeci — zatrazi novi
          unawaited(Future.delayed(const Duration(seconds: 5), () => Push.getToken('HCM')));
        },
      );

      _setupMessageListener();

      // The plugin can return a token synchronously via `Push.getToken()` or
      // asynchronously via the `getTokenStream` — call both paths explicitly so
      // that we can log any token and register it immediately.
      // First, try to get token directly (synchronous return from SDK)
      try {
        // Read the App ID and AGConnect values from `agconnect-services.json`
        try {
          await Push.getAppId();
        } catch (e) {
          debugPrint('[V2HuaweiPushService] getAppId greška: $e');
        }

        try {
          await Push.getAgConnectValues();
        } catch (e) {
          debugPrint('[V2HuaweiPushService] getAgConnectValues greška: $e');
        }

        // Request the token explicitly: the Push.getToken requires a scope
        // parameter and does not return the token; the token is emitted on
        // Push.getTokenStream. Requesting the token explicitly increases the
        // chance of getting a token quickly.
        try {
          Push.getToken('HCM');
        } catch (e) {
          // If we get error 907135000, HMS is not available
          if (e.toString().contains('907135000')) {
            _initialized = true;
            _initializing = false;
            return null;
          }
        }
      } catch (e) {
        debugPrint('❌ [HuaweiPush] General error during token setup: $e');
      }

      // The plugin emits tokens asynchronously on the stream. Wait a short while for the first
      // non-null stream value so that initialization can report a token when
      // one is available immediately after startup.
      try {
        // Wait longer for the token to appear on the stream, as the SDK may
        // emit the token with a delay while contacting Huawei servers.
        // Timeout: 5 sekundi
        final firstValue = await Push.getTokenStream.first.timeout(const Duration(seconds: 5));
        if (firstValue.isNotEmpty) {
          _currentToken = firstValue;
          await _registerTokenWithServer(firstValue);
          _initialized = true;
          _initializing = false;
          return firstValue;
        } else {
          debugPrint('[V2HuaweiPushService] getTokenStream: prazan token');
        }
      } catch (e) {
        // If HMS is not available, don't keep trying
        if (e.toString().contains('907135000') || e.toString().contains('HMS')) {
          _initialized = true;
          _initializing = false;
          return null;
        }
        // No token arriving quickly — that's OK, the long-lived stream will
        // still handle tokens once they become available.
      }

      _initialized = true;
      _initializing = false;
      return null;
    } catch (e) {
      // Non-fatal: plugin may throw if not configured on device.
      _initializing = false;
      return null;
    }
  }

  /// Pokreni listener za dolazne Huawei push poruke
  void _setupMessageListener() {
    if (_messageListenerRegistered) return;
    _messageListenerRegistered = true;

    try {
      _messageSub?.cancel();
      _messageSub = Push.onMessageReceivedStream.listen((RemoteMessage message) async {
        try {
          // Emituj dogadjaj unutar aplikacije
          Map<String, dynamic> data = {};
          if (message.data != null) {
            try {
              data = jsonDecode(message.data!) as Map<String, dynamic>;
            } catch (_) {
              // Ako nije JSON, mozda je direktno mapa u nekoj verziji plugina
              // ali huawei_push obicno salje string
            }
          }

          V2RealtimeNotificationService.onForegroundNotification(data);

          // Get notification details
          final title = message.notification?.title ?? (data['title'] as String?) ?? 'Gavra Notification';
          final body = message.notification?.body ??
              (data['body'] as String?) ??
              (data['message'] as String?) ??
              'Nova notifikacija';

          // Prikazi lokalnu notifikaciju
          await V2LocalNotificationService.showRealtimeNotification(
            title: title,
            body: body,
            payload: jsonEncode(data),
          );
        } catch (e) {
          debugPrint('[V2HuaweiPushService] _setupMessageListener poruka greška: $e');
        }
      });
    } catch (e) {
      debugPrint('[V2HuaweiPushService] _setupMessageListener setup greška: $e');
    }
  }

  /// Registruje HMS token u push_tokens tabelu
  /// Koristi unificirani PushTokenService
  Future<void> _registerTokenWithServer(String token) async {
    String? driverName;
    try {
      driverName = await V2AuthManager.getCurrentDriver();
    } catch (e) {
      debugPrint('[V2HuaweiPushService] _registerTokenWithServer getCurrentDriver greška: $e');
      driverName = null;
    }

    // Registruj samo ako je vozac ulogovan
    if (driverName == null || driverName.isEmpty) {
      return;
    }

    try {
      await V2PushTokenService.registerToken(
        token: token,
        provider: 'huawei',
        vozacId: V2VozacCache.getUuidByIme(driverName),
      );
    } catch (e) {
      debugPrint('[V2HuaweiPushService] _registerTokenWithServer greška: $e');
    }
  }

  /// Pokušaj registracije pending tokena (ako postoji)
  Future<void> tryRegisterPendingToken() async {
    // Delegiraj na PushTokenService
    await V2PushTokenService.tryRegisterPendingToken();
  }
}
