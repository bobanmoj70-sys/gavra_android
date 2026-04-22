import '../../globals.dart';
import '../../services/v3/v3_operativna_nedelja_service.dart';
import '../../utils/v3_status_filters.dart';
import '../../utils/v3_time_utils.dart';

class V3BojaStatusHelper {
  V3BojaStatusHelper._();

  static bool matchesSelectedSlot({
    required V3OperativnaNedeljaEntry entry,
    required String grad,
    required String vreme,
  }) {
    final gradNorm = (entry.grad ?? '').trim().toUpperCase();
    final selectedGradNorm = grad.trim().toUpperCase();
    if (gradNorm != selectedGradNorm) return false;

    final entryVreme = V3TimeUtils.normalizeToHHmm(entry.polazakAt);
    final selectedVreme = V3TimeUtils.normalizeToHHmm(vreme);
    return entryVreme == selectedVreme;
  }

  static int countMestaForSlot({
    required Iterable<V3OperativnaNedeljaEntry> entries,
    required String grad,
    required String vreme,
  }) {
    return entries.where((entry) {
      return matchesSelectedSlot(entry: entry, grad: grad, vreme: vreme);
    }).fold(0, (sum, entry) => sum + entry.brojMesta);
  }

  static int compareEntriesForDisplay({
    required V3OperativnaNedeljaEntry a,
    required V3OperativnaNedeljaEntry b,
    required String? currentVozacId,
    required String? Function(V3OperativnaNedeljaEntry entry) assignedVozacIdForEntry,
    required String Function(String putnikId) putnikNameById,
  }) {
    int rankFor(V3OperativnaNedeljaEntry entry) {
      if (V3StatusFilters.isOtkazanoAt(entry.otkazanoAt)) return 3;
      if (V3StatusFilters.isPokupljenAt(entry.pokupljenAt)) return 2;

      if (currentVozacId != null && currentVozacId.isNotEmpty) {
        final assigned = (assignedVozacIdForEntry(entry) ?? '').trim();
        if (assigned.isNotEmpty) {
          return assigned == currentVozacId ? 0 : 1;
        }
      }

      return 1;
    }

    final aRank = rankFor(a);
    final bRank = rankFor(b);
    if (aRank != bRank) return aRank.compareTo(bRank);

    final aIme = putnikNameById(a.putnikId);
    final bIme = putnikNameById(b.putnikId);
    return aIme.compareTo(bIme);
  }

  static String? assignedVozacIdForPutnik({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String putnikId,
    required String grad,
    required String vreme,
    required String datumIso,
    required String Function(Map<String, dynamic> row) vozacIdForRow,
    required bool Function(Map<String, dynamic> row) isVisibleRow,
    String vremeKolona = 'polazak_at',
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    for (final row in operativnaRows) {
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row[vremeKolona]?.toString());
      final rowDatum = V3DanHelper.parseIsoDatePart(row['datum']?.toString() ?? '');
      final rowPutnikId = row['created_by']?.toString() ?? '';

      if (rowPutnikId != putnikId) continue;
      if (rowGrad != grad) continue;
      if (rowVreme != normVreme) continue;
      if (rowDatum != datumIso) continue;
      if (!isVisibleRow(row)) continue;

      final vozacId = vozacIdForRow(row).trim();
      if (vozacId.isNotEmpty) return vozacId;
    }

    return null;
  }

  static String? sharedVozacIdForTermin({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String grad,
    required String vreme,
    required String datumIso,
    required String Function(Map<String, dynamic> row) vozacIdForRow,
    required bool Function(Map<String, dynamic> row) isVisibleRow,
    String vremeKolona = 'polazak_at',
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    String? zajednickiVozacId;
    var hasRows = false;

    for (final row in operativnaRows) {
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row[vremeKolona]?.toString());
      final rowDatum = V3DanHelper.parseIsoDatePart(row['datum']?.toString() ?? '');

      if (rowGrad != grad) continue;
      if (rowVreme != normVreme) continue;
      if (rowDatum != datumIso) continue;
      if (!isVisibleRow(row)) continue;

      hasRows = true;
      final vozacId = vozacIdForRow(row).trim();
      if (vozacId.isEmpty) return null;

      if (zajednickiVozacId == null) {
        zajednickiVozacId = vozacId;
      } else if (zajednickiVozacId != vozacId) {
        return null;
      }
    }

    if (!hasRows) return null;
    return zajednickiVozacId;
  }
}
