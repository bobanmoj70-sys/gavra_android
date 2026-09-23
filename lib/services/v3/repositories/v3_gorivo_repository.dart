import '../../../globals.dart';

class V3GorivoRepository {
  Future<List<dynamic>> selectFirst() {
    return supabase.from('v3_gorivo').select().limit(1);
  }

  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) {
    return supabase.from('v3_gorivo').insert(payload).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_gorivo').update(payload).eq('id', id).select().single();
  }

  Future<List<dynamic>> selectPotrosnjaBetween({
    required String startIsoUtc,
    required String endIsoUtc,
  }) {
    return supabase
        .from('v3_gorivo_istorija')
        .select('id, vrsta, litri, created_at')
        .eq('vrsta', 'potrosnja')
        .gte('created_at', startIsoUtc)
        .lt('created_at', endIsoUtc)
        .order('created_at', ascending: true);
  }
}
