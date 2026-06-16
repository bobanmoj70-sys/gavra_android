import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_string_utils.dart';

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
  Timer? _refreshTimer;

  String get putnikId => widget.putnikId;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  static const String _colVozacId = 'vozac_id';
  static const String _colEtaSeconds = 'eta_seconds';
  static const String _colComputedAt = 'computed_at';

  ({int? etaSeconds, bool isStale, String? vozacId, String? terminId}) _readEtaState(Map<String, dynamic>? row) {
    if (row == null) {
      return (etaSeconds: null, isStale: false, vozacId: null, terminId: null);
    }

    final eta = (row[_colEtaSeconds] as num?)?.toInt();
    final computedAtRaw = row[_colComputedAt];
    DateTime? computedAt;
    if (computedAtRaw is DateTime) {
      computedAt = computedAtRaw;
    } else if (computedAtRaw is String) {
      computedAt = DateTime.tryParse(computedAtRaw);
    }
    final stale = computedAt == null || DateTime.now().difference(computedAt) > etaStaleThreshold;
    final vozacId = row[_colVozacId]?.toString();
    final terminId = row['termin_id']?.toString();

    return (etaSeconds: eta, isStale: stale, vozacId: vozacId, terminId: terminId);
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

  ({DateTime departure, String? grad, Map<String, dynamic> row, String? vozacId})? _findNextPutnikRide() {
    final now = DateTime.now();
    DateTime? best;
    String? bestGrad;
    Map<String, dynamic>? bestRow;
    String? bestVozacId;

    for (final row in V3MasterRealtimeManager.instance.operativnaNedeljaCache.values) {
      final createdBy = row['created_by']?.toString();
      if (createdBy != putnikId) continue;
      if (row['pokupljen_at'] != null) continue;
      if (row['otkazano_at'] != null) continue;

      final departure = _parseDepartureDateTime(row);
      if (departure == null) continue;
      final terminId = row['id']?.toString();
      final hasActiveEta =
          terminId != null && V3MasterRealtimeManager.instance.etaResultsCache.containsKey('$terminId:$putnikId');
      if (departure.isBefore(now) && !hasActiveEta) continue;
      if (departure.isBefore(now.subtract(const Duration(minutes: 60)))) continue;
      String? vozacId;

      // Prvo proveri individualnu dodelu u v3_trenutna_dodela
      if (terminId != null) {
        for (final dodela in V3MasterRealtimeManager.instance.trenutnaDodelaCache.values) {
          if (dodela['termin_id']?.toString() == terminId && dodela['putnik_v3_auth_id']?.toString() == putnikId) {
            vozacId = dodela['vozac_v3_auth_id']?.toString();
            break;
          }
        }
      }

      // Ako nema individualne dodele, proveri slot dodelu u v3_trenutna_dodela_slot
      if (vozacId == null) {
        final datumIso = row['datum']?.toString();
        final grad = row['grad']?.toString();
        final polazakAt = row['polazak_at']?.toString();
        if (datumIso != null && grad != null && polazakAt != null) {
          final normVreme = V3StringUtils.trimTimeToHhMm(polazakAt);
          for (final slot in V3MasterRealtimeManager.instance.trenutnaDodelaSlotCache.values) {
            final slotVreme = slot['vreme']?.toString();
            if (slotVreme != null &&
                slot['datum']?.toString() == datumIso &&
                slot['grad']?.toString() == grad &&
                V3StringUtils.trimTimeToHhMm(slotVreme) == normVreme) {
              vozacId = slot['vozac_v3_auth_id']?.toString();
              break;
            }
          }
        }
      }

      if (best == null || departure.isBefore(best)) {
        best = departure;
        bestGrad = row['grad']?.toString();
        bestRow = row;
        bestVozacId = vozacId;
      }
    }

    if (best == null || bestRow == null) return null;
    return (departure: best, grad: bestGrad, row: bestRow, vozacId: bestVozacId);
  }

  String? _getAdresaNazivById(String? adresaId) {
    if (adresaId == null || adresaId.trim().isEmpty) return null;
    final row = V3MasterRealtimeManager.instance.adreseCache[adresaId.trim()];
    final naziv = row?['naziv']?.toString().trim();
    if (naziv == null || naziv.isEmpty) return null;
    return naziv;
  }

  String? _resolveWaitingAddressForRide(Map<String, dynamic> rideRow) {
    final overrideId = rideRow['adresa_override_id']?.toString();
    final overrideNaziv = _getAdresaNazivById(overrideId);
    if (overrideNaziv != null) return overrideNaziv;

    final putnik = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (putnik == null) return null;

    final grad = (rideRow['grad']?.toString() ?? '').trim().toUpperCase();
    final koristiSekundarnu = rideRow['koristi_sekundarnu'] == true;

    if (grad == 'BC') {
      final primaryId = putnik['adresa_bc_id']?.toString();
      final secondaryId = putnik['adresa_bc_id_2']?.toString();
      final preferredId = koristiSekundarnu ? (secondaryId ?? primaryId) : primaryId;
      return _getAdresaNazivById(preferredId) ?? _getAdresaNazivById(secondaryId);
    }

    if (grad == 'VS') {
      final primaryId = putnik['adresa_vs_id']?.toString();
      final secondaryId = putnik['adresa_vs_id_2']?.toString();
      final preferredId = koristiSekundarnu ? (secondaryId ?? primaryId) : primaryId;
      return _getAdresaNazivById(preferredId) ?? _getAdresaNazivById(secondaryId);
    }

    return null;
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
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const [
        'v3_eta_results',
        'v3_auth',
        'v3_operativna_nedelja',
        'v3_trenutna_dodela_slot',
        'v3_trenutna_dodela'
      ]),
      builder: (context, _) {
        final nextRide = _findNextPutnikRide();
        final nextTerminId = nextRide?.row['id']?.toString();
        final assignedVozacId = nextRide?.vozacId;

        final cacheKey = nextTerminId != null ? '$nextTerminId:$putnikId' : null;
        final row = cacheKey != null ? V3MasterRealtimeManager.instance.etaResultsCache[cacheKey] : null;
        final etaState = _readEtaState(row);
        final eta = etaState.etaSeconds;
        final isStale = etaState.isStale;
        final etaVozacId = etaState.vozacId;
        final etaTerminId = etaState.terminId;

        final hasFreshEta =
            eta != null && !isStale && etaTerminId != null && nextTerminId != null && etaTerminId == nextTerminId;
        final minutes = hasFreshEta ? _buildEtaMinutes(eta) : null;
        final nextRideLabel =
            nextRide == null ? 'Nema zakazane vožnje' : _formatNextRide(nextRide.departure, nextRide.grad);
        final waitingAddress = nextRide == null ? null : _resolveWaitingAddressForRide(nextRide.row);

        return V3ContainerUtils.styledContainer(
          padding: const EdgeInsets.all(12),
          backgroundColor: Colors.green.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.8), width: 1.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasFreshEta)
                Column(
                  children: [
                    const Text(
                      'Procenjeno vreme dolaska',
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
                      'za $minutes min',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    const Text(
                      'Sledeća vožnja',
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
                    if (waitingAddress != null) ...[
                      const SizedBox(height: 8),
                      V3ContainerUtils.styledContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Čeka na: $waitingAddress',
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              if (hasFreshEta && etaVozacId != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Vozač: ${V3MasterRealtimeManager.instance.vozaciCache[etaVozacId]?['ime_prezime'] ?? etaVozacId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (nextRide != null && assignedVozacId != null) ...[
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final vozacIme = V3MasterRealtimeManager.instance.vozaciCache[assignedVozacId]?['ime_prezime'];
                    if (vozacIme == null || vozacIme.isEmpty) return const SizedBox.shrink();
                    return Text(
                      'Vozač: $vozacIme',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
