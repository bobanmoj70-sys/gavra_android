import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

/// Detekcija Huawei uređaja i provera instaliranih aplikacija
class V2DeviceUtils {
  V2DeviceUtils._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Keširani Future - sprečava race condition pri višestrukim paralelnim pozivima
  static Future<bool>? _isHuaweiDeviceFuture;

  /// Proveri da li je uređaj Huawei/Honor
  static Future<bool> isHuaweiDevice() {
    return _isHuaweiDeviceFuture ??= _detectHuawei();
  }

  static Future<bool> _detectHuawei() async {
    if (!Platform.isAndroid) return false;

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      return manufacturer.contains('huawei') || manufacturer.contains('honor');
    } catch (e, st) {
      debugPrint('[V2DeviceUtils] Greška pri detekciji uređaja: $e\n$st');
      return false;
    }
  }
}
