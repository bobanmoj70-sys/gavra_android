import 'package:uuid/uuid.dart';

import '../../../globals.dart';

class V3PutnikRepository {
  static const String _legacyPutnikSelect =
      'id:id, ime_prezime:ime, telefon_1:telefon, telefon_2, tip_putnika:tip, adresa_bc_id:adresa_primary_bc_id, adresa_vs_id:adresa_primary_vs_id, adresa_bc_id_2:adresa_secondary_bc_id, adresa_vs_id_2:adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_provider, push_token_2, push_provider_2, created_at, updated_at';

  Future<List<dynamic>> listByPhone(String normalizedPhone) {
    return supabase
        .from('v3_auth')
        .select(_legacyPutnikSelect)
        .or('telefon.eq.$normalizedPhone,telefon_2.eq.$normalizedPhone')
        .neq('tip', 'vozac')
        .limit(1);
  }

  Future<Map<String, dynamic>?> getActiveById(String id) {
    return supabase.from('v3_auth').select(_legacyPutnikSelect).eq('id', id).neq('tip', 'vozac').maybeSingle();
  }

  Future<Map<String, dynamic>?> getActiveByPushToken(String token) {
    return supabase
        .from('v3_auth')
        .select(_legacyPutnikSelect)
        .or('push_token.eq.$token,push_token_2.eq.$token')
        .neq('tip', 'vozac')
        .maybeSingle();
  }

  Future<void> upsert(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);
    final id = payload['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      payload['id'] = const Uuid().v4();
    }

    final mapped = _mapPayload(payload);
    return supabase.from('v3_auth').upsert(mapped, onConflict: 'id');
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    final mapped = _mapPayload(payload);
    if (mapped.isEmpty) return Future.value();
    return supabase.from('v3_auth').update(mapped).eq('id', id);
  }

  Future<void> deleteById(String id) {
    return supabase.from('v3_auth').delete().eq('id', id);
  }

  Map<String, dynamic> _mapPayload(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};

    if (payload.containsKey('id')) out['id'] = payload['id'];
    if (payload.containsKey('ime_prezime')) out['ime'] = payload['ime_prezime'];
    if (payload.containsKey('telefon_1')) out['telefon'] = payload['telefon_1'];
    if (payload.containsKey('telefon_2')) out['telefon_2'] = payload['telefon_2'];
    if (payload.containsKey('tip_putnika')) out['tip'] = payload['tip_putnika'];

    if (payload.containsKey('adresa_bc_id')) out['adresa_primary_bc_id'] = payload['adresa_bc_id'];
    if (payload.containsKey('adresa_vs_id')) out['adresa_primary_vs_id'] = payload['adresa_vs_id'];
    if (payload.containsKey('adresa_bc_id_2')) out['adresa_secondary_bc_id'] = payload['adresa_bc_id_2'];
    if (payload.containsKey('adresa_vs_id_2')) out['adresa_secondary_vs_id'] = payload['adresa_vs_id_2'];

    if (payload.containsKey('cena_po_danu')) out['cena_po_danu'] = payload['cena_po_danu'];
    if (payload.containsKey('cena_po_pokupljenju')) out['cena_po_pokupljenju'] = payload['cena_po_pokupljenju'];
    if (payload.containsKey('push_token')) out['push_token'] = payload['push_token'];
    if (payload.containsKey('push_provider')) out['push_provider'] = payload['push_provider'];
    if (payload.containsKey('push_token_2')) out['push_token_2'] = payload['push_token_2'];
    if (payload.containsKey('push_provider_2')) out['push_provider_2'] = payload['push_provider_2'];

    return out;
  }
}
