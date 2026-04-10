import '../../globals.dart';
import '../../utils/v3_phone_utils.dart';

class V3AuthLookupService {
  V3AuthLookupService._();

  static const String _authLookupSelect =
      'id, ime, telefon, telefon_2, boja, tip, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_provider, push_token_2, push_provider_2, created_at, updated_at';

  static Future<Map<String, dynamic>?> getVozacByPhone(String normalizedPhone) async {
    final candidates = _phoneCandidates(normalizedPhone);
    if (candidates.isEmpty) return null;

    final orClause = _buildPhoneOrClause(candidates);

    final rows = await supabase.from('v3_auth').select(_authLookupSelect).or(orClause).limit(2);

    if (rows.length > 1) {
      throw StateError('Pronađeno više vozača za isti broj telefona.');
    }

    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    if (row['tip'] != 'vozac') return null;
    return _mapAuthToLegacyVozac(row);
  }

  static Future<Map<String, dynamic>?> getPutnikByPhone(String normalizedPhone) async {
    final candidates = _phoneCandidates(normalizedPhone);
    if (candidates.isEmpty) return null;

    final orClause = _buildPhoneOrClause(candidates);

    final rows = await supabase.from('v3_auth').select(_authLookupSelect).or(orClause).limit(2);

    if (rows.length > 1) {
      throw StateError('Pronađeno više putnika za isti broj telefona.');
    }

    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    if (row['tip'] == 'vozac') return null;
    return _mapAuthToLegacyPutnik(row);
  }

  static Map<String, dynamic> _mapAuthToLegacyVozac(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'boja': row['boja'],
      'push_token': row['push_token'],
      'push_provider': row['push_provider'],
      'push_token_2': row['push_token_2'],
      'push_provider_2': row['push_provider_2'],
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
      'push_provider': row['push_provider'],
      'push_token_2': row['push_token_2'],
      'push_provider_2': row['push_provider_2'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  static List<String> _phoneCandidates(String inputPhone) {
    final raw = inputPhone.trim();
    if (raw.isEmpty) return const [];

    final normalized = V3PhoneUtils.normalize(raw);
    final digits = normalized.replaceAll('+', '');
    final out = <String>{};

    void addCandidate(String? value) {
      final v = (value ?? '').trim();
      if (v.isNotEmpty) out.add(v);
    }

    addCandidate(raw);
    addCandidate(normalized);

    if (digits.isNotEmpty) {
      addCandidate(digits); // 381...
      addCandidate('+$digits');
    }

    if (digits.startsWith('381') && digits.length > 3) {
      addCandidate('0${digits.substring(3)}');
    }

    return out.toList();
  }

  static String _buildPhoneOrClause(List<String> phones) {
    final clauses = <String>[];
    for (final phone in phones) {
      clauses.add('telefon.eq.$phone');
      clauses.add('telefon_2.eq.$phone');
    }
    return clauses.join(',');
  }
}
