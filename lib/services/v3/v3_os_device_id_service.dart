import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class V3DeviceIdentity {
  final String? androidDeviceId;
  final String? androidBuildId;
  final String? iosDeviceId;
  final String? iosBuildId;

  const V3DeviceIdentity({
    this.androidDeviceId,
    this.androidBuildId,
    this.iosDeviceId,
    this.iosBuildId,
  });
}

class V3OsDeviceIdService {
  V3OsDeviceIdService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const MethodChannel _pushTokenChannel = MethodChannel('com.gavra013.gavra_android/push_token');

  static String? _clean(String? value) {
    final safe = (value ?? '').trim();
    return safe.isEmpty ? null : safe;
  }

  static Future<String?> _getAndroidIdFromChannel() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final androidId = await _pushTokenChannel.invokeMethod<String>('getAndroidId');
        final safeId = _clean(androidId);
        if (safeId != null) {
          debugPrint('[V3OsDeviceIdService] Android ID from channel (attempt=$attempt)');
          return safeId;
        }
        debugPrint('[V3OsDeviceIdService] Empty Android ID from channel (attempt=$attempt)');
      } on MissingPluginException catch (e) {
        debugPrint('[V3OsDeviceIdService] getAndroidId MissingPluginException (attempt=$attempt): $e');
      } catch (e) {
        debugPrint('[V3OsDeviceIdService] getAndroidId channel error (attempt=$attempt): $e');
      }

      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return null;
  }

  static Future<V3DeviceIdentity> getDeviceIdentity() async {
    try {
      if (kIsWeb) {
        return const V3DeviceIdentity();
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        var androidDeviceId = _clean(androidInfo.data['androidId']?.toString());
        androidDeviceId ??= _clean(androidInfo.data['android_id']?.toString());
        androidDeviceId ??= await _getAndroidIdFromChannel();
        final androidBuildId = _clean(androidInfo.id);

        return V3DeviceIdentity(
          androidDeviceId: androidDeviceId,
          androidBuildId: androidBuildId,
        );
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? iosDeviceId;
        String? iosBuildId;

        for (var attempt = 1; attempt <= 3; attempt++) {
          final iosInfo = await _deviceInfo.iosInfo;
          iosDeviceId = _clean(iosInfo.identifierForVendor);
          iosBuildId = _clean(iosInfo.systemVersion);

          if (iosDeviceId != null) {
            break;
          }

          if (attempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }

        return V3DeviceIdentity(
          iosDeviceId: iosDeviceId,
          iosBuildId: iosBuildId,
        );
      }

      return const V3DeviceIdentity();
    } catch (_) {
      return const V3DeviceIdentity();
    }
  }
}
