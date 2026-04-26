import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

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
  static const Duration _refreshInterval = Duration(seconds: 30);
  static const Duration _driverStartSignalWindow = Duration(minutes: 5);

  Timer? _timer;
  _V3DolazakData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(_refreshInterval, (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
        .select('termin_id, vozac_v3_auth_id, status')
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

    final terminIds = assignments.map((e) => e.terminId).toList(growable: false);
    final operativnaRows = await supabase
        .from('v3_operativna_nedelja')
        .select('id, datum, grad, vreme, polazak_at')
        .inFilter('id', terminIds);

    Map<String, dynamic>? selectedRow;
    String selectedVozacId = '';
    DateTime? selectedPlanned;

    for (final raw in (operativnaRows as List<dynamic>)) {
      if (raw is! Map<String, dynamic>) continue;
      final row = raw;

      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      final assignment = assignments.where((a) => a.terminId == id).firstOrNull;
      if (assignment == null) continue;
      final datum = _parseDateOnly(row['datum']);
      final planned = datum == null ? null : _resolvePlannedDateTime(row, datum);

      if (selectedRow == null) {
        selectedRow = row;
        selectedVozacId = assignment.vozacId;
        selectedPlanned = planned;
        continue;
      }

      if (planned != null && (selectedPlanned == null || planned.isBefore(selectedPlanned))) {
        selectedRow = row;
        selectedVozacId = assignment.vozacId;
        selectedPlanned = planned;
      }
    }

    if (selectedRow == null || selectedVozacId.isEmpty) {
      return null;
    }

    final hasDriverStartSignal = await _hasRecentDriverLocationSignal(selectedVozacId);
    if (!hasDriverStartSignal) return null;

    final vozacName = _resolveVozacName(selectedVozacId);
    final grad = (selectedRow['grad'] ?? '').toString().toUpperCase();

    return _V3DolazakData(
      vozacId: selectedVozacId,
      vozacIme: vozacName,
      grad: grad,
      plannedAt: selectedPlanned ?? DateTime.now(),
    );
  }

  DateTime? _parseDateOnly(dynamic raw) {
    final parsed = DateTime.tryParse((raw ?? '').toString());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime? _resolvePlannedDateTime(Map<String, dynamic> row, DateTime date) {
    final hhmm = _extractHhMm(row['polazak_at']) ?? _extractHhMm(row['vreme']);
    if (hhmm == null) return null;

    final parts = hhmm.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  String? _extractHhMm(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;

    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
      return value;
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;

    final h = parsed.hour.toString().padLeft(2, '0');
    final m = parsed.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<bool> _hasRecentDriverLocationSignal(String vozacId) async {
    final id = vozacId.trim();
    if (id.isEmpty) return false;

    final tableCandidates = <String>[
      'v3_vozac_lokacije',
      'vozac_lokacije',
    ];

    final columnCandidates = <Map<String, String>>[
      {'vozacId': 'created_by', 'at': 'updated_at'},
      {'vozacId': 'vozac_id', 'at': 'recorded_at'},
      {'vozacId': 'vozac_id', 'at': 'updated_at'},
      {'vozacId': 'driver_id', 'at': 'recorded_at'},
      {'vozacId': 'vozac', 'at': 'recorded_at'},
      {'vozacId': 'created_by', 'at': 'recorded_at'},
    ];

    for (final table in tableCandidates) {
      for (final cols in columnCandidates) {
        try {
          final row = await supabase
              .from(table)
              .select('${cols['vozacId']}, ${cols['at']}')
              .eq(cols['vozacId']!, id)
              .order(cols['at']!, ascending: false)
              .limit(1)
              .maybeSingle();

          if (row == null) continue;

          final rawAt = row[cols['at']];
          final parsedAt = DateTime.tryParse((rawAt ?? '').toString())?.toLocal();
          if (parsedAt == null) continue;

          final age = DateTime.now().difference(parsedAt);
          if (age <= _driverStartSignalWindow) return true;
        } catch (_) {
          continue;
        }
      }
    }

    return false;
  }

  String _resolveVozacName(String vozacId) {
    final rm = V3MasterRealtimeManager.instance;
    final fromVozaci = rm.vozaciCache[vozacId]?['ime_prezime']?.toString().trim();
    if (fromVozaci != null && fromVozaci.isNotEmpty) return fromVozaci;

    final fromAuth = rm.authCache[vozacId]?['ime']?.toString().trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    return 'Vozač';
  }

  int _buildEtaMinutes(DateTime plannedAt) {
    final now = DateTime.now();
    final diff = plannedAt.difference(now);
    if (diff.inMinutes < 0) return 0;
    return diff.inMinutes;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'procenjeno vreme dolaska prevoza',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_buildEtaMinutes(data.plannedAt)}',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha9,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'vozac ${data.vozacIme} (${data.vozacId})',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha9,
              fontSize: 12,
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
    required this.vozacId,
    required this.vozacIme,
    required this.grad,
    required this.plannedAt,
  });

  final String vozacId;
  final String vozacIme;
  final String grad;
  final DateTime plannedAt;
}
