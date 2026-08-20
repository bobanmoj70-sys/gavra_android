import '../../utils/v3_belgrade_time.dart';
import 'v3_trenutna_dodela_slot_service.dart';
import 'v3_vozilo_service.dart';

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
  /// Prioritet: eksplicitna dodela po slotu (`activeVoziloBySlotKey`) →
  /// fallback na trajnu dodelu voza\u010da (`v3_vozila.vozac_id`) ako je [vozacId] prosle\u0111en.
  static String resolveVoziloIdForSlot({
    required String datumIso,
    required String grad,
    required String vreme,
    required Map<String, String> activeVoziloBySlotKey,
    String? vozacId,
  }) {
    final key = V3TrenutnaDodelaSlotService.slotKey(datumIso: datumIso, grad: grad, vreme: vreme);
    final bySlot = activeVoziloBySlotKey[key] ?? '';
    if (bySlot.isNotEmpty) return bySlot;

    final driverId = (vozacId ?? '').trim();
    if (driverId.isNotEmpty) {
      return V3VoziloService.getVoziloForVozac(driverId)?.id ?? '';
    }
    return '';
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
