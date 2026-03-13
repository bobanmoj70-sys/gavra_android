import 'package:flutter/material.dart';

/// Centralizovani helper za prikazivanje SnackBar poruka u aplikaciji.
class V2AppSnackBar {
  V2AppSnackBar._();

  static void _show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xFF323232),
    Color textColor = Colors.white,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Zelena — uspješna operacija
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: const Color(0xFF2E7D32),
      icon: Icons.check_circle_outline,
    );
  }

  /// Crvena — greška
  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: const Color(0xFFC62828),
      icon: Icons.error_outline,
      duration: const Duration(seconds: 4),
    );
  }

  /// Plava — informacija
  static void info(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: const Color(0xFF1565C0),
      icon: Icons.info_outline,
    );
  }

  /// Zlatna — upozorenje
  static void warning(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: const Color(0xFFF57F17),
      icon: Icons.warning_amber_outlined,
    );
  }

  /// Ljubičasta — plaćanje/finansije
  static void payment(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: const Color(0xFF6A1B9A),
      icon: Icons.payments_outlined,
    );
  }
}
