import '../../globals.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_time_utils.dart';
import 'v3_osrm_service.dart';

class V3TrenutnaDodelaService {
  V3TrenutnaDodelaService._();

  static const String tableName = 'v3_trenutna_dodela';
  static const String statusAktivan = 'aktivan';
  static const String _colTerminId = 'termin_id';
  static const String _colPutnikId = 'putnik_v3_auth_id';
  static const String colVozacId = 'vozac_v3_auth_id';
  static const String _colStatus = 'status';
  static const String _colUpdatedBy = 'updated_by';
  static const String _colRouteOrder = 'route_order';
  static const String _colEta = 'eta';

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

  static Future<bool> hasNepokupljeniPutnikForVozac({
    required String vozacId,
  }) async {
    final vozac = vozacId.trim();
    if (vozac.isEmpty) return false;

    final assignmentsRaw = await supabase
        .from(tableName)
        .select('$_colTerminId, $_colStatus')
        .eq(colVozacId, vozac)
        .eq(_colStatus, statusAktivan);

    final terminIds = <String>[];
    for (final row in (assignmentsRaw as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final status = mapped[_colStatus]?.toString() ?? '';
      if (!V3StatusPolicy.isDodelaAktivna(status)) continue;

      final terminId = mapped[_colTerminId]?.toString().trim() ?? '';
      if (terminId.isEmpty) continue;
      terminIds.add(terminId);
    }

    if (terminIds.isEmpty) return false;

    final operativnaRaw =
        await supabase.from('v3_operativna_nedelja').select('id, otkazano_at, pokupljen_at').inFilter('id', terminIds);

    for (final row in (operativnaRaw as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      if (V3StatusPolicy.canAssign(
        status: null,
        otkazanoAt: mapped['otkazano_at'],
        pokupljenAt: mapped['pokupljen_at'],
      )) {
        return true;
      }
    }

    return false;
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

  static Future<void> refreshRouteOrderEtaForVozac({
    required String vozacId,
    required double originLat,
    required double originLng,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final vozac = vozacId.trim();
    if (vozac.isEmpty) return;

    final slotDatum = datumIso.trim();
    final slotGrad = grad.trim().toUpperCase();
    final slotVreme = V3TimeUtils.normalizeToHHmm(vreme);
    if (slotDatum.isEmpty || slotGrad.isEmpty || slotVreme.isEmpty) return;

    final assignmentsRaw = await supabase
        .from(tableName)
        .select('$_colTerminId, $_colPutnikId, $_colStatus')
        .eq(colVozacId, vozac)
        .eq(_colStatus, statusAktivan);

    final assignments = <({String terminId, String putnikId})>[];
    for (final row in (assignmentsRaw as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final status = mapped[_colStatus]?.toString() ?? '';
      if (!V3StatusPolicy.isDodelaAktivna(status)) continue;

      final terminId = mapped[_colTerminId]?.toString().trim() ?? '';
      final putnikId = mapped[_colPutnikId]?.toString().trim() ?? '';
      if (terminId.isEmpty || putnikId.isEmpty) continue;

      assignments.add((terminId: terminId, putnikId: putnikId));
    }

    if (assignments.isEmpty) return;

    final terminIds = assignments.map((a) => a.terminId).toSet().toList(growable: false);
    final putnikIds = assignments.map((a) => a.putnikId).toSet().toList(growable: false);

    final operativnaRaw = await supabase
        .from('v3_operativna_nedelja')
        .select('id, grad, koristi_sekundarnu, adresa_override_id, otkazano_at, pokupljen_at')
        .inFilter('id', terminIds);

    final putniciRaw = await supabase
        .from('v3_auth')
        .select(
          'id, adresa_bc_id:adresa_primary_bc_id, adresa_bc_id_2:adresa_secondary_bc_id, adresa_vs_id:adresa_primary_vs_id, adresa_vs_id_2:adresa_secondary_vs_id',
        )
        .inFilter('id', putnikIds);

    final operativnaById = <String, Map<String, dynamic>>{};
    for (final row in (operativnaRaw as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final id = mapped['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      operativnaById[id] = mapped;
    }

    final putnikById = <String, Map<String, dynamic>>{};
    for (final row in (putniciRaw as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final id = mapped['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      putnikById[id] = mapped;
    }

    final scopedAssignments = <({String terminId, String putnikId})>[];
    for (final assignment in assignments) {
      final operativna = operativnaById[assignment.terminId];
      if (operativna == null) continue;

      final rowDatum = V3DanHelper.parseIsoDatePart(operativna['datum']?.toString() ?? '');
      final rowGrad = (operativna['grad']?.toString() ?? '').trim().toUpperCase();
      final rowVreme = V3TimeUtils.normalizeToHHmm(operativna['polazak_at']?.toString());

      if (rowDatum != slotDatum) continue;
      if (rowGrad != slotGrad) continue;
      if (rowVreme != slotVreme) continue;

      scopedAssignments.add(assignment);
    }

    if (scopedAssignments.isEmpty) return;

    final adresaIds = <String>{};
    for (final assignment in scopedAssignments) {
      final operativna = operativnaById[assignment.terminId];
      final putnik = putnikById[assignment.putnikId];
      if (operativna == null || putnik == null) continue;

      final adresaId = _resolveAdresaId(
        grad: operativna['grad']?.toString(),
        koristiSekundarnu: operativna['koristi_sekundarnu'] as bool? ?? false,
        adresaOverrideId: operativna['adresa_override_id']?.toString(),
        putnikRow: putnik,
      );
      if (adresaId.isNotEmpty) {
        adresaIds.add(adresaId);
      }
    }

    final adreseById = <String, ({double lat, double lng})>{};
    if (adresaIds.isNotEmpty) {
      final adreseRaw = await supabase
          .from('v3_adrese')
          .select('id, gps_lat, gps_lng')
          .inFilter('id', adresaIds.toList(growable: false));

      for (final row in (adreseRaw as List<dynamic>)) {
        final mapped = row as Map<String, dynamic>;
        final id = mapped['id']?.toString().trim() ?? '';
        final lat = _toDouble(mapped['gps_lat']);
        final lng = _toDouble(mapped['gps_lng']);
        if (id.isEmpty || lat == null || lng == null) continue;
        adreseById[id] = (lat: lat, lng: lng);
      }
    }

    final activeStops = <V3OsrmStop>[];
    final stopIdByTerminId = <String, String>{};

    for (final assignment in scopedAssignments) {
      final operativna = operativnaById[assignment.terminId];
      final putnik = putnikById[assignment.putnikId];
      if (operativna == null || putnik == null) continue;

      if (!V3StatusPolicy.canAssign(
        status: null,
        otkazanoAt: operativna['otkazano_at'],
        pokupljenAt: operativna['pokupljen_at'],
      )) {
        continue;
      }

      final adresaId = _resolveAdresaId(
        grad: operativna['grad']?.toString(),
        koristiSekundarnu: operativna['koristi_sekundarnu'] as bool? ?? false,
        adresaOverrideId: operativna['adresa_override_id']?.toString(),
        putnikRow: putnik,
      );

      final coords = adreseById[adresaId];
      if (coords == null) continue;

      final stopId = assignment.terminId;
      stopIdByTerminId[assignment.terminId] = stopId;
      activeStops.add(V3OsrmStop(id: stopId, lat: coords.lat, lng: coords.lng));
    }

    if (activeStops.isEmpty) {
      await _clearRouteEtaForTerminIds(terminIds: terminIds, updatedBy: vozac);
      return;
    }

    final optimizedIds = await V3OsrmService.optimizeStopOrderByDuration(
      originLat: originLat,
      originLng: originLng,
      stops: activeStops,
    );

    if (optimizedIds == null || optimizedIds.isEmpty) {
      return;
    }

    final stopById = {for (final stop in activeStops) stop.id: stop};
    final orderedStops = optimizedIds.map((id) => stopById[id]).whereType<V3OsrmStop>().toList(growable: false);

    if (orderedStops.isEmpty) {
      return;
    }

    final etaByStopId = await V3OsrmService.getEtaMinutesForOrderedStops(
      originLat: originLat,
      originLng: originLng,
      orderedStops: orderedStops,
    );

    final routeOrderByStopId = <String, int>{};
    for (var index = 0; index < orderedStops.length; index++) {
      routeOrderByStopId[orderedStops[index].id] = index + 1;
    }

    for (final assignment in scopedAssignments) {
      final stopId = stopIdByTerminId[assignment.terminId];
      final routeOrder = stopId != null ? routeOrderByStopId[stopId] : null;
      final eta = stopId != null ? (etaByStopId == null ? null : etaByStopId[stopId]) : null;

      await supabase.from(tableName).update(<String, dynamic>{
        _colRouteOrder: routeOrder,
        _colEta: eta,
        _colUpdatedBy: vozac,
      }).eq(_colTerminId, assignment.terminId);
    }
  }

  static Future<void> _clearRouteEtaForTerminIds({
    required List<String> terminIds,
    required String updatedBy,
  }) async {
    for (final terminId in terminIds) {
      await supabase.from(tableName).update(<String, dynamic>{
        _colRouteOrder: null,
        _colEta: null,
        _colUpdatedBy: updatedBy,
      }).eq(_colTerminId, terminId);
    }
  }

  static String _resolveAdresaId({
    required String? grad,
    required bool koristiSekundarnu,
    required String? adresaOverrideId,
    required Map<String, dynamic> putnikRow,
  }) {
    final override = (adresaOverrideId ?? '').trim();
    if (override.isNotEmpty) return override;

    final gradNorm = (grad ?? '').trim().toUpperCase();
    if (gradNorm == 'BC') {
      final a1 = (putnikRow['adresa_bc_id']?.toString() ?? '').trim();
      final a2 = (putnikRow['adresa_bc_id_2']?.toString() ?? '').trim();
      if (koristiSekundarnu) {
        if (a2.isNotEmpty) return a2;
        if (a1.isNotEmpty) return a1;
        return '';
      }
      if (a1.isNotEmpty) return a1;
      if (a2.isNotEmpty) return a2;
      return '';
    }

    if (gradNorm == 'VS') {
      final a1 = (putnikRow['adresa_vs_id']?.toString() ?? '').trim();
      final a2 = (putnikRow['adresa_vs_id_2']?.toString() ?? '').trim();
      if (koristiSekundarnu) {
        if (a2.isNotEmpty) return a2;
        if (a1.isNotEmpty) return a1;
        return '';
      }
      if (a1.isNotEmpty) return a1;
      if (a2.isNotEmpty) return a2;
      return '';
    }

    return '';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
