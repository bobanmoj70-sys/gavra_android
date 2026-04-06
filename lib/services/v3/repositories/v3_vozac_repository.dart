import '../../../globals.dart';

class V3VozacRepository {
  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_vozaci').update(payload).eq('id', id);
  }

  Future<Map<String, dynamic>?> getActiveByIdAndPushToken({
    required String vozacId,
    required String pushToken,
  }) {
    return supabase
        .from('v3_vozaci')
        .select('id')
        .eq('id', vozacId)
        .eq('push_token', pushToken)
        .eq('aktivno', true)
        .maybeSingle();
  }

  Future<void> insert(Map<String, dynamic> payload) {
    return supabase.from('v3_vozaci').insert(payload);
  }
}
