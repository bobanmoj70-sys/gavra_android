import '../../globals.dart';
import '../../utils/v3_status_policy.dart';

class V3TrenutnaDodelaService {
  V3TrenutnaDodelaService._();

  static const String tableName = 'v3_trenutna_dodela';
  static const String statusAktivan = 'aktivan';
  static const String _colTerminId = 'termin_id';
  static const String _colPutnikId = 'putnik_v3_auth_id';
  static const String colVozacId = 'vozac_v3_auth_id';
  static const String _colStatus = 'status';
  static const String _colUpdatedBy = 'updated_by';

  static Future<Map<String, String>> loadActiveVozacByTerminId({
    String? putnikId,
    String? vozacId,
  }) async {
    dynamic query =
        supabase.from(tableName).select('$_colTerminId, $colVozacId, $_colStatus').eq(_colStatus, statusAktivan);

    final trimmedPutnikId = (putnikId ?? '').trim();
    if (trimmedPutnikId.isNotEmpty) {
      query = query.eq(_colPutnikId, trimmedPutnikId);
    }

    final trimmedVozacId = (vozacId ?? '').trim();
    if (trimmedVozacId.isNotEmpty) {
      query = query.eq(colVozacId, trimmedVozacId);
    }

    final rows = await query;

    final result = <String, String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final status = mapped[_colStatus]?.toString() ?? '';
      if (!V3StatusPolicy.isDodelaAktivna(status)) continue;

      final terminId = mapped[_colTerminId]?.toString().trim() ?? '';
      final assignedVozacId = mapped[colVozacId]?.toString().trim() ?? '';
      if (terminId.isEmpty || assignedVozacId.isEmpty) continue;

      result[terminId] = assignedVozacId;
    }

    return result;
  }

  static Future<Set<String>> loadActiveTerminIds({
    String? putnikId,
    String? vozacId,
  }) async {
    final activeVozacByTerminId = await loadActiveVozacByTerminId(
      putnikId: putnikId,
      vozacId: vozacId,
    );
    return activeVozacByTerminId.keys.toSet();
  }

  static Future<void> upsertActiveTerminDodela({
    required String terminId,
    required String putnikId,
    required String vozacId,
    String? updatedBy,
  }) async {
    final payload = <String, dynamic>{
      _colTerminId: terminId.trim(),
      _colPutnikId: putnikId.trim(),
      colVozacId: vozacId.trim(),
      _colStatus: statusAktivan,
      if ((updatedBy ?? '').trim().isNotEmpty) _colUpdatedBy: updatedBy!.trim(),
    };

    await supabase.from(tableName).upsert(payload, onConflict: _colTerminId);
  }

  static Future<void> upsertActiveTerminDodele(
    Iterable<({String terminId, String putnikId, String vozacId})> assignments, {
    String? updatedBy,
  }) async {
    final actor = (updatedBy ?? '').trim();
    final payload = <Map<String, dynamic>>[];

    for (final assignment in assignments) {
      final terminId = assignment.terminId.trim();
      final putnikId = assignment.putnikId.trim();
      final vozacId = assignment.vozacId.trim();
      if (terminId.isEmpty || putnikId.isEmpty || vozacId.isEmpty) continue;

      payload.add(<String, dynamic>{
        _colTerminId: terminId,
        _colPutnikId: putnikId,
        colVozacId: vozacId,
        _colStatus: statusAktivan,
        if (actor.isNotEmpty) _colUpdatedBy: actor,
      });
    }

    if (payload.isEmpty) return;
    await supabase.from(tableName).upsert(payload, onConflict: _colTerminId);
  }

  static Future<void> deleteByTerminId(String terminId) async {
    final id = terminId.trim();
    if (id.isEmpty) return;
    await supabase.from(tableName).delete().eq(_colTerminId, id);
  }

  static Future<void> deleteByTerminIds(Iterable<String> terminIds) async {
    for (final terminId in terminIds) {
      await deleteByTerminId(terminId);
    }
  }
}
