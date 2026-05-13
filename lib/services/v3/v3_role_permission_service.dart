import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _pushPromptedKey = 'v3_perm_push_prompted_v2';
  static const String _notifListenerPromptedKey = 'v3_perm_notif_listener_prompted_v1';

  static const MethodChannel _wakelockChannel = MethodChannel('com.gavra013.gavra_android/wakelock');

  // ─────────────────────────────────────────────────────────────────────
  // Javni API
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> ensureDriverPermissionsOnLogin() async {
    await _requestCommonPermissions();
  }

  static Future<void> ensurePassengerPermissionsOnLogin() async {
    await _requestCommonPermissions();
  }

  /// Zajedničke dozvole za SVE korisnike (vozači + putnici).
  static Future<void> _requestCommonPermissions() async {
    await _requestPushOnce(_pushPromptedKey);
    await _requestNotifListenerOnce();
  }

  /// Poziva se pretežno iz FCM / Firebase push handlera
  /// da probudi ekran na dolaznu notifikaciju (8 sekundi).
  static Future<void> wakeScreenOnPush({int durationMs = 8000}) async {
    if (!Platform.isAndroid) return;
    try {
      await _wakelockChannel.invokeMethod<bool>(
        'wakeScreen',
        {'duration': durationMs},
      );
    } catch (e) {
      debugPrint('[Permissions] wakeScreenOnPush greška: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Privatne metode
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> _requestPushOnce(String key) async {
    // Na iOS-u dozvole imaju stanja koja direktno možemo proveravati (i tražiti iznova ako nije određeno).
    // Za one koji su već "denied" (odbijeni), moramo im izbaciti sistemski upit ili obavestiti.
    if (Platform.isIOS) {
      try {
        var settings = await FirebaseMessaging.instance.getNotificationSettings();

        if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
          settings = await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
          debugPrint('[Permissions][iOS] Push tražen, status: ${settings.authorizationStatus}');
        } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('[Permissions][iOS] Dozvola odbijena. Možemo baciti popup ka settingsima.');
          // Ovde možemo naknadno otvoriti podešavanja aplikacije, a za sad radimo request permission bez provisiona
          settings = await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
        } else {
          debugPrint('[Permissions][iOS] Push dozvola već postoji: ${settings.authorizationStatus}');
        }
      } catch (e) {
        debugPrint('[Permissions][iOS] Push dozvola greška: $e');
      }
      return;
    }

    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[Permissions] Push dozvola greška: $e');
    }
  }

  /// Traži NotificationListenerService dozvolu jednom po instalaciji.
  /// Ova dozvola se ne može tražiti runtime API-jem — otvara se Settings ekran.
  /// Korisnik mora ručno da je odobri u:
  ///   Settings → Apps → Special App Access → Notification Access → Gavra 013
  static Future<void> _requestNotifListenerOnce() async {
    if (!Platform.isAndroid) return;

    final alreadyPrompted = await _storage.read(key: _notifListenerPromptedKey) == 'true';
    if (alreadyPrompted) return;

    try {
      // Provjeri da li je dozvola već odobrena
      final granted = await _isNotifListenerGranted();
      if (!granted) {
        // Otvori Settings ekran za Notification Access
        await _wakelockChannel.invokeMethod<void>('openNotifListenerSettings').catchError((_) async {
          // Fallback: permission_handler openAppSettings ako native metoda ne postoji
          await openAppSettings();
        });
        debugPrint('[Permissions] Notification listener Settings otvoren.');
      } else {
        debugPrint('[Permissions] Notification listener već odobren.');
      }
    } catch (e) {
      debugPrint('[Permissions] NotifListener prompt greška: $e');
    } finally {
      await _storage.write(key: _notifListenerPromptedKey, value: 'true');
    }
  }

  static Future<bool> _isNotifListenerGranted() async {
    try {
      final result = await _wakelockChannel.invokeMethod<bool>('isNotifListenerGranted');
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
