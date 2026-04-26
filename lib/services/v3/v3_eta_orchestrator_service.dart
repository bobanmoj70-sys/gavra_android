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

    if (assignments.isEmpty) return null;

    final activeVozacBySlotKey = await V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey();

    final terminIds = assignments.map((e) => e.terminId).toList(growable: false);
    final operativnaRows = await supabase
        .from('v3_operativna_nedelja')
        .select('id, datum, grad, polazak_at, adresa_override_id, koristi_sekundarnu, created_by')
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
      return null;
    }

    final vozacLok = await _getLatestVozacLokacija(selectedVozacId);
    if (vozacLok == null) return null;

    final vozacName = _resolveVozacName(selectedVozacId);
    final putnikCoord = await _resolvePutnikCoordinate(
      putnikId: putnikId,
      row: selectedRow,
    );
    if (putnikCoord == null) return null;

    final selectedTerminId = (selectedRow['id'] ?? '').toString().trim();
    if (selectedTerminId.isEmpty) return null;

    final terminDodelaRows = await supabase
        .from('v3_trenutna_dodela')
        .select('putnik_v3_auth_id')
        .eq('termin_id', selectedTerminId)
        .eq('vozac_v3_auth_id', selectedVozacId)
        .eq('status', 'aktivan');

    final stops = <V3RouteWaypoint>[];
    final addedPutnikIds = <String>{};

    for (final raw in (terminDodelaRows as List<dynamic>)) {
      if (raw is! Map<String, dynamic>) continue;

      final stopPutnikId = (raw['putnik_v3_auth_id'] ?? '').toString().trim();
      if (stopPutnikId.isEmpty || addedPutnikIds.contains(stopPutnikId)) continue;

      final stopCoord = stopPutnikId == putnikId
          ? putnikCoord
          : await _resolvePutnikCoordinate(
              putnikId: stopPutnikId,
              row: selectedRow,
            );
      if (stopCoord == null) continue;

      stops.add(
        V3RouteWaypoint(
          id: stopPutnikId,
          label: stopPutnikId,
          coordinate: stopCoord,
        ),
      );
      addedPutnikIds.add(stopPutnikId);
    }

    if (!addedPutnikIds.contains(putnikId)) {
      stops.add(
        V3RouteWaypoint(
          id: putnikId,
          label: putnikId,
          coordinate: putnikCoord,
        ),
      );
    }
    if (stops.isEmpty) return null;

    final etaResult = await _osrmRouteService.computeEtaForStopsFromSource(
      source: V3RouteCoordinate(latitude: vozacLok.lat, longitude: vozacLok.lng),
      stops: stops,
    );
    if (etaResult == null) return null;

    final etaSeconds = etaResult.etaByWaypointId[putnikId];
    if (etaSeconds == null) return null;

    return V3EtaDolazakData(
      vozacIme: vozacName,
      etaSeconds: etaSeconds,
    );
  }

  Future<V3RouteCoordinate?> _resolvePutnikCoordinate({
    required String putnikId,
    required Map<String, dynamic> row,
  }) async {
    final grad = (row['grad'] ?? '').toString().trim().toUpperCase();
    if (grad.isEmpty) return null;

    final adresaIdOverride = (row['adresa_override_id'] ?? '').toString().trim();
    final koristiSekundarnu = (row['koristi_sekundarnu'] as bool?) ?? false;
    return _routeWaypointResolverService.resolveCoordinateForPutnikFromAuth(
      putnikId: putnikId,
      grad: grad,
      koristiSekundarnu: koristiSekundarnu,
      adresaIdOverride: adresaIdOverride,
    );
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
      if (starostSekundi > 90) return null;

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
