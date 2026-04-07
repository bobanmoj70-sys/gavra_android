import 'package:uuid/uuid.dart';

import '../../../globals.dart';

class V3VozacRepository {
  Future<void> deleteById(String id) {
    return supabase.from('v3_auth').delete().eq('auth_id', id).eq('tip', 'vozac');
  }

  Future<void> updateById(String id, Map<String, dynamic> payload) {
    final mapped = _mapLegacyPayloadToAuthUpdate(payload);
    if (mapped.isEmpty) return Future.value();

    return supabase.from('v3_auth').update(mapped).eq('auth_id', id).eq('tip', 'vozac');
  }

  Future<Map<String, dynamic>?> getActiveByIdAndPushToken({
    required String vozacId,
    required String pushToken,
  }) {
    return supabase
        .from('v3_auth')
        .select('auth_id')
        .eq('auth_id', vozacId)
        .eq('tip', 'vozac')
        .eq('push_token', pushToken)
        .maybeSingle();
  }

  Future<void> insert(Map<String, dynamic> payload) {
    final telefon = payload['telefon_1']?.toString().trim() ?? '';
    if (telefon.isEmpty) {
      throw ArgumentError('telefon_1 je obavezan za unos vozača');
    }

    final authId = payload['id']?.toString().trim();
    final mapped = <String, dynamic>{
      'auth_id': authId != null && authId.isNotEmpty ? authId : const Uuid().v4(),
      'ime': payload['ime_prezime'],
      'telefon': telefon,
      'telefon_2': payload['telefon_2'],
      'boja': payload['boja'],
      'push_token': payload['push_token'],
      'tip': 'vozac',
    };
    return supabase.from('v3_auth').insert(mapped);
  }

  Map<String, dynamic> _mapLegacyPayloadToAuthUpdate(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};

    if (payload.containsKey('ime_prezime')) out['ime'] = payload['ime_prezime'];
    if (payload.containsKey('telefon_1')) out['telefon'] = payload['telefon_1'];
    if (payload.containsKey('telefon_2')) out['telefon_2'] = payload['telefon_2'];
    if (payload.containsKey('boja')) out['boja'] = payload['boja'];
    if (payload.containsKey('push_token')) out['push_token'] = payload['push_token'];

    return out;
  }
}
