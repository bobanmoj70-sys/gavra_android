import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Menadžer jezika aplikacije (SR / EN / RU / DE).
/// Prati isti obrazac kao V3ThemeManager — singleton + ValueNotifier za MaterialApp.
class V3LocaleManager {
  factory V3LocaleManager() => _instance;
  V3LocaleManager._internal() {
    _localeNotifier = ValueNotifier(_defaultLocale);
  }
  static final V3LocaleManager _instance = V3LocaleManager._internal();
  static const List<String> _supportedLocaleCodes = <String>['sr', 'en', 'ru', 'de'];
  static const List<Locale> supportedLocales = <Locale>[
    Locale('sr'),
    Locale('en'),
    Locale('ru'),
    Locale('de'),
  ];
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
    final code = _normalizeLocaleCode(locale.languageCode) ?? _defaultLocale.languageCode;
    _localeNotifier.value = Locale(code);
    await _persistLocale(code);
  }

  /// Prebaci na sledeći podržani jezik.
  Future<void> toggleLocale() async {
    final currentCode = currentLocale.languageCode;
    final currentIndex = _supportedLocaleCodes.indexOf(currentCode);
    final nextCode = _supportedLocaleCodes[(currentIndex < 0 ? 0 : currentIndex + 1) % _supportedLocaleCodes.length];
    await changeLocale(Locale(nextCode));
  }

  /// Učitaj sačuvani jezik iz secure storage (pozvati pre MaterialApp kada je moguće).
  Future<void> loadLocaleFromStorage() async {
    try {
      final storedCode = await _secureStorage.read(key: _localeStorageKey).timeout(_readTimeout, onTimeout: () => null);
      final normalizedStoredCode = _normalizeLocaleCode(storedCode);
      if (normalizedStoredCode != null) {
        _localeNotifier.value = Locale(normalizedStoredCode);
        return;
      }

      final systemCode = _normalizeLocaleCode(WidgetsBinding.instance.platformDispatcher.locale.languageCode);
      _localeNotifier.value = Locale(systemCode ?? _defaultLocale.languageCode);
    } catch (_) {
      return;
    }
  }

  String? _normalizeLocaleCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return _supportedLocaleCodes.contains(code) ? code : null;
  }

  Future<void> _persistLocale(String code) async {
    try {
      await _secureStorage.write(key: _localeStorageKey, value: code);
    } catch (_) {}
  }
}
