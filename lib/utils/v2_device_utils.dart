import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detekcija Huawei uređaja i provera instaliranih aplikacija
class V2DeviceUtils {
  V2DeviceUtils._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Keširane vrednosti
  static bool? _isHuaweiDevice;

  /// Proveri da li je uređaj Huawei/Honor
  static Future<bool> isHuaweiDevice() async {
    if (_isHuaweiDevice != null) return _isHuaweiDevice!;

    if (!Platform.isAndroid) {
      _isHuaweiDevice = false;
      return false;
    }

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();

      _isHuaweiDevice = manufacturer.contains('huawei') || manufacturer.contains('honor');

      return _isHuaweiDevice!;
    } catch (e) {
      _isHuaweiDevice = false;
      return false;
    }
  }
}
