import '../../../globals.dart';

class V3PinZahtevRepository {
  Future<Map<String, dynamic>?> getPendingByPutnikId(String putnikId) {
    return supabase
        .from('v3_pin_zahtevi')
        .select('id')
        .eq('putnik_id', putnikId)
        .eq('status', 'ceka')
        .limit(1)
        .maybeSingle();
  }

  Future<void> insert(Map<String, dynamic> payload) {
    return supabase.from('v3_pin_zahtevi').insert(payload);
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_pin_zahtevi').update(payload).eq('id', id);
  }
}
