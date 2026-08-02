import 'package:flutter/material.dart';

class V3AppSettingsState {
  V3AppSettingsState._();
  static final V3AppSettingsState instance = V3AppSettingsState._();

  final ValueNotifier<DateTime?> activeWeekStart = ValueNotifier<DateTime?>(null);
  final ValueNotifier<DateTime?> activeWeekEnd = ValueNotifier<DateTime?>(null);

  /// Runtime-only HERE WeGo install listing URLs from `v3_app_settings`
  /// (not hardcoded in binary).
  String? hereWegoInstallUrlAndroid;
  String? hereWegoInstallUrlIos;

  DateTime? get activeWeekStartValue => activeWeekStart.value;
  DateTime? get activeWeekEndValue => activeWeekEnd.value;

  void setActiveWeekStart(DateTime? value) {
    activeWeekStart.value = value;
  }

  void setActiveWeekEnd(DateTime? value) {
    activeWeekEnd.value = value;
  }

  void setHereWegoInstallUrlAndroid(String? value) {
    final trimmed = value?.trim();
    hereWegoInstallUrlAndroid = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void setHereWegoInstallUrlIos(String? value) {
    final trimmed = value?.trim();
    hereWegoInstallUrlIos = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Platform-specific install URL for HERE WeGo (from remote config).
  String? hereWegoInstallUrlForCurrentPlatform({required bool isIos, required bool isAndroid}) {
    if (isIos) return hereWegoInstallUrlIos;
    if (isAndroid) return hereWegoInstallUrlAndroid;
    return null;
  }
}
