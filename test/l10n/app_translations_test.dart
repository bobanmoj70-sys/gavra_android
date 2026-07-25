import 'package:flutter_test/flutter_test.dart';
import 'package:gavra_android/l10n/app_translations.dart';

/// Test kompletnosti prevoda: garantuje da svaki kljuc u svakom namespace-u
/// ima definisan tekst za svih 5 podrzanih jezika (sr, en, ru, de, zh),
/// i da tekst nije prazan string. Sprecava da se u buducnosti doda string
/// samo na srpskom i zaboravi prevod za ostale jezike.
void main() {
  const supportedLangs = ['sr', 'en', 'ru', 'de', 'zh'];

  test('svaki prevodni kljuc ima svih 5 jezika i nije prazan', () {
    final missing = <String>[];

    for (final nsEntry in AppTranslations.allNamespaces.entries) {
      final namespace = nsEntry.key;
      for (final keyEntry in nsEntry.value.entries) {
        final key = keyEntry.key;
        final langsMap = keyEntry.value;
        for (final lang in supportedLangs) {
          final text = langsMap[lang];
          if (text == null || text.trim().isEmpty) {
            missing.add('[$namespace] "$key" -> nedostaje ili je prazan jezik "$lang"');
          }
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Pronadjeni nedostajuci/prazni prevodi:\n${missing.join('\n')}',
    );
  });

  test('nema duplih namespace-ova (sanity check strukture)', () {
    final namespaces = AppTranslations.allNamespaces.keys.toList();
    final uniqueNamespaces = namespaces.toSet();
    expect(namespaces.length, uniqueNamespaces.length, reason: 'Postoje dupli namespace kljucevi u AppTranslations');
  });

  test('AppTranslations.ns vraca praznu mapu za nepostojeci namespace', () {
    expect(AppTranslations.ns('nepostojeci_namespace_xyz'), isEmpty);
  });
}
