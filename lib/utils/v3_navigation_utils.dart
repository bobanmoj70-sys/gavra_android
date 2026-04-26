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
}
