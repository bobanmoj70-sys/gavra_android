import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/v2_vozac_cache.dart';
import 'v2_auth_manager.dart';
import 'v2_local_notification_service.dart';
import 'v2_push_token_service.dart';
import 'v2_realtime_notification_service.dart';

/// Top-level background handler — registruje se sa Firebase Messaging pluginom
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final payload = Map<String, dynamic>.from(message.data);
    await backgroundNotificationHandler(payload);
  } catch (e) {
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
  }
}

class V2FirebaseService {
  static String? _currentDriver;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  /// Inicijalizuje Firebase
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) return;

      final messaging = FirebaseMessaging.instance;

      // Background Handler Registration
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permission
      try {
        await messaging.requestPermission();
      } catch (e) {
      }
    } catch (e) {
    }
  }

  /// Dobija trenutnog vozaca - DELEGIRA NA V2AuthManager
  /// V2AuthManager cita iz Supabase (push_tokens tabela) kao izvor istine
  static Future<String?> getCurrentDriver() async {
    _currentDriver = await V2AuthManager.getCurrentDriver();
    return _currentDriver;
  }

  /// Postavlja trenutnog vozaca
  static Future<void> setCurrentDriver(String driver) async {
    _currentDriver = driver;
  }

  /// Brise trenutnog vozaca
  static Future<void> clearCurrentDriver() async {
    _currentDriver = null;
  }

  /// Dobija FCM token
  static Future<String?> getFCMToken() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final messaging = FirebaseMessaging.instance;
      return await messaging.getToken();
    } catch (e) {
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
          },
        );

        return token;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Registruje FCM token u push_tokens tabelu
  /// Koristi unificirani PushTokenService
  static Future<void> _registerTokenWithServer(String token) async {
    String? driverName;
    String? putnikId;
    String? putnikIme;

    try {
      driverName = await V2AuthManager.getCurrentDriver();

      // Ako nije vozac, proveri da li je V2Putnik
      if (driverName == null || driverName.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        // Ovi kljucevi se koriste u RegistrovaniPutnikProfilScreen za auto-login i identifikaciju
        // Moramo naci putnikId - obicno se dobija iz baze pri prijavi, ali ga mozemo kesirati
        putnikId = prefs.getString('registrovani_putnik_id');
        putnikIme = prefs.getString('registrovani_putnik_ime');
      }
    } catch (e) {
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
      }
    } catch (e) {
    }
  }

  /// Flag da sprecimo visestruko registrovanje FCM listenera
  static bool _fcmListenerRegistered = false;

  /// Postavlja FCM listener
  static void setupFCMListeners() {
    // Sprecava visestruko registrovanje (duplirane notifikacije)
    if (_fcmListenerRegistered) return;
    _fcmListenerRegistered = true;

    if (Firebase.apps.isEmpty) return;

    FirebaseMessaging.onMessage.listen(
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
        }
      },
      onError: (error) {
      },
    );

    FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) {
        try {
          // Navigate or handle tap
          V2RealtimeNotificationService.handleInitialMessage(message.data);
        } catch (e) {
        }
      },
      onError: (error) {
      },
    );
  }
}
