import 'package:uuid/uuid.dart';

import '../../../globals.dart';

class V3VozacRepository {
  static const String _authVozacSelect =
      'auth_id, ime, telefon, telefon_2, boja, push_token, created_at, updated_at, tip';

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

  Future<Map<String, dynamic>?> getByPhone(String normalizedPhone) async {
    final row = await supabase
        .from('v3_auth')
        .select(_authVozacSelect)
        .or('telefon.eq.$normalizedPhone,telefon_2.eq.$normalizedPhone')
        .eq('tip', 'vozac')
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return _mapAuthRowToLegacyVozac(row);
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
      'push_provider': payload['push_provider'],
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
    if (payload.containsKey('push_provider')) out['push_provider'] = payload['push_provider'];

    return out;
  }

  Map<String, dynamic> _mapAuthRowToLegacyVozac(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['auth_id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'boja': row['boja'],
      'push_token': row['push_token'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }
}
