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
  static TextEditingController get emailController => getController('email');
  static TextEditingController get telefonController => getController('telefon');
  static TextEditingController get sifraController => getController('sifra');
  static TextEditingController get pinController => getController('pin');

  /// Контролери за промену шифре
  static TextEditingController get staraSifraController => getController('stara_sifra');
  static TextEditingController get novaSifraController => getController('nova_sifra');
  static TextEditingController get potvrdaSifraController => getController('potvrda_sifra');

  /// Контролер за претрагу
  static TextEditingController get searchController => getController('search');

  /// Scoped контролери за претрагу (избегавају сударе између екрана)
  static TextEditingController get homeSearchController => getController('home_search');
  static TextEditingController get putniciSearchController => getController('putnici_search');
  static TextEditingController get adreseSearchController => getController('adrese_search');

  /// Scoped контролери за логин форме (путник/возач)
  static TextEditingController get putnikEmailController => getController('putnik_email');
  static TextEditingController get putnikTelefonController => getController('putnik_telefon');
  static TextEditingController get putnikPinController => getController('putnik_pin');
  static TextEditingController get vozacEmailController => getController('vozac_email');
  static TextEditingController get vozacTelefonController => getController('vozac_telefon');
  static TextEditingController get vozacSifraController => getController('vozac_sifra');

  /// Контролери за адресе/локације
  static TextEditingController get imeController => getController('ime');
  static TextEditingController get adresaController => getController('adresa');
  static TextEditingController get opisController => getController('opis');
  static TextEditingController get iznosController => getController('iznos');

  /// Контролери за временске захтеве
  static TextEditingController get preController => getController('pre');
  static TextEditingController get posleController => getController('posle');
  static TextEditingController get napomenaController => getController('napomena');

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

  /// Валидација имејла
  static bool isValidEmail(String key) {
    final email = getControllerText(key);
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// Валидација телефона
  static bool isValidPhone(String key) {
    final phone = getControllerText(key);
    return RegExp(r'^\+?[0-9\s\-\(\)]{8,20}$').hasMatch(phone);
  }
}
