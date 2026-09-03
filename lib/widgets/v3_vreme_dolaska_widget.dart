import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_translations.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_app_settings_state.dart';
import '../services/v3/v3_tracking_config.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_belgrade_time.dart';
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
  Timer? _refreshTimer;

  String get putnikId => widget.putnikId;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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

  // Prevodi za ETA widget (SR/EN/RU/DE).
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vremeDolaskaWidget');

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  /// Direktni lookup — cache ključ je uvek termin_id:putnik_id.
  Map<String, dynamic>? _findEtaRow(String terminId, String putnikId) {
    return V3MasterRealtimeManager.instance.etaResultsCache['$terminId:$putnikId'];
  }

  /// Tracking prozor za prikaz ETA: T-15 .. T+40 (isto kao vozački tracking).
  bool _isInEtaTrackingWindow(DateTime departure, DateTime now) {
    return v3IsTrackingWindowOpen(polazakAt: departure, now: now);
  }

  int _buildEtaMinutes(int etaSeconds) {
    if (etaSeconds <= 0) return 0;
    return (etaSeconds / 60).round();
  }

  DateTime? _parseDepartureDateTime(Map<String, dynamic> row) {
    final datumRaw = row['datum'];
    final polazakRaw = row['polazak_at'];

    DateTime? datum;
    if (datumRaw is DateTime) {
      datum = V3BelgradeTime.dateOnly(datumRaw);
    } else if (datumRaw is String && datumRaw.trim().isNotEmpty) {
      final parsed = V3BelgradeTime.parseDatum(datumRaw.trim());
      if (parsed != null) {
        datum = V3BelgradeTime.dateOnly(parsed);
      }
    }

    if (polazakRaw is DateTime) {
      return polazakRaw;
    }

    if (polazakRaw is String && polazakRaw.trim().isNotEmpty) {
      final timeRaw = polazakRaw.trim();
      final parsedDateTime = V3BelgradeTime.parseTs(timeRaw);
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
          return V3BelgradeTime.dateTime(datum.year, datum.month, datum.day, hour, minute)
              .add(Duration(seconds: second));
        }
      }
    }

    return null;
  }

  ({DateTime departure, String? grad, Map<String, dynamic> row, String? vozacId})? _findNextPutnikRide() {
    final now = V3BelgradeTime.now();
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
      // Nema vremenskog hard-stopa: putnik je već filtriran gore (nije pokupljen/otkazan).
      String? vozacId;

      final terminId = row['id']?.toString();

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
          final normVreme = V3BelgradeTime.normalizeToHHmm(polazakAt);
          for (final slot in V3MasterRealtimeManager.instance.trenutnaDodelaSlotCache.values) {
            final slotVreme = slot['vreme']?.toString();
            if (slotVreme != null &&
                slot['datum']?.toString() == datumIso &&
                slot['grad']?.toString() == grad &&
                V3BelgradeTime.normalizeToHHmm(slotVreme) == normVreme) {
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

  /// Rešava ID adrese na kojoj putnik čeka za datu vožnju.
  String? _resolveWaitingAddressId(Map<String, dynamic> rideRow) {
    final overrideId = rideRow['adresa_override_id']?.toString();
    if (overrideId != null && overrideId.trim().isNotEmpty) return overrideId.trim();

    final putnik = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (putnik == null) return null;

    final grad = (rideRow['grad']?.toString() ?? '').trim().toUpperCase();
    final koristiSekundarnu = rideRow['koristi_sekundarnu'] == true;

    if (grad == 'BC') {
      final primaryId = putnik['adresa_bc_id']?.toString();
      final secondaryId = putnik['adresa_bc_id_2']?.toString();
      final preferredId = koristiSekundarnu ? (secondaryId ?? primaryId) : primaryId;
      return preferredId ?? secondaryId;
    }

    if (grad == 'VS') {
      final primaryId = putnik['adresa_vs_id']?.toString();
      final secondaryId = putnik['adresa_vs_id_2']?.toString();
      final preferredId = koristiSekundarnu ? (secondaryId ?? primaryId) : primaryId;
      return preferredId ?? secondaryId;
    }

    return null;
  }

  String? _resolveWaitingAddressForRide(Map<String, dynamic> rideRow) {
    final adresaId = _resolveWaitingAddressId(rideRow);
    return _getAdresaNazivById(adresaId);
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  ({double lat, double lng})? _resolveWaitingAddressCoords(Map<String, dynamic> rideRow) {
    final adresaId = _resolveWaitingAddressId(rideRow);
    if (adresaId == null || adresaId.isEmpty) return null;
    final row = V3MasterRealtimeManager.instance.adreseCache[adresaId];
    if (row == null) return null;
    final lat = _toDoubleOrNull(row['gps_lat']);
    final lng = _toDoubleOrNull(row['gps_lng']);
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  Future<void> _openMapsForRide(Map<String, dynamic> rideRow) async {
    final coords = _resolveWaitingAddressCoords(rideRow);
    if (coords == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('noGpsForAddress'))),
        );
      }
      return;
    }

    // Putnik: samo maps app template iz Supabase (nema web/fallback).
    final appUri = V3AppSettingsState.instance.buildMapsAppUri(
      latitude: coords.lat,
      longitude: coords.lng,
      isIos: Platform.isIOS,
      isAndroid: Platform.isAndroid,
    );
    if (appUri != null) {
      try {
        if (await canLaunchUrl(appUri)) {
          final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
          if (ok) return;
        } else {
          // iOS canLaunchUrl može lagati za custom scheme — i dalje pokušaj launch.
          final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      } catch (_) {
        // show error below
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('cannotOpenMaps'))),
      );
    }
  }

  String _formatNextRide(DateTime departure, String? grad) {
    final day = departure.day.toString().padLeft(2, '0');
    final month = departure.month.toString().padLeft(2, '0');
    final hour = departure.hour.toString().padLeft(2, '0');
    final minute = departure.minute.toString().padLeft(2, '0');
    final gradPart = (grad == null || grad.trim().isEmpty) ? '' : ' • ${grad.trim().toUpperCase()}';
    return '$day.$month. ${_tr('u')} $hour:$minute$gradPart';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, __, ___) => StreamBuilder<int>(
        stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const [
          'v3_eta_results',
          'v3_auth',
          'v3_operativna_nedelja',
          'v3_trenutna_dodela_slot',
          'v3_trenutna_dodela'
        ]),
        builder: (context, _) {
          final now = V3BelgradeTime.now();
          final nextRide = _findNextPutnikRide();
          final nextTerminId = nextRide?.row['id']?.toString();
          final assignedVozacId = nextRide?.vozacId;

          // Jednostavno: ETA red za ovu vožnju + tracking prozor T-15..T+40.
          // Sakrij samo ako su i dodela i ETA vozač poznati i razlikuju se.
          final row = nextTerminId != null ? _findEtaRow(nextTerminId, putnikId) : null;
          final eta = row != null ? (row[_colEtaSeconds] as num?)?.toInt() : null;
          final etaVozacId = row?[_colVozacId]?.toString();

          final inTrackingWindow = nextRide != null && _isInEtaTrackingWindow(nextRide.departure, now);
          final vozacMismatch = assignedVozacId != null &&
              etaVozacId != null &&
              assignedVozacId.isNotEmpty &&
              etaVozacId.isNotEmpty &&
              assignedVozacId != etaVozacId;
          final hasActiveEta = eta != null && inTrackingWindow && !vozacMismatch;
          final minutes = hasActiveEta ? _buildEtaMinutes(eta) : null;
          final nextRideLabel =
              nextRide == null ? _tr('nemaZakazaneVoznje') : _formatNextRide(nextRide.departure, nextRide.grad);
          final waitingAddress = nextRide == null ? null : _resolveWaitingAddressForRide(nextRide.row);

          return V3ContainerUtils.styledContainer(
            padding: const EdgeInsets.all(12),
            backgroundColor: Colors.green.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.8), width: 1.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasActiveEta)
                  Column(
                    children: [
                      Text(
                        _tr('procenjenoVreme'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_tr('zaMin')} $minutes ${_tr('min')}',
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
                      Text(
                        _tr('sledecaVoznja'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
                      if (waitingAddress != null && nextRide != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _openMapsForRide(nextRide.row),
                          child: V3ContainerUtils.styledContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.greenAccent,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '${_tr('cekaNa')}: $waitingAddress',
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.white38,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                if (hasActiveEta && etaVozacId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_tr('vozac')}: ${V3MasterRealtimeManager.instance.vozaciCache[etaVozacId]?['ime_prezime'] ?? etaVozacId}',
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
                        '${_tr('vozac')}: $vozacIme',
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
      ),
    );
  }
}
