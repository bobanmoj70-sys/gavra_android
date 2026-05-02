import 'package:flutter/material.dart';

class V3AppSettingsState {
  V3AppSettingsState._();
  static final V3AppSettingsState instance = V3AppSettingsState._();

  final ValueNotifier<DateTime?> activeWeekStart = ValueNotifier<DateTime?>(null);
  final ValueNotifier<DateTime?> activeWeekEnd = ValueNotifier<DateTime?>(null);

  DateTime? get activeWeekStartValue => activeWeekStart.value;
  DateTime? get activeWeekEndValue => activeWeekEnd.value;

  void setActiveWeekStart(DateTime? value) {
    activeWeekStart.value = value;
  }

  void setActiveWeekEnd(DateTime? value) {
    activeWeekEnd.value = value;
  }
}
