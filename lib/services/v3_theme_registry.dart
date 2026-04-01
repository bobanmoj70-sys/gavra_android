import 'package:flutter/material.dart';

import '../theme.dart';

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
    'night_blue': V2ThemeDefinition(
      id: 'night_blue',
      name: '🌙 Night Blue',
      description: 'Tema iz nijansi Pošiljke gradient screenshot-a',
      colorScheme: nightBlueColorScheme,
      themeData: nightBlueTheme,
      styles: NightBlueStyles,
      gradient: nightBlueGradient,
    ),
  };

  // Keširane vrijednosti — izracunavaju se jednom
  static final V2ThemeDefinition _defaultTheme = _themes.values.firstWhere(
    (t) => t.isDefault,
    orElse: () => _themes.values.first,
  );
  static final List<String> _themeNames = List.unmodifiable(_themes.keys);

  /// Vraća sve dostupne teme
  static Map<String, V2ThemeDefinition> get allThemes => Map.unmodifiable(_themes);

  /// Vraća listu ID-eva tema (keširana, nealocira novu listu pri svakom pozivu)
  static List<String> get themeNames => _themeNames;

  /// Vraća temu po ID-u
  static V2ThemeDefinition? getTheme(String themeId) => _themes[themeId];

  /// Vraća ThemeData po ID-u
  static ThemeData getThemeData(String themeId) {
    return _themes[themeId]?.themeData ?? _defaultTheme.themeData;
  }

  /// Vraća default temu (keširana)
  static V2ThemeDefinition get defaultTheme => _defaultTheme;

  /// Proverava da li tema postoji
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
  final Type styles; // TripleBlueFashionStyles, itd.
  final LinearGradient gradient;
  final bool isDefault;
  final List<String>? tags;

  /// Kreira kopiju sa izmenjenim vrednostima
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
