import '../../../globals.dart';

class V3KreditRepository {
  Future<List<Map<String, dynamic>>> list() async {
    final response = await supabase.from('v3_krediti').select().order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) async {
    return supabase.from('v3_krediti').insert(payload).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) async {
    return supabase.from('v3_krediti').update(payload).eq('id', id).select().single();
  }

  Future<void> deleteById(String id) async {
    await supabase.from('v3_krediti').delete().eq('id', id);
  }
}
