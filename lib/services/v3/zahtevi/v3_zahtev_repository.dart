import '../../../globals.dart';
import 'v3_zahtev_mapper.dart';
import 'v3_zahtev_types.dart';

class V3ZahtevRepository {
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) {
    return supabase.from('v3_zahtevi').insert(data).select().single();
  }

  Future<Map<String, dynamic>> updatePatch(V3ZahtevPatch patch) {
    return supabase.from('v3_zahtevi').update(V3ZahtevMapper.patchToDb(patch)).eq('id', patch.id).select().single();
  }

  Future<Map<String, dynamic>> updateRaw(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_zahtevi').update(payload).eq('id', id).select().single();
  }

  Future<Map<String, dynamic>?> updateRawMaybeSingle(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_zahtevi').update(payload).eq('id', id).select().maybeSingle();
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_zahtevi').delete().eq('id', id);
  }

  Future<Map<String, dynamic>?> getById(String id) {
    return supabase.from('v3_zahtevi').select().eq('id', id).maybeSingle();
  }
}
