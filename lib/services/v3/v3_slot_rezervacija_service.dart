import '../../globals.dart';
import '../../utils/v3_time_utils.dart';

class V3SlotRezervacijaService {
  V3SlotRezervacijaService._();

  static String normalizeGrad(String grad) => grad.trim().toUpperCase();

  static String normalizeVreme(String? vreme) => V3TimeUtils.normalizeToHHmm(vreme);

  static String normalizeDatum(String datumIso) {
    final value = datumIso.trim();
    if (value.length >= 10) return value.substring(0, 10);
    return value;
  }

  static String slotKey({
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    final d = normalizeDatum(datumIso);
    final g = normalizeGrad(grad);
    final v = normalizeVreme(vreme);
    return '$d|$g|$v';
  }

  static Future<Map<String, String>> loadActiveVozacBySlotKey() async {
    final rows = await supabase
        .from('v3_slot_rezervacije')
        .select('datum, grad, vreme, vozac_v3_auth_id, status')
        .eq('status', 'aktivan');

    final next = <String, String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final status = mapped['status']?.toString() ?? '';
      if (status != 'aktivan') continue;

      final datumIso = normalizeDatum(mapped['datum']?.toString() ?? '');
      final grad = normalizeGrad(mapped['grad']?.toString() ?? '');
      final vreme = normalizeVreme(mapped['vreme']?.toString());
      final vozacId = mapped['vozac_v3_auth_id']?.toString().trim() ?? '';
      if (datumIso.isEmpty || grad.isEmpty || vreme.isEmpty || vozacId.isEmpty) continue;

      next[slotKey(datumIso: datumIso, grad: grad, vreme: vreme)] = vozacId;
    }

    return next;
  }

  static Future<Set<String>> loadActiveSlotKeysForVozac({
    required String vozacId,
    String? datumIso,
  }) async {
    final vozac = vozacId.trim();
    if (vozac.isEmpty) return <String>{};

    dynamic query = supabase
        .from('v3_slot_rezervacije')
        .select('datum, grad, vreme, status')
        .eq('vozac_v3_auth_id', vozac)
        .eq('status', 'aktivan');

    final normalizedDatum = datumIso == null ? '' : normalizeDatum(datumIso);
    if (normalizedDatum.isNotEmpty) {
      query = query.eq('datum', normalizedDatum);
    }

    final rows = await query;
    final result = <String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final datum = normalizeDatum(mapped['datum']?.toString() ?? '');
      final grad = normalizeGrad(mapped['grad']?.toString() ?? '');
      final vreme = normalizeVreme(mapped['vreme']?.toString());
      if (datum.isEmpty || grad.isEmpty || vreme.isEmpty) continue;
      result.add(slotKey(datumIso: datum, grad: grad, vreme: vreme));
    }

    return result;
  }

  static Future<void> upsertActive({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    String? updatedBy,
  }) async {
    final payload = <String, dynamic>{
      'datum': normalizeDatum(datumIso),
      'grad': normalizeGrad(grad),
      'vreme': normalizeVreme(vreme),
      'vozac_v3_auth_id': vozacId.trim(),
      'status': 'aktivan',
      if ((updatedBy ?? '').trim().isNotEmpty) 'updated_by': updatedBy!.trim(),
    };

    await supabase.from('v3_slot_rezervacije').upsert(
          payload,
          onConflict: 'datum,grad,vreme',
        );
  }

  static Future<void> deleteSlot({
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    await supabase
        .from('v3_slot_rezervacije')
        .delete()
        .eq('datum', normalizeDatum(datumIso))
        .eq('grad', normalizeGrad(grad))
        .eq('vreme', normalizeVreme(vreme));
  }
}
