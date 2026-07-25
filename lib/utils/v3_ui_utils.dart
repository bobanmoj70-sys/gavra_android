import 'package:flutter/material.dart';

import '../services/v3_locale_manager.dart';
import 'v3_app_snack_bar.dart';

/// Shortcut metode za česte snackbar poruke u odrzavanje screenu.
class V3UIUtils {
  V3UIUtils._();

  static const Map<String, Map<String, String>> _t = {
    'saved': {'sr': '✅ Sačuvano', 'en': '✅ Saved', 'ru': '✅ Сохранено', 'de': '✅ Gespeichert', 'zh': '✅ 已保存'},
    'saveError': {
      'sr': '❌ Greška pri čuvanju',
      'en': '❌ Error while saving',
      'ru': '❌ Ошибка при сохранении',
      'de': '❌ Fehler beim Speichern',
      'zh': '❌ 保存时出错',
    },
    'errorDuring': {
      'sr': '❌ Greška pri %ACTION%: %ERROR%',
      'en': '❌ Error during %ACTION%: %ERROR%',
      'ru': '❌ Ошибка при %ACTION%: %ERROR%',
      'de': '❌ Fehler bei %ACTION%: %ERROR%',
      'zh': '❌ %ACTION% 时出错：%ERROR%',
    },
  };

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
