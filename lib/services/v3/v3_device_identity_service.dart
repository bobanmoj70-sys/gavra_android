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
  static const _installationIdKey = 'v3_installation_id';

  static String? _clean(String? value) {
    final safe = (value ?? '').trim();
    return safe.isEmpty ? null : safe;
  }

  /// UUID po instalaciji aplikacije. Menja se nakon reinstall-a.
  static Future<String> getStableDeviceId() async {
    final cached = _clean(await _storage.read(key: _installationIdKey));
    if (cached != null) return cached;

    final id = const Uuid().v4();
    try {
      await _storage.write(key: _installationIdKey, value: id);
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] SecureStorage write error: $e');
    }
    return id;
  }

  /// Stabilan ID fizičkog uređaja: SSAID na Androidu, IDFV na iOS-u.
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

  /// Vraća oba identifikatora odjednom.
  static Future<({String installationId, String? hardwareId})> getDeviceIds() async {
    final installationId = await getStableDeviceId();
    final hardwareId = await getHardwareId();
    return (installationId: installationId, hardwareId: hardwareId);
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _installationIdKey);
    } catch (e) {
      debugPrint('[V3DeviceIdentityService] SecureStorage delete error: $e');
    }
  }
}
