import '../../../globals.dart';

class V3VoziloRepository {
  Future<void> upsert(Map<String, dynamic> data) {
    return supabase.from('v3_vozila').upsert(data);
  }

  Future<Map<String, dynamic>> upsertReturning(Map<String, dynamic> data) {
    return supabase.from('v3_vozila').upsert(data).select().single();
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_vozila').update(payload).eq('id', id);
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_vozila').update(payload).eq('id', id).select().single();
  }
}
