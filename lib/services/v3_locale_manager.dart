import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Menadžer jezika aplikacije (SR / EN).
/// Prati isti obrazac kao V3ThemeManager — singleton + ValueNotifier za MaterialApp.
class V3LocaleManager {
  factory V3LocaleManager() => _instance;
  V3LocaleManager._internal() {
    _localeNotifier = ValueNotifier(_defaultLocale);
  }
  static final V3LocaleManager _instance = V3LocaleManager._internal();
  static const FlutterSecureStorage _secureStorage =
      FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _localeStorageKey = 'v3_locale_code';
  static const Duration _readTimeout = Duration(seconds: 2);
  static const Locale _defaultLocale = Locale('sr');

  late final ValueNotifier<Locale> _localeNotifier;

  /// ValueNotifier za reaktivno slušanje jezika (za MaterialApp).
  ValueNotifier<Locale> get localeNotifier => _localeNotifier;

  /// Trenutni jezik.
  Locale get currentLocale => _localeNotifier.value;

  /// Da li je trenutni jezik engleski.
  bool get isEnglish => _localeNotifier.value.languageCode == 'en';

  /// Da li je trenutni jezik ruski.
  bool get isRussian => _localeNotifier.value.languageCode == 'ru';

  /// Da li je trenutni jezik nemački.
  bool get isGerman => _localeNotifier.value.languageCode == 'de';

  /// Promeni jezik i sačuvaj izbor.
  Future<void> changeLocale(Locale locale) async {
    _localeNotifier.value = locale;
    await _persistLocale(locale.languageCode);
  }

  /// Prebaci između SR i EN.
  Future<void> toggleLocale() async {
    await changeLocale(isEnglish ? const Locale('sr') : const Locale('en'));
  }

  /// Učitaj sačuvani jezik iz secure storage (pozvati pre MaterialApp kada je moguće).
  Future<void> loadLocaleFromStorage() async {
    try {
      final storedCode = await _secureStorage.read(key: _localeStorageKey).timeout(_readTimeout, onTimeout: () => null);
      if (storedCode == null || storedCode.isEmpty) return;
      if (storedCode != 'sr' && storedCode != 'en' && storedCode != 'ru' && storedCode != 'de') return;
      _localeNotifier.value = Locale(storedCode);
    } catch (_) {
      return;
    }
  }

  Future<void> _persistLocale(String code) async {
    try {
      await _secureStorage.write(key: _localeStorageKey, value: code);
    } catch (_) {}
  }
}
