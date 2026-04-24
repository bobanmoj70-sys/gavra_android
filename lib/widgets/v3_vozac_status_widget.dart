import 'dart:async';

import 'package:flutter/material.dart';

import '../services/v3/v3_osrm_service.dart';
import '../services/v3/v3_vozac_lokacija_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_style_helper.dart';

class V3VozacStatusWidget extends StatefulWidget {
  final String vozacId;

  /// Sve stanice aktivnog termina koje ulaze u optimizaciju.
  final List<V3OsrmStop> termStops;

  /// ID stopa (putnik id) za koji prikazujemo ETA.
  final String targetStopId;

  const V3VozacStatusWidget({
    super.key,
    required this.vozacId,
    required this.termStops,
    required this.targetStopId,
  });

  @override
  State<V3VozacStatusWidget> createState() => _V3VozacStatusWidgetState();
}

class _V3VozacStatusWidgetState extends State<V3VozacStatusWidget> {
  Timer? _refreshTimer;
  String? _etaVreme;
  int _etaRequestId = 0;

  @override
  void initState() {
    super.initState();
    _refreshEta();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshEta();
    });
  }

  @override
  void didUpdateWidget(covariant V3VozacStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vozacId != widget.vozacId ||
        oldWidget.targetStopId != widget.targetStopId ||
        !_sameStops(oldWidget.termStops, widget.termStops)) {
      _refreshEta();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  bool _sameStops(
    List<V3OsrmStop> a,
    List<V3OsrmStop> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].lat != b[i].lat || a[i].lng != b[i].lng) {
        return false;
      }
    }
    return true;
  }

  Future<void> _refreshEta() async {
    final requestId = ++_etaRequestId;

    if (widget.termStops.isEmpty) {
      if (mounted && requestId == _etaRequestId) setState(() => _etaVreme = null);
      return;
    }

    final lokacijaVozaca = V3VozacLokacijaService.getVozacLokacijaSync(widget.vozacId, onlyActive: true);
    if (lokacijaVozaca == null) {
      if (mounted && requestId == _etaRequestId) setState(() => _etaVreme = null);
      return;
    }

    final vozacLat = _toDouble(lokacijaVozaca['lat']);
    final vozacLng = _toDouble(lokacijaVozaca['lng']);
    if (vozacLat == null || vozacLng == null) {
      if (mounted && requestId == _etaRequestId) setState(() => _etaVreme = null);
      return;
    }

    V3OsrmStop? targetStop;
    for (final stop in widget.termStops) {
      if (stop.id == widget.targetStopId) {
        targetStop = stop;
        break;
      }
    }
    if (targetStop == null) {
      if (mounted && requestId == _etaRequestId) {
        setState(() => _etaVreme = null);
      }
      return;
    }

    final optimizedIds = await V3OsrmService.optimizeStopOrderByDuration(
      originLat: vozacLat,
      originLng: vozacLng,
      stops: widget.termStops,
    );

    if (requestId != _etaRequestId) return;

    int? durationMin;
    if (optimizedIds != null && optimizedIds.isNotEmpty) {
      final stopById = {for (final stop in widget.termStops) stop.id: stop};
      final optimizedStops = optimizedIds.map((id) => stopById[id]).whereType<V3OsrmStop>().toList(growable: false);

      final etaByStopId = await V3OsrmService.getEtaMinutesForOrderedStops(
        originLat: vozacLat,
        originLng: vozacLng,
        orderedStops: optimizedStops,
      );
      if (etaByStopId != null) {
        durationMin = etaByStopId[widget.targetStopId];
      }
    }

    durationMin ??= await V3OsrmService.getEtaMinutes(
      waypoints: [
        (lat: vozacLat, lng: vozacLng),
        (lat: targetStop.lat, lng: targetStop.lng),
      ],
    );

    if (requestId != _etaRequestId) return;

    if (durationMin == null) {
      if (mounted && requestId == _etaRequestId) setState(() => _etaVreme = null);
      return;
    }

    final eta = DateTime.now().add(Duration(minutes: durationMin));
    if (mounted) {
      setState(() {
        _etaVreme = V3DanHelper.formatVreme(eta.hour, eta.minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prikazVreme = _etaVreme ?? '—';

    return V3ContainerUtils.styledContainer(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: V3StyleHelper.radius16,
      backgroundColor: V3StyleHelper.whiteAlpha06,
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Procenjeno vreme dolaska',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha75,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            prikazVreme,
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha9,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
