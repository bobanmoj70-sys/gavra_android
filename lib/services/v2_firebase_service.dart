import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/v2_vozac_cache.dart';
import 'v2_auth_manager.dart';
import 'v2_local_notification_service.dart';
import 'v2_push_token_service.dart';
import 'v2_realtime_notification_service.dart';

/// Top-level background handler — registruje se sa Firebase Messaging pluginom
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await backgroundNotificationHandler(message.data);
  } catch (e) {
    debugPrint('[V2FirebaseService] firebaseMessagingBackgroundHandler greška: $e');
  }
}

/// Provider-agnostic background notification handler
Future<void> backgroundNotificationHandler(Map<String, dynamic> payload) async {
  try {
    final title = payload['title'] as String? ?? 'Gavra Notification';
    final body = payload['body'] as String? ?? (payload['message'] as String?) ?? 'Nova notifikacija';
    await V2LocalNotificationService.showNotificationFromBackground(
      title: title,
      body: body,
      payload: jsonEncode(payload),
    );
  } catch (e) {
    debugPrint('[V2FirebaseService] backgroundNotificationHandler greška: $e');
  }
}

class V2FirebaseService {
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _onMessageSubscription;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  /// Inicijalizuje Firebase i registruje background handler
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) return;
      // Background Handler Registration
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[V2FirebaseService] initialize greška: $e');
    }
  }

  /// Dobija trenutnog vozaca — delegira na V2AuthManager
  static Future<String?> getCurrentDriver() => V2AuthManager.getCurrentDriver();

  /// Dobija FCM token
  static Future<String?> getFCMToken() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final messaging = FirebaseMessaging.instance;
      return await messaging.getToken();
    } catch (e) {
      debugPrint('[V2FirebaseService] getFCMToken greška: $e');
      return null;
    }
  }

  /// Registruje FCM token na server (push_tokens tabela)
  /// Ovo se mora pozvati pri pokretanju aplikacije
  static Future<String?> initializeAndRegisterToken() async {
    try {
      if (Firebase.apps.isEmpty) return null;

      final messaging = FirebaseMessaging.instance;

      // Request permission
      try {
        await messaging.requestPermission();
      } catch (e) {
        debugPrint('[V2FirebaseService] _registerTokenWithServer requestPermission greška: $e');
      }

      // Get token
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenWithServer(token);

        await _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
          (newToken) async {
            await _registerTokenWithServer(newToken);
          },
          onError: (error) {
            debugPrint('[V2FirebaseService] tokenRefresh onError: $error');
          },
        );

        return token;
      }

      return null;
    } catch (e) {
      debugPrint('[V2FirebaseService] initializeAndRegisterToken greška: $e');
      return null;
    }
  }

  /// Registruje FCM token u push_tokens tabelu
  /// Koristi unificirani PushTokenService
  static Future<void> _registerTokenWithServer(String token) async {
    String? driverName;
    String? putnikId;

    try {
      driverName = await V2AuthManager.getCurrentDriver();

      // Ako nije vozac, proveri da li je registrovani putnik
      if (driverName == null || driverName.isEmpty) {
        final secureStorage = FlutterSecureStorage();
        putnikId = await secureStorage.read(key: 'registrovani_putnik_id');
      }
    } catch (e) {
      debugPrint('[V2FirebaseService] _registerTokenWithServer dohvat vozaca greška: $e');
    }

    // Registruj ako imamo bilo koga
    try {
      if (driverName != null && driverName.isNotEmpty) {
        final vozacId = V2VozacCache.getUuidByIme(driverName);
        await V2PushTokenService.registerToken(
          token: token,
          provider: 'fcm',
          vozacId: vozacId,
        );
      } else if (putnikId != null && putnikId.isNotEmpty) {
        await V2PushTokenService.registerToken(
          token: token,
          provider: 'fcm',
          putnikId: putnikId,
        );
      } else {
        debugPrint('[V2FirebaseService] _registerTokenWithServer: nema ni vozaca ni putnika');
      }
    } catch (e) {
      debugPrint('[V2FirebaseService] _registerTokenWithServer greška: $e');
    }
  }

  /// Flag da sprecimo visestruko registrovanje FCM listenera
  static bool _fcmListenerRegistered = false;

  /// Postavlja FCM listenere
  static void setupFCMListeners() {
    // Sprecava visestruko registrovanje (duplirane notifikacije)
    if (_fcmListenerRegistered) return;

    // Firebase mora biti inicijalizovan — ako nije, ne postavljamo flag
    // da bismo mogli pokusati ponovo kad Firebase postane dostupan
    if (Firebase.apps.isEmpty) return;

    _fcmListenerRegistered = true;

    _onMessageSubscription = FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {
        // Emituj dogadjaj unutar aplikacije
        V2RealtimeNotificationService.onForegroundNotification(message.data);

        // Show a local notification when app is foreground
        try {
          // Prvo pokusaj notification payload, pa data payload
          final title = message.notification?.title ?? (message.data['title'] as String?) ?? 'Gavra Notification';
          final body = message.notification?.body ??
              (message.data['body'] as String?) ??
              (message.data['message'] as String?) ??
              'Nova notifikacija';
          V2LocalNotificationService.showRealtimeNotification(
              title: title, body: body, payload: message.data.isNotEmpty ? jsonEncode(message.data) : null);
        } catch (e) {
          debugPrint('[V2FirebaseService] setupFCMListeners onMessage greška: $e');
        }
      },
      onError: (error) {
        debugPrint('[V2FirebaseService] setupFCMListeners onMessage onError: $error');
      },
    );

    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) {
        try {
          // Navigate or handle tap
          V2RealtimeNotificationService.handleInitialMessage(message.data);
        } catch (e) {
          debugPrint('[V2FirebaseService] setupFCMListeners onMessageOpenedApp greška: $e');
        }
      },
      onError: (error) {
        debugPrint('[V2FirebaseService] setupFCMListeners onMessageOpenedApp onError: $error');
      },
    );
  }

  /// Otkazuje sve aktivne FCM stream subscriptions
  static Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    await _onMessageOpenedAppSubscription?.cancel();
    _onMessageOpenedAppSubscription = null;
    _fcmListenerRegistered = false;
  }
}
