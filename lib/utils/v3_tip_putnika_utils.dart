import 'package:flutter/material.dart';

/// Centralni helper za vizualni prikaz tipa putnika.
/// Koristi se za boje, ikone i badge labele po tipu putnika.
class V3TipPutnikaUtils {
  V3TipPutnikaUtils._();

  /// Vraća boju asociranu sa tipom putnika.
  /// Npr. koristi se za avatar border, badge pozadinu i tekst.
  static Color color(String? tip) {
    return switch ((tip ?? '').toLowerCase()) {
      'vozac' => const Color(0xFF5A5DE8),
      'radnik' => const Color(0xFF3B7DD8),
      'ucenik' => const Color(0xFF44A08D),
      'posiljka' => const Color(0xFFE65C00),
      'dnevni' => const Color(0xFFFF6B6B),
      _ => Colors.grey,
    };
  }

  /// Vraća ikonu asociranu sa tipom putnika.
  static IconData icon(String? tip) {
    return switch ((tip ?? '').toLowerCase()) {
      'vozac' => Icons.directions_car,
      'radnik' => Icons.engineering,
      'ucenik' => Icons.school,
      'dnevni' => Icons.today,
      'posiljka' => Icons.local_shipping,
      _ => Icons.person,
    };
  }

  /// Vraća kratku badge labelu za prikaz u karticama (UPPERCASE).
  /// Npr. 'radnik' → 'RADNIK'
  static String badgeLabel(String? tip) {
    return switch ((tip ?? '').toLowerCase()) {
      'vozac' => 'VOZAC',
      'radnik' => 'RADNIK',
      'ucenik' => 'UCENIK',
      'posiljka' => 'POSILJKA',
      'dnevni' => 'DNEVNI',
      _ => (tip ?? 'PUTNIK').toUpperCase(),
    };
  }
}
