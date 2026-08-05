import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_belgrade_time.dart';

class V3TrenutnaDodelaSlotService {
  V3TrenutnaDodelaSlotService._();

  static const String tableName = 'v3_trenutna_dodela_slot';
  static const String colDatum = 'datum';
  static const String colGrad = 'grad';
  static const String colVreme = 'vreme';
  static const String colVozacId = 'vozac_v3_auth_id';
  static const String colUpdatedBy = 'updated_by';

  /// Delegira na deljeni `V3BelgradeTime.parseIsoDatePart` (JEDAN IZVOR ISTINE za
  /// normalizaciju ISO datuma na `yyyy-MM-dd`, ranije duplirano ovde kao manje
  /// robustna kopija bez podrške za timezone offset).
  static String _normalizeDatumIso(String? raw) => V3BelgradeTime.parseIsoDatePart(raw);

  static String _normalizeGrad(String? raw) => (raw ?? '').trim().toUpperCase();

  static String _normalizeVreme(String? raw) => V3BelgradeTime.normalizeToHHmm(raw);

  static String slotKey({
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    return '$datum|$gradNorm|$vremeNorm';
  }

  static Future<Map<String, String>> loadActiveVozacBySlotKey({
    String? vozacId,
    String? datumIso,
  }) async {
    dynamic query = supabase.from(tableName).select('$colDatum, $colGrad, $colVreme, $colVozacId');

    final trimmedVozacId = (vozacId ?? '').trim();
    if (trimmedVozacId.isNotEmpty) {
      query = query.eq(colVozacId, trimmedVozacId);
    }

    final trimmedDatum = _normalizeDatumIso(datumIso);
    if (trimmedDatum.isNotEmpty) {
      query = query.eq(colDatum, trimmedDatum);
    }

    final rows = await query;

    final result = <String, String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final datum = _normalizeDatumIso(mapped[colDatum]?.toString());
      final grad = _normalizeGrad(mapped[colGrad]?.toString());
      final vreme = _normalizeVreme(mapped[colVreme]?.toString());
      final assignedVozacId = mapped[colVozacId]?.toString().trim() ?? '';
      if (datum.isEmpty || grad.isEmpty || vreme.isEmpty || assignedVozacId.isEmpty) continue;

      result['$datum|$grad|$vreme'] = assignedVozacId;
    }

    return result;
  }

  static Future<String?> upsertActiveSlotDodela({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    String? updatedBy,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    final vozac = vozacId.trim();

    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty || vozac.isEmpty) return null;

    final payload = <String, dynamic>{
      colDatum: datum,
      colGrad: gradNorm,
      colVreme: vremeNorm,
      colVozacId: vozac,
      if ((updatedBy ?? '').trim().isNotEmpty) colUpdatedBy: updatedBy!.trim(),
    };

    final result = await supabase
        .from(tableName)
        .upsert(payload, onConflict: '$colDatum,$colGrad,$colVreme')
        .select('id')
        .single();
    return result['id']?.toString();
  }

  static Future<void> syncPassengerCoordinates(
    List<Map<String, dynamic>> passengers,
  ) async {
    if (passengers.isEmpty) return;

    for (final p in passengers) {
      final terminId = (p['termin_id'] ?? '').toString().trim();
      final lat = p['lat'];
      final lng = p['lng'];
      if (terminId.isEmpty || lat == null || lng == null) continue;

      final latNum = double.tryParse(lat.toString());
      final lngNum = double.tryParse(lng.toString());
      if (latNum == null || lngNum == null) continue;

      await supabase.from('v3_trenutna_dodela').update({
        'adresa_gps_lat': latNum,
        'adresa_gps_lng': lngNum,
      }).eq('termin_id', terminId);
    }
  }

  static Future<void> deleteBySlot({
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty) return;

    await supabase.from(tableName).delete().eq(colDatum, datum).eq(colGrad, gradNorm).eq(colVreme, vremeNorm);
  }

