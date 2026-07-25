import 'package:flutter/material.dart';

import '../services/v3_locale_manager.dart';
import 'v3_app_snack_bar.dart';
import '../l10n/app_translations.dart';

/// Shortcut metode za česte snackbar poruke u odrzavanje screenu.
class V3UIUtils {
  V3UIUtils._();

  static final Map<String, Map<String, String>> _t = AppTranslations.ns('uiUtils');

  static String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  static String _trf(String key, Map<String, String> params) {
    var text = _tr(key);
    params.forEach((placeholder, value) {
      text = text.replaceAll('%$placeholder%', value);
    });
    return text;
  }

  static void showSaveSuccess(BuildContext context) => V3AppSnackBar.success(context, _tr('saved'));

  static void showSaveError(BuildContext context, [Object? error]) {
    final msg = error != null ? '${_tr('saveError')}: $error' : _tr('saveError');
    V3AppSnackBar.error(context, msg);
  }

  static void showCatchError(BuildContext context, String action, Object error) =>
      V3AppSnackBar.error(context, _trf('errorDuring', {'ACTION': action, 'ERROR': error.toString()}));
}
