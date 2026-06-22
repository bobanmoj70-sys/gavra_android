import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'v3_os_device_id_service.dart';

class V3DeviceIdentityService {
  V3DeviceIdentityService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _stableDeviceIdKey = 'v3_stable_device_id';

  static String? _clean(String? value) {
    final safe = (value ?? '').trim();
    return safe.isEmpty ? null : safe;
  }

  static Future<String> getStableDeviceId() async {
    final cached = _clean(await _storage.read(key: _stableDeviceIdKey));
    if (cached != null) return cached;

    String? nativeId;
    try {
      final identity = await V3OsDeviceIdService.getDeviceIdentity();
      if (kIsWeb) {
        nativeId = null;
      } else if (Platform.isAndroid) {
        nativeId = _clean(identity.androidDeviceId);
      } else if (Platform.isIOS) {
        nativeId = _clean(identity.iosDeviceId);
      }
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] Native device id error: $e');
    }

    final id = nativeId ?? const Uuid().v4();
    try {
      await _storage.write(key: _stableDeviceIdKey, value: id);
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] SecureStorage write error: $e');
    }

    return id;
  }

  static Future<String?> getHardwareId() async {
    try {
      final identity = await V3OsDeviceIdService.getDeviceIdentity();
      if (kIsWeb) return null;
      if (Platform.isAndroid) return _clean(identity.androidDeviceId);
      if (Platform.isIOS) return _clean(identity.iosDeviceId);
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] getHardwareId error: $e');
    }
    return null;
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _stableDeviceIdKey);
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] SecureStorage delete error: $e');
    }
  }
}
