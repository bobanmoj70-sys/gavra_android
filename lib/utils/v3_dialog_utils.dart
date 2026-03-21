import 'package:flutter/material.dart';

import 'v3_button_utils.dart';

/// Централизовани утилс за управљање AlertDialog компонентама
/// Елиминише дупликате и обезбеђује конзистентан styling
class V3DialogUtils {
  // Темна боја за позадину дијалога
  static const Color _darkBg = Color(0xFF1A1A1A);
  static const Color _altDarkBg = Color(0xFF1a1a2e);

  /// Основни AlertDialog са стандардним styling-ом
  static Future<T?> showBasicDialog<T>({
    required BuildContext context,
    required String title,
    required String content,
    IconData? titleIcon,
    Color? titleIconColor,
    List<Widget>? actions,
    bool barrierDismissible = true,
    Color? backgroundColor,
    double borderRadius = 16,
    Color? borderColor,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor != null ? BorderSide(color: borderColor.withValues(alpha: 0.3)) : BorderSide.none,
        ),
        title: titleIcon != null
            ? Row(
                children: [
                  Icon(titleIcon, color: titleIconColor ?? Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: const TextStyle(color: Colors.white)),
                  ),
                ],
              )
            : Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          content,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: actions,
      ),
    );
  }

  /// Потврдни дијалог (Yes/No)
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    IconData? titleIcon,
    Color? titleIconColor,
    String confirmText = 'Da',
    String cancelText = 'Ne',
    Color? confirmColor,
    Color? cancelColor,
  }) {
    return showBasicDialog<bool>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, false),
          text: cancelText,
          foregroundColor: cancelColor ?? Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, true),
          text: confirmText,
          foregroundColor: confirmColor ?? Colors.amber,
        ),
      ],
    );
  }

  /// Информативни дијалог са једним дугметом
  static Future<void> showInfoDialog({
    required BuildContext context,
    required String title,
    required String content,
    IconData? titleIcon,
    Color? titleIconColor,
    String buttonText = 'U redu',
    Color? buttonColor,
  }) {
    return showBasicDialog<void>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: buttonText,
          foregroundColor: buttonColor ?? Colors.amber,
        ),
      ],
    );
  }

  /// Дијалог са избором (више опција)
  static Future<String?> showChoiceDialog({
    required BuildContext context,
    required String title,
    required String content,
    required Map<String, String> choices, // key -> display text
    IconData? titleIcon,
    Color? titleIconColor,
    String? cancelText,
  }) {
    final actions = <Widget>[];

    // Додај cancel дугме ако је задато
    if (cancelText != null) {
      actions.add(
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: cancelText,
          foregroundColor: Colors.grey,
        ),
      );
    }

    // Додај дугмад за избор
    choices.forEach((key, displayText) {
      actions.add(
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context, key),
          text: displayText,
          foregroundColor: Colors.amber,
        ),
      );
    });

    return showBasicDialog<String>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      actions: actions,
    );
  }

  /// Дијалог са custom content-ом (за сложене случајеве)
  static Future<T?> showCustomDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    IconData? titleIcon,
    Color? titleIconColor,
    List<Widget>? actions,
    bool barrierDismissible = true,
    Color? backgroundColor,
    double borderRadius = 16,
    Color? borderColor,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor != null ? BorderSide(color: borderColor.withValues(alpha: 0.3)) : BorderSide.none,
        ),
        title: titleIcon != null
            ? Row(
                children: [
                  Icon(titleIcon, color: titleIconColor ?? Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: const TextStyle(color: Colors.white)),
                  ),
                ],
              )
            : Text(title, style: const TextStyle(color: Colors.white)),
        content: content,
        actions: actions,
      ),
    );
  }
}
