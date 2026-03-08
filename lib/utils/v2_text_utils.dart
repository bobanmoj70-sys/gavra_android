/// Utilities za rad sa tekstom u aplikaciji
class V2TextUtils {
  V2TextUtils._();

  /// Normalizuje tekst - konvertuje kvačice u obična slova
  /// Ovo omogućava poređenje "godišnji" i "godisnji" kao istih
  static String normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll('ć', 'c')
        .replaceAll('č', 'c')
        .replaceAll('š', 's')
        .replaceAll('ž', 'z')
        .replaceAll('đ', 'd');
  }

  /// Kategorije statusa za lakše korišćenje (originalni stringovi)
  static const List<String> bolovanjeGodisnji = [
    'bolovanje',
    'godišnji',
    'godisnji',
  ];
  static const List<String> otkazani = ['otkazano', 'otkazan'];
  static const List<String> pokupljeni = ['pokupljen'];
  static const List<String> neaktivni = ['obrisan', 'neaktivan'];

  // Pre-normalizovani setovi za O(1) lookup u isStatusActive
  // Izračunati jednom umesto ponovnog pozivanja normalizeText() na svakom .any() pozivu
  static final Set<String> _neaktivniSet = {
    ...neaktivni.map(normalizeText),
  };
  static final Set<String> _otkazaniSet = {
    ...otkazani.map(normalizeText),
  };
  static final Set<String> _bolovanjeGodisnjiSet = {
    ...bolovanjeGodisnji.map(normalizeText),
  };

  /// Proverava da li je putnik u aktivnom statusu (nije otkazan, na bolovanju itd.)
  /// Koristi se za BROJANJE zauzetih mesta.
  /// NAPOMENA: null status se tretira kao aktivan (putnik bez statusa = aktivan).
  static bool isStatusActive(String? status) {
    if (status == null) return true;
    final normalized = normalizeText(status);
    return !_otkazaniSet.contains(normalized) &&
        !_bolovanjeGodisnjiSet.contains(normalized) &&
        !_neaktivniSet.contains(normalized);
  }
}