  static Future<void> deleteSlot({
    required String datumIso,
    required String grad,
    required String vreme,
    String? vozacId,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty) return;

    dynamic query = supabase.from(tableName).delete().eq(colDatum, datum).eq(colGrad, gradNorm).eq(colVreme, vremeNorm);
    final vozacNorm = (vozacId ?? '').trim();
    if (vozacNorm.isNotEmpty) {
      query = query.eq(colVozacId, vozacNorm);
    }
    await query;
  }

  static Future<String?> activateSlot({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    String? updatedBy,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    final vozac = vozacId.trim();
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty || vozac.isEmpty) return null;

    final existing = await supabase
        .from(tableName)
        .select('id')
        .eq(colDatum, datum)
        .eq(colGrad, gradNorm)
        .eq(colVreme, vremeNorm)
        .maybeSingle();

    if (existing != null) {
      final id = existing['id']?.toString();
      // Multi-driver: ne prepisuj vozac_v3_auth_id na deljenom slotu.
      if ((updatedBy ?? '').trim().isNotEmpty && id != null && id.isNotEmpty) {
        await supabase.from(tableName).update({colUpdatedBy: updatedBy!.trim()}).eq('id', id);
      }
      return id;
    }

    final result = await supabase
        .from(tableName)
        .insert(<String, dynamic>{
          colDatum: datum,
          colGrad: gradNorm,
          colVreme: vremeNorm,
          colVozacId: vozac,
          if ((updatedBy ?? '').trim().isNotEmpty) colUpdatedBy: updatedBy!.trim(),
        })
        .select('id')
        .single();
    return result['id']?.toString();
  }

  static Future<String?> fetchSlotId({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty) return null;

    // Slot je po (datum,grad,vreme) — vozacId se ne koristi (multi-driver shared).
    final rows = await supabase
        .from(tableName)
        .select('id')
        .eq(colDatum, datum)
        .eq(colGrad, gradNorm)
        .eq(colVreme, vremeNorm)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['id']?.toString();
  }

  static Future<void> deleteAllSlotsForVozac({
    required String vozacId,
  }) async {
    final vozac = vozacId.trim();
    if (vozac.isEmpty) return;

    await supabase.from(tableName).delete().eq(colVozacId, vozac);
  }

  static Future<List<Map<String, String>>> loadAllSlotsForVozac({
    required String vozacId,
  }) async {
    final vozac = vozacId.trim();
    if (vozac.isEmpty) return <Map<String, String>>[];

    final rows = await supabase.from(tableName).select('$colDatum, $colGrad, $colVreme').eq(colVozacId, vozac);

    final result = <Map<String, String>>[];
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final datum = _normalizeDatumIso(mapped[colDatum]?.toString());
      final grad = _normalizeGrad(mapped[colGrad]?.toString());
      final vreme = _normalizeVreme(mapped[colVreme]?.toString());
      if (datum.isEmpty || grad.isEmpty || vreme.isEmpty) continue;

      result.add(<String, String>{
        colDatum: datum,
        colGrad: grad,
        colVreme: vreme,
      });
    }

    return result;
  }

  static Future<Map<String, String>> loadAllVozacBySlotKey({
    String? datumIso,
  }) async {
    dynamic query = supabase.from(tableName).select('$colDatum, $colGrad, $colVreme, $colVozacId, updated_at');

    final trimmedDatum = _normalizeDatumIso(datumIso);
    if (trimmedDatum.isNotEmpty) {
      query = query.eq(colDatum, trimmedDatum);
    }

    query = query.order('updated_at', ascending: false);

    final rows = await query;

    final result = <String, String>{};
    for (final row in (rows as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final datum = _normalizeDatumIso(mapped[colDatum]?.toString());
      final grad = _normalizeGrad(mapped[colGrad]?.toString());
      final vreme = _normalizeVreme(mapped[colVreme]?.toString());
      final vozacId = (mapped[colVozacId]?.toString() ?? '').trim();
      if (datum.isNotEmpty && grad.isNotEmpty && vreme.isNotEmpty && vozacId.isNotEmpty) {
        final key = '$datum|$grad|$vreme';
        if (result.containsKey(key)) {
          debugPrint(
              '[V3TrenutnaDodelaSlotService] Duplicate slotKey detected while loading: $key (keeping latest updated_at row)');
          continue;
        }
        result[key] = vozacId;
      }
    }
    return result;
  }
}
