import 'package:flutter/material.dart';

import 'v3_theme_registry.dart';

/// Menadžer tema — in-memory, bez persistencije.
/// Koristi V2ThemeRegistry za definicije tema.
class V2ThemeManager extends ChangeNotifier {
  factory V2ThemeManager() => _instance;
  V2ThemeManager._internal() {
    _currentTheme = V2ThemeRegistry.defaultTheme;
    _currentThemeId = _currentTheme.id;
    _themeNotifier = ValueNotifier(_currentTheme.themeData);
  }
  static final V2ThemeManager _instance = V2ThemeManager._internal();

  late String _currentThemeId;
  late V2ThemeDefinition _currentTheme;
  late final ValueNotifier<ThemeData> _themeNotifier;

  /// Trenutna tema ID
  String get currentThemeId => _currentThemeId;

  /// ValueNotifier za reaktivno slušanje tema (za MaterialApp)
  ValueNotifier<ThemeData> get themeNotifier => _themeNotifier;

  /// Trenutna tema definicija
  V2ThemeDefinition get currentTheme => _currentTheme;

  /// Trenutni ThemeData
  ThemeData get currentThemeData => _currentTheme.themeData;

  /// Trenutni gradijent
  LinearGradient get currentGradient => _currentTheme.gradient;

  /// Alias — za kompatibilnost sa theme.dart extension
  LinearGradient get backgroundGradient => currentGradient;

  /// Promeni temu po ID-u
  Future<void> changeTheme(String themeId) async {
    if (!V2ThemeRegistry.hasTheme(themeId)) return;
    _currentThemeId = themeId;
    _currentTheme = V2ThemeRegistry.getTheme(themeId)!;
    _themeNotifier.value = _currentTheme.themeData;
    _themeNotifier.notifyListeners();
    notifyListeners();
  }

  /// Sledeća tema u listi (cycling)
  Future<void> nextTheme() async {
    final names = V2ThemeRegistry.themeNames;
    final next = (names.indexOf(_currentThemeId) + 1) % names.length;
    await changeTheme(names[next]);
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    super.dispose();
  }
}
