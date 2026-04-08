import '../../../globals.dart';

class V3OperativnaNedeljaRepository {
  Future<Map<String, dynamic>?> updateByIdReturningMaybeSingle(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').update(payload).eq('id', id).select().maybeSingle();
  }

  Future<Map<String, dynamic>> updateByIdReturningSingle(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').update(payload).eq('id', id).select().single();
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').update(payload).eq('id', id);
  }

  Future<void> insert(Map<String, dynamic> payload) {
    return supabase.from('v3_operativna_nedelja').insert(payload);
  }

  Future<List<dynamic>> updateByTerminReturningList({
    required String datumIso,
    required String grad,
    required String dodeljenoVreme,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('polazak_at', dodeljenoVreme)
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

  Future<List<dynamic>> updateByPutnikGradDodeljenoDatumReturningList({
    required String putnikId,
    required String grad,
    required String dodeljenoVreme,
    required String datumIso,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('created_by', putnikId)
        .eq('grad', grad)
        .eq('polazak_at', dodeljenoVreme)
        .eq('datum', datumIso)
        .select();
  }

  Future<List<dynamic>> listByVozacAndDateRange({
    required String vozacId,
    required String fromDate,
    required String toDate,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .select('id, datum, grad, polazak_at, created_by, pokupljen_at, otkazano_at')
        .eq('pokupljen_by', vozacId)
        .isFilter('otkazano_at', null)
        .gte('datum', fromDate)
        .lte('datum', toDate);
  }
}
