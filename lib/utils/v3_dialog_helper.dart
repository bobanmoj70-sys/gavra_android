import 'package:flutter/material.dart';

import 'v3_button_utils.dart';

/// 🎖️💥 V3DIALOGHELPER - CENTRALIZOVANI DIALOG DUPLIKATE ELIMINATOR! 💥🎖️
/// Konsoliduje sve showDialog, showModalBottomSheet, showConfirmDialog duplikate
/// u jedinstvenu centralizovanu utility klasu sa standardnim styling-om
class V3DialogHelper {
  V3DialogHelper._();

  // ─── KONSTANTE STYLING ─────────────────────────────────────────────────────

  static const Color _darkBg = Color(0xFF1A1A1A);
  static const Color _altDarkBg = Color(0xFF1a1a2e);
  static const Color _gradientDark1 = Color(0xFF1a1a2e);
  static const Color _gradientDark2 = Color(0xFF16213e);
  static const double _defaultBorderRadius = 16.0;
  static const Duration _animationDuration = Duration(milliseconds: 250);

  // ─── OSNOVNI DIALOG METODI ─────────────────────────────────────────────────

  /// Osnovni AlertDialog sa standardnim styling-om
  static Future<T?> showBasicDialog<T>({
    required BuildContext context,
    required String title,
    required String content,
    IconData? titleIcon,
    Color? titleIconColor,
    List<Widget>? actions,
    bool barrierDismissible = true,
    Color? backgroundColor,
    double borderRadius = _defaultBorderRadius,
    Color? borderColor,
  }) {
    if (!context.mounted) return Future.value(null);

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor != null
              ? BorderSide(color: borderColor.withValues(alpha: 0.3))
              : BorderSide.none,
        ),
        title: titleIcon != null
            ? Row(
                children: [
                  Icon(titleIcon, color: titleIconColor ?? Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(color: Colors.white)),
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

  /// Custom dialog sa widget content-om
  static Future<T?> showCustomDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    IconData? titleIcon,
    Color? titleIconColor,
    List<Widget>? actions,
    bool barrierDismissible = true,
    Color? backgroundColor,
    double borderRadius = _defaultBorderRadius,
    Color? borderColor,
  }) {
    if (!context.mounted) return Future.value(null);

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor != null
              ? BorderSide(color: borderColor.withValues(alpha: 0.3))
              : BorderSide.none,
        ),
        title: titleIcon != null
            ? Row(
                children: [
                  Icon(titleIcon, color: titleIconColor ?? Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              )
            : Text(title, style: const TextStyle(color: Colors.white)),
        content: content,
        actions: actions,
      ),
    );
  }

  // ─── CONFIRM/INFO DIALOG METODI ────────────────────────────────────────────

  /// Potvrdan dialog (Yes/No) - kompatibilan sa V3NavigationUtils API
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message, // V3NavigationUtils koristi 'message'
    String confirmText = 'Da',
    String cancelText = 'Ne',
    IconData? titleIcon,
    Color? titleIconColor,
    Color? confirmColor,
    Color? cancelColor,
    bool isDangerous = false,
  }) {
    if (!context.mounted) return Future.value(null);

    return showBasicDialog<bool>(
      context: context,
      title: title,
      content: message, // message → content mapping
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
          foregroundColor:
              isDangerous ? Colors.red : (confirmColor ?? Colors.amber),
        ),
      ],
    );
  }

  /// Info dialog sa jednim dugmetom
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

  /// Error dialog sa crvenim stilom
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
  }) {
    return showBasicDialog<void>(
      context: context,
      title: title,
      content: message,
      titleIcon: Icons.error,
      titleIconColor: Colors.red,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: okText,
          foregroundColor: Colors.red,
        ),
      ],
    );
  }

  /// Success dialog sa zelenim stilom
  static Future<void> showSuccessDialog({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
  }) {
    return showBasicDialog<void>(
      context: context,
      title: title,
      content: message,
      titleIcon: Icons.check_circle,
      titleIconColor: Colors.green,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: okText,
          foregroundColor: Colors.green,
        ),
      ],
    );
  }

  /// Warning dialog sa narandžastim stilom
  static Future<void> showWarningDialog({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
  }) {
    return showBasicDialog<void>(
      context: context,
      title: title,
      content: message,
      titleIcon: Icons.warning,
      titleIconColor: Colors.orange,
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: okText,
          foregroundColor: Colors.orange,
        ),
      ],
    );
  }

  // ─── CHOICE/SELECTION DIALOGI ──────────────────────────────────────────────

  /// Dialog sa više opcija
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

    // Dodaj cancel dugme ako je zadato
    if (cancelText != null) {
      actions.add(
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: cancelText,
          foregroundColor: Colors.grey,
        ),
      );
    }

    // Dodaj dugmad za izbor
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

  /// Simple dialog sa listom opcija
  static Future<T?> showSimpleDialog<T>({
    required BuildContext context,
    required String title,
    required List<SimpleDialogOption> options,
    Color? backgroundColor,
    double borderRadius = _defaultBorderRadius,
    Color? borderColor,
  }) {
    if (!context.mounted) return Future.value(null);

    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor != null
              ? BorderSide(color: borderColor.withValues(alpha: 0.3))
              : BorderSide.none,
        ),
        children: options,
      ),
    );
  }

  // ─── LOADING DIALOGI ───────────────────────────────────────────────────────

  /// Loading dialog koji se može zatvoriti programski
  static Future<void> showLoadingDialog({
    required BuildContext context,
    String message = 'Učitavanje...',
    bool barrierDismissible = false,
    Color? backgroundColor,
  }) {
    if (!context.mounted) return Future.value();

    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_defaultBorderRadius),
        ),
        content: Row(
          children: [
            const CircularProgressIndicator(color: Colors.amber),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Progress dialog sa progress barom
  static Future<void> showProgressDialog({
    required BuildContext context,
    required String title,
    required double progress, // 0.0 - 1.0
    String? subtitle,
    bool barrierDismissible = false,
    Color? backgroundColor,
  }) {
    if (!context.mounted) return Future.value();

    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: backgroundColor ?? _darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_defaultBorderRadius),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 16),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM SHEET DIALOGI ──────────────────────────────────────────────────

  /// Standardni modal bottom sheet
  static Future<T?> showBottomSheet<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = false,
    bool enableDrag = true,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
  }) {
    if (!context.mounted) return Future.value(null);

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor ?? Colors.transparent,
      elevation: elevation,
      shape: shape,
      builder: (ctx) => child,
    );
  }

  /// Gradient styled bottom sheet
  static Future<T?> showGradientBottomSheet<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
    bool enableDrag = true,
    double borderRadius = 20.0,
    Color? borderColor,
    Gradient? gradient,
  }) {
    if (!context.mounted) return Future.value(null);

    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      enableDrag: enableDrag,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          gradient: gradient ??
              const LinearGradient(
                colors: [_gradientDark1, _gradientDark2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(borderRadius),
          ),
          border: borderColor != null
              ? Border.all(color: borderColor.withValues(alpha: 0.2))
              : null,
        ),
        child: child,
      ),
    );
  }

  // ─── INPUT DIALOGI ─────────────────────────────────────────────────────────

  /// Text input dialog
  static Future<String?> showTextInputDialog({
    required BuildContext context,
    required String title,
    required String hintText,
    String? initialValue,
    TextInputType keyboardType = TextInputType.text,
    String confirmText = 'Potvrdi',
    String cancelText = 'Otkaži',
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final controller = TextEditingController(text: initialValue);
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: _darkBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_defaultBorderRadius),
          ),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              errorText: errorText,
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.amber),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
            onChanged: (value) {
              if (validator != null) {
                final error = validator(value);
                if (error != errorText) {
                  setState(() => errorText = error);
                }
              }
            },
          ),
          actions: [
            V3ButtonUtils.textButton(
              onPressed: () {
                controller.dispose();
                Navigator.pop(ctx);
              },
              text: cancelText,
              foregroundColor: Colors.grey,
            ),
            V3ButtonUtils.textButton(
              onPressed: () {
                final value = controller.text;
                if (validator != null) {
                  final error = validator(value);
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                }
                controller.dispose();
                Navigator.pop(ctx, value);
              },
              text: confirmText,
              foregroundColor: Colors.amber,
            ),
          ],
        ),
      ),
    );
  }

  // ─── UTILITY METODI ────────────────────────────────────────────────────────

  /// Zatvara sve trenutno otvorene dialoge
  static void closeAllDialogs(BuildContext context) {
    while (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Proverava da li je dialog otvoren
  static bool isDialogOpen(BuildContext context) {
    return ModalRoute.of(context)?.isCurrent != true;
  }

  /// Standardne dialog akcije (cancel/confirm)
  static List<Widget> standardActions({
    required BuildContext context,
    String cancelText = 'Otkaži',
    VoidCallback? onCancel,
    required String confirmText,
    required VoidCallback onConfirm,
    bool isDestructive = false,
    bool isLoading = false,
  }) {
    return [
      V3ButtonUtils.textButton(
        onPressed: onCancel ?? () => Navigator.pop(context),
        text: cancelText,
        foregroundColor: Colors.grey,
      ),
      V3ButtonUtils.textButton(
        onPressed: isLoading ? null : onConfirm,
        text: isLoading ? 'Radi...' : confirmText,
        foregroundColor: isDestructive ? Colors.red : Colors.amber,
      ),
    ];
  }
}
