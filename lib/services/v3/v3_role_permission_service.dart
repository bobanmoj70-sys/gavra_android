import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_translations.dart';
import '../../utils/v3_button_utils.dart';
import '../../utils/v3_dialog_helper.dart';
import '../v3_locale_manager.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const MethodChannel _wakelockChannel = MethodChannel('com.gavra013.gavra_android/wakelock');

  /// Vozač: push + lokacija (WhenInUse → Always) + Android battery exemption.
  /// Isti redosled na Android i iOS. Ponavlja se pri svakom loginu dok Always nije granted.
  static Future<void> ensureDriverPermissionsOnLogin(BuildContext context) async {
    await _requestCommonPermissions();
    await _requestDriverLocationPermissions(context);
  }

  static Future<void> ensurePassengerPermissionsOnLogin() async {
    await _requestCommonPermissions();
  }

  static Future<void> _requestCommonPermissions() async {
    await _requestPushOnce();
  }

  /// Android: budi ekran na dolazni push.
  static Future<void> wakeScreenOnPush({int durationMs = 8000}) async {
    if (!Platform.isAndroid) return;
    try {
      await _wakelockChannel.invokeMethod<bool>('wakeScreen', {'duration': durationMs});
    } catch (e) {
      debugPrint('[Permissions] wakeScreenOnPush greška: $e');
    }
  }

  static Future<void> _requestPushOnce() async {
    if (Platform.isIOS) {
      try {
        var settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.notDetermined ||
            settings.authorizationStatus == AuthorizationStatus.denied) {
          settings = await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
        }
        debugPrint('[Permissions][iOS] Push: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('[Permissions][iOS] Push greška: $e');
      }
      return;
    }

    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[Permissions] Push greška: $e');
    }
  }

  /// Android + iOS: WhenInUse pa Always (redosled obavezan na obe platforme).
  /// Disclosure pre request-a (store policy). Bez "jednom" flaga — ponavlja dok nema Always.
  static Future<void> _requestDriverLocationPermissions(BuildContext context) async {
    if (!context.mounted) return;

    try {
      var whenInUse = await Permission.locationWhenInUse.status;
      var always = await Permission.locationAlways.status;

      if (whenInUse.isGranted && always.isGranted) {
        await _requestAndroidBatteryExemptionIfNeeded();
        return;
      }

      if (!context.mounted) return;
      final accepted = await _showLocationDisclosure(context);
      if (!accepted || !context.mounted) {
        debugPrint('[Permissions] Vozač odbio disclosure — lokacija se ne traži.');
        return;
      }

      // 1) WhenInUse (iOS/Android) — Always request bez ovoga ne radi.
      if (!whenInUse.isGranted) {
        whenInUse = await Permission.locationWhenInUse.request();
      }
      if (!whenInUse.isGranted) {
        debugPrint('[Permissions] WhenInUse nije odobren: $whenInUse');
        return;
      }

      // 2) Always — background tracking / FGS location na obe platforme.
      always = await Permission.locationAlways.status;
      if (!always.isGranted) {
        always = await Permission.locationAlways.request();
      }
      debugPrint('[Permissions] Always: $always');

      await _requestAndroidBatteryExemptionIfNeeded();
    } catch (e) {
      debugPrint('[Permissions] Vozač GPS greška: $e');
    }
  }

  /// Samo Android — iOS nema ekvivalent.
  static Future<void> _requestAndroidBatteryExemptionIfNeeded() async {
    if (!Platform.isAndroid) return;
    try {
      final battery = await Permission.ignoreBatteryOptimizations.status;
      if (!battery.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('[Permissions] Battery greška: $e');
    }
  }

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
