import '../../utils/v3_belgrade_time.dart';
import 'v3_trenutna_dodela_slot_service.dart';

class V3DodelaResolverService {
  V3DodelaResolverService._();

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

  /// Kombi za konkretan slot (datum+grad+vreme).
  /// Isključivo eksplicitna dodela po slotu (`activeVoziloBySlotKey`) — BEZ
  /// fallback-a na trajnu dodelu vozača. Kombi je nezavisan atribut sloga,
  /// isto kao dodela putnika, i ne treba da se "nasleđuje" od vozača.
  static String resolveVoziloIdForSlot({
    required String datumIso,
    required String grad,
    required String vreme,
    required Map<String, String> activeVoziloBySlotKey,
  }) {
    final key = V3TrenutnaDodelaSlotService.slotKey(datumIso: datumIso, grad: grad, vreme: vreme);
    return activeVoziloBySlotKey[key] ?? '';
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

    final datumIso = V3BelgradeTime.parseIsoDatePart(row['datum']);
    final grad = row['grad']?.toString() ?? '';
    final rawVreme = row[vremeKolona]?.toString() ?? row['vreme']?.toString() ?? '';
    final normVreme = V3BelgradeTime.normalizeToHHmm(rawVreme);
    if (datumIso.isEmpty || grad.trim().isEmpty || normVreme.isEmpty) return '';

    return resolveVozacIdForSlot(
      datumIso: datumIso,
      grad: grad,
      vreme: normVreme,
      activeVozacBySlotKey: activeVozacBySlotKey,
    );
  }
}
