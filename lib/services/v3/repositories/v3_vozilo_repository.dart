import '../../../globals.dart';

class V3VoziloRepository {
  Future<Map<String, dynamic>> upsertReturning(Map<String, dynamic> data) {
    return supabase.from('v3_vozila').upsert(data).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_vozila').update(payload).eq('id', id).select().single();
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_vozila').delete().eq('id', id);
  }

  Future<void> insertServisIstorija(Map<String, dynamic> data) async {
    await supabase.from('v3_servis_istorija').insert(data);
  }

  /// Ažurira redove istorije za (vozilo, tip, stari datum).
  /// Vraća true ako je bar jedan red izmenjen.
  Future<bool> updateServisIstorija(
    String voziloId,
    String tip,
    String stariDatumIso,
    Map<String, dynamic> values,
  ) async {
    final res = await supabase
        .from('v3_servis_istorija')
        .update(values)
        .eq('vozilo_id', voziloId)
        .eq('tip', tip)
        .eq('datum', stariDatumIso)
        .select();
    return res.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> fetchServisIstorija(String voziloId, String tip) {
    return supabase
        .from('v3_servis_istorija')
        .select('datum, km')
        .eq('vozilo_id', voziloId)
        .eq('tip', tip)
        .order('datum', ascending: true)
        .order('created_at', ascending: true);
  }
}
