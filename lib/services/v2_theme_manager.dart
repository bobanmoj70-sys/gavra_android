import 'package:flutter/material.dart';

/// Menadžer tema — pruža gradijente pozadine za aplikaciju.
class V2ThemeManager {
  static final V2ThemeManager _instance = V2ThemeManager._internal();
  factory V2ThemeManager() => _instance;
  V2ThemeManager._internal();

  int _currentThemeIndex = 0;

  final List<LinearGradient> _gradients = [
    // Tamno plava (Originalna Gavra tema)
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF0A0A1A),
        Color(0xFF0D1B2A),
        Color(0xFF0A1628),
      ],
      stops: [0.0, 0.5, 1.0],
    ),
    // Deep Space
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF000000),
        Color(0xFF1A1A2E),
        Color(0xFF16213E),
      ],
    ),
    // Midnight Purple
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF0F0C29),
        Color(0xFF302B63),
        Color(0xFF24243E),
      ],
    ),
    // Emerald Dark
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF000000),
        Color(0xFF0F2027),
        Color(0xFF203A43),
      ],
    ),
  ];

  /// Menja temu na sledeću u listi
  Future<void> nextTheme() async {
    _currentThemeIndex = (_currentThemeIndex + 1) % _gradients.length;
  }

  /// Trenutni gradijent pozadine
  LinearGradient get currentGradient => _gradients[_currentThemeIndex];
}
