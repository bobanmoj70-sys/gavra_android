import 'package:flutter/material.dart';

import 'v3_app_snack_bar.dart';

/// V3 Error Handling Utilities
/// Centralizes error handling patterns across V3 screens/widgets
///
/// KORISTI: Eliminiše dupliciranje if(mounted) V3AppSnackBar.error poziva
/// SIGURNOST: Automatski mounted check + consistent error formatting
class V3ErrorUtils {
  V3ErrorUtils._();

  static const String _fallbackError = 'Greška';
  static const String _networkErrorMessage = '📶 Internet je slab ili nedostupan. Proverite vezu i pokušajte ponovo.';
  static const String _genericServerErrorMessage = '⚠️ Trenutno ne možemo da obradimo zahtev. Pokušajte ponovo.';

  static bool _isConnectivityError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('clientexception') ||
        lower.contains('http exception') ||
        lower.contains('network request failed') ||
        lower.contains('temporary failure in name resolution');
  }

  static bool _isTechnicalBackendError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('postgrestexception') ||
        lower.contains('postgres') ||
        lower.contains('supabase') ||
        lower.contains('sqlstate') ||
        lower.contains('function_response') ||
        lower.contains('grpc') ||
        lower.contains('statuscode(') ||
        lower.contains('status code');
  }

  static String toUserMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return _fallbackError;
    }

    if (_isConnectivityError(trimmed)) {
      return _networkErrorMessage;
    }

    if (_isTechnicalBackendError(trimmed)) {
      return _genericServerErrorMessage;
    }

    if (trimmed.startsWith('❌')) {
      final withoutPrefix = trimmed.replaceFirst(RegExp(r'^(❌\s*)+'), '').trimLeft();
      return '❌ $withoutPrefix';
    }

    return trimmed;
  }

  static String _normalizeErrorMessage(String message) {
    return toUserMessage(message);
  }

  /// Safely show error message with mounted check
  ///
  /// **Koristi umesto:** if (mounted) V3AppSnackBar.error(context, 'message');
  /// **Primjer:** V3ErrorUtils.safeError(this, context, 'Greška: $e');
  static void safeError(State state, BuildContext context, String message) {
    if (state.mounted) {
      final normalized = _normalizeErrorMessage(message);
      if (_isConnectivityError(message)) {
        V3AppSnackBar.warning(context, normalized);
        return;
      }
      V3AppSnackBar.error(context, normalized);
    }
  }

  /// Safely show error using BuildContext.mounted (for non-State callers)
  static void safeErrorContext(BuildContext context, String message) {
    if (context.mounted) {
      final normalized = _normalizeErrorMessage(message);
      if (_isConnectivityError(message)) {
        V3AppSnackBar.warning(context, normalized);
        return;
      }
      V3AppSnackBar.error(context, normalized);
    }
  }

  /// Show standard async operation error
  ///
  /// **Koristi umesto:** if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
  /// **Primjer:** V3ErrorUtils.asyncError(this, context, e);
  static void asyncError(State state, BuildContext context, dynamic error) {
    safeError(state, context, '❌ Greška: $error');
  }

  /// Show validation error message
  ///
  /// **Koristi umesto:** if (mounted) V3AppSnackBar.error(context, '❌ Validation message');
  /// **Primjer:** V3ErrorUtils.validationError(this, context, 'Pogrešan unos');
  static void validationError(State state, BuildContext context, String message) {
    safeError(state, context, '❌ $message');
  }

  /// Show permission error message
  ///
  /// **Koristi umesto:** if (mounted) V3AppSnackBar.error(context, 'Permission message');
  /// **Primjer:** V3ErrorUtils.permissionError(this, context, 'Dozvola je potrebna');
  static void permissionError(State state, BuildContext context, String message) {
    safeError(state, context, message);
  }
}
