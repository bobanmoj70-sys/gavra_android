import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_time_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_osrm_route_service.dart';
import 'v3_route_waypoint_resolver_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';

class V3EtaDolazakData {
  const V3EtaDolazakData({
    required this.vozacIme,
    required this.etaSeconds,
  });

  final String vozacIme;
  final int etaSeconds;
}

/// TTL entry za kratki in-memory cache.
class _TtlEntry<T> {
  _TtlEntry(this.value, this.expiresAt);
  final T value;
  final DateTime expiresAt;
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class V3EtaOrchestratorService {
  V3EtaOrchestratorService({
    V3RouteWaypointResolverService? routeWaypointResolverService,
    V3OsrmRouteService? osrmRouteService,
  })  : _routeWaypointResolverService = routeWaypointResolverService ?? V3RouteWaypointResolverService(),
        _osrmRouteService = osrmRouteService ?? V3OsrmRouteService();

  static const String _vozacLokacijeTable = 'v3_vozac_lokacije';
  static const String _vozacLokacijeColVozacId = 'created_by';
  static const String _vozacLokacijeColUpdatedAt = 'updated_at';

  // TTL cache za vozac lokaciju — GPS šalje svakih 30s, pa 35s TTL je sigurno
  static const Duration _lokacijaTtl = Duration(seconds: 35);
  // TTL cache za waypoints_json — mijenja se samo kad vozač klikne START
  static const Duration _waypointsTtl = Duration(seconds: 90);

  final Map<String, _TtlEntry<({double lat, double lng})>> _lokacijaCache = {};
  final Map<String, _TtlEntry<List<V3RouteWaypoint>?>> _waypointsCache = {};

  final V3RouteWaypointResolverService _routeWaypointResolverService;
  final V3OsrmRouteService _osrmRouteService;

  Future<V3EtaDolazakData?> loadEtaForPutnik(String rawPutnikId) async {
    final putnikId = rawPutnikId.trim();
    if (putnikId.isEmpty) return null;

    debugPrint('[ETA] loadEtaForPutnik START putnikId=$putnikId');

    // OPTIMIZACIJA: Pozivi #1 i #2 paralelno umjesto sekvencijalno
    final dodelaFuture = supabase
        .from('v3_trenutna_dodela')
        .select('termin_id, vozac_v3_auth_id')
        .eq('putnik_v3_auth_id', putnikId)
        .eq('status', 'aktivan');
    final slotsFuture = V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey();

    final parallelInit = await Future.wait<dynamic>([dodelaFuture, slotsFuture]);

    final dodelaRows = parallelInit[0] as List<dynamic>;
    final activeVozacBySlotKey = parallelInit[1] as Map<String, String>;

    final assignments = dodelaRows
        .whereType<Map<String, dynamic>>()
        .map((row) => (
              terminId: (row['termin_id'] ?? '').toString().trim(),
              vozacId: (row['vozac_v3_auth_id'] ?? '').toString().trim(),
            ))
        .where((entry) => entry.terminId.isNotEmpty && entry.vozacId.isNotEmpty)
        .toList(growable: false);

    if (assignments.isEmpty) {
      debugPrint('[ETA] ❌ nema aktivnih dodela za putnikId=$putnikId');
      return null;
    }
    debugPrint(
        '[ETA] dodele(${assignments.length}): ${assignments.map((a) => 'termin=${a.terminId.substring(0, 8)} vozac=${a.vozacId.substring(0, 8)}').join(', ')}');
    debugPrint('[ETA] aktivni slotovi(${activeVozacBySlotKey.length}): ${activeVozacBySlotKey.keys.join(', ')}');

    // OPTIMIZACIJA: Poziv #3 eliminisan — koristimo operativnaNedeljaCache umjesto live DB
    final rm = V3MasterRealtimeManager.instance;
    final terminIds = assignments.map((e) => e.terminId).toSet();
    final operativnaRows = terminIds
        .map((id) => rm.operativnaNedeljaCache[id] ?? rm.operativnaAssignedCache[id])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    debugPrint('[ETA] operativna iz cache: ${operativnaRows.length} (od ${terminIds.length} terminId-a)');

    Map<String, dynamic>? selectedRow;
    String selectedVozacId = '';
    int? selectedDeltaSeconds;
    final now = DateTime.now();

    for (final row in operativnaRows) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      // Ako je putnik već pokupljen — ETA nema smisla prikazivati
      final pokupljenAt = row['pokupljen_at'];
      if (pokupljenAt != null) {
        debugPrint('[ETA] termin=${id.substring(0, 8)} — putnik pokupljen, preskačem');
        continue;
      }

      final assignment = assignments.where((a) => a.terminId == id).firstOrNull;
      if (assignment == null) continue;

      final planned = _resolvePlannedDateTime(row, now);
      final deltaSeconds = planned?.difference(now).inSeconds;
      final candidateSlotKey = V3TrenutnaDodelaSlotService.slotKey(
        datumIso: V3DateUtils.parseIsoDatePart(row['datum']),
        grad: (row['grad'] ?? '').toString(),
        vreme: row['polazak_at']?.toString() ?? row['vreme']?.toString() ?? '',
      );
      final candidateMatchesStartedSlot =
          candidateSlotKey.isNotEmpty && activeVozacBySlotKey[candidateSlotKey] == assignment.vozacId;
      debugPrint(
          '[ETA] termin=${id.substring(0, 8)} slotKey=$candidateSlotKey matchesStarted=$candidateMatchesStartedSlot slotVozac=${activeVozacBySlotKey[candidateSlotKey]?.substring(0, 8)} assignmentVozac=${assignment.vozacId.substring(0, 8)}');
      if (!candidateMatchesStartedSlot) continue;

      if (selectedRow == null) {
        selectedRow = row;
        selectedVozacId = assignment.vozacId;
        selectedDeltaSeconds = deltaSeconds;
        continue;
      }

      final currentDelta = selectedDeltaSeconds;
      final shouldReplace = _isBetterEtaCandidate(
        currentDeltaSeconds: currentDelta,
        candidateDeltaSeconds: deltaSeconds,
      );

      if (shouldReplace) {
        selectedRow = row;
        selectedVozacId = assignment.vozacId;
        selectedDeltaSeconds = deltaSeconds;
      }
    }

    if (selectedRow == null || selectedVozacId.isEmpty) {
      debugPrint('[ETA] ❌ nema selectedRow nakon slot matching');
      return null;
    }

    final selectedDatum = V3DateUtils.parseIsoDatePart(selectedRow['datum']);
    final selectedGrad = (selectedRow['grad'] ?? '').toString().trim().toUpperCase();
    final selectedVreme = selectedRow['polazak_at']?.toString() ?? '';
    final slotCacheKey = '$selectedVozacId|$selectedDatum|$selectedGrad|$selectedVreme';

    debugPrint(
        '[ETA] tražim slot: datum=$selectedDatum grad=$selectedGrad vreme=$selectedVreme vozacId=${selectedVozacId.substring(0, 8)}');

    // OPTIMIZACIJA: Pozivi #4 (lokacija) i #5 (waypoints) paralelno + TTL cache
    final lokacijaCached = _lokacijaCache[selectedVozacId];
    final waypointsCached = _waypointsCache[slotCacheKey];

    final needsLokacija = lokacijaCached == null || !lokacijaCached.isValid;
    final needsWaypoints = waypointsCached == null || !waypointsCached.isValid;

    debugPrint(
        '[ETA] cache: lokacija=${!needsLokacija ? 'HIT' : 'MISS'} waypoints=${!needsWaypoints ? 'HIT' : 'MISS'}');

    // OPTIMIZACIJA: Pozivi #4 (lokacija) i #5 (waypoints) paralelno + TTL cache
    final lokacijaFuture = needsLokacija
        ? _fetchVozacLokacija(selectedVozacId)
        : Future<({double lat, double lng})?>.value(lokacijaCached.value);
    final waypointsFuture = needsWaypoints
        ? _fetchWaypointsJson(selectedVozacId, selectedDatum, selectedGrad, selectedVreme)
        : Future<List<V3RouteWaypoint>?>.value(waypointsCached.value);

    final parallelLW = await Future.wait<dynamic>([lokacijaFuture, waypointsFuture]);

    final vozacLok = parallelLW[0] as ({double lat, double lng})?;
    if (needsLokacija) {
      if (vozacLok != null) {
        _lokacijaCache[selectedVozacId] = _TtlEntry(vozacLok, DateTime.now().add(_lokacijaTtl));
      } else {
        _lokacijaCache.remove(selectedVozacId);
      }
    }

    if (vozacLok == null) {
      debugPrint('[ETA] ❌ vozac lokacija null ili stale (>300s) za vozacId=${selectedVozacId.substring(0, 8)}');
      return null;
    }
    debugPrint('[ETA] vozac lokacija: lat=${vozacLok.lat} lng=${vozacLok.lng}');

    final vozacName = _resolveVozacName(selectedVozacId);

    final List<V3RouteWaypoint>? stopsFromSlot = parallelLW[1] as List<V3RouteWaypoint>?;
    if (needsWaypoints) {
      _waypointsCache[slotCacheKey] = _TtlEntry(stopsFromSlot, DateTime.now().add(_waypointsTtl));
    } else {
      debugPrint('[ETA] waypoints iz TTL cache: ${stopsFromSlot?.length ?? 0} stops');
    }

    debugPrint(
        '[ETA] stopsFromSlot=${stopsFromSlot == null ? 'NULL' : '${stopsFromSlot.length} stops'} (putnikUWaypointima=${stopsFromSlot?.any((s) => s.id == putnikId) ?? false})');

    if (stopsFromSlot != null) {
      final putnikJeUStops = stopsFromSlot.any((s) => s.id == putnikId);
      if (!putnikJeUStops) {
        debugPrint('[ETA] ❌ putnikId=$putnikId nije u waypoints_json');
        return null;
      }

      final etaResult = await _osrmRouteService.computeEtaForStopsFixedOrder(
        source: V3RouteCoordinate(latitude: vozacLok.lat, longitude: vozacLok.lng),
        stops: stopsFromSlot,
      );
      if (etaResult == null) {
        debugPrint('[ETA] ❌ OSRM computeEtaForStopsFixedOrder vratio null');
        return null;
      }
      final etaSeconds = etaResult.etaByWaypointId[putnikId];
      if (etaSeconds == null) {
        debugPrint(
            '[ETA] ❌ etaByWaypointId nema putnikId=$putnikId keys=${etaResult.etaByWaypointId.keys.take(3).join(',')}');
        return null;
      }
      debugPrint('[ETA] ✅ ETA: ${etaSeconds}s (${(etaSeconds / 60).ceil()} min) vozac=$vozacName');
      return V3EtaDolazakData(vozacIme: vozacName, etaSeconds: etaSeconds);
    }

    debugPrint('[ETA] ❌ stopsFromSlot null — vozač nije kliknuo START ili waypoints_json prazan');
    return null;
  }

