import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class V3DeviceIdentity {
  final String? osDeviceId;
  final String? androidDeviceId;
  final String? androidBuildId;
  final String? iosDeviceId;
  final String? iosBuildId;

  const V3DeviceIdentity({
    this.osDeviceId,
    this.androidDeviceId,
    this.androidBuildId,
    this.iosDeviceId,
    this.iosBuildId,
  });
}

class V3OsDeviceIdService {
  V3OsDeviceIdService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const FlutterSecureStorage _storage =
      FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _storageKey = 'v3_os_device_id';

  static bool _isUsableId(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return false;
    if (v == 'unknown' || v == 'null' || v == 'rel' || v == 'test-keys') return false;
    return true;
  }

  static String _generateFallbackId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final hash = now.toRadixString(16).padLeft(12, '0');
    return 'gavra-$hash';
  }

  static String? _clean(String? value) {
    final safe = (value ?? '').trim();
    return safe.isEmpty ? null : safe;
  }

  static Future<V3DeviceIdentity> getDeviceIdentity() async {
    final osDeviceId = _clean(await getOsDeviceId());

    try {
      if (kIsWeb) {
        return V3DeviceIdentity(osDeviceId: osDeviceId);
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        final androidBuildId = _clean(androidInfo.id);

        return V3DeviceIdentity(
          osDeviceId: osDeviceId,
          androidDeviceId: osDeviceId,
          androidBuildId: androidBuildId,
        );
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final iosDeviceId = _clean(iosInfo.identifierForVendor);
        final iosBuildId = _clean(iosInfo.systemVersion);

        return V3DeviceIdentity(
          osDeviceId: osDeviceId,
          iosDeviceId: iosDeviceId,
          iosBuildId: iosBuildId,
        );
      }

      return V3DeviceIdentity(osDeviceId: osDeviceId);
    } catch (_) {
      return V3DeviceIdentity(osDeviceId: osDeviceId);
    }
  }

  static Future<String?> getOsDeviceId() async {
    try {
      if (kIsWeb) return null;

      final stored = (await _storage.read(key: _storageKey) ?? '').trim();
      if (_isUsableId(stored)) return stored;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        final androidId = (androidInfo.data['androidId'] ?? '').toString().trim();
        if (_isUsableId(androidId)) {
          await _storage.write(key: _storageKey, value: androidId);
          return androidId;
        }

        final fallbackId = _generateFallbackId();
        await _storage.write(key: _storageKey, value: fallbackId);
        return fallbackId;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final idfv = (iosInfo.identifierForVendor ?? '').trim();
        if (_isUsableId(idfv)) {
          await _storage.write(key: _storageKey, value: idfv);
          return idfv;
        }

        final fallbackId = _generateFallbackId();
        await _storage.write(key: _storageKey, value: fallbackId);
        return fallbackId;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
