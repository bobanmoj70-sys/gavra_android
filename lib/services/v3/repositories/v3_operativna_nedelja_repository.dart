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
        .eq('dodeljeno_vreme', dodeljenoVreme)
        .select();
  }

  Future<List<dynamic>> updateByPutnikDatumGradAktivnoReturningList({
    required String putnikId,
    required String datumIso,
    required String grad,
    required Map<String, dynamic> payload,
  }) {
    return supabase
        .from('v3_operativna_nedelja')
        .update(payload)
        .eq('putnik_id', putnikId)
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('aktivno', true)
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
        .eq('putnik_id', putnikId)
        .eq('grad', grad)
        .eq('dodeljeno_vreme', dodeljenoVreme)
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
        .select('id, datum, grad, dodeljeno_vreme, zeljeno_vreme, status_final, aktivno, putnik_id, pokupljen')
        .eq('vozac_id', vozacId)
        .eq('aktivno', true)
        .gte('datum', fromDate)
        .lte('datum', toDate);
  }
}
