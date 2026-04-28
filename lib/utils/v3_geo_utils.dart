/// V3GeoUtils - helper za geo/grad operacije
class V3GeoUtils {
  V3GeoUtils._();

  /// Vraća puno ime grada za geocoding (Nominatim/OSM query)
  static String gradLabelForGeocoding(String grad) {
    switch (grad.trim().toUpperCase()) {
      case 'BC':
        return 'Bela Crkva';
      case 'VS':
        return 'Vršac';
      default:
        return grad;
    }
  }

  /// Hardcoded koordinate centara gradova — pouzdanije od Nominatim geocodinga.
  /// Vraća (lat, lng) ili null ako grad nije poznat.
  static ({double lat, double lng})? gradCenterCoord(String grad) {
    switch (grad.trim().toUpperCase()) {
      case 'VS':
        return (lat: 45.1196, lng: 21.3050); // centar Vršac
      case 'BC':
        return (lat: 44.8994, lng: 21.4165); // centar Bela Crkva
      default:
        return null;
    }
  }
}
