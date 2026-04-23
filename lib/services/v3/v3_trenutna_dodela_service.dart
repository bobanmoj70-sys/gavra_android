import '../../globals.dart';
import '../../utils/v3_status_policy.dart';

class V3TrenutnaDodelaService {
  V3TrenutnaDodelaService._();

  static Future<Map<String, String>> loadActiveVozacByTerminId({
    String? putnikId,
    String? vozacId,
  }) async {
    dynamic query =
        supabase.from('v3_trenutna_dodela').select('termin_id, vozac_v3_auth_id, status').eq('status', 'aktivan');

    final trimmedPutnikId = (putnikId ?? '').trim();
    if (trimmedPutnikId.isNotEmpty) {
      query = query.eq('putnik_v3_auth_id', trimmedPutnikId);
    }

    final trimmedVozacId = (vozacId ?? '').trim();
    if (trimmedVozacId.isNotEmpty) {
      query = query.eq('vozac_v3_auth_id', trimmedVozacId);
    }

    final rows = await query;

    final result = <String, String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final status = mapped['status']?.toString() ?? '';
      if (!V3StatusPolicy.isDodelaAktivna(status)) continue;

      final terminId = mapped['termin_id']?.toString().trim() ?? '';
      final assignedVozacId = mapped['vozac_v3_auth_id']?.toString().trim() ?? '';
      if (terminId.isEmpty || assignedVozacId.isEmpty) continue;

      result[terminId] = assignedVozacId;
    }

    return result;
  }

  static Future<void> upsertActiveTerminDodela({
    required String terminId,
    required String putnikId,
    required String vozacId,
    String? updatedBy,
  }) async {
    final payload = <String, dynamic>{
      'termin_id': terminId.trim(),
      'putnik_v3_auth_id': putnikId.trim(),
      'vozac_v3_auth_id': vozacId.trim(),
      'status': 'aktivan',
      if ((updatedBy ?? '').trim().isNotEmpty) 'updated_by': updatedBy!.trim(),
    };

    await supabase.from('v3_trenutna_dodela').upsert(payload, onConflict: 'termin_id');
  }

  static Future<void> deleteByTerminId(String terminId) async {
    final id = terminId.trim();
    if (id.isEmpty) return;
    await supabase.from('v3_trenutna_dodela').delete().eq('termin_id', id);
  }
}
