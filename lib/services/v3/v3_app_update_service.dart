import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../globals.dart';
import 'repositories/v3_app_settings_repository.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

class V3AppUpdateService {
  V3AppUpdateService._();

  static final V3AppSettingsRepository _repository = V3AppSettingsRepository();
  static const Set<String> _updateGateBypassUserIds = <String>{
    '824f7bd7-e19c-4471-b7a2-d6031d810242',
  };

  static Future<void> refreshUpdateInfo({Map<String, dynamic>? appSettingsRow}) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        updateInfoNotifier.value = null;
        return;
      }

      final row = appSettingsRow ??
          await _repository.getGlobal(
            selectColumns:
                'latest_version_android, min_supported_version_android, force_update_android, store_url_android, maintenance_mode_android, maintenance_title_android, maintenance_message_android, '
                'latest_version_ios, min_supported_version_ios, force_update_ios, store_url_ios, maintenance_mode_ios, maintenance_title_ios, maintenance_message_ios',
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
      final minSupported = (selected['minSupported'] ?? '').toString().trim();
      final maintenanceMode = selected['maintenanceMode'] == true;
      final maintenanceTitle = (selected['maintenanceTitle'] ?? '').toString().trim();
      final maintenanceMessage = (selected['maintenanceMessage'] ?? '').toString().trim();
      var storeUrl = (selected['storeUrl'] ?? '').toString().trim();
      if (Platform.isAndroid && storeUrl.isEmpty) {
        storeUrl = playStoreUrl;
      }
      final forceFlag = selected['force'] == true;

      if (_isUpdateGateBypassedForOperator()) {
        updateInfoNotifier.value = null;
        return;
      }

      if (maintenanceMode) {
        updateInfoNotifier.value = V2UpdateInfo(
          latestVersion: latest.isNotEmpty ? latest : currentVersion,
          storeUrl: storeUrl,
          isForced: true,
          isMaintenance: true,
          maintenanceTitle: maintenanceTitle.isNotEmpty ? maintenanceTitle : 'Malo čačkamo ispod haube 🔧',
          maintenanceMessage: maintenanceMessage.isNotEmpty
              ? maintenanceMessage
              : 'Radovi su u toku, šlemovi su na glavama i traka je razvučena. Vrati se uskoro — biće bolje nego pre 😄',
        );
        return;
      }

      if (storeUrl.isEmpty) {
        updateInfoNotifier.value = null;
        return;
      }

      if (!forceFlag) {
        updateInfoNotifier.value = null;
        return;
      }

      final requiredVersion = minSupported.isNotEmpty ? minSupported : latest;
      if (requiredVersion.isEmpty) {
        updateInfoNotifier.value = null;
        return;
      }

      if (!_isVersionLower(currentVersion, requiredVersion)) {
        updateInfoNotifier.value = null;
        return;
      }

      final effectiveLatest = latest.isNotEmpty ? latest : requiredVersion;

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
        'minSupported': row['min_supported_version_ios'],
        'force': row['force_update_ios'],
        'storeUrl': row['store_url_ios'],
        'maintenanceMode': row['maintenance_mode_ios'],
        'maintenanceTitle': row['maintenance_title_ios'],
        'maintenanceMessage': row['maintenance_message_ios'],
      };
    }

    return {
      'latest': row['latest_version_android'],
      'minSupported': row['min_supported_version_android'],
      'force': row['force_update_android'],
      'storeUrl': row['store_url_android'],
      'maintenanceMode': row['maintenance_mode_android'],
      'maintenanceTitle': row['maintenance_title_android'],
      'maintenanceMessage': row['maintenance_message_android'],
    };
  }

  static bool _isVersionLower(String current, String required) {
    return _compareVersions(current, required) < 0;
  }

  static bool _isUpdateGateBypassedForOperator() {
    final putnikId = (V3PutnikService.currentPutnik?['id'] ?? '').toString().trim();
    if (putnikId.isNotEmpty && _updateGateBypassUserIds.contains(putnikId)) return true;

    final vozacId = V3VozacService.currentVozac?.id.trim() ?? '';
    if (vozacId.isNotEmpty && _updateGateBypassUserIds.contains(vozacId)) return true;

    return false;
  }

  static int _compareVersions(String left, String right) {
    List<int> parse(String input) {
      final cleaned = input.trim().split('+').first.split('-').first;
      if (cleaned.isEmpty) return const [0];
      return cleaned.split('.').map((segment) => int.tryParse(segment) ?? 0).toList(growable: false);
    }

    final leftParts = parse(left);
    final rightParts = parse(right);
    final maxLength = leftParts.length > rightParts.length ? leftParts.length : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;
      if (leftValue < rightValue) return -1;
      if (leftValue > rightValue) return 1;
    }

    return 0;
  }
}
