import '../../../globals.dart';

class V3GpsTripStateRepository {
  Future<void> upsert(Map<String, dynamic> payload) {
    return supabase.from('v3_gps_trip_state').upsert(payload, onConflict: 'vozac_id,datum,grad,polazak_vreme');
  }

  Future<List<dynamic>> listByVozacGradAndDateRange({
    required String vozacId,
    required String grad,
    required String fromDate,
    required String toDate,
  }) {
    return supabase
        .from('v3_gps_trip_state')
        .select('id, polazak_vreme')
        .eq('vozac_id', vozacId)
        .eq('grad', grad)
        .gte('datum', fromDate)
        .lte('datum', toDate);
  }

  Future<void> updateByIds({
    required List<String> ids,
    required Map<String, dynamic> payload,
  }) {
    return supabase.from('v3_gps_trip_state').update(payload).inFilter('id', ids);
  }

  Future<void> deleteByTermin({
    required String datumIso,
    required String grad,
    required String polazakVremeIso,
    String? vozacId,
  }) async {
    var query = supabase
        .from('v3_gps_trip_state')
        .delete()
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('polazak_vreme', polazakVremeIso);

    if (vozacId != null && vozacId.trim().isNotEmpty) {
      query = query.eq('vozac_id', vozacId.trim());
    }

    await query;
  }

  Future<List<dynamic>> listByTermin({
    required String datumIso,
    required String grad,
    required String polazakVremeIso,
  }) {
    return supabase
        .from('v3_gps_trip_state')
        .select('id, vozac_id')
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('polazak_vreme', polazakVremeIso);
  }

  Future<List<dynamic>> listOperativnaAssignedByTermin({
    required String datumIso,
    required String grad,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .select('vozac_id, dodeljeno_vreme, zeljeno_vreme, status_final')
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('aktivno', true)
        .not('vozac_id', 'is', null);
  }

  Future<void> deleteByIds(List<String> ids) {
    return supabase.from('v3_gps_trip_state').delete().inFilter('id', ids);
  }
}
