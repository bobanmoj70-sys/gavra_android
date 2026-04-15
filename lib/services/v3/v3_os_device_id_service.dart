import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class V3OsDeviceIdService {
  V3OsDeviceIdService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<String?> getOsDeviceId() async {
    try {
      if (kIsWeb) return null;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        final id = androidInfo.id.trim();
        if (id.isNotEmpty) return id;

        final androidId = androidInfo.fingerprint.trim();
        if (androidId.isNotEmpty) return androidId;

        return null;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final idfv = (iosInfo.identifierForVendor ?? '').trim();
        if (idfv.isNotEmpty) return idfv;
        return null;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