  DateTime? _resolvePlannedDateTime(Map<String, dynamic> row, DateTime now) {
    final hhmm = _extractHhMm(row['polazak_at']) ?? _extractHhMm(row['vreme']);
    if (hhmm == null) return null;

    final parts = hhmm.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    final datumIso = V3DateUtils.parseIsoDatePart(row['datum']);
    DateTime? datumRef;
    if (datumIso.isNotEmpty) {
      datumRef = DateTime.tryParse(datumIso);
    }
    final base = datumRef ?? now;

    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  bool _isBetterEtaCandidate({
    required int? currentDeltaSeconds,
    required int? candidateDeltaSeconds,
  }) {
    if (candidateDeltaSeconds == null) return false;
    if (currentDeltaSeconds == null) return true;

    final candidateIsFuture = candidateDeltaSeconds >= 0;
    final currentIsFuture = currentDeltaSeconds >= 0;

    if (candidateIsFuture && !currentIsFuture) return true;
    if (!candidateIsFuture && currentIsFuture) return false;

    if (candidateIsFuture && currentIsFuture) {
      return candidateDeltaSeconds < currentDeltaSeconds;
    }

    return candidateDeltaSeconds > currentDeltaSeconds;
  }

  String? _extractHhMm(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;

    return V3TimeUtils.extractHHmmToken(value);
  }

  /// Dohvata poslednju lokaciju vozača direktno iz DB.
  /// Vraća null ako lokacija ne postoji ili je starija od 300s.
  Future<({double lat, double lng})?> _fetchVozacLokacija(String vozacId) async {
    final id = vozacId.trim();
    if (id.isEmpty) return null;

    try {
      final row = await supabase
          .from(_vozacLokacijeTable)
          .select('$_vozacLokacijeColVozacId, lat, lng, $_vozacLokacijeColUpdatedAt')
          .eq(_vozacLokacijeColVozacId, id)
          .order(_vozacLokacijeColUpdatedAt, ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;

      final rawAt = row[_vozacLokacijeColUpdatedAt];
      final parsedAt = DateTime.tryParse((rawAt ?? '').toString())?.toLocal();
      if (parsedAt == null) return null;

      final starostSekundi = DateTime.now().difference(parsedAt).inSeconds;
      if (starostSekundi > 300) return null;

      final lat = _parseDouble(row['lat']);
      final lng = _parseDouble(row['lng']);
      if (lat == null || lng == null) return null;

      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  /// Dohvata i parsira waypoints_json iz aktivnog slota za dati vozač/datum/grad/vreme.
  Future<List<V3RouteWaypoint>?> _fetchWaypointsJson(
    String vozacId,
    String datumIso,
    String grad,
    String vreme,
  ) async {
    try {
      final slotRow = await supabase
          .from(V3TrenutnaDodelaSlotService.tableName)
          .select(V3TrenutnaDodelaSlotService.colWaypointsJson)
          .eq(V3TrenutnaDodelaSlotService.colDatum, datumIso)
          .eq(V3TrenutnaDodelaSlotService.colGrad, grad)
          .eq(V3TrenutnaDodelaSlotService.colVreme, vreme)
          .eq(V3TrenutnaDodelaSlotService.colVozacId, vozacId)
          .eq(V3TrenutnaDodelaSlotService.colStatus, V3TrenutnaDodelaSlotService.statusAktivan)
          .maybeSingle();

      final rawWaypoints = slotRow?[V3TrenutnaDodelaSlotService.colWaypointsJson];
      debugPrint(
          '[ETA] fetchWaypointsJson: slotRow=${slotRow == null ? 'NULL' : 'found'} rawType=${rawWaypoints?.runtimeType}');

      if (rawWaypoints is! List) return null;

      final parsed = <V3RouteWaypoint>[];
      for (final item in rawWaypoints) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        final lat = _parseDouble(item['lat']);
        final lng = _parseDouble(item['lng']);
        if (id.isNotEmpty && lat != null && lng != null) {
          parsed.add(V3RouteWaypoint(id: id, label: id, coordinate: V3RouteCoordinate(latitude: lat, longitude: lng)));
        }
      }

      debugPrint('[ETA] fetchWaypointsJson: parsed ${parsed.length} waypoints');
      return parsed.isNotEmpty ? parsed : null;
    } catch (e) {
      debugPrint('[ETA] fetchWaypointsJson error: $e');
      return null;
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  String _resolveVozacName(String vozacId) {
    final rm = V3MasterRealtimeManager.instance;
    final fromVozaci = rm.vozaciCache[vozacId]?['ime_prezime']?.toString().trim();
    if (fromVozaci != null && fromVozaci.isNotEmpty) return fromVozaci;

    final fromAuth = rm.authCache[vozacId]?['ime']?.toString().trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    return 'Vozač';
  }
}
