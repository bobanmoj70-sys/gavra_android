import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_translations.dart';
import '../../utils/v3_button_utils.dart';
import '../../utils/v3_dialog_helper.dart';
import '../v3_locale_manager.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _pushPromptedKey = 'v3_perm_push_prompted_v2';
  static const String _locationPromptedKey = 'v3_perm_location_prompted_v1';

  static const MethodChannel _wakelockChannel = MethodChannel('com.gavra013.gavra_android/wakelock');

  // ─────────────────────────────────────────────────────────────────────
  // Javni API
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> ensureDriverPermissionsOnLogin(BuildContext context) async {
    await _requestCommonPermissions();
    // GPS/lokacija + battery optimization SAMO za vozača — mora biti odobreno
    // UNAPRED (pri loginu) da bi tracking mogao da krene čim vozač otvori app.
    await _requestDriverLocationPermissions(context);
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
  ///
  /// Location permission is requested only for the DRIVER role.
  /// Passengers do not request or use location/background-location access.
  static Future<void> _requestDriverLocationPermissions(BuildContext context) async {
    final alreadyPrompted = await _storage.read(key: _locationPromptedKey) == 'true';
    if (alreadyPrompted) return;

    // Ako korisnik već ima sve potrebne dozvole, nema potrebe ponovo
    // prikazivati disclosure (npr. nakon reinstalacije ili restore-a).
    final locationStatus = await Permission.locationWhenInUse.status;
    final alwaysStatus = await Permission.locationAlways.status;
    final batteryStatus =
        Platform.isAndroid ? await Permission.ignoreBatteryOptimizations.status : PermissionStatus.granted;
    if (locationStatus.isGranted && alwaysStatus.isGranted && batteryStatus.isGranted) {
      await _storage.write(key: _locationPromptedKey, value: 'true');
      return;
    }

    // Google Play zahteva "prominent disclosure" PRE nego što se zatraži
    // bilo koja osetljiva dozvola, posebno BACKGROUND_LOCATION.
    final accepted = await _showLocationDisclosure(context);
    if (!accepted) {
      debugPrint('[Permissions] Vozač odbio prominent disclosure — lokacija se ne traži.');
      return;
    }

    // Beležimo tek nakon prihvatanja, tako da korisnik koji slučajno odbije
    // disclosure može ponovo da ga vidi pri sledećem login-u.
    await _storage.write(key: _locationPromptedKey, value: 'true');

    try {
      if (!locationStatus.isGranted) {
        await Permission.locationWhenInUse.request();
      }

      // "Always" dozvola je neophodna za background location tracking kako na
      // iOS-u tako i na Android-u (manifest već deklariše ACCESS_BACKGROUND_LOCATION).
      // Redosled je bitan: locationWhenInUse MORA biti odobren pre nego što se
      // može tražiti locationAlways.
      if (!alwaysStatus.isGranted) {
        await Permission.locationAlways.request();
      }

      if (Platform.isAndroid && !batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }

      debugPrint('[Permissions] Vozač GPS/battery dozvole obrađene.');
    } catch (e) {
      debugPrint('[Permissions] Vozač GPS/battery dozvola greška: $e');
    }
  }

  /// Prikazuje "prominent disclosure" dijalog koji objašnjava zašto aplikacija
  /// prikuplja lokaciju u pozadini. Vraća `true` ako korisnik pristane da nastavi
  /// sa zahtevom za dozvolu.
  static Future<bool> _showLocationDisclosure(BuildContext context) async {
    final code = V3LocaleManager().currentLocale.languageCode;
    final t = AppTranslations.ns('locationDisclosure');
    String tr(String key) => t[key]?[code] ?? t[key]?['sr'] ?? key;

    final result = await V3DialogHelper.showBasicDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: tr('title'),
      content: tr('message'),
      titleIcon: Icons.location_on,
      titleIconColor: Colors.amber,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, false),
          text: tr('dontAllow'),
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, true),
          text: tr('allow'),
          foregroundColor: Colors.amber,
        ),
      ],
    );

    return result ?? false;
  }
}
