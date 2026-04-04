import '../../../globals.dart';

class V3TripStopsRepository {
  Future<void> upsert(Map<String, dynamic> payload) {
    return supabase.from('v3_trip_stops').upsert(payload, onConflict: 'operativna_id');
  }

  Future<List<dynamic>> listTripStateByKey({
    required String vozacId,
    required String datumIso,
    required String grad,
  }) {
    return supabase
        .from('v3_gps_trip_state')
        .select('id, polazak_vreme')
        .eq('vozac_id', vozacId)
        .eq('datum', datumIso)
        .eq('grad', grad);
  }
}
