import '../../../globals.dart';

class V3AdresaRepository {
  Future<Map<String, dynamic>> upsertReturning(Map<String, dynamic> data) {
    return supabase.from('v3_adrese').upsert(data).select().single();
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_adrese').delete().eq('id', id);
  }
}
