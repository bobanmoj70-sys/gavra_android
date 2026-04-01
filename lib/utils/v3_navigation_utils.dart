import 'package:flutter/material.dart';

/// Centralizovane navigation utility funkcije za konzistentan UX.
/// Eliminiše duplikate Navigator.push, showDialog, pushReplacement poziva.
class V3NavigationUtils {
  V3NavigationUtils._();

  // ─── SCREEN NAVIGATION ─────────────────────────────────────────────────

  /// Standardni push sa MaterialPageRoute
  static Future<T?> pushScreen<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
  }) async {
    if (!context.mounted) return null;
    return Navigator.push<T>(
      context,
      MaterialPageRoute<T>(
        builder: (_) => screen,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }

  /// Push and remove until - zamenjuje sve prethodne ekrane
  static Future<T?> pushAndRemoveUntil<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool Function(Route<dynamic>)? predicate,
  }) async {
    if (!context.mounted) return null;
    return Navigator.pushAndRemoveUntil<T>(
      context,
      MaterialPageRoute<T>(builder: (_) => screen),
      predicate ?? (route) => false,
    );
  }

  /// Push replacement - zamenjuje trenutni ekran
  static Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    BuildContext context,
    Widget screen, {
    TO? result,
  }) async {
    if (!context.mounted) return null;
    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute<T>(builder: (_) => screen),
      result: result,
    );
  }

  /// Pop sa rezultatom
  static void pop<T extends Object?>(
    BuildContext context, [
    T? result,
    bool useRootNavigator = false,
  ]) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: useRootNavigator).pop<T>(result);
  }

  // ─── DIALOG UTILITIES ──────────────────────────────────────────────────

  /// Standardni confirm dialog sa Yes/No dugmićima
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Da',
    String cancelText = 'Ne',
    bool isDangerous = false,
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted) return null;
    return showDialog<bool>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: useRootNavigator).pop(false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: useRootNavigator).pop(true),
            style: isDangerous ? TextButton.styleFrom(foregroundColor: Colors.red) : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// Info dialog sa OK dugmetom
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
    String okText = 'OK',
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: useRootNavigator).pop(),
            child: Text(okText),
          ),
        ],
      ),
    );
  }

  /// Error dialog sa crvenim stilom
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String okText = 'OK',
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(color: Colors.red),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: useRootNavigator).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(okText),
          ),
        ],
      ),
    );
  }

  /// Loading dialog koji se može zatvoriti programski
  static Future<void> showLoadingDialog(
    BuildContext context, {
    String message = 'Učitavanje...',
    bool barrierDismissible = false,
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// Custom dialog wrapper sa standardnim stilom
  static Future<T?> showCustomDialog<T>(
    BuildContext context, {
    required Widget child,
    bool barrierDismissible = true,
    Color? barrierColor,
    bool useRootNavigator = true,
  }) async {
    if (!context.mounted) return null;
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => child,
    );
  }

  // ─── BOTTOM SHEET UTILITIES ────────────────────────────────────────────

  /// Standardni bottom sheet
  static Future<T?> showBottomSheet<T>(
    BuildContext context, {
    required Widget child,
    bool isScrollControlled = true,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = false,
  }) async {
    if (!context.mounted) return null;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => child,
    );
  }

  // ─── ADVANCED NAVIGATION ───────────────────────────────────────────────

  /// Push named route
  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) async {
    if (!context.mounted) return null;
    return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
  }

  /// Push named and remove until
  static Future<T?> pushNamedAndRemoveUntil<T extends Object?>(
    BuildContext context,
    String newRouteName, {
    bool Function(Route<dynamic>)? predicate,
    Object? arguments,
  }) async {
    if (!context.mounted) return null;
    return Navigator.pushNamedAndRemoveUntil<T>(
      context,
      newRouteName,
      predicate ?? (route) => false,
      arguments: arguments,
    );
  }

  /// Push replacement named
  static Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(
    BuildContext context,
    String routeName, {
    TO? result,
    Object? arguments,
  }) async {
    if (!context.mounted) return null;
    return Navigator.pushReplacementNamed<T, TO>(
      context,
      routeName,
      result: result,
      arguments: arguments,
    );
  }

  /// Pop until route
  static void popUntil(BuildContext context, String routeName) {
    if (!context.mounted) return;
    Navigator.popUntil(context, ModalRoute.withName(routeName));
  }

  /// Pop and push (restart navigation stack)
  static Future<T?> popAndPush<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool useRootNavigator = false,
  }) async {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    if (navigator.canPop()) {
      navigator.pop();
    }
    return navigator.push<T>(MaterialPageRoute<T>(builder: (_) => screen));
  }

  // ─── VALIDATION HELPERS ────────────────────────────────────────────────

  /// Proverava da li je context još uvek mounted
  static bool isMounted(BuildContext context) {
    return context.mounted;
  }

  /// Safe navigation - izvršava akciju samo ako je context mounted
  static T? safeNavigate<T>(BuildContext context, T Function() action) {
    if (!context.mounted) return null;
    return action();
  }
}
