import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../globals.dart';

class V3AppUpdateService {
  V3AppUpdateService._();

  static Future<void> refreshUpdateInfo({Map<String, dynamic>? appSettingsRow}) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        updateInfoNotifier.value = null;
        return;
      }

      final row = appSettingsRow ??
          await supabase
              .from('v3_app_settings')
              .select(
                'latest_version_android, min_supported_version_android, force_update_android, store_url_android, '
                'latest_version_ios, min_supported_version_ios, force_update_ios, store_url_ios',
              )
              .eq('id', 'global')
              .maybeSingle();

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
      final minSupported = (selected['min'] ?? '').toString().trim();
      var storeUrl = (selected['storeUrl'] ?? '').toString().trim();
      if (Platform.isAndroid && storeUrl.isEmpty) {
        storeUrl = playStoreUrl;
      }
      final forceFlag = selected['force'] == true;

      if (latest.isEmpty || storeUrl.isEmpty) {
        updateInfoNotifier.value = null;
        return;
      }

      final isOutdated = _compareVersions(currentVersion, latest) < 0;
      if (!isOutdated) {
        updateInfoNotifier.value = null;
        return;
      }

      final isBelowMin = minSupported.isNotEmpty && _compareVersions(currentVersion, minSupported) < 0;
      final isForced = isBelowMin || forceFlag;

      updateInfoNotifier.value = V2UpdateInfo(
        latestVersion: latest,
        storeUrl: storeUrl,
        isForced: isForced,
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
        'min': row['min_supported_version_ios'],
        'force': row['force_update_ios'],
        'storeUrl': row['store_url_ios'],
      };
    }

    return {
      'latest': row['latest_version_android'],
      'min': row['min_supported_version_android'],
      'force': row['force_update_android'],
      'storeUrl': row['store_url_android'],
    };
  }

  static int _compareVersions(String current, String target) {
    final currentParts = _versionToParts(current);
    final targetParts = _versionToParts(target);
    final maxLen = currentParts.length > targetParts.length ? currentParts.length : targetParts.length;

    for (var i = 0; i < maxLen; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final t = i < targetParts.length ? targetParts[i] : 0;
      if (c < t) return -1;
      if (c > t) return 1;
    }
    return 0;
  }

  static List<int> _versionToParts(String version) {
    final normalized = version.split('+').first.trim();
    if (normalized.isEmpty) return const [0];

    return normalized.split('.').map((segment) {
      final numeric = segment.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(numeric) ?? 0;
    }).toList();
  }
}
