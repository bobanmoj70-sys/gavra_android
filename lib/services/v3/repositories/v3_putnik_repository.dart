import '../../../globals.dart';

class V3PutnikRepository {
  Future<List<dynamic>> listByPhone(String normalizedPhone) {
    return supabase
        .from('v3_putnici')
        .select()
        .or('telefon_1.eq.$normalizedPhone,telefon_2.eq.$normalizedPhone')
        .limit(1);
  }

  Future<Map<String, dynamic>?> getActiveById(String id) {
    return supabase.from('v3_putnici').select().eq('id', id).eq('aktivno', true).maybeSingle();
  }

  Future<Map<String, dynamic>?> getActiveByPushToken(String token) {
    return supabase
        .from('v3_putnici')
        .select()
        .or('push_token.eq.$token,push_token_2.eq.$token')
        .eq('aktivno', true)
        .maybeSingle();
  }

  Future<void> upsert(Map<String, dynamic> data) {
    return supabase.from('v3_putnici').upsert(data);
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_putnici').update(payload).eq('id', id);
  }
}
