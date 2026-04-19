import '../../globals.dart';

class V3AuthLookupService {
  V3AuthLookupService._();

  static const String _authLookupSelect =
      'id, ime, telefon, telefon_2, boja, tip, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, created_at, updated_at';

  static Future<Map<String, dynamic>?> getVozacByPhone(String normalizedPhone) async {
    final ready = await ensureSupabaseReady();
    if (!ready) return null;

    final phone = normalizedPhone.trim();
    if (phone.isEmpty) return null;

    final authId = await _findAuthIdByPhone(phone);
    if (authId == null) return null;

    final row = await _getAuthById(authId);
    if (row == null) return null;

    if (row['tip'] != 'vozac') return null;
    return _mapAuthToLegacyVozac(row);
  }

  static Future<Map<String, dynamic>?> getPutnikByPhone(String normalizedPhone) async {
    final ready = await ensureSupabaseReady();
    if (!ready) return null;

    final phone = normalizedPhone.trim();
    if (phone.isEmpty) return null;

    final authId = await _findAuthIdByPhone(phone);
    if (authId == null) return null;

    final row = await _getAuthById(authId);
    if (row == null) return null;

    if (row['tip'] == 'vozac') return null;
    return _mapAuthToLegacyPutnik(row);
  }

  static Future<String?> _findAuthIdByPhone(String phone) async {
    final data = await supabase.rpc(
      'v3_auth_find_id_by_phone',
      params: {'p_telefon': phone},
    );
    final authId = data?.toString().trim() ?? '';
    if (authId.isEmpty) return null;
    return authId;
  }

  static Future<Map<String, dynamic>?> _getAuthById(String authId) async {
    final row = await supabase.from('v3_auth').select(_authLookupSelect).eq('id', authId).maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row.cast<String, dynamic>());
  }

  static Map<String, dynamic> _mapAuthToLegacyVozac(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'boja': row['boja'],
      'push_token': row['push_token'],
      'push_token_2': row['push_token_2'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  static Map<String, dynamic> _mapAuthToLegacyPutnik(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'tip_putnika': row['tip'],
      'adresa_bc_id': row['adresa_primary_bc_id'],
      'adresa_vs_id': row['adresa_primary_vs_id'],
      'adresa_bc_id_2': row['adresa_secondary_bc_id'],
      'adresa_vs_id_2': row['adresa_secondary_vs_id'],
      'cena_po_danu': row['cena_po_danu'],
      'cena_po_pokupljenju': row['cena_po_pokupljenju'],
      'push_token': row['push_token'],
      'push_token_2': row['push_token_2'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }
}
