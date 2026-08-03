import 'dart:async';
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

  /// Vozač: push + lokacija (WhenInUse → Always).
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
  ///
  /// Na Android 10+ / Huawei / Xiaomi sistemski dijalog često NUDI samo
  /// „While in use“ — Always se bira u Permission manager / App settings.
  /// Zato posle WhenInUse vodimo vozača eksplicitno u podešavanja.
  static Future<void> _requestDriverLocationPermissions(BuildContext context) async {
    if (!context.mounted) return;

    try {
      var whenInUse = await Permission.locationWhenInUse.status;
      var always = await Permission.locationAlways.status;

      if (whenInUse.isGranted && always.isGranted) {
        return;
      }

      if (!context.mounted) return;
      final accepted = await _showLocationDisclosure(context);
      if (!accepted || !context.mounted) {
        debugPrint('[Permissions] Vozač odbio disclosure — lokacija se ne traži.');
        return;
      }

      // 1) WhenInUse — obavezno pre Always na obe platforme.
      if (!whenInUse.isGranted) {
        whenInUse = await Permission.locationWhenInUse.request();
      }
      if (!whenInUse.isGranted) {
        debugPrint('[Permissions] WhenInUse nije odobren: $whenInUse');
        if (context.mounted) {
          await _offerOpenSettingsForLocation(context, permanentlyDenied: whenInUse.isPermanentlyDenied);
        }
        return;
      }

      // 2) Always — background tracking / FGS.
      always = await Permission.locationAlways.status;
      if (always.isGranted) {
        debugPrint('[Permissions] Always već odobren');
        return;
      }

      // Pokušaj OS request (stock Android 11+ otvara location permission page;
      // Huawei često prikaže dijalog BEZ Always opcije).
      always = await Permission.locationAlways.request();
      debugPrint('[Permissions] Always posle request: $always');

      if (always.isGranted) {
        return;
      }

      // 3) OEM stvarnost: vodič + App Settings (Always se bira tamo, ne u dijalogu).
      if (!context.mounted) return;
      final opened = await _showAlwaysLocationGuide(context);
      if (opened) {
        // Ne zovi ponovo locationAlways.request() — na Huawei/Xiaomi opet
        // izađe dijalog samo sa „While in use“. App Settings ima pravu opciju.
        await _openAppSettingsAndWaitForResume();
        always = await Permission.locationAlways.status;
        debugPrint('[Permissions] Always posle Settings: $always');
      }

      if (!always.isGranted) {
        debugPrint('[Permissions] Always NIJE odobren — tracking neće moći u pozadini');
      }
    } catch (e) {
      debugPrint('[Permissions] Vozač GPS greška: $e');
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

  /// Objašnjava da Always mora ručno u Settings (Huawei / Android 11+).
  /// Vraća true ako vozač želi da otvori podešavanja.
  static Future<bool> _showAlwaysLocationGuide(BuildContext context) async {
    final code = V3LocaleManager().currentLocale.languageCode;
    final t = AppTranslations.ns('locationDisclosure');
    String tr(String key) => t[key]?[code] ?? t[key]?['sr'] ?? key;

    final result = await V3DialogHelper.showBasicDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: tr('alwaysTitle'),
      content: tr('alwaysMessage'),
      titleIcon: Icons.settings_suggest,
      titleIconColor: Colors.amber,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, false),
          text: tr('notNow'),
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, true),
          text: tr('openSettings'),
          foregroundColor: Colors.amber,
        ),
      ],
    );

    return result ?? false;
  }

  static Future<void> _offerOpenSettingsForLocation(
    BuildContext context, {
    required bool permanentlyDenied,
  }) async {
    if (!permanentlyDenied && !Platform.isAndroid) return;
    final opened = await _showAlwaysLocationGuide(context);
    if (opened) {
      await _openAppSettingsAndWaitForResume();
    }
  }

  /// Otvori App Settings i sačekaj povratak u app (ili timeout).
  static Future<void> _openAppSettingsAndWaitForResume() async {
    final completer = Completer<void>();
    late final AppLifecycleListener listener;
    var sawPaused = false;

    listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden) {
          sawPaused = true;
        }
        if (sawPaused && state == AppLifecycleState.resumed && !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      final ok = await openAppSettings();
      debugPrint('[Permissions] openAppSettings=$ok');
      if (!ok) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          debugPrint('[Permissions] Settings wait timeout');
        },
      );
    } catch (e) {
      debugPrint('[Permissions] openAppSettings greška: $e');
    } finally {
      listener.dispose();
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Javni helper: kad auto-start padne jer nema Always — vodi u Settings.
  static Future<bool> promptAlwaysLocationIfNeeded(BuildContext context) async {
    if (!context.mounted) return false;
    final always = await Permission.locationAlways.status;
    if (always.isGranted) return true;

    final opened = await _showAlwaysLocationGuide(context);
    if (!opened) return false;

    await _openAppSettingsAndWaitForResume();
    return (await Permission.locationAlways.status).isGranted;
  }
}
