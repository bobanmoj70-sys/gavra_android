import '../../../globals.dart';

class V3FinansijeRepository {
  Future<void> insert(Map<String, dynamic> payload) {
    return supabase.from('v3_finansije').insert(payload);
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_finansije').update(payload).eq('id', id);
  }

  Future<Map<String, dynamic>?> getLatestByCriteria({
    required String tip,
    required String kategorija,
    required String vozacId,
    required String dayStartIso,
    required String dayEndIso,
    String selectColumns = '*',
  }) {
    return supabase
        .from('v3_finansije')
        .select(selectColumns)
        .eq('tip', tip)
        .eq('kategorija', kategorija)
        .eq('vozac_id', vozacId)
        .gte('created_at', dayStartIso)
        .lt('created_at', dayEndIso)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}
