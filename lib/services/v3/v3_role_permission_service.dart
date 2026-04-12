import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class V3RolePermissionService {
  V3RolePermissionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _pushPromptedKey = 'v3_perm_push_prompted_v1';

  static Future<void> ensureDriverPermissionsOnLogin() async {
    await _requestPushOnce(_pushPromptedKey);
  }

  static Future<void> ensurePassengerPermissionsOnLogin() async {
    await _requestPushOnce(_pushPromptedKey);
  }

  static Future<void> _requestPushOnce(String key) async {
    final alreadyPrompted = await _storage.read(key: key) == 'true';
    if (alreadyPrompted) return;

    try {
      final notifStatus = await Permission.notification.request();
      if (Platform.isIOS) {
        debugPrint('[Permissions] iOS push status: $notifStatus');
      }
    } catch (e) {
      debugPrint('[Permissions] Push dozvola greška: $e');
    } finally {
      await _storage.write(key: key, value: 'true');
    }
  }
}
