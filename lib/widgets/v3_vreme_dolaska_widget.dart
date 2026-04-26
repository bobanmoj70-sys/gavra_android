import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_address_coordinate_service.dart';
import '../services/v3/v3_adresa_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';
import '../utils/v3_time_utils.dart';

class V3VremeDolaskaWidget extends StatefulWidget {
  const V3VremeDolaskaWidget({
    super.key,
    required this.putnikId,
  });

  final String putnikId;

  @override
  State<V3VremeDolaskaWidget> createState() => _V3VremeDolaskaWidgetState();
}

class _V3VremeDolaskaWidgetState extends State<V3VremeDolaskaWidget> {
  static const String _vozacLokacijeTable = 'v3_vozac_lokacije';
  static const String _vozacLokacijeColVozacId = 'created_by';
  static const String _vozacLokacijeColUpdatedAt = 'updated_at';

  final V3AddressCoordinateService _addressCoordinateService = V3AddressCoordinateService();

  RealtimeChannel? _realtimeChannel;
  _V3DolazakData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _bindRealtime();
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
    super.dispose();
  }

  void _bindRealtime() {
    final existing = _realtimeChannel;
    if (existing != null) {
      unawaited(supabase.removeChannel(existing));
      _realtimeChannel = null;
    }

    final channel = supabase.channel(
      'v3_eta_dolazak_${widget.putnikId}_${DateTime.now().microsecondsSinceEpoch}',
    );

    for (final table in const <String>[
      'v3_trenutna_dodela',
      'v3_trenutna_dodela_slot',
      'v3_vozac_lokacije',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          if (!mounted) return;
          unawaited(_reload());
        },
      );
    }

    _realtimeChannel = channel;
    channel.subscribe();
  }

  Future<void> _reload() async {
    if (!mounted) return;

    try {
      final data = await _loadData();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _loading = false;
      });
    }
  }

  Future<_V3DolazakData?> _loadData() async {
    final putnikId = widget.putnikId.trim();
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

    final vozacIds = assignments.map((e) => e.vozacId).toSet().toList(growable: false);
    final activeSlotKeys = await _loadActiveSlotKeys(vozacIds);

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
      final candidateSlotKey = _buildSlotKeyFromOperativnaRow(row, vozacId: assignment.vozacId);
      final candidateMatchesStartedSlot = candidateSlotKey.isNotEmpty && activeSlotKeys.contains(candidateSlotKey);
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
    final grad = (selectedRow['grad'] ?? '').toString().toUpperCase();

    // OSRM ETA od vozačeve lokacije do putnikove adrese
    final rm = V3MasterRealtimeManager.instance;

    // Prio 1: adresa_override_id iz operativne nedelje
    final adresaIdOverride = (selectedRow['adresa_override_id'] ?? '').toString().trim();
    final koristiSekundarnu = (selectedRow['koristi_sekundarnu'] as bool?) ?? false;

    final String? adresaId;
    if (adresaIdOverride.isNotEmpty) {
      adresaId = adresaIdOverride;
    } else {
      // Prio 2: putnikova primarna/sekundarna adresa iz authCache
      final authRow = rm.authCache[putnikId];
      if (grad == 'BC') {
        final bc1 = authRow?['adresa_primary_bc_id']?.toString();
        final bc2 = authRow?['adresa_secondary_bc_id']?.toString();
        adresaId = koristiSekundarnu ? (bc2?.isNotEmpty == true ? bc2 : bc1) : (bc1?.isNotEmpty == true ? bc1 : bc2);
      } else {
        final vs1 = authRow?['adresa_primary_vs_id']?.toString();
        final vs2 = authRow?['adresa_secondary_vs_id']?.toString();
        adresaId = koristiSekundarnu ? (vs2?.isNotEmpty == true ? vs2 : vs1) : (vs1?.isNotEmpty == true ? vs1 : vs2);
      }
    }

    if (adresaId == null || adresaId.isEmpty) return null;

    final adresaNaziv = V3AdresaService.getAdresaById(adresaId)?.naziv ?? '';
    final gradLabel = grad == 'BC' ? 'Bela Crkva' : 'Vrsac';
    final fallbackQuery = adresaNaziv.isNotEmpty ? '$adresaNaziv, $gradLabel, Srbija' : '';
    if (fallbackQuery.isEmpty) return null;

    final putnikCoord = await _addressCoordinateService.resolveCoordinate(
      adresaId: adresaId,
      fallbackQuery: fallbackQuery,
    );
    if (putnikCoord == null) return null;

    final etaSeconds = await _fetchOsrmDurationSeconds(
      fromLat: vozacLok.lat,
      fromLng: vozacLok.lng,
      toLat: putnikCoord.latitude,
      toLng: putnikCoord.longitude,
    );
    if (etaSeconds == null) return null;

    return _V3DolazakData(
      vozacIme: vozacName,
      etaSeconds: etaSeconds,
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

    final datumIso = _parseIsoDatePart(row['datum']);
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

  Future<Set<String>> _loadActiveSlotKeys(List<String> vozacIds) async {
    if (vozacIds.isEmpty) return const <String>{};

    final rows = await supabase
        .from('v3_trenutna_dodela_slot')
        .select('datum, grad, vreme, vozac_v3_auth_id')
        .eq('status', 'aktivan')
        .inFilter('vozac_v3_auth_id', vozacIds);

    final activeKeys = <String>{};

    for (final raw in (rows as List<dynamic>)) {
      if (raw is! Map<String, dynamic>) continue;
      final row = raw;
      final slotKey = _buildSlotKeyFromSlotRow(row, vozacId: row['vozac_v3_auth_id']?.toString());
      if (slotKey.isEmpty) continue;
      activeKeys.add(slotKey);
    }

    return activeKeys;
  }

  String _buildSlotKeyFromOperativnaRow(Map<String, dynamic> row, {String? vozacId}) {
    final datum = _parseIsoDatePart(row['datum']);
    final grad = (row['grad'] ?? '').toString().trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(row['polazak_at']?.toString() ?? row['vreme']?.toString() ?? '');
    final vozac = (vozacId ?? '').trim();
    if (datum.isEmpty || grad.isEmpty || vreme.isEmpty || vozac.isEmpty) return '';
    return '$datum|$grad|$vreme|$vozac';
  }

  String _buildSlotKeyFromSlotRow(Map<String, dynamic> row, {String? vozacId}) {
    final datum = _parseIsoDatePart(row['datum']);
    final grad = (row['grad'] ?? '').toString().trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(row['vreme']?.toString() ?? '');
    final vozac = (vozacId ?? row['vozac_v3_auth_id']?.toString() ?? '').trim();
    if (datum.isEmpty || grad.isEmpty || vreme.isEmpty || vozac.isEmpty) return '';
    return '$datum|$grad|$vreme|$vozac';
  }

  String _parseIsoDatePart(dynamic raw) {
    final value = (raw ?? '').toString().trim();
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

      final lat = _parseDouble(row['lat']);
      final lng = _parseDouble(row['lng']);
      if (lat == null || lng == null) return null;

      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _fetchOsrmDurationSeconds({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    try {
      final baseUrl = dotenv.maybeGet('OSRM_BASE_URL')?.trim() ?? 'https://router.project-osrm.org';
      final coords = '$fromLng,$fromLat;$toLng,$toLat';
      final uri = Uri.parse('$baseUrl/route/v1/driving/$coords').replace(
        queryParameters: {'overview': 'false', 'steps': 'false'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if ((decoded['code']?.toString() ?? '') != 'Ok') return null;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final duration = routes.first['duration'];
      if (duration == null) return null;
      return (duration as num).toInt();
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

  int _buildEtaMinutes(int etaSeconds) {
    if (etaSeconds <= 0) return 0;
    return (etaSeconds / 60).ceil();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return V3ContainerUtils.styledContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: V3StyleHelper.whiteAlpha06,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V3StyleHelper.whiteAlpha13),
        child: const Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(12),
      backgroundColor: Colors.green.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.8), width: 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '🚐 Procenjeno vreme dolaska',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_buildEtaMinutes(data.etaSeconds)} min',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '👤 ${data.vozacIme}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha9,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _V3DolazakData {
  const _V3DolazakData({
    required this.vozacIme,
    required this.etaSeconds,
  });

  final String vozacIme;
  final int etaSeconds;
}
