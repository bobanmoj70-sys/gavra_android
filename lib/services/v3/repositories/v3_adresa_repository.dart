import '../../../globals.dart';

class V3AdresaRepository {
  Future<void> upsert(Map<String, dynamic> data) {
    return supabase.from('v3_adrese').upsert(data);
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_adrese').delete().eq('id', id);
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_adrese').update(payload).eq('id', id);
  }
}
