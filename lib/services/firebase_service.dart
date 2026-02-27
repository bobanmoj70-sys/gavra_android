import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_manager.dart';
import 'firebase_background_handler.dart';
import 'v2_local_notification_service.dart';
import 'v2_realtime_notification_service.dart';
import 'v2_push_token_service.dart';

class FirebaseService {
  static String? _currentDriver;

  /// Inicijalizuje Firebase
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) return;

      final messaging = FirebaseMessaging.instance;

      // ðŸŒ™ Background Handler Registration
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permission
      try {
        await messaging.requestPermission();
      } catch (e) {
        debugPrint('âš ï¸ Error requesting FCM permission: $e');
      }
    } catch (e) {
      // IgnoriÅ¡i greÅ¡ke
    }
  }

  /// Dobija trenutnog vozaÄa - DELEGIRA NA AuthManager
  /// AuthManager Äita iz Supabase (push_tokens tabela) kao izvor istine
  static Future<String?> getCurrentDriver() async {
    _currentDriver = await AuthManager.getCurrentDriver();
    return _currentDriver;
  }

  /// Postavlja trenutnog vozaÄa
  static Future<void> setCurrentDriver(String driver) async {
    _currentDriver = driver;
  }

  /// BriÅ¡e trenutnog vozaÄa
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

  /// ðŸ“² Registruje FCM token na server (push_tokens tabela)
  /// Ovo se mora pozvati pri pokretanju aplikacije
  static Future<String?> initializeAndRegisterToken() async {
    try {
      if (Firebase.apps.isEmpty) return null;

      final messaging = FirebaseMessaging.instance;

      // Request permission
      try {
        await messaging.requestPermission();
      } catch (e) {
        debugPrint('âš ï¸ Error requesting FCM permission (init): $e');
      }

      // Get token
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenWithServer(token);

        // Listen for token refresh
        messaging.onTokenRefresh.listen(
          (newToken) async {
            await _registerTokenWithServer(newToken);
          },
          onError: (error) {
            debugPrint('ðŸ”´ [FirebaseService] Token refresh error: $error');
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
      driverName = await AuthManager.getCurrentDriver();

      // Ako nije vozaÄ, proveri da li je putnik
      if (driverName == null || driverName.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        // Ovi kljuÄevi se koriste u RegistrovaniPutnikProfilScreen za auto-login i identifikaciju
        // Moramo naÄ‡i putnikId - obiÄno se dobija iz baze pri prijavi, ali ga moÅ¾emo keÅ¡irati
        putnikId = prefs.getString('registrovani_putnik_id');
        putnikIme = prefs.getString('registrovani_putnik_ime');
      }
    } catch (e) {
      debugPrint('âš ï¸ Error getting current user for FCM: $e');
    }

    // Registruj ako imamo bilo koga
    if (driverName != null && driverName.isNotEmpty) {
      await V2PushTokenService.registerToken(
        token: token,
        provider: 'fcm',
        userType: 'vozac',
        userId: driverName,
      );
    } else if (putnikId != null && putnikId.isNotEmpty) {
      await V2PushTokenService.registerToken(
        token: token,
        provider: 'fcm',
        userType: 'putnik',
        userId: putnikIme,
        putnikId: putnikId,
      );
    } else {
      debugPrint('âš ï¸ [FirebaseService] Korisnik nije ulogovan - FCM token nije registrovan na serveru');
    }
  }

  /// ðŸ”’ Flag da spreÄimo viÅ¡estruko registrovanje FCM listenera
  static bool _fcmListenerRegistered = false;

  /// Postavlja FCM listener
  static void setupFCMListeners() {
    // âœ… SpreÄava viÅ¡estruko registrovanje (duplirane notifikacije)
    if (_fcmListenerRegistered) return;
    _fcmListenerRegistered = true;

    if (Firebase.apps.isEmpty) return;

    FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {
        // Emituj dogadjaj unutar aplikacije
        RealtimeNotificationService.onForegroundNotification(message.data);

        // Show a local notification when app is foreground
        try {
          // Prvo pokuÅ¡aj notification payload, pa data payload
          final title = message.notification?.title ?? message.data['title'] as String? ?? 'Gavra Notification';
          final body = message.notification?.body ??
              message.data['body'] as String? ??
              message.data['message'] as String? ??
              'Nova notifikacija';
          LocalNotificationService.showRealtimeNotification(
              title: title, body: body, payload: message.data.isNotEmpty ? jsonEncode(message.data) : null);
        } catch (_) {}
      },
      onError: (error) {
        debugPrint('ðŸ”´ [FirebaseService] onMessage stream error: $error');
      },
    );

    FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) {
        try {
          // Navigate or handle tap
          RealtimeNotificationService.handleInitialMessage(message.data);
        } catch (e) {
          debugPrint('ðŸ”´ [FirebaseService] onMessageOpenedApp error: $e');
        }
      },
      onError: (error) {
        debugPrint('ðŸ”´ [FirebaseService] onMessageOpenedApp stream error: $error');
      },
    );
  }
}


