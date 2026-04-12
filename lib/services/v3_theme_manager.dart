import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'v3_theme_registry.dart';

/// Menadžer tema — in-memory, bez persistencije.
/// Koristi V3ThemeRegistry za definicije tema.
class V3ThemeManager extends ChangeNotifier {
  factory V3ThemeManager() => _instance;
  V3ThemeManager._internal() {
    _currentTheme = V3ThemeRegistry.defaultTheme;
    _currentThemeId = _currentTheme.id;
    _themeNotifier = ValueNotifier(_currentTheme.themeData);
  }
  static final V3ThemeManager _instance = V3ThemeManager._internal();
  static const FlutterSecureStorage _secureStorage =
      FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _themeStorageKey = 'v3_theme_id';

  late String _currentThemeId;
  late V3ThemeDefinition _currentTheme;
  late final ValueNotifier<ThemeData> _themeNotifier;

  /// Trenutna tema ID
  String get currentThemeId => _currentThemeId;

  /// ValueNotifier za reaktivno slušanje tema (za MaterialApp)
  ValueNotifier<ThemeData> get themeNotifier => _themeNotifier;

  /// Trenutna tema definicija
  V3ThemeDefinition get currentTheme => _currentTheme;

  /// Trenutni ThemeData
  ThemeData get currentThemeData => _currentTheme.themeData;

  /// Trenutni gradijent
  LinearGradient get currentGradient => _currentTheme.gradient;

  /// Alias — za kompatibilnost sa theme.dart extension
  LinearGradient get backgroundGradient => currentGradient;

  /// Promeni temu po ID-u
  Future<void> changeTheme(String themeId) async {
    if (!V3ThemeRegistry.hasTheme(themeId)) return;
    _currentThemeId = themeId;
    _currentTheme = V3ThemeRegistry.getTheme(themeId)!;
    await _persistThemeId(themeId);
    _themeNotifier.value = _currentTheme.themeData;
    _themeNotifier.notifyListeners();
    notifyListeners();
  }

  /// Učitaj temu iz secure storage (pozvati pre MaterialApp kada je moguće).
  Future<void> loadThemeFromStorage() async {
    try {
      final storedThemeId = await _secureStorage.read(key: _themeStorageKey);
      if (storedThemeId == null || storedThemeId.isEmpty) return;
      if (!V3ThemeRegistry.hasTheme(storedThemeId)) return;

      _currentThemeId = storedThemeId;
      _currentTheme = V3ThemeRegistry.getTheme(storedThemeId)!;
      _themeNotifier.value = _currentTheme.themeData;
      _themeNotifier.notifyListeners();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistThemeId(String themeId) async {
    try {
      await _secureStorage.write(key: _themeStorageKey, value: themeId);
    } catch (_) {}
  }

  /// Sledeća tema u listi (cycling)
  Future<void> nextTheme() async {
    final names = V3ThemeRegistry.themeNames;
    final next = (names.indexOf(_currentThemeId) + 1) % names.length;
    await changeTheme(names[next]);
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    super.dispose();
  }
}
