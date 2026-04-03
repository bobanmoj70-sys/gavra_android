import '../../../globals.dart';

class V3VozacLokacijaRepository {
  Future<void> upsert(Map<String, dynamic> payload) {
    return supabase.from('v3_vozac_lokacije').upsert(payload, onConflict: 'vozac_id');
  }

  Future<void> updateByVozacId(String vozacId, Map<String, dynamic> payload) {
    return supabase.from('v3_vozac_lokacije').update(payload).eq('vozac_id', vozacId);
  }
}
