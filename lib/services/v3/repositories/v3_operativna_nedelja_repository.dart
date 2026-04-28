import '../../../globals.dart';

class V3OperativnaNedeljaRepository {
  Future<Map<String, dynamic>> updateByIdReturningSingle(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').update(payload).eq('id', id).select().single();
  }

  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').insert(payload).select().single();
  }

  Future<List<dynamic>> updateByPutnikDatumGradAktivniReturningList({
    required String putnikId,
    required String datumIso,
    required String grad,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('created_by', putnikId)
        .eq('datum', datumIso)
        .eq('grad', grad)
        .isFilter('otkazano_at', null)
        .select();
  }

}
