import 'package:flutter/material.dart';

/// V3TextUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ ТЕКСТОМ
/// Елиминише све TextEditingController дупликате!
class V3TextUtils {
  // Контролери за честе форме
  static final _controllers = <String, TextEditingController>{};

  /// Прави или враћа постојећи контролер
  static TextEditingController getController(String key) {
    return _controllers.putIfAbsent(key, () => TextEditingController());
  }

  /// Брише контролер
  static void disposeController(String key) {
    _controllers[key]?.dispose();
    _controllers.remove(key);
  }

  /// Очисти текст у контролеру
  static void clearController(String key) {
    _controllers[key]?.clear();
  }

  /// Постави текст у контролер
  static void setControllerText(String key, String text) {
    final controller = getController(key);
    controller.text = text;
  }

  /// Добиј текст из контролера
  static String getControllerText(String key) {
    return _controllers[key]?.text ?? '';
  }

  // СПЕЦИЈАЛИЗОВАНИ КОНТРОЛЕРИ ЗА ЧЕСТО КОРИШЋЕНЕ ФОРМЕ

  /// Контролери за логин форме
  static TextEditingController get telefonController =>
      getController('telefon');

  /// Контролер за претрагу
  static TextEditingController get searchController => getController('search');

  /// Scoped контролери за претрагу (избегавају сударе између екрана)
  static TextEditingController get homeSearchController =>
      getController('home_search');
  static TextEditingController get putniciSearchController =>
      getController('putnici_search');
  static TextEditingController get adreseSearchController =>
      getController('adrese_search');

  /// Scoped контролери за логин форме (путник/возач)
  static TextEditingController get putnikTelefonController =>
      getController('putnik_telefon');
  static TextEditingController get vozacTelefonController =>
      getController('vozac_telefon');

  /// Контролери за адресе/локације
  static TextEditingController get imeController => getController('ime');
  static TextEditingController get adresaController => getController('adresa');
  static TextEditingController get opisController => getController('opis');
  static TextEditingController get iznosController => getController('iznos');

  /// Контролери за временске захтеве
  static TextEditingController get preController => getController('pre');
  static TextEditingController get posleController => getController('posle');

  /// МАСОВНО ОЧИШЋАВАЊЕ СВИХ КОНТРОЛЕРА
  static void clearAllControllers() {
    for (final controller in _controllers.values) {
      controller.clear();
    }
  }

  /// МАСОВНО УНИШТАВАЊЕ СВИХ КОНТРОЛЕРА
  static void disposeAllControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  /// Валидација празног текста
  static bool isEmpty(String key) {
    return getControllerText(key).trim().isEmpty;
  }

  /// Валидација дужине текста
  static bool isValidLength(String key, int minLength, [int? maxLength]) {
    final text = getControllerText(key);
    if (text.length < minLength) return false;
    if (maxLength != null && text.length > maxLength) return false;
    return true;
  }

  /// Валидација телефона
  static bool isValidPhone(String key) {
    final phone = getControllerText(key);
    return RegExp(r'^\+?[0-9\s\-\(\)]{8,20}$').hasMatch(phone);
  }
}
