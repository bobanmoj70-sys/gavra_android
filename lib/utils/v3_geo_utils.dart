/// V3GeoUtils - helper za geo/grad operacije
class V3GeoUtils {
  V3GeoUtils._();

  /// Vraća puno ime grada za geocoding (Nominatim/OSM query)
  /// 'BC' → 'Bačka Palanka', 'VS' → 'Vrbas', itd.
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
}
