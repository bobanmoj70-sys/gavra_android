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
  static const String _locationPromptedKey = 'v3_perm_location_prompted_v1';

  static const MethodChannel _wakelockChannel = MethodChannel('com.gavra013.gavra_android/wakelock');

  // ─────────────────────────────────────────────────────────────────────
  // Javni API
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> ensureDriverPermissionsOnLogin() async {
    await _requestCommonPermissions();
    // GPS/lokacija + battery optimization SAMO za vozača — mora biti odobreno
    // UNAPRED (pri loginu) da bi tracking mogao da krene čim vozač otvori app.
    await _requestDriverLocationPermissions();
  }

  static Future<void> ensurePassengerPermissionsOnLogin() async {
    await _requestCommonPermissions();
  }

  /// Zajedničke dozvole za SVE korisnike (vozači + putnici).
  static Future<void> _requestCommonPermissions() async {
    await _requestPushOnce(_pushPromptedKey);
    // NotificationListenerService se ne koristi — uklonjeno da se ne bi
    // zbunjivali korisnici sa nepotrebnim Settings ekranom.
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

  /// Traži dozvolu za lokaciju (fine/coarse) JEDNOM po instalaciji, za oba
  /// OS-a (Android + iOS), a izuzeće od battery optimization samo na
  /// Androidu (iOS nema ekvivalentan koncept). Ovo je preduslov da GPS
  /// tracking uopšte može da čita poziciju dok vozač koristi app, uključujući
  /// i period dok je app u pozadini nakon što je tracking pokrenut iz
  /// foreground-a. Dozvole MORAJU biti odobrene unapred (ovde, pri loginu,
  /// dok app ima aktivni foreground UI) jer OS ne dozvoljava dijalog u
  /// pozadini.
  static Future<void> _requestDriverLocationPermissions() async {
    final alreadyPrompted = await _storage.read(key: _locationPromptedKey) == 'true';
    if (alreadyPrompted) return;

    try {
      final locationStatus = await Permission.locationWhenInUse.status;
      if (!locationStatus.isGranted) {
        await Permission.locationWhenInUse.request();
      }

      // iOS zahteva "Always" dozvolu da bi Geolocator position stream sa
      // allowBackgroundLocationUpdates radio dok je app u pozadini/suspendovana.
      // Redosled je bitan: locationWhenInUse MORA biti odobren pre nego što se
      // može tražiti locationAlways.
      if (Platform.isIOS) {
        final alwaysStatus = await Permission.locationAlways.status;
        if (!alwaysStatus.isGranted) {
          await Permission.locationAlways.request();
        }
      }

      if (Platform.isAndroid) {
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }

      debugPrint('[Permissions] Vozač GPS/battery dozvole obrađene.');
    } catch (e) {
      debugPrint('[Permissions] Vozač GPS/battery dozvola greška: $e');
    } finally {
      await _storage.write(key: _locationPromptedKey, value: 'true');
    }
  }
}
