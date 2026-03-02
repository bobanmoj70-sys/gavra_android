import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_statistika_istorija_service.dart';

/// Servis za globalna podešavanja aplikacije iz Supabase
class V2AppSettingsService {
  V2AppSettingsService._();

  /// Inicijalizuje podešavanja — čita iz rm.settingsCache (rm već sluša tabelu).
  static Future<void> initialize() async {
    await _loadSettings();
  }

  /// Učitaj sva podešavanja iz rm.settingsCache (nema DB upita)
  static Future<void> _loadSettings() async {
    try {
      final rm = V2MasterRealtimeManager.instance;
      final response = rm.settingsCache['global'];
      if (response == null) return;

      final navBarType = response['nav_bar_type'] as String? ?? 'letnji';
      navBarTypeNotifier.value = navBarType;
      praznicniModNotifier.value = navBarType == 'praznici';

      _checkForUpdates(
        minVersion: response['min_version'] as String?,
        latestVersion: response['latest_version'] as String?,
        storeUrlAndroid: response['store_url_android'] as String?,
        storeUrlHuawei: response['store_url_huawei'] as String?,
        storeUrlIos: response['store_url_ios'] as String?,
      );
    } catch (e) {
      // Ako nema reda, ostavi default vrednosti
    }
  }

  /// Poredi verzije i puni updateInfoNotifier
  static Future<void> _checkForUpdates({
    required String? minVersion,
    required String? latestVersion,
    required String? storeUrlAndroid,
    required String? storeUrlHuawei,
    required String? storeUrlIos,
  }) async {
    if (latestVersion == null || latestVersion.isEmpty) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);
      final latest = _parseVersion(latestVersion);
      final min = minVersion != null && minVersion.isNotEmpty ? _parseVersion(minVersion) : null;

      // Odaberi store URL prema platformi
      final storeUrl = Platform.isIOS
          ? (storeUrlIos ?? '')
          : Platform.isAndroid
              ? (storeUrlAndroid ?? '')
              : (storeUrlHuawei ?? '');

      if (storeUrl.isEmpty) return;

      final isForced = min != null && _isOlderThan(current, min);
      final hasUpdate = _isOlderThan(current, latest);

      if (hasUpdate || isForced) {
        updateInfoNotifier.value = V2UpdateInfo(
          latestVersion: latestVersion,
          storeUrl: storeUrl,
          isForced: isForced,
        );
      } else {
        updateInfoNotifier.value = null;
      }
    } catch (e) {
      debugPrint('[AppSettings] Version check failed: $e');
    }
  }

  /// Parsira "6.0.61" u listu integera [6, 0, 61]
  static List<int> _parseVersion(String version) {
    return version.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  }

  /// Vraća true ako je [a] starija verzija od [b]
  static bool _isOlderThan(List<int> a, List<int> b) {
    final len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }

  /// Otvori store za update
  static Future<void> openStore() async {
    final info = updateInfoNotifier.value;
    if (info == null) return;
    final uri = Uri.parse(info.storeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Postavi nav_bar_type (samo admin može)
  static Future<void> setNavBarType(String type) async {
    await supabase
        .from('v2_app_settings')
        .update({'nav_bar_type': type, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', 'global');

    try {
      await V2StatistikaIstorijaService.logGeneric(
          tip: 'admin_akcija', detalji: 'Promenjen red vožnje na: ${type.toUpperCase()}');
    } catch (e) {
      debugPrint('[AppSettingsService] logGeneric error: $e');
    }
  }
}
