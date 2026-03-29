import 'dart:async';

import 'package:flutter/material.dart';

import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_osrm_service.dart';
import '../services/v3/v3_vozac_lokacija_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_style_helper.dart';

class V3VozacStatusWidget extends StatefulWidget {
  final String putnikId;
  final String vozacId;
  final String vreme;
  final String grad;
  final DateTime datum;
  final String? adresaId;

  const V3VozacStatusWidget({
    super.key,
    required this.putnikId,
    required this.vozacId,
    required this.vreme,
    required this.grad,
    required this.datum,
    this.adresaId,
  });

  @override
  State<V3VozacStatusWidget> createState() => _V3VozacStatusWidgetState();
}

class _V3VozacStatusWidgetState extends State<V3VozacStatusWidget> {
  Timer? _refreshTimer;
  String? _etaVreme;

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
    if (oldWidget.vozacId != widget.vozacId || oldWidget.adresaId != widget.adresaId) {
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

  Future<void> _refreshEta() async {
    final adresa = V3AdresaService.getAdresaById(widget.adresaId);
    final lokacijaVozaca = V3VozacLokacijaService.getVozacLokacijaSync(widget.vozacId);

    if (adresa == null || !adresa.hasValidCoordinates || lokacijaVozaca == null) {
      if (mounted) setState(() => _etaVreme = null);
      return;
    }

    final vozacLat = _toDouble(lokacijaVozaca['lat']);
    final vozacLng = _toDouble(lokacijaVozaca['lng']);
    if (vozacLat == null || vozacLng == null) {
      if (mounted) setState(() => _etaVreme = null);
      return;
    }

    final durationMin = await V3OsrmService.getRouteDurationMinutes(
      originLat: vozacLat,
      originLng: vozacLng,
      destinationLat: adresa.gpsLat!,
      destinationLng: adresa.gpsLng!,
    );

    if (durationMin == null) {
      if (mounted) setState(() => _etaVreme = null);
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
