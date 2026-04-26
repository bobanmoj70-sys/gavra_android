import 'package:flutter/material.dart';

import 'v3_app_snack_bar.dart';

/// Shortcut metode za česte snackbar poruke u odrzavanje screenu.
class V3UIUtils {
  V3UIUtils._();

  static void showSaveSuccess(BuildContext context) => V3AppSnackBar.success(context, '✅ Sačuvano');

  static void showSaveError(BuildContext context, [Object? error]) {
    final msg = error != null ? '❌ Greška pri čuvanju: $error' : '❌ Greška pri čuvanju';
    V3AppSnackBar.error(context, msg);
  }

  static void showCatchError(BuildContext context, String action, Object error) =>
      V3AppSnackBar.error(context, '❌ Greška pri $action: $error');
}
