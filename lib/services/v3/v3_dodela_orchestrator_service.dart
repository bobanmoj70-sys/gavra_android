import '../../utils/v3_date_utils.dart';
import '../../utils/v3_time_utils.dart';
import 'v3_trenutna_dodela_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';

class V3DodelaOrchestratorService {
  V3DodelaOrchestratorService._();

  static Future<int> assignTerminDefault({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    String? updatedBy,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) async {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    final matchedRows = _rowsForSlot(
      operativnaRows: operativnaRows,
      datumIso: datumIso,
      grad: grad,
      vreme: normVreme,
      includeRow: includeRow,
    );

    await V3TrenutnaDodelaService.upsertActiveTerminDodele(
      matchedRows
          .map((row) => (
                terminId: row['id']?.toString() ?? '',
                putnikId: row['created_by']?.toString() ?? '',
                vozacId: vozacId,
              ))
          .toList(growable: false),
      updatedBy: updatedBy,
    );

    return matchedRows.length;
  }

  static Future<int> clearTerminDefault({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String grad,
    required String vreme,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) async {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    await V3TrenutnaDodelaSlotService.deleteBySlot(
      datumIso: datumIso,
      grad: grad,
      vreme: normVreme,
    );

    final matchedRows = _rowsForSlot(
      operativnaRows: operativnaRows,
      datumIso: datumIso,
      grad: grad,
      vreme: normVreme,
      includeRow: includeRow,
    );

    final terminIds =
        matchedRows.map((row) => row['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList(growable: false);

    await V3TrenutnaDodelaService.deleteByTerminIds(terminIds);
    return terminIds.length;
  }

  static Future<bool> assignPutnikOverride({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String putnikId,
    required String grad,
    required String vreme,
    required String vozacId,
    String? updatedBy,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) async {
    final row = _findOperativnaRowForPutnik(
      operativnaRows: operativnaRows,
      datumIso: datumIso,
      putnikId: putnikId,
      grad: grad,
      vreme: vreme,
      includeRow: includeRow,
    );
    if (row == null) return false;

    final terminId = row['id']?.toString() ?? '';
    if (terminId.isEmpty) return false;

    await V3TrenutnaDodelaService.upsertActiveTerminDodela(
      terminId: terminId,
      putnikId: putnikId,
      vozacId: vozacId,
      updatedBy: updatedBy,
    );

    return true;
  }

  static Future<void> clearPutnikOverride({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String putnikId,
    required String grad,
    required String vreme,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) async {
    final row = _findOperativnaRowForPutnik(
      operativnaRows: operativnaRows,
      datumIso: datumIso,
      putnikId: putnikId,
      grad: grad,
      vreme: vreme,
      includeRow: includeRow,
    );
    if (row == null) return;

    final terminId = row['id']?.toString() ?? '';
    if (terminId.isEmpty) return;

    await V3TrenutnaDodelaService.deleteByTerminId(terminId);
  }

  static List<Map<String, dynamic>> _rowsForSlot({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String grad,
    required String vreme,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    return operativnaRows.where((row) {
      final datum = V3DateUtils.parseIsoDatePart(row['datum']);
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row['polazak_at']?.toString());
      if (datum != datumIso || rowGrad != grad || rowVreme != normVreme) return false;
      return includeRow(row);
    }).toList(growable: false);
  }

  static Map<String, dynamic>? _findOperativnaRowForPutnik({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String datumIso,
    required String putnikId,
    required String grad,
    required String vreme,
    required bool Function(Map<String, dynamic> row) includeRow,
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    for (final row in operativnaRows) {
      final datum = V3DateUtils.parseIsoDatePart(row['datum']);
      final rowPutnikId = row['created_by']?.toString() ?? '';
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row['polazak_at']?.toString());

      if (datum == datumIso && rowPutnikId == putnikId && rowGrad == grad && rowVreme == normVreme && includeRow(row)) {
        return row;
      }
    }

    return null;
  }
}
