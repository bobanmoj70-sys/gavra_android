import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../services/v3/v3_eta_orchestrator_service.dart';
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
  final V3EtaOrchestratorService _etaOrchestratorService = V3EtaOrchestratorService();

  RealtimeChannel? _realtimeChannel;
  Timer? _refreshTimer;
  V3EtaDolazakData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _bindRealtime();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
      final data = await _etaOrchestratorService.loadEtaForPutnik(widget.putnikId);
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
