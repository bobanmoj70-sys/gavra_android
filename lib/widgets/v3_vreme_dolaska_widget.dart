import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../utils/v3_container_utils.dart';

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
  static const String _tableName = 'v3_eta_results';
  static const String _colPutnikId = 'putnik_id';
  static const String _colVozacId = 'vozac_id';
  static const String _colEtaSeconds = 'eta_seconds';
  static const String _colComputedAt = 'computed_at';

  // ETA se smatra zastarelom ako je starija od 2 sata
  static const Duration _staleThreshold = Duration(hours: 2);

  RealtimeChannel? _realtimeChannel;
  Timer? _pollTimer;
  int _realtimeReconnectAttempts = 0;
  int? _etaSeconds;
  bool _isStale = false;
  String? _vozacId;

  @override
  void initState() {
    super.initState();
    _reload();
    _bindRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  void _bindRealtime() {
    final existing = _realtimeChannel;
    if (existing != null) {
      unawaited(Supabase.instance.client.removeChannel(existing));
      _realtimeChannel = null;
    }

    final channel = Supabase.instance.client.channel(
      'v3_eta_dolazak_${widget.putnikId}',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _tableName,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: _colPutnikId,
        value: widget.putnikId,
      ),
      callback: (payload) {
        if (!mounted) return;
        final newRow = payload.newRecord;
        if (newRow.isNotEmpty) {
          _applyRow(newRow);
        } else {
          // DELETE event
          if (mounted) setState(() => _etaSeconds = null);
        }
      },
    );

    _realtimeChannel = channel;
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _realtimeReconnectAttempts = 0;
      }
      if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[V3VremeDolaskaWidget] realtime $status: $error');
        if (mounted) {
          _realtimeReconnectAttempts += 1;
          final capped = _realtimeReconnectAttempts.clamp(1, 5);
          final delayMs = 500 * (1 << capped);
          Future<void>.delayed(Duration(milliseconds: delayMs), () {
            if (mounted) {
              _reload();
              _bindRealtime();
            }
          });
        }
      }
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    try {
      debugPrint('[ETA_WIDGET] _reload for putnikId=${widget.putnikId}');
      final rows = await Supabase.instance.client
          .from(_tableName)
          .select('$_colEtaSeconds, $_colComputedAt, $_colVozacId')
          .eq(_colPutnikId, widget.putnikId)
          .limit(1);

      if (!mounted) return;

      debugPrint('[ETA_WIDGET] _reload rows.length=${rows.length} rows=$rows');
      if (rows.isNotEmpty) {
        _applyRow(rows.first);
      } else {
        setState(() => _etaSeconds = null);
      }
    } catch (e) {
      debugPrint('[ETA_WIDGET] _reload error: $e');
      if (mounted) setState(() => _etaSeconds = null);
    }
  }

  void _applyRow(Map<String, dynamic> row) {
    final eta = (row[_colEtaSeconds] as num?)?.toInt();
    final computedAtRaw = row[_colComputedAt];
    final computedAt = computedAtRaw is String ? DateTime.tryParse(computedAtRaw) : null;
    final stale = computedAt == null || DateTime.now().difference(computedAt) > _staleThreshold;
    final vozacId = row[_colVozacId]?.toString();
    debugPrint('[ETA_WIDGET] _applyRow eta=$eta computedAt=$computedAt stale=$stale vozacId=$vozacId');

    if (mounted) {
      setState(() {
        _etaSeconds = eta;
        _isStale = stale;
        _vozacId = vozacId;
      });
    }
  }

  int _buildEtaMinutes(int etaSeconds) {
    if (etaSeconds <= 0) return 0;
    return (etaSeconds / 60).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final eta = _etaSeconds;
    debugPrint('[ETA_WIDGET] build: eta=$eta isStale=$_isStale putnikId=${widget.putnikId}');
    if (eta == null || _isStale) return const SizedBox.shrink();

    final minutes = _buildEtaMinutes(eta);

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
            minutes <= 0 ? 'Stiže uskoro' : 'za $minutes min',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (_vozacId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Vozač: ${V3MasterRealtimeManager.instance.vozaciCache[_vozacId]?['ime_prezime'] ?? _vozacId}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
