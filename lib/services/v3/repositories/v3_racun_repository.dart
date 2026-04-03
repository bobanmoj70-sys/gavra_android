import '../../../globals.dart';

class V3RacunRepository {
  Future<List<dynamic>> listRedniBrojByGodinaDescLimit1(int godina) {
    return supabase
        .from('v3_racuni')
        .select('redni_broj')
        .eq('godina', godina)
        .order('redni_broj', ascending: false)
        .limit(1);
  }

  Future<List<dynamic>> listAktivneFirmeByPutnikIds(List<dynamic> putnikIds) {
    return supabase
        .from('v3_racuni')
        .select('putnik_id, firma_naziv, firma_adresa, firma_pib, firma_mb, firma_ziro')
        .inFilter('putnik_id', putnikIds)
        .eq('aktivno', true);
  }
}
