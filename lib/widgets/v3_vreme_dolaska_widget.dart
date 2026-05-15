import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../utils/v3_container_utils.dart';

class V3VremeDolaskaWidget extends StatelessWidget {
  const V3VremeDolaskaWidget({
    super.key,
    required this.putnikId,
  });

  final String putnikId;

  static const String _colVozacId = 'vozac_id';
  static const String _colEtaSeconds = 'eta_seconds';
  static const String _colComputedAt = 'computed_at';

  // ETA se smatra zastarelom ako nema svežeg update-a duže vreme.
  // Ovo sprečava da ETA widget ostane "zalepljen" kada lokacije prestanu da stižu.
  static const Duration _staleThreshold = Duration(minutes: 15);

  ({int? etaSeconds, bool isStale, String? vozacId}) _readEtaState(Map<String, dynamic>? row) {
    if (row == null) {
      return (etaSeconds: null, isStale: false, vozacId: null);
    }

    final eta = (row[_colEtaSeconds] as num?)?.toInt();
    final computedAtRaw = row[_colComputedAt];
    DateTime? computedAt;
    if (computedAtRaw is DateTime) {
      computedAt = computedAtRaw;
    } else if (computedAtRaw is String) {
      computedAt = DateTime.tryParse(computedAtRaw);
    }
    final stale = computedAt == null || DateTime.now().difference(computedAt) > _staleThreshold;
    final vozacId = row[_colVozacId]?.toString();

    return (etaSeconds: eta, isStale: stale, vozacId: vozacId);
  }

  int _buildEtaMinutes(int etaSeconds) {
    if (etaSeconds <= 0) return 0;
    return (etaSeconds / 60).ceil();
  }

  DateTime? _parseDepartureDateTime(Map<String, dynamic> row) {
    final datumRaw = row['datum'];
    final polazakRaw = row['polazak_at'];

    DateTime? datum;
    if (datumRaw is DateTime) {
      datum = DateTime(datumRaw.year, datumRaw.month, datumRaw.day);
    } else if (datumRaw is String && datumRaw.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(datumRaw.trim());
      if (parsed != null) {
        datum = DateTime(parsed.year, parsed.month, parsed.day);
      }
    }

    if (polazakRaw is DateTime) {
      return polazakRaw;
    }

    if (polazakRaw is String && polazakRaw.trim().isNotEmpty) {
      final timeRaw = polazakRaw.trim();
      final parsedDateTime = DateTime.tryParse(timeRaw);
      if (parsedDateTime != null) {
        return parsedDateTime;
      }

      if (datum != null) {
        final timePart = timeRaw.contains('T') ? timeRaw.split('T').last : timeRaw;
        final parts = timePart.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          final second = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
          return DateTime(datum.year, datum.month, datum.day, hour, minute, second);
        }
      }
    }

    return null;
  }

  ({DateTime departure, String? grad})? _findNextPutnikRide() {
    final now = DateTime.now();
    DateTime? best;
    String? bestGrad;

    for (final row in V3MasterRealtimeManager.instance.operativnaNedeljaCache.values) {
      final createdBy = row['created_by']?.toString();
      if (createdBy != putnikId) continue;
      if (row['pokupljen_at'] != null) continue;
      if (row['otkazano_at'] != null) continue;

      final departure = _parseDepartureDateTime(row);
      if (departure == null) continue;
      if (departure.isBefore(now)) continue;

      if (best == null || departure.isBefore(best)) {
        best = departure;
        bestGrad = row['grad']?.toString();
      }
    }

    if (best == null) return null;
    return (departure: best, grad: bestGrad);
  }

  String _formatNextRide(DateTime departure, String? grad) {
    final day = departure.day.toString().padLeft(2, '0');
    final month = departure.month.toString().padLeft(2, '0');
    final hour = departure.hour.toString().padLeft(2, '0');
    final minute = departure.minute.toString().padLeft(2, '0');
    final gradPart = (grad == null || grad.trim().isEmpty) ? '' : ' • ${grad.trim().toUpperCase()}';
    return '$day.$month. u $hour:$minute$gradPart';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_eta_results', 'v3_auth', 'v3_operativna_nedelja']),
      builder: (context, _) {
        final row = V3MasterRealtimeManager.instance.etaResultsCache[putnikId];
        final etaState = _readEtaState(row);
        final eta = etaState.etaSeconds;
        final isStale = etaState.isStale;
        final vozacId = etaState.vozacId;

        final hasFreshEta = eta != null && !isStale;
        final minutes = hasFreshEta ? _buildEtaMinutes(eta) : null;
        final nextRide = hasFreshEta ? null : _findNextPutnikRide();
        final nextRideLabel =
            nextRide == null ? 'Nema zakazane vožnje' : _formatNextRide(nextRide.departure, nextRide.grad);

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
              if (hasFreshEta)
                Text(
                  'za $minutes min',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                )
              else
                Column(
                  children: [
                    const Text(
                      'Sledeća putnikova vožnja',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextRideLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              if (hasFreshEta && vozacId != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Vozač: ${V3MasterRealtimeManager.instance.vozaciCache[vozacId]?['ime_prezime'] ?? vozacId}',
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
      },
    );
  }
}
