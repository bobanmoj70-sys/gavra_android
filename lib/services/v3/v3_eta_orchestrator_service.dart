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

class V3EtaOrchestratorService {
  V3EtaOrchestratorService({
    V3RouteWaypointResolverService? routeWaypointResolverService,
    V3OsrmRouteService? osrmRouteService,
  })  : _routeWaypointResolverService = routeWaypointResolverService ?? V3RouteWaypointResolverService(),
        _osrmRouteService = osrmRouteService ?? V3OsrmRouteService();

  static const String _vozacLokacijeTable = 'v3_vozac_lokacije';
  static const String _vozacLokacijeColVozacId = 'created_by';
  static const String _vozacLokacijeColUpdatedAt = 'updated_at';

  final V3RouteWaypointResolverService _routeWaypointResolverService;
  final V3OsrmRouteService _osrmRouteService;

  Future<V3EtaDolazakData?> loadEtaForPutnik(String rawPutnikId) async {
    final putnikId = rawPutnikId.trim();
    if (putnikId.isEmpty) return null;

    debugPrint('[ETA] loadEtaForPutnik START putnikId=$putnikId');

    final dodelaRows = await supabase
        .from('v3_trenutna_dodela')
        .select('termin_id, vozac_v3_auth_id')
        .eq('putnik_v3_auth_id', putnikId)
        .eq('status', 'aktivan');

    final assignments = (dodelaRows as List<dynamic>)
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

    final activeVozacBySlotKey = await V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey();
    debugPrint('[ETA] aktivni slotovi(${activeVozacBySlotKey.length}): ${activeVozacBySlotKey.keys.join(', ')}');

    final terminIds = assignments.map((e) => e.terminId).toList(growable: false);
    final operativnaRows = await supabase
        .from('v3_operativna_nedelja')
        .select('id, datum, grad, polazak_at, adresa_override_id, koristi_sekundarnu, created_by, pokupljen_at')
        .inFilter('id', terminIds);

    Map<String, dynamic>? selectedRow;
    String selectedVozacId = '';
    int? selectedDeltaSeconds;
    final now = DateTime.now();

    for (final raw in (operativnaRows as List<dynamic>)) {
      if (raw is! Map<String, dynamic>) continue;
      final row = raw;

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

    final vozacLok = await _getLatestVozacLokacija(selectedVozacId);
    if (vozacLok == null) {
      debugPrint('[ETA] ❌ vozac lokacija null ili stale (>300s) za vozacId=${selectedVozacId.substring(0, 8)}');
      return null;
    }
    debugPrint('[ETA] vozac lokacija: lat=${vozacLok.lat} lng=${vozacLok.lng}');

    final vozacName = _resolveVozacName(selectedVozacId);

    final selectedDatum = V3DateUtils.parseIsoDatePart(selectedRow['datum']);
    final selectedGrad = (selectedRow['grad'] ?? '').toString().trim().toUpperCase();
    final selectedVreme = selectedRow['polazak_at']?.toString() ?? '';
    debugPrint(
        '[ETA] tražim slot: datum=$selectedDatum grad=$selectedGrad vreme=$selectedVreme vozacId=${selectedVozacId.substring(0, 8)}');

    // Pokušaj da učitaš waypoints iz slota (upisuje ih vozač pri optimizaciji)
    final slotRow = await supabase
        .from(V3TrenutnaDodelaSlotService.tableName)
        .select(V3TrenutnaDodelaSlotService.colWaypointsJson)
        .eq(V3TrenutnaDodelaSlotService.colDatum, selectedDatum)
        .eq(V3TrenutnaDodelaSlotService.colGrad, selectedGrad)
        .eq(V3TrenutnaDodelaSlotService.colVreme, selectedVreme)
        .eq(V3TrenutnaDodelaSlotService.colVozacId, selectedVozacId)
        .eq(V3TrenutnaDodelaSlotService.colStatus, V3TrenutnaDodelaSlotService.statusAktivan)
        .maybeSingle();

    final rawWaypoints = slotRow?[V3TrenutnaDodelaSlotService.colWaypointsJson];
    debugPrint(
        '[ETA] slotRow=${slotRow == null ? 'NULL' : 'found'} rawWaypoints type=${rawWaypoints?.runtimeType} isList=${rawWaypoints is List}');

    List<V3RouteWaypoint>? stopsFromSlot;
    if (rawWaypoints is List) {
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
      if (parsed.isNotEmpty) stopsFromSlot = parsed;
      debugPrint(
          '[ETA] parsed waypoints: ${parsed.length} (putnikUWaypointima=${parsed.any((s) => s.id == putnikId)})');
    }

    // Ako slot ima sačuvane waypoints od poslednje optimizacije — koristi ih direktno
    // Koristimo /route API (fiksni redosled) jer je waypoints_json već optimizovan
    // Destinacija (__destination__) ostaje u listi da OSRM zna pravi smer, ali se ETA ne traži za nju
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

    // Nema waypoints_json — vozač nije kliknuo START ili još nije optimizovao rutu
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

  Future<({double lat, double lng})?> _getLatestVozacLokacija(String vozacId) async {
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
