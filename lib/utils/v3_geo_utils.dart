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
  /// Ove koordinate moraju biti sinhronizovane sa DEFAULT_START/DEST u
  /// supabase/functions/v3-compute-eta/index.ts i
  /// supabase/functions/v3-auto-prepare-termins/index.ts.
  static ({double lat, double lng})? gradCenterCoord(String grad) {
    switch (grad.trim().toUpperCase()) {
      case 'VS':
        return (lat: 45.118736452002345, lng: 21.301195520159723); // centar Vršac
      case 'BC':
        return (lat: 44.90281796231954, lng: 21.424364904529384); // centar Bela Crkva
      default:
        return null;
    }
  }
}
