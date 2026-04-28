import '../../../globals.dart';

class V3OperativnaNedeljaRepository {
  Future<Map<String, dynamic>> updateByIdReturningSingle(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').update(payload).eq('id', id).select().single();
  }

  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').insert(payload).select().single();
  }

  Future<List<dynamic>> updateByTerminReturningList({
    required String datumIso,
    required String grad,
    required String polazakAt,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('polazak_at', polazakAt)
        .select();
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

  Future<List<dynamic>> updateByPutnikGradPolazakAtDatumReturningList({
    required String putnikId,
    required String grad,
    required String polazakAt,
    required String datumIso,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('created_by', putnikId)
        .eq('grad', grad)
        .eq('polazak_at', polazakAt)
        .eq('datum', datumIso)
        .select();
  }

  Future<List<dynamic>> listByDateRange({
    required String fromDate,
    required String toDate,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .select('id, datum, grad, polazak_at, created_by, pokupljen_at, otkazano_at')
        .isFilter('otkazano_at', null)
        .gte('datum', fromDate)
        .lte('datum', toDate);
  }
}
