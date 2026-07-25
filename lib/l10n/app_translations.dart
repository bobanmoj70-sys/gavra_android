/// Centralizovane prevodne mape aplikacije (SR/EN/RU/DE/ZH).
/// Podeljeno u vise 'part' fajlova radi lakse navigacije:
///  - app_translations_screens_a.dart : ekrani (deo 1)
///  - app_translations_screens_b.dart : ekrani (deo 2)
///  - app_translations_widgets.dart   : widgeti i utility klase
library;

part 'app_translations_screens_a.dart';
part 'app_translations_screens_b.dart';
part 'app_translations_widgets.dart';

class AppTranslations {
  AppTranslations._();

  static const Map<String, Map<String, Map<String, String>>> _all = {
    ..._screensA,
    ..._screensB,
    ..._widgetsAndUtils,
  };

  /// Vraca prevodnu mapu (key -> {jezik: tekst}) za dati namespace.
  static Map<String, Map<String, String>> ns(String namespace) =>
      _all[namespace] ?? const {};

  /// Sve namespace mape (za testove/audit alate koji proveravaju kompletnost prevoda).
  static Map<String, Map<String, Map<String, String>>> get allNamespaces => _all;
}
