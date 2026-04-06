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
  /// **Primjer:** V3ErrorUtils.permissionError(this, context, 'GPS dozvola je potrebna');
  static void permissionError(State state, BuildContext context, String message) {
    safeError(state, context, message);
  }

  /// Show network/connection error
  ///
  /// **Koristi umjesto:** ručnog network error handling-a
  /// **Primjer:** V3ErrorUtils.networkError(this, context, 'Nema internet konekcije');
  static void networkError(State state, BuildContext context, [String? customMessage]) {
    safeError(state, context, customMessage ?? '🌐 Greška sa mrežom - proverite internet konekciju');
  }

  /// Show operation specific error with context
  ///
  /// **Koristi umjesto:** ručnog formatiranja error poruka
  /// **Primjer:** V3ErrorUtils.operationError(this, context, 'čuvanje podataka', e);
  static void operationError(State state, BuildContext context, String operation, dynamic error) {
    safeError(state, context, 'Greška pri $operation: $error');
  }

  /// Execute async operation with automatic error handling
  ///
  /// **Koristi umjesto:** ručnog try-catch sa error display
  /// **Primjer:** await V3ErrorUtils.safeExecute(this, context, () async { ... });
  static Future<T?> safeExecute<T>(
    State state,
    BuildContext context,
    Future<T> Function() operation, {
    String? errorPrefix,
    bool showSuccessMessage = false,
    String? successMessage,
  }) async {
    try {
      final result = await operation();
      if (showSuccessMessage && successMessage != null && state.mounted) {
        V3AppSnackBar.success(context, successMessage);
      }
      return result;
    } catch (e) {
      final prefix = errorPrefix ?? 'Greška';
      safeError(state, context, '$prefix: $e');
      return null;
    }
  }

  /// Execute async operation with custom error handler
  ///
  /// **Koristi umjesto:** komplikovanih try-catch blokova
  /// **Primjer:** await V3ErrorUtils.executeWithHandler(this, context, () async { ... }, (e) => 'Custom: $e');
  static Future<T?> executeWithHandler<T>(
    State state,
    BuildContext context,
    Future<T> Function() operation,
    String Function(dynamic) errorHandler,
  ) async {
    try {
      return await operation();
    } catch (e) {
      safeError(state, context, errorHandler(e));
      return null;
    }
  }

  /// Validate and show error if validation fails
  ///
  /// **Koristi umjesto:** ručnog validation + error display
  /// **Primjer:** if (!V3ErrorUtils.validate(this, context, broj.isNotEmpty, 'Polje je obavezno')) return;
  static bool validate(
    State state,
    BuildContext context,
    bool condition,
    String errorMessage,
  ) {
    if (!condition) {
      validationError(state, context, errorMessage);
      return false;
    }
    return true;
  }

  /// Batch validation with multiple conditions
  ///
  /// **Koristi umjesto:** višestruke validation provjere
  /// **Primjer:** if (!V3ErrorUtils.validateAll(this, context, [
  ///   (broj.isNotEmpty, 'Polje je obavezno'),
  ///   (password.length >= 6, 'Šifra mora imati min 6 karaktera')
  /// ])) return;
  static bool validateAll(
    State state,
    BuildContext context,
    List<(bool, String)> validations,
  ) {
    for (final (condition, message) in validations) {
      if (!validate(state, context, condition, message)) {
        return false;
      }
    }
    return true;
  }
}
