import '../../../globals.dart';

class V3VoziloRepository {
  Future<Map<String, dynamic>> upsertReturning(Map<String, dynamic> data) {
    return supabase.from('v3_vozila').upsert(data).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_vozila').update(payload).eq('id', id).select().single();
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_vozila').delete().eq('id', id);
  }

  Future<void> insertServisIstorija(Map<String, dynamic> data) async {
    await supabase.from('v3_servis_istorija').insert(data);
  }

  Future<List<Map<String, dynamic>>> fetchServisIstorija(String voziloId, String tip) {
    return supabase
        .from('v3_servis_istorija')
        .select('datum, km')
        .eq('vozilo_id', voziloId)
        .eq('tip', tip)
        .order('datum')
        .order('created_at');
  }
}
