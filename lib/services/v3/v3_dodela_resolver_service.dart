import '../../utils/v3_time_utils.dart';
import 'v3_trenutna_dodela_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';

class V3DodelaResolverService {
  V3DodelaResolverService._();

  static Future<({Map<String, String> byTerminId, Map<String, String> bySlotKey})> loadActiveAssignments({
    String? putnikId,
    String? vozacId,
  }) async {
    final byTerminId = await V3TrenutnaDodelaService.loadActiveVozacByTerminId(
      putnikId: putnikId,
      vozacId: vozacId,
    );
    final bySlotKey = await V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey(
      vozacId: vozacId,
    );
    return (byTerminId: byTerminId, bySlotKey: bySlotKey);
  }

  static String resolveVozacIdForSlot({
    required String datumIso,
    required String grad,
    required String vreme,
    required Map<String, String> activeVozacBySlotKey,
  }) {
    return activeVozacBySlotKey[V3TrenutnaDodelaSlotService.slotKey(
          datumIso: datumIso,
          grad: grad,
          vreme: vreme,
        )] ??
        '';
  }

  static String resolveVozacIdForOperativnaRow({
    required Map<String, dynamic> row,
    required Map<String, String> activeVozacByTerminId,
    required Map<String, String> activeVozacBySlotKey,
    String vremeKolona = 'polazak_at',
  }) {
    final terminId = row['id']?.toString().trim() ?? '';
    if (terminId.isNotEmpty) {
      final direct = activeVozacByTerminId[terminId] ?? '';
      if (direct.isNotEmpty) return direct;
    }

    final datumIso = _parseIsoDatePart(row['datum']?.toString());
    final grad = row['grad']?.toString() ?? '';
    final rawVreme = row[vremeKolona]?.toString() ?? row['vreme']?.toString() ?? '';
    final normVreme = V3TimeUtils.normalizeToHHmm(rawVreme);
    if (datumIso.isEmpty || grad.trim().isEmpty || normVreme.isEmpty) return '';

    return resolveVozacIdForSlot(
      datumIso: datumIso,
      grad: grad,
      vreme: normVreme,
      activeVozacBySlotKey: activeVozacBySlotKey,
    );
  }

  static String _parseIsoDatePart(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(raw);
    return match?.group(1) ?? '';
  }
}
