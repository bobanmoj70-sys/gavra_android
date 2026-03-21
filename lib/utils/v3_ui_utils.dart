import 'package:flutter/material.dart';

import 'v3_app_snack_bar.dart';

/// Centralizovane UI utility funkcije za česte patterne.
/// Eliminiše duplikate if(mounted) + SnackBar poziva.
class V3UIUtils {
  V3UIUtils._();

  // ─── SAFE SNACKBAR METHODS ─────────────────────────────────────────

  /// Sigurno prikazuje success SnackBar samo ako je widget mounted
  static void showSuccess(BuildContext context, String message) {
    if (context.mounted) {
      V3AppSnackBar.success(context, message);
    }
  }

  /// Sigurno prikazuje error SnackBar samo ako je widget mounted
  static void showError(BuildContext context, String message) {
    if (context.mounted) {
      V3AppSnackBar.error(context, message);
    }
  }

  /// Sigurno prikazuje warning SnackBar samo ako je widget mounted
  static void showWarning(BuildContext context, String message) {
    if (context.mounted) {
      V3AppSnackBar.warning(context, message);
    }
  }

  /// Sigurno prikazuje info SnackBar samo ako je widget mounted
  static void showInfo(BuildContext context, String message) {
    if (context.mounted) {
      V3AppSnackBar.info(context, message);
    }
  }

  // ─── COMMON ERROR MESSAGES ─────────────────────────────────────────

  /// Standardna "Greška pri čuvanju" poruka
  static void showSaveError(BuildContext context, [Object? error]) {
    final msg = error != null ? '❌ Greška pri čuvanju: $error' : '❌ Greška pri čuvanju';
    showError(context, msg);
  }

  /// Standardna "Sačuvano" poruka
  static void showSaveSuccess(BuildContext context) {
    showSuccess(context, '✅ Sačuvano');
  }

  /// Standardna greška za catch blokove
  static void showCatchError(BuildContext context, String action, Object error) {
    showError(context, '❌ Greška pri $action: $error');
  }

  // ─── SAFE SETSTATE WRAPPER ─────────────────────────────────────────

  /// Sigurno izvršava setState samo ako je widget mounted
  /// Korisiti kao: V3UIUtils.safeSetState(this, () { _loading = true; });
  static void safeSetState(State widget, VoidCallback fn) {
    if (widget.mounted) {
      // ignore: invalid_use_of_protected_member
      widget.setState(fn);
    }
  }
}
