import '../../globals.dart';

class V3AuthLookupService {
  V3AuthLookupService._();

  static const String _authLookupSelect =
      'auth_id, ime, telefon, telefon_2, boja, tip, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_provider, push_token_2, push_provider_2, created_at, updated_at';

  static Future<Map<String, dynamic>?> getVozacByPhone(String normalizedPhone) async {
    final phone = normalizedPhone.trim();
    if (phone.isEmpty) return null;

    final rows = await supabase
        .from('v3_auth')
        .select(_authLookupSelect)
        .eq('tip', 'vozac')
        .or('telefon.eq.$phone,telefon_2.eq.$phone')
        .limit(2);

    if (rows.length > 1) {
      throw StateError('Pronađeno više vozača za isti broj telefona.');
    }

    if (rows.isEmpty) return null;
    return _mapAuthToLegacyVozac(Map<String, dynamic>.from(rows.first as Map));
  }

  static Future<Map<String, dynamic>?> getPutnikByPhone(String normalizedPhone) async {
    final phone = normalizedPhone.trim();
    if (phone.isEmpty) return null;

    final rows = await supabase
        .from('v3_auth')
        .select(_authLookupSelect)
        .neq('tip', 'vozac')
        .or('telefon.eq.$phone,telefon_2.eq.$phone')
        .limit(2);

    if (rows.length > 1) {
      throw StateError('Pronađeno više putnika za isti broj telefona.');
    }

    if (rows.isEmpty) return null;
    return _mapAuthToLegacyPutnik(Map<String, dynamic>.from(rows.first as Map));
  }

  static Map<String, dynamic> _mapAuthToLegacyVozac(Map<String, dynamic> row) {
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

  static Map<String, dynamic> _mapAuthToLegacyPutnik(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['auth_id'],
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
      'push_provider': row['push_provider'],
      'push_token_2': row['push_token_2'],
      'push_provider_2': row['push_provider_2'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }
}
