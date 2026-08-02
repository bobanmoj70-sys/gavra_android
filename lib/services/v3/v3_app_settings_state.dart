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

  /// Runtime-only maps URL templates from `v3_app_settings`.
  /// Placeholders: `{lat}` `{lng}`.
  String? mapsAppUrlTemplateAndroid;
  String? mapsAppUrlTemplateIos;
  String? mapsWebUrlTemplate;

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

  void setMapsAppUrlTemplateAndroid(String? value) {
    final trimmed = value?.trim();
    mapsAppUrlTemplateAndroid = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void setMapsAppUrlTemplateIos(String? value) {
    final trimmed = value?.trim();
    mapsAppUrlTemplateIos = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void setMapsWebUrlTemplate(String? value) {
    final trimmed = value?.trim();
    mapsWebUrlTemplate = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Platform-specific install URL for HERE WeGo (from remote config).
  String? hereWegoInstallUrlForCurrentPlatform({required bool isIos, required bool isAndroid}) {
    if (isIos) return hereWegoInstallUrlIos;
    if (isAndroid) return hereWegoInstallUrlAndroid;
    return null;
  }

  /// Maps app deep-link template for current platform (remote only).
  String? mapsAppUrlTemplateForCurrentPlatform({required bool isIos, required bool isAndroid}) {
    if (isIos) return mapsAppUrlTemplateIos;
    if (isAndroid) return mapsAppUrlTemplateAndroid;
    return null;
  }

  /// Build URI from a remote template (`{lat}` / `{lng}`).
  Uri? buildUriFromTemplate(String? template, {required double latitude, required double longitude}) {
    if (template == null || template.isEmpty) return null;
    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);
    final raw = template.replaceAll('{lat}', lat).replaceAll('{lng}', lng);
    return Uri.tryParse(raw);
  }

  /// Build maps app deep link from remote config for current platform.
  Uri? buildMapsAppUri({
    required double latitude,
    required double longitude,
    required bool isIos,
    required bool isAndroid,
  }) {
    return buildUriFromTemplate(
      mapsAppUrlTemplateForCurrentPlatform(isIos: isIos, isAndroid: isAndroid),
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Build maps web URL from remote template (`{lat}` / `{lng}`).
  Uri? buildMapsWebUri({required double latitude, required double longitude}) {
    return buildUriFromTemplate(
      mapsWebUrlTemplate,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
