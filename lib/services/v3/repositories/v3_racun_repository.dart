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

  /// Dohvata kompletan račun iz baze na osnovu unutrašnjeg ID-a.
  Future<Map<String, dynamic>?> getRacunById(String id) async {
    final response =
        await supabase.from('v3_racuni').select('*').eq('id', id).maybeSingle();
    return response;
  }
}
