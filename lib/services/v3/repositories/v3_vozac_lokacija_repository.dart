import '../../../globals.dart';

class V3VozacLokacijaRepository {
  Future<void> upsert(Map<String, dynamic> payload) {
    return supabase.from('v3_vozac_lokacije').upsert(payload, onConflict: 'created_by');
  }

  Future<void> updateByCreatedBy(String vozacId, Map<String, dynamic> payload) {
    return supabase.from('v3_vozac_lokacije').update(payload).eq('created_by', vozacId);
  }
}
