import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../globals.dart';
import 'repositories/v3_app_settings_repository.dart';

class V3AppUpdateService {
  V3AppUpdateService._();

  static final V3AppSettingsRepository _repository = V3AppSettingsRepository();

  static Future<void> refreshUpdateInfo({Map<String, dynamic>? appSettingsRow}) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        updateInfoNotifier.value = null;
        return;
      }

      final row = appSettingsRow ??
          await _repository.getGlobal(
            selectColumns: 'latest_version_android, force_update_android, store_url_android, '
                'latest_version_ios, force_update_ios, store_url_ios',
          );

      if (row == null) {
        updateInfoNotifier.value = null;
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();
      final playStoreUrl = 'https://play.google.com/store/apps/details?id=${packageInfo.packageName}';

      final key = Platform.isIOS ? 'ios' : 'android';
      final selected = _resolvePlatformConfig(row, key);

      final latest = (selected['latest'] ?? '').toString().trim();
      var storeUrl = (selected['storeUrl'] ?? '').toString().trim();
      if (Platform.isAndroid && storeUrl.isEmpty) {
        storeUrl = playStoreUrl;
      }
      final forceFlag = selected['force'] == true;

      if (storeUrl.isEmpty) {
        updateInfoNotifier.value = null;
        return;
      }

      if (!forceFlag) {
        updateInfoNotifier.value = null;
        return;
      }

      final effectiveLatest = latest.isNotEmpty ? latest : currentVersion;

      updateInfoNotifier.value = V2UpdateInfo(
        latestVersion: effectiveLatest,
        storeUrl: storeUrl,
        isForced: true,
      );
    } catch (e) {
      debugPrint('⚠️ [V3AppUpdateService] refreshUpdateInfo greška: $e');
      updateInfoNotifier.value = null;
    }
  }

  static Map<String, dynamic> _resolvePlatformConfig(Map<String, dynamic> row, String key) {
    if (key == 'ios') {
      return {
        'latest': row['latest_version_ios'],
        'force': row['force_update_ios'],
        'storeUrl': row['store_url_ios'],
      };
    }

    return {
      'latest': row['latest_version_android'],
      'force': row['force_update_android'],
      'storeUrl': row['store_url_android'],
    };
  }
}
