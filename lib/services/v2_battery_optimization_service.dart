import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service that handles battery optimization warnings for phones that
/// aggressively kill background apps (Huawei, Xiaomi, Oppo, Vivo, etc.)
///
/// These manufacturers have custom battery optimization that kills apps
/// even when they're on Android's battery whitelist. Users must manually
/// enable background running in device-specific settings.
class V2BatteryOptimizationService {
  V2BatteryOptimizationService._();

  static const String _shownKey = 'battery_optimization_warning_shown';
  static const String _dismissedKey = 'battery_optimization_dismissed';

  /// Check if we should show the battery optimization warning
  /// Returns true for Huawei, Xiaomi, Oppo, Vivo, OnePlus, Samsung
  static Future<bool> shouldShowWarning() async {
    if (!Platform.isAndroid) return false;

    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_dismissedKey) ?? false) {
      return false;
    }

    if (prefs.getBool(_shownKey) ?? false) {
      return false;
    }

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final manufacturer = androidInfo.manufacturer.toLowerCase();

    // List of manufacturers with aggressive battery optimization
    final problematicManufacturers = [
      'huawei',
      'honor',
      'xiaomi',
      'redmi',
      'poco',
      'oppo',
      'realme',
      'vivo',
      'oneplus',
      'samsung',
      'meizu',
      'asus',
      'lenovo',
      'zte',
      'nubia',
      'tecno',
      'infinix',
    ];

    return problematicManufacturers.any((m) => manufacturer.contains(m));
  }

  /// Mark that we've shown the warning this session
  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
  }

  /// Mark that user has dismissed the warning permanently
  static Future<void> markDismissedPermanently() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  }

  /// Get manufacturer-specific settings intent
  static Future<String?> getManufacturer() async {
    if (!Platform.isAndroid) return null;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.manufacturer.toLowerCase();
  }

  /// Open battery optimization settings
  /// Tries manufacturer-specific settings first, then falls back to Android default
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;

    final manufacturer = await getManufacturer();

    try {
      // Try manufacturer-specific intents first
      if (manufacturer?.contains('huawei') == true || manufacturer?.contains('honor') == true) {
        await _openHuaweiBatterySettings();
      } else if (manufacturer?.contains('xiaomi') == true ||
          manufacturer?.contains('redmi') == true ||
          manufacturer?.contains('poco') == true) {
        await _openXiaomiBatterySettings();
      } else if (manufacturer?.contains('oppo') == true || manufacturer?.contains('realme') == true) {
        await _openOppoBatterySettings();
      } else if (manufacturer?.contains('vivo') == true) {
        await _openVivoBatterySettings();
      } else if (manufacturer?.contains('oneplus') == true) {
        await _openOnePlusBatterySettings();
      } else if (manufacturer?.contains('samsung') == true) {
        await _openSamsungBatterySettings();
      } else {
        await _openDefaultBatterySettings();
      }
    } catch (e) {
      // Fallback to default Android battery settings
      await _openDefaultBatterySettings();
    }
  }

  static Future<void> _openHuaweiBatterySettings() async {
    // 1. Try Huawei App Launch (power management) - Most common for older EMUI
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.huawei.systemmanager',
        componentName: 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    // 2. Try Power Intensity (newer EMUI)
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.huawei.systemmanager',
        componentName: 'com.huawei.systemmanager.power.ui.PowerIntensityActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    // 3. Try Protect Activity (Legacy)
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.huawei.systemmanager',
        componentName: 'com.huawei.systemmanager.optimize.process.ProtectActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    // Fallback to general battery settings
    await _openDefaultBatterySettings();
  }

  static Future<void> _openXiaomiBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.miui.powerkeeper',
        componentName: 'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    // Try Security app
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.miui.securitycenter',
        componentName: 'com.miui.permcenter.autostart.AutoStartManagementActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    await _openDefaultBatterySettings();
  }

  static Future<void> _openOppoBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.coloros.safecenter',
        componentName: 'com.coloros.safecenter.startupapp.StartupAppListActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    await _openDefaultBatterySettings();
  }

  static Future<void> _openVivoBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.vivo.permissionmanager',
        componentName: 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    await _openDefaultBatterySettings();
  }

  static Future<void> _openOnePlusBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.oneplus.security',
        componentName: 'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    await _openDefaultBatterySettings();
  }

  static Future<void> _openSamsungBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.samsung.android.lool',
        componentName: 'com.samsung.android.sm.battery.ui.BatteryActivity',
      );
      await intent.launch();
      return;
    } catch (e) {
    }

    await _openDefaultBatterySettings();
  }

  static Future<void> _openDefaultBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
    }
  }

  /// Zatraži sistemski popup za isključenje battery optimization
  /// Ovo prikazuje Android sistemski dijalog "Dozvoli/Odbij"
  /// Radi na svim Android uređajima, ali Huawei/Xiaomi mogu ignorisati
  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return false;

    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.gavra013.gavra_android',
      );
      await intent.launch();
      return true;
    } catch (e) {
      // Fallback ako sistemski popup ne radi
      await _openDefaultBatterySettings();
      return false;
    }
  }

  /// Show the battery optimization warning dialog
  /// Prvo pokušava sistemski popup, ako korisnik odbije - prikazuje uputstva
  static Future<void> showWarningDialog(BuildContext context) async {
    final manufacturer = await getManufacturer() ?? '';
    if (!context.mounted) return;

    final displayName = manufacturer.isNotEmpty ? manufacturer : 'your phone';
    final manufacturerName = displayName[0].toUpperCase() + displayName.substring(1);

    // Prvo pokušaj sistemski popup (jednostavnije za korisnika)
    // Na Huawei/Xiaomi ovo možda neće biti dovoljno, ali vredi pokušati
    final isHuaweiOrXiaomi = manufacturer.contains('huawei') ||
        manufacturer.contains('honor') ||
        manufacturer.contains('xiaomi') ||
        manufacturer.contains('redmi') ||
        manufacturer.contains('poco');

    if (!isHuaweiOrXiaomi) {
      // Za Samsung i ostale - sistemski popup je dovoljan
      await requestIgnoreBatteryOptimization();
      await markShown();
      return;
    }

    // Za Huawei/Xiaomi - prikaži detaljnija uputstva jer sistemski popup nije dovoljan

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_alert, color: Colors.orange[700], size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Omogući notifikacije',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$manufacturerName telefoni automatski blokiraju pozadinske notifikacije radi uštede baterije.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ovo omogućava da vam ekran zasvetli kad stigne poruka.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kliknite "Dozvoli" i pratite korake:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildStep('1', 'Nađite Gavra 013 u listi'),
            _buildStep('2', 'Isključite "Upravljaj automatski"'),
            _buildStep('3', 'Uključite SVE opcije'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await markDismissedPermanently();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Ne prikazuj više'),
          ),
          TextButton(
            onPressed: () async {
              await markShown();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Kasnije'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await markShown();
              if (context.mounted) Navigator.of(context).pop();
              await openBatterySettings();
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Otvori podešavanja'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
