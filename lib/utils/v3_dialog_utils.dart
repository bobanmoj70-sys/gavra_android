import 'package:flutter/material.dart';

import 'v3_button_utils.dart';

/// Централизовани утилс за управљање AlertDialog компонентама
/// Елиминише дупликате и обезбеђује конзистентан styling
class V3DialogUtils {
  V3DialogUtils._();

  // Темна боја за позадину дијалога
  static const Color _darkBg = Color(0xFF1A1A1A);
  static const double _defaultBorderRadius = 16;

  static ShapeBorder _buildDialogShape({required double borderRadius, Color? borderColor}) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: borderColor != null ? BorderSide(color: borderColor.withValues(alpha: 0.3)) : BorderSide.none,
    );
  }

  static Widget _buildDialogTitle({
    required String title,
    required IconData titleIcon,
    Color? titleIconColor,
  }) {
    return Row(
      children: [
        Icon(titleIcon, color: titleIconColor ?? Colors.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  /// Основни AlertDialog са стандардним styling-ом
  static Future<T?> showBasicDialog<T>({
    required BuildContext context,
    required String title,
    required String content,
    IconData? titleIcon,
    Color? titleIconColor,
    List<Widget>? actions,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    Color? backgroundColor,
    double borderRadius = _defaultBorderRadius,
    Color? borderColor,
  }) {
    if (!context.mounted) return Future.value(null);

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: _buildDialogShape(borderRadius: borderRadius, borderColor: borderColor),
        title: titleIcon != null
            ? _buildDialogTitle(title: title, titleIcon: titleIcon, titleIconColor: titleIconColor)
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
    bool useRootNavigator = true,
  }) {
    if (!context.mounted) return Future.value(null);

    return showBasicDialog<bool>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      useRootNavigator: useRootNavigator,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.of(context, rootNavigator: useRootNavigator).pop(false),
          text: cancelText,
          foregroundColor: cancelColor ?? Colors.grey,
        ),
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.of(context, rootNavigator: useRootNavigator).pop(true),
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
    bool useRootNavigator = true,
  }) {
    if (!context.mounted) return Future.value();

    return showBasicDialog<void>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      useRootNavigator: useRootNavigator,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.of(context, rootNavigator: useRootNavigator).pop(),
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
    bool useRootNavigator = true,
  }) {
    if (!context.mounted) return Future.value(null);

    final actions = <Widget>[];

    // Додај cancel дугме ако је задато
    if (cancelText != null) {
      actions.add(
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.of(context, rootNavigator: useRootNavigator).pop(),
          text: cancelText,
          foregroundColor: Colors.grey,
        ),
      );
    }

    // Додај дугмад за избор
    for (final entry in choices.entries) {
      actions.add(
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.of(context, rootNavigator: useRootNavigator).pop(entry.key),
          text: entry.value,
          foregroundColor: Colors.amber,
        ),
      );
    }

    return showBasicDialog<String>(
      context: context,
      title: title,
      content: content,
      titleIcon: titleIcon,
      titleIconColor: titleIconColor,
      useRootNavigator: useRootNavigator,
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
    bool useRootNavigator = true,
    Color? backgroundColor,
    double borderRadius = _defaultBorderRadius,
    Color? borderColor,
  }) {
    if (!context.mounted) return Future.value(null);

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: _buildDialogShape(borderRadius: borderRadius, borderColor: borderColor),
        title: titleIcon != null
            ? _buildDialogTitle(title: title, titleIcon: titleIcon, titleIconColor: titleIconColor)
            : Text(title, style: const TextStyle(color: Colors.white)),
        content: content,
        actions: actions,
      ),
    );
  }
}
