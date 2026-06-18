import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_time_utils.dart';

class V3TrenutnaDodelaSlotService {
  V3TrenutnaDodelaSlotService._();

  static const String tableName = 'v3_trenutna_dodela_slot';
  static const String colDatum = 'datum';
  static const String colGrad = 'grad';
  static const String colVreme = 'vreme';
  static const String colVozacId = 'vozac_v3_auth_id';
  static const String colUpdatedBy = 'updated_by';
  static const String colWaypointsJson = 'waypoints_json';

  static String _normalizeDatumIso(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';

    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(value);
    return match?.group(1) ?? '';
  }

  static String _normalizeGrad(String? raw) => (raw ?? '').trim().toUpperCase();

  static String _normalizeVreme(String? raw) => V3TimeUtils.normalizeToHHmm(raw);

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

  static Future<List<Map<String, String>>> loadActiveSlotsForVozac({
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
        .upsert(payload, onConflict: '$colDatum,$colGrad,$colVreme,$colVozacId')
        .select('id')
        .single();
    return result['id']?.toString();
  }

  static Future<void> updateWaypointsJson({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    required List<Map<String, dynamic>> waypoints,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    final vozacIdNorm = vozacId.trim();
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty || vozacIdNorm.isEmpty || waypoints.isEmpty) return;

    final updatedRows = await supabase
        .from(tableName)
        .update({colWaypointsJson: waypoints})
        .eq(colDatum, datum)
        .eq(colGrad, gradNorm)
        .eq(colVreme, vremeNorm)
        .eq(colVozacId, vozacIdNorm)
        .select('datum');

    if (updatedRows.isEmpty) {
      debugPrint(
          '[V3TrenutnaDodelaSlotService] updateWaypointsJson: 0 rows updated for slot=$datum|$gradNorm|$vremeNorm vozac=$vozacIdNorm');
    }
  }

  static Future<void> updateCurrentLocation({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    required double lat,
    required double lng,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    final vozacIdNorm = vozacId.trim();
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty || vozacIdNorm.isEmpty) return;

    // Samo čuvaj trenutnu lokaciju, ne istoriju
    final currentLocation = <Map<String, dynamic>>[
      {
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().toIso8601String(),
      }
    ];

    final updatedRows = await supabase
        .from(tableName)
        .update({colWaypointsJson: currentLocation})
        .eq(colDatum, datum)
        .eq(colGrad, gradNorm)
        .eq(colVreme, vremeNorm)
        .eq(colVozacId, vozacIdNorm)
        .select('datum');

    if (updatedRows.isEmpty) {
      debugPrint(
          '[V3TrenutnaDodelaSlotService] updateCurrentLocation: 0 rows updated for slot=$datum|$gradNorm|$vremeNorm vozac=$vozacIdNorm');
    }
  }

  static Future<void> mergePassengersIntoWaypointsJson({
    required String datumIso,
    required String grad,
    required String vreme,
    required String vozacId,
    required List<Map<String, dynamic>> passengers,
  }) async {
    final datum = _normalizeDatumIso(datumIso);
    final gradNorm = _normalizeGrad(grad);
    final vremeNorm = _normalizeVreme(vreme);
    final vozacIdNorm = vozacId.trim();
    if (datum.isEmpty || gradNorm.isEmpty || vremeNorm.isEmpty || vozacIdNorm.isEmpty) return;

    final rows = await supabase
        .from(tableName)
        .select('id, $colWaypointsJson')
        .eq(colDatum, datum)
        .eq(colGrad, gradNorm)
        .eq(colVreme, vremeNorm)
        .eq(colVozacId, vozacIdNorm);

    if ((rows as List<dynamic>).isEmpty) return;

    final row = rows.first;
    final rowId = row['id']?.toString().trim() ?? '';
    if (rowId.isEmpty) return;

    final existing = row[colWaypointsJson];
    final merged = <String, dynamic>{
      if (existing is Map) ...Map<String, dynamic>.from(existing as Map<String, dynamic>),
      'passengers': passengers,
    };

    await supabase.from(tableName).update({colWaypointsJson: merged}).eq('id', rowId);
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

    final payload = <String, dynamic>{
      colDatum: datum,
      colGrad: gradNorm,
      colVreme: vremeNorm,
      colVozacId: vozac,
      if ((updatedBy ?? '').trim().isNotEmpty) colUpdatedBy: updatedBy!.trim(),
    };

    final result = await supabase
        .from(tableName)
        .upsert(payload, onConflict: '$colDatum,$colGrad,$colVreme,$colVozacId')
        .select('id')
        .single();
    return result['id']?.toString();
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
    dynamic query = supabase.from(tableName).select('$colDatum, $colGrad, $colVreme, $colVozacId');

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
      final vozacId = (mapped[colVozacId]?.toString() ?? '').trim();
      if (datum.isNotEmpty && grad.isNotEmpty && vreme.isNotEmpty && vozacId.isNotEmpty) {
        result['$datum|$grad|$vreme'] = vozacId;
      }
    }
    return result;
  }
}
