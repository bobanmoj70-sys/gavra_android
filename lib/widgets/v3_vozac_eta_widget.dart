import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_stream_utils.dart';

/// Widget za praćenje dolaska vozača u real-time.
/// Prikazuje ETA countdown i status vožnje za putnika.
///
/// AKTIVACIJA: 15 min pre planiranog polaska do završetka vožnje
/// TEHNOLOGIJA: Koristi postojeći GPS stream, Haversine ETA kalkulacija
class V3VozacEtaWidget extends StatefulWidget {
  final String putnikId;
  final String vozacId;
  final String vreme;
  final String grad;
  final DateTime datum;

  const V3VozacEtaWidget({
    super.key,
    required this.putnikId,
    required this.vozacId,
    required this.vreme,
    required this.grad,
    required this.datum,
  });

  @override
  State<V3VozacEtaWidget> createState() => _V3VozacEtaWidgetState();
}

class _V3VozacEtaWidgetState extends State<V3VozacEtaWidget> {
  // ETA подaci
  int? _etaMinutes;
  String _status = 'Priprema se...';
  bool _isVisible = false;
  double _effectiveSpeedKmh = 40.0;

  // Cache
  V3Vozac? _vozac;
  V3Putnik? _putnik;
  V3Adresa? _putnikAdresa;
  Map<String, dynamic>? _vozacLokacija;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _checkVisibility();
    _startTracking();
  }

  @override
  void dispose() {
    V3StreamUtils.cancelSubscription('vozac_eta_location_for_putnik');
    super.dispose();
  }

  Future<void> _initializeData() async {
    // Učitaj vozač podatke
    _vozac = V3VozacService.getVozacById(widget.vozacId);

    // Učitaj putnik podatke iz cache-a
    final rm = V3MasterRealtimeManager.instance;
    final putnikData = rm.putniciCache[widget.putnikId];
    if (putnikData != null) {
      _putnik = V3Putnik.fromJson(putnikData);

      // Određi adresu na osnovu grada
      final adresaId = widget.grad.toUpperCase() == 'BC'
          ? (_putnik!.adresaBcId ?? _putnik!.adresaBcId2)
          : (_putnik!.adresaVsId ?? _putnik!.adresaVsId2);

      if (adresaId != null) {
        _putnikAdresa = V3AdresaService.getAdresaById(adresaId);
      }
    }

    V3StateUtils.safeSetState(this, () {});
  }

  void _checkVisibility() {
    final now = DateTime.now();
    final polazakVreme = _parsePolazakVreme();

    if (polazakVreme == null) {
      _isVisible = false;
      return;
    }

    // Vidljiv 15 min pre polaska do 2 sata nakon polaska
    final showFrom = polazakVreme.subtract(const Duration(minutes: 15));
    final showUntil = polazakVreme.add(const Duration(hours: 2));

    _isVisible = now.isAfter(showFrom) && now.isBefore(showUntil);
  }

  DateTime? _parsePolazakVreme() {
    try {
      final parts = widget.vreme.split(':');
      if (parts.length < 2) return null;

      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      return DateTime(
        widget.datum.year,
        widget.datum.month,
        widget.datum.day,
        hour,
        minute,
      );
    } catch (e) {
      return null;
    }
  }

  void _startTracking() {
    // Real-time subscription na vozačevu lokaciju
    V3StreamUtils.subscribe<void>(
        key: 'vozac_eta_location_for_putnik',
        stream: V3MasterRealtimeManager.instance.onChange,
        onData: (_) {
          _checkVisibility();
          _updateVozacLokacija();
          V3StateUtils.safeSetState(this, () {});
        });

    // Initial update
    _updateVozacLokacija();
    V3StateUtils.safeSetState(this, () {});
  }

  void _updateVozacLokacija() {
    final rm = V3MasterRealtimeManager.instance;

    // Pronađi najnoviju lokaciju vozača
    final locations = rm.vozacLokacijeCache.values.where((loc) => loc['vozac_id'] == widget.vozacId).toList();

    if (locations.isNotEmpty) {
      // Sortiraj po timestamp-u i uzmi najnoviju
      locations.sort((a, b) {
        final tsA = a['updated_at'] as String? ?? '';
        final tsB = b['updated_at'] as String? ?? '';
        return tsB.compareTo(tsA);
      });

      _vozacLokacija = locations.first;
      _updateETA();
    }
  }

  void _updateETA() {
    if (_vozacLokacija == null || _putnikAdresa == null || !_putnikAdresa!.hasValidCoordinates) {
      _status = 'GPS nedostupan';
      _etaMinutes = null;
      return;
    }

    final vozacLat = (_vozacLokacija!['lat'] as num?)?.toDouble();
    final vozacLng = (_vozacLokacija!['lng'] as num?)?.toDouble();

    if (vozacLat == null || vozacLng == null) {
      _status = 'Lokacija nedostupna';
      _etaMinutes = null;
      return;
    }

    // Haversine formula za udaljenost
    final distance = _calculateDistance(
      vozacLat,
      vozacLng,
      _putnikAdresa!.gpsLat!,
      _putnikAdresa!.gpsLng!,
    );

    if (distance < 0.1) {
      _etaMinutes = 0;
      _status = 'Vozač je stigao!';
      return;
    }

    // Dinamička ETA kalkulacija (koristi realnu brzinu vozača kada je dostupna)
    final averageSpeedKmh = _resolveEtaSpeedKmh();
    final etaHours = distance / averageSpeedKmh;
    final etaRawMinutes = (etaHours * 60).round();
    _etaMinutes = etaRawMinutes < 0 ? 0 : (etaRawMinutes > (24 * 60) ? 24 * 60 : etaRawMinutes);

    // Status na osnovu udaljenosti
    if (distance < 0.5) {
      // < 500m
      _status = 'Vozač je blizu';
    } else if (_etaMinutes! <= 2) {
      _status = 'Vozač stiže uskoro';
    } else {
      _status = 'Vozač je na putu';
    }
  }

  double _resolveEtaSpeedKmh() {
    final rawSpeed = (_vozacLokacija?['brzina'] as num?)?.toDouble();
    if (rawSpeed == null) {
      return _effectiveSpeedKmh;
    }

    if (rawSpeed >= 3 && rawSpeed <= 160) {
      final clamped = rawSpeed < 12 ? 12.0 : (rawSpeed > 70 ? 70.0 : rawSpeed);
      _effectiveSpeedKmh = clamped;
      return _effectiveSpeedKmh;
    }

    // Ako vozač trenutno stoji (semafor/stajanje), zadrži poslednju stabilnu brzinu.
    if (rawSpeed >= 0 && rawSpeed < 3) {
      return _effectiveSpeedKmh;
    }

    return _effectiveSpeedKmh;
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  String _formatETA() {
    if (_etaMinutes == null) return '';

    if (_etaMinutes! < 1) {
      return 'stiže sada';
    } else if (_etaMinutes! < 60) {
      return 'stiže za ${_etaMinutes}min';
    } else {
      final hours = _etaMinutes! ~/ 60;
      final mins = _etaMinutes! % 60;
      return mins > 0 ? 'stiže za ${hours}h ${mins}min' : 'stiže za ${hours}h';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible || _vozac == null) {
      return const SizedBox.shrink();
    }

    final vozacColor = _vozac!.boja != null ? Color(int.tryParse(_vozac!.boja!) ?? 0xFF2196F3) : Colors.blue;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            vozacColor.withValues(alpha: 0.1),
            vozacColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: vozacColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header sa ikonom i vozač info
          Row(
            children: [
              V3ContainerUtils.styledContainer(
                padding: const EdgeInsets.all(8),
                backgroundColor: vozacColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                child: const Icon(
                  Icons.directions_car,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vozac!.imePrezime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${widget.grad} ${widget.vreme}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Live indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _vozacLokacija != null ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Status i ETA
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_etaMinutes != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatETA(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ETA broj
              if (_etaMinutes != null)
                V3ContainerUtils.styledContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: vozacColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  child: Text(
                    '${_etaMinutes}min',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
