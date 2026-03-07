import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
// V2ThemeRegistry i V2ThemeDefinition se nalaze na dnu ovog fajla (spojeni sa v2_theme_registry.dart)

// THEME MANAGER - Upravljanje trenutnom temom
class V2ThemeManager extends ChangeNotifier {
  factory V2ThemeManager() => _instance;
  V2ThemeManager._internal() {
    _currentTheme = V2ThemeRegistry.getTheme(_currentThemeId) ?? V2ThemeRegistry.defaultTheme;
  }
  static final V2ThemeManager _instance = V2ThemeManager._internal();

  static const String _themePrefsKey = 'selected_theme_id';

  String _currentThemeId = 'triple_blue_fashion';
  V2ThemeDefinition? _currentTheme;
  final ValueNotifier<ThemeData> _themeNotifier = ValueNotifier(V2ThemeRegistry.defaultTheme.themeData);

  /// Trenutna tema ID
  String get currentThemeId => _currentThemeId;

  /// ValueNotifier za reaktivno slušanje tema
  ValueNotifier<ThemeData> get themeNotifier => _themeNotifier;

  /// Trenutna tema definicija
  V2ThemeDefinition get currentTheme => _currentTheme!;

  /// Trenutni ThemeData
  ThemeData get currentThemeData => currentTheme.themeData;

  /// Trenutni gradient
  LinearGradient get currentGradient => currentTheme.gradient;

  /// Trenutni gradijent za pozadinu (shortcut)
  LinearGradient get backgroundGradient => currentGradient;

  /// Initialize - učitaj poslednju selekciju
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedThemeId = prefs.getString(_themePrefsKey);

      if (savedThemeId != null && V2ThemeRegistry.hasTheme(savedThemeId)) {
        // Učitaj sačuvanu temu
        _currentThemeId = savedThemeId;
        _currentTheme = V2ThemeRegistry.getTheme(savedThemeId);
      } else {
        // Fallback na default temu
        final defaultTheme = V2ThemeRegistry.defaultTheme;
        _currentThemeId = defaultTheme.id;
        _currentTheme = defaultTheme;
      }
    } catch (e) {
      debugPrint('[V2ThemeManager] initialize greška: $e');
      final defaultTheme = V2ThemeRegistry.defaultTheme;
      _currentThemeId = defaultTheme.id;
      _currentTheme = defaultTheme;
    }

    _themeNotifier.value = currentThemeData; // Ažuriraj ValueNotifier
    notifyListeners();
  }

  /// Promeni temu
  Future<void> changeTheme(String themeId) async {
    if (!V2ThemeRegistry.hasTheme(themeId)) {
      throw Exception('Tema $themeId ne postoji!');
    }

    // Sačuvaj izbor u SharedPreferences PRE nego ažuriramo state
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePrefsKey, themeId);
    } catch (e) {
      debugPrint('[V2ThemeManager] changeTheme spremi greška: $e');
    }

    _currentThemeId = themeId;
    _currentTheme = V2ThemeRegistry.getTheme(themeId);

    // Obavesti listenere
    _themeNotifier.value = currentThemeData;
    notifyListeners();
  }

  /// Sledeća tema u listi (za cycling)
  Future<void> nextTheme() async {
    final themeNames = V2ThemeRegistry.themeNames;
    final currentIndex = themeNames.indexOf(_currentThemeId);
    final nextIndex = (currentIndex + 1) % themeNames.length;
    await changeTheme(themeNames[nextIndex]);
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    super.dispose();
  }
}

// =============================================================================
// Spojeno iz v2_theme_registry.dart
// =============================================================================

/// Registry svih dostupnih tema aplikacije.
class V2ThemeRegistry {
  V2ThemeRegistry._();

  static final Map<String, V2ThemeDefinition> _themes = {
    'triple_blue_fashion': V2ThemeDefinition(
      id: 'triple_blue_fashion',
      name: '⚡ Triple Blue Fashion',
      description: 'Electric + Ice + Neon kombinacija',
      colorScheme: tripleBlueFashionColorScheme,
      themeData: tripleBlueFashionTheme,
      styles: TripleBlueFashionStyles,
      gradient: tripleBlueFashionGradient,
      isDefault: true,
    ),
    'dark_steel_grey': V2ThemeDefinition(
      id: 'dark_steel_grey',
      name: '🖤 Dark Steel Grey',
      description: 'Triple Blue Fashion sa crno-sivim gradijentom',
      colorScheme: darkSteelGreyColorScheme,
      themeData: tripleBlueFashionTheme,
      styles: DarkSteelGreyStyles,
      gradient: darkSteelGreyGradient,
    ),
    'passionate_rose': V2ThemeDefinition(
      id: 'passionate_rose',
      name: '❤️ Passionate Rose',
      description: 'Electric Red + Ruby + Crimson + Pink Ice kombinacija',
      colorScheme: passionateRoseColorScheme,
      themeData: tripleBlueFashionTheme,
      styles: PassionateRoseStyles,
      gradient: passionateRoseGradient,
    ),
    'dark_pink': V2ThemeDefinition(
      id: 'dark_pink',
      name: '💖 Dark Pink',
      description: 'Tamna tema sa neon pink akcentima',
      colorScheme: darkPinkColorScheme,
      themeData: tripleBlueFashionTheme,
      styles: DarkPinkStyles,
      gradient: darkPinkGradient,
    ),
  };

  static final V2ThemeDefinition _defaultTheme = _themes.values.firstWhere(
    (t) => t.isDefault,
    orElse: () => _themes.values.first,
  );
  static final List<String> _themeNames = List.unmodifiable(_themes.keys);

  static Map<String, V2ThemeDefinition> get allThemes => Map.unmodifiable(_themes);
  static List<String> get themeNames => _themeNames;
  static V2ThemeDefinition? getTheme(String themeId) => _themes[themeId];
  static ThemeData getThemeData(String themeId) => _themes[themeId]?.themeData ?? _defaultTheme.themeData;
  static V2ThemeDefinition get defaultTheme => _defaultTheme;
  static bool hasTheme(String themeId) => _themes.containsKey(themeId);
}

/// Definicija teme — sve sto treba za kompletnu temu.
class V2ThemeDefinition {
  const V2ThemeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.colorScheme,
    required this.themeData,
    required this.styles,
    required this.gradient,
    this.isDefault = false,
    this.tags,
  });
  final String id;
  final String name;
  final String description;
  final ColorScheme colorScheme;
  final ThemeData themeData;
  final Type styles;
  final LinearGradient gradient;
  final bool isDefault;
  final List<String>? tags;

  V2ThemeDefinition copyWith({
    String? id,
    String? name,
    String? description,
    ColorScheme? colorScheme,
    ThemeData? themeData,
    Type? styles,
    LinearGradient? gradient,
    bool? isDefault,
    List<String>? tags,
  }) {
    return V2ThemeDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorScheme: colorScheme ?? this.colorScheme,
      themeData: themeData ?? this.themeData,
      styles: styles ?? this.styles,
      gradient: gradient ?? this.gradient,
      isDefault: isDefault ?? this.isDefault,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2ThemeDefinition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
