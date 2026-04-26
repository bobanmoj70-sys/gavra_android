import 'package:flutter/material.dart';

import 'v3_app_snack_bar.dart';

/// V3 Error Handling Utilities
/// Centralizes error handling patterns across V3 screens/widgets
///
/// KORISTI: Eliminiše dupliciranje if(mounted) V3AppSnackBar.error poziva
/// SIGURNOST: Automatski mounted check + consistent error formatting
class V3ErrorUtils {
  V3ErrorUtils._();

  static String _normalizeErrorMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return 'Greška';
    }

    if (trimmed.startsWith('❌')) {
      final withoutPrefix = trimmed.replaceFirst(RegExp(r'^(❌\s*)+'), '').trimLeft();
      return '❌ $withoutPrefix';
    }

    return trimmed;
  }

  /// Safely show error message with mounted check
  ///
  /// **Koristi umjesto:** if (mounted) V3AppSnackBar.error(context, 'message');
  /// **Primjer:** V3ErrorUtils.safeError(this, context, 'Greška: $e');
  static void safeError(State state, BuildContext context, String message) {
    if (state.mounted) {
      V3AppSnackBar.error(context, _normalizeErrorMessage(message));
    }
  }

  /// Safely show error using BuildContext.mounted (for non-State callers)
  static void safeErrorContext(BuildContext context, String message) {
    if (context.mounted) {
      V3AppSnackBar.error(context, _normalizeErrorMessage(message));
    }
  }

  /// Show standard async operation error
  ///
  /// **Koristi umjesto:** if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
  /// **Primjer:** V3ErrorUtils.asyncError(this, context, e);
  static void asyncError(State state, BuildContext context, dynamic error) {
    safeError(state, context, '❌ Greška: $error');
  }

  /// Show validation error message
  ///
  /// **Koristi umjesto:** if (mounted) V3AppSnackBar.error(context, '❌ Validation message');
  /// **Primjer:** V3ErrorUtils.validationError(this, context, 'Pogrešan unos');
  static void validationError(State state, BuildContext context, String message) {
    safeError(state, context, '❌ $message');
  }

  /// Show permission error message
  ///
  /// **Koristi umjesto:** if (mounted) V3AppSnackBar.error(context, 'Permission message');
  /// **Primjer:** V3ErrorUtils.permissionError(this, context, 'Dozvola je potrebna');
  static void permissionError(State state, BuildContext context, String message) {
    safeError(state, context, message);
  }
}
