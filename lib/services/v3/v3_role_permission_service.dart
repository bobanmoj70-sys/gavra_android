import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _driverPushPromptedKey = 'v3_perm_driver_push_prompted_v1';
  static const String _driverGpsPromptedKey = 'v3_perm_driver_gps_prompted_v1';
  static const String _passengerPushPromptedKey = 'v3_perm_passenger_push_prompted_v1';

  static Future<void> ensureDriverPermissionsOnLogin() async {
    await _requestPushOnce(_driverPushPromptedKey);
    await _requestDriverGpsOnce();
  }

  static Future<void> ensurePassengerPermissionsOnLogin() async {
    await _requestPushOnce(_passengerPushPromptedKey);
  }

  static Future<void> _requestPushOnce(String key) async {
    final alreadyPrompted = await _storage.read(key: key) == 'true';
    if (alreadyPrompted) return;

    try {
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } else {
        await Permission.notification.request();
      }
    } catch (_) {
      // Ignoriši i upiši prompted flag da ne ponavljamo dijalog
    } finally {
      await _storage.write(key: key, value: 'true');
    }
  }

  static Future<void> _requestDriverGpsOnce() async {
    final alreadyPrompted = await _storage.read(key: _driverGpsPromptedKey) == 'true';
    if (alreadyPrompted) return;

    try {
      final locationWhenInUse = await Permission.location.status;
      if (!locationWhenInUse.isGranted) {
        await Permission.location.request();
      }

      final locationAlways = await Permission.locationAlways.status;
      if (!locationAlways.isGranted) {
        await Permission.locationAlways.request();
      }
    } catch (_) {
      // Ignoriši i upiši prompted flag da ne ponavljamo dijalog
    } finally {
      await _storage.write(key: _driverGpsPromptedKey, value: 'true');
    }
  }
}
