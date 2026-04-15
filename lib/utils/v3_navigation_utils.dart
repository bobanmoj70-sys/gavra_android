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
