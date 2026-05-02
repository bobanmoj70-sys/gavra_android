import '../../../globals.dart';

class V3FinansijeRepository {
  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) {
    return supabase.from('v3_finansije').insert(payload).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_finansije').update(payload).eq('id', id).select().single();
  }

  Future<Map<String, dynamic>?> findMesecnuNaplatu({
    required String putnikId,
    required int mesec,
    required int godina,
  }) {
    return supabase
        .from('v3_finansije')
        .select('id')
        .eq('tip', 'prihod')
        .eq('kategorija', 'operativna_naplata')
        .eq('putnik_v3_auth_id', putnikId)
        .eq('mesec', mesec)
        .eq('godina', godina)
        .limit(1)
        .maybeSingle();
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
        .eq('naplaceno_by', vozacId)
        .gte('created_at', dayStartIso)
        .lt('created_at', dayEndIso)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}
