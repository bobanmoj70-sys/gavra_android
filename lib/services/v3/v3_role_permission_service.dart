import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/app_platform.dart';
import '../../l10n/app_translations.dart';
import '../../utils/v3_button_utils.dart';
import '../../utils/v3_dialog_helper.dart';
import '../v3_locale_manager.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const MethodChannel _wakelockChannel = MethodChannel(AppPlatform.wakelockChannel);

  /// true samo ako je OS dozvola Always granted.
  static Future<bool> isDriverAlwaysLocationGranted() async {
    try {
      return (await Permission.locationAlways.status).isGranted;
    } catch (e) {
      debugPrint('[Permissions] isDriverAlwaysLocationGranted greška: $e');
      return false;
    }
  }

  /// Vozač: push + **obavezna** Always lokacija.
  /// Vraća true samo ako je Always odobren — inače vozač NE sme u app.
  static Future<bool> ensureDriverPermissionsOnLogin(BuildContext context) async {
    await enforcePushPermission(context);
    if (!context.mounted) return false;
    return enforceDriverAlwaysLocation(context);
  }

  static Future<void> ensurePassengerPermissionsOnLogin(BuildContext context) async {
    await enforcePushPermission(context);
  }

  /// Android: budi ekran na dolazni push.
  static Future<void> wakeScreenOnPush({int durationMs = 8000}) async {
    if (!Platform.isAndroid) return;
    try {
      await _wakelockChannel.invokeMethod<bool>(
        AppPlatform.methodWakeScreen,
        {'duration': durationMs},
      );
    } catch (e) {
      debugPrint('[Permissions] wakeScreenOnPush greška: $e');
    }
  }

  static bool _pushGateShowing = false;

  /// true samo ako je push permission odobren (iOS provisional/ephemeral = isključeno).
  static Future<bool> isPushPermissionGranted() async {
    try {
      if (Platform.isIOS) {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        return s.authorizationStatus == AuthorizationStatus.authorized;
      }
      return (await Permission.notification.status).isGranted;
    } catch (e) {
      debugPrint('[Permissions] isPushPermissionGranted greška: $e');
      return true; // fail-open: ne blokiraj app na grešku servisa
    }
  }

  /// Push gate sa izlazom: blokirajući dijalog → Settings → re-check, uz
  /// "Nastavi bez obaveštenja" kao jedini izlaz (App Store 4.5.4 zahteva da
  /// push ne bude uslov za rad app-a, pa escape mora postojati).
  /// Vraća true ako je permission odobren na kraju toka.
  static Future<bool> enforcePushPermission(BuildContext context) async {
    if (!context.mounted) return false;
    try {
      if (await isPushPermissionGranted()) return true;

      // Sistemski request samo dok status nije "denied" — na iOS denied više
      // nikad ne prikazuje dijalog, jedini put je Settings.
      if (Platform.isIOS) {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        if (s.authorizationStatus == AuthorizationStatus.notDetermined) {
          await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      } else {
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      }
      var granted = await isPushPermissionGranted();

      while (context.mounted && !granted) {
        final openSettings = await _showPushGateDialog(context);
        if (!context.mounted) return false;
        if (!openSettings) return false; // "Nastavi bez obaveštenja"
        await _openAppSettingsAndWaitForResume();
        granted = await isPushPermissionGranted();
      }
      return granted;
    } catch (e) {
      debugPrint('[Permissions] enforcePushPermission greška: $e');
      return true; // fail-open
    }
  }

  /// Re-check na resume: gate samo kad je korisnik aktivno odbio/ugasio
  /// dozvolu u Settings (iOS denied / Android permanentlyDenied).
  /// notDetermined rešava login flow kroz OS request.
  static Future<void> promptPushGateIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    try {
      if (Platform.isIOS) {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        if (s.authorizationStatus != AuthorizationStatus.denied) return;
      } else {
        final status = await Permission.notification.status;
        if (!status.isPermanentlyDenied) return;
      }
      if (!context.mounted) return;
      await enforcePushPermission(context);
    } catch (e) {
      debugPrint('[Permissions] promptPushGateIfNeeded greška: $e');
    }
  }

  /// Hard gate (firma): Always lokacija ili nema posla u app-u.
  ///
  /// Nema "kasnije" / skip. Samo Settings ili odustajanje (return false).
  /// WhenInUse → Always (redosled obavezan na Android + iOS).
  static Future<bool> enforceDriverAlwaysLocation(BuildContext context) async {
    if (!context.mounted) return false;

    try {
      if (await isDriverAlwaysLocationGranted()) {
        final gpsOn = await Geolocator.isLocationServiceEnabled();
        if (gpsOn) return true;
      }

      // Disclosure — prihvat uslova rada ili izlaz.
      if (!await isDriverAlwaysLocationGranted()) {
        if (!context.mounted) return false;
        final accepted = await _showLocationDisclosureMandatory(context);
        if (!accepted || !context.mounted) {
          debugPrint('[Permissions] Vozač odbio uslov Always — blokada app-a');
          return false;
        }
      }

      // GPS servis mora biti uključen.
      while (context.mounted && !await Geolocator.isLocationServiceEnabled()) {
        final open = await _showMandatoryDialog(
          context,
          titleKey: 'gpsOffTitle',
          messageKey: 'gpsOffMessage',
        );
        if (!open) return false;
        await Geolocator.openLocationSettings();
        await _waitForResume();
      }
      if (!context.mounted) return false;

      // 1) WhenInUse
      var whenInUse = await Permission.locationWhenInUse.status;
      if (!whenInUse.isGranted) {
        whenInUse = await Permission.locationWhenInUse.request();
      }
      while (context.mounted && !whenInUse.isGranted) {
        final open = await _showMandatoryDialog(
          context,
          titleKey: 'whenInUseTitle',
          messageKey: 'whenInUseMessage',
        );
        if (!open) return false;
        await _openAppSettingsAndWaitForResume();
        whenInUse = await Permission.locationWhenInUse.status;
      }
      if (!context.mounted) return false;

      // 2) Always — OS request pa Settings petlja dok ne prođe.
      var always = await Permission.locationAlways.status;
      if (!always.isGranted) {
        always = await Permission.locationAlways.request();
        debugPrint('[Permissions] Always posle request: $always');
      }

      while (context.mounted && !always.isGranted) {
        final open = await _showMandatoryDialog(
          context,
          titleKey: 'alwaysTitle',
          messageKey: 'alwaysMessage',
        );
        if (!open) return false;
        // Ne zovi ponovo locationAlways.request() — OEM često nudi samo While in use.
        await _openAppSettingsAndWaitForResume();
        always = await Permission.locationAlways.status;
        debugPrint('[Permissions] Always posle Settings: $always');
      }

      final ok = context.mounted && always.isGranted;
      if (!ok) {
        debugPrint('[Permissions] Always NIJE odobren — app blokiran za vozača');
      }
      return ok;
    } catch (e) {
      debugPrint('[Permissions] enforceDriverAlwaysLocation greška: $e');
      return false;
    }
  }

  static String _trLocation(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    final t = AppTranslations.ns('locationDisclosure');
    return t[key]?[code] ?? t[key]?['sr'] ?? key;
  }

  static String _trNotification(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    final t = AppTranslations.ns('notificationPermission');
    return t[key]?[code] ?? t[key]?['sr'] ?? key;
  }

  /// Uslov rada: Dozvoli ili Odustajem (nema skip u app).
  static Future<bool> _showLocationDisclosureMandatory(BuildContext context) async {
    final result = await V3DialogHelper.showBasicDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: _trLocation('title'),
      content: _trLocation('message'),
      titleIcon: Icons.location_on,
      titleIconColor: Colors.amber,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, false),
          text: _trLocation('refuseWork'),
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, true),
          text: _trLocation('allow'),
          foregroundColor: Colors.amber,
        ),
      ],
    );
    return result ?? false;
  }

  /// true = otvori settings, false = odustajem od posla.
  static Future<bool> _showMandatoryDialog(
    BuildContext context, {
    required String titleKey,
    required String messageKey,
  }) async {
    final result = await V3DialogHelper.showBasicDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: _trLocation(titleKey),
      content: _trLocation(messageKey),
      titleIcon: Icons.location_off,
      titleIconColor: Colors.amber,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, false),
          text: _trLocation('refuseWork'),
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, true),
          text: _trLocation('openSettings'),
          foregroundColor: Colors.amber,
        ),
      ],
    );
    return result ?? false;
  }

  /// true = otvori settings, false = nastavi bez notifikacija.
  static Future<bool> _showPushGateDialog(BuildContext context) async {
    if (!context.mounted) return false;
    if (_pushGateShowing) return false;
    _pushGateShowing = true;
    try {
      final result = await V3DialogHelper.showBasicDialog<bool>(
        context: context,
        barrierDismissible: false,
        title: _trNotification('title'),
        content: _trNotification('message'),
        titleIcon: Icons.notifications_off,
        titleIconColor: Colors.amber,
        actions: [
          V3ButtonUtils.textButton(
            onPressed: () => Navigator.pop(context, false),
            text: _trNotification('continueAnyway'),
            foregroundColor: Colors.grey,
          ),
          V3ButtonUtils.textButton(
            onPressed: () => Navigator.pop(context, true),
            text: _trLocation('openSettings'),
            foregroundColor: Colors.amber,
          ),
        ],
      );
      return result ?? false;
    } finally {
      _pushGateShowing = false;
    }
  }

  static Future<void> _waitForResume() async {
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
      await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          debugPrint('[Permissions] resume wait timeout');
        },
      );
    } finally {
      listener.dispose();
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Otvori App Settings i sačekaj povratak u app (ili timeout).
  static Future<void> _openAppSettingsAndWaitForResume() async {
    try {
      final ok = await openAppSettings();
      debugPrint('[Permissions] openAppSettings=$ok');
      if (!ok) return;
      await _waitForResume();
    } catch (e) {
      debugPrint('[Permissions] openAppSettings greška: $e');
    }
  }

  /// Javni helper: kad auto-start padne jer nema Always — vodi u Settings petlju.
  static Future<bool> promptAlwaysLocationIfNeeded(BuildContext context) async {
    if (!context.mounted) return false;
    if (await isDriverAlwaysLocationGranted()) return true;
    return enforceDriverAlwaysLocation(context);
  }
}
