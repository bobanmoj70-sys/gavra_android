import 'package:uuid/uuid.dart';

import '../../../globals.dart';

class V3PutnikRepository {
  static const String _authRawSelect =
      'id, ime, telefon, telefon_2, tip, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, created_at, updated_at';

  static const String _putnikSelectProjection =
      'id:id, ime_prezime:ime, telefon_1:telefon, telefon_2, tip_putnika:tip, adresa_bc_id:adresa_primary_bc_id, adresa_vs_id:adresa_primary_vs_id, adresa_bc_id_2:adresa_secondary_bc_id, adresa_vs_id_2:adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, created_at, updated_at';

  Future<Map<String, dynamic>?> getActiveById(String id) {
    return supabase.from('v3_auth').select(_putnikSelectProjection).eq('id', id).neq('tip', 'vozac').maybeSingle();
  }

  Future<Map<String, dynamic>?> getActiveByPushToken(String token) {
    return supabase
        .from('v3_auth')
        .select(_putnikSelectProjection)
        .or('push_token.eq.$token,push_token_2.eq.$token')
        .neq('tip', 'vozac')
        .maybeSingle();
  }

  Future<Map<String, dynamic>> upsertReturning(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);
    final id = payload['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      payload['id'] = const Uuid().v4();
    }

    final mapped = _mapPayload(payload);
    return supabase.from('v3_auth').upsert(mapped, onConflict: 'id').select(_authRawSelect).single();
  }

  Future<void> deleteById(String id) {
    return Future.value();
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
    if (payload.containsKey('push_token_2')) out['push_token_2'] = payload['push_token_2'];

    return out;
  }
}
