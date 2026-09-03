import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v3_uplata_pazara.dart';
import '../screens/v3_vozac_pazar_popup.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_app_settings_state.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_uplata_pazara_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_status_policy.dart';

class V3PazarListener extends StatefulWidget {
  final Widget child;

  const V3PazarListener({super.key, required this.child});

  @override
  State<V3PazarListener> createState() => _V3PazarListenerState();
}

class _V3PazarListenerState extends State<V3PazarListener> {
  static final DateTime _defaultPazarPolicyStartDate = V3BelgradeTime.dateTime(2026, 9, 4);

  StreamSubscription<int>? _revisionSub;
  StreamSubscription<int>? _voznjeRevisionSub;
  bool _dialogOpen = false;
  bool _autoTriggerInFlight = false;
  bool _checkInFlight = false;
  Timer? _autoCheckTimer;

  static const Duration _autoDelayAfterLastRide = Duration(minutes: 60);
  static const Duration _autoCheckInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    debugPrint('[V3PazarListener] initState - listener aktiviran (realtime)');

    // Jednokratna provera pri pokretanju (fallback ako cache nije spreman)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPazar(fromRealtime: false));

    // Slušamo promene u tabeli v3_uplata_pazara preko realtime manager-a
    _revisionSub = V3MasterRealtimeManager.instance.tableRevisionStream('v3_uplata_pazara').listen((revision) {
      debugPrint('[V3PazarListener] realtime promena u v3_uplata_pazara (revision=$revision)');
      _checkPazar(fromRealtime: true);
    });

    // Slušamo promene koje utiču na "poslednju vožnju" vozača.
    _voznjeRevisionSub = V3MasterRealtimeManager.instance.tablesRevisionStream(const [
      'v3_trenutna_dodela',
      'v3_operativna_nedelja',
    ]).listen((revision) {
      debugPrint('[V3PazarListener] realtime promena vožnji (revision=$revision)');
      _checkPazar(fromRealtime: true);
    });

    _autoCheckTimer = Timer.periodic(_autoCheckInterval, (_) {
      _checkPazar(fromRealtime: false);
    });
  }

  @override
  void dispose() {
    _revisionSub?.cancel();
    _voznjeRevisionSub?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  DateTime? _parseBelgradeDateTimeFromIsoAndHHmm({
    required String datumIso,
    required String hhmm,
  }) {
    if (datumIso.length < 10) return null;
    final year = int.tryParse(datumIso.substring(0, 4));
    final month = int.tryParse(datumIso.substring(5, 7));
    final day = int.tryParse(datumIso.substring(8, 10));
    final parts = hhmm.split(':');
    if (year == null || month == null || day == null || parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return V3BelgradeTime.dateTime(year, month, day, hour, minute);
  }

  bool _isPolicyActiveFor(DateTime dayBelgrade) {
    final dayOnly = V3BelgradeTime.dateTime(dayBelgrade.year, dayBelgrade.month, dayBelgrade.day);
    final configuredStart = V3AppSettingsState.instance.pazarPolicyStartDateValue;
    final effectiveStart = configuredStart ?? _defaultPazarPolicyStartDate;
    return !dayOnly.isBefore(effectiveStart);
  }

  DateTime? _findLastAssignedRideForToday({
    required String vozacId,
    required DateTime nowBelgrade,
  }) {
    final rm = V3MasterRealtimeManager.instance;
    final todayIso = V3BelgradeTime.toIsoDate(nowBelgrade);
    DateTime? latest;

    for (final assignment in rm.trenutnaDodelaCache.values) {
      final assignedVozacId = (assignment['vozac_v3_auth_id']?.toString() ?? '').trim();
      if (assignedVozacId != vozacId) continue;

      final terminId = (assignment['termin_id']?.toString() ?? '').trim();
      if (terminId.isEmpty) continue;

      final row = rm.operativnaNedeljaCache[terminId] ?? rm.operativnaAssignedCache[terminId];
      if (row == null) continue;
      if (V3StatusPolicy.isTimestampSet(row['otkazano_at'])) continue;

      final datumIso = V3BelgradeTime.parseIsoDatePart(row['datum']?.toString() ?? '');
      if (datumIso != todayIso) continue;

      final vreme = V3BelgradeTime.normalizeToHHmm(row['polazak_at']?.toString() ?? row['vreme']?.toString());
      if (vreme.isEmpty) continue;

      final departure = _parseBelgradeDateTimeFromIsoAndHHmm(
        datumIso: datumIso,
        hhmm: vreme,
      );
      if (departure == null) continue;

      if (latest == null || departure.isAfter(latest)) {
        latest = departure;
      }
    }

    return latest;
  }

  bool _isDailyPazarAlreadySubmitted(V3DnevnaUplataPazara? dnevna) {
    if (dnevna == null) return false;
    return dnevna.zahtevanUnos == false;
  }

  Future<void> _autoRequestIfDue({
    required DateTime nowBelgrade,
    required String vozacId,
    required V3DnevnaUplataPazara? dnevna,
  }) async {
    if (_autoTriggerInFlight) return;
    if (dnevna?.zahtevanUnos == true) return;
    if (_isDailyPazarAlreadySubmitted(dnevna)) return;

    final lastRide = _findLastAssignedRideForToday(
      vozacId: vozacId,
      nowBelgrade: nowBelgrade,
    );
    if (lastRide == null) return;

    final dueAt = lastRide.add(_autoDelayAfterLastRide);
    if (nowBelgrade.isBefore(dueAt)) {
      return;
    }

    final pazarMap = V3FinansijeService.getPazarPoVozacuZaDan(nowBelgrade);
    final ukupno = dnevna?.ukupno ?? (pazarMap[vozacId] ?? 0.0);
    if (ukupno <= 0.009) {
      debugPrint('[V3PazarListener] auto zahtev preskočen: ukupno pazar=0 za vozacId=$vozacId');
      return;
    }

    _autoTriggerInFlight = true;
    try {
      await V3UplataPazaraService.sacuvajDnevnuUplatu(
        vozacId: vozacId,
        datum: nowBelgrade,
        predao: dnevna?.predao ?? 0,
        ukupno: ukupno,
        zahtevanUnos: true,
      );
      debugPrint('[V3PazarListener] auto zahtev unosa aktiviran (60min posle poslednje vožnje)');
    } catch (e) {
      debugPrint('[V3PazarListener] auto zahtev unosa error: $e');
    } finally {
      _autoTriggerInFlight = false;
    }
  }

  Future<void> _checkPazar({required bool fromRealtime}) async {
    if (_checkInFlight) {
      debugPrint('[V3PazarListener] check je u toku, preskačem');
      return;
    }

    _checkInFlight = true;
    try {
      if (_dialogOpen) {
        debugPrint('[V3PazarListener] dialog je već otvoren, preskačem');
        return;
      }

      final currentVozac = V3VozacService.currentVozac;
      final vozacId = currentVozac?.id;
      if (vozacId == null || vozacId.isEmpty) {
        debugPrint('[V3PazarListener] currentVozac je null/empty');
        return;
      }

      final today = V3BelgradeTime.now();
      if (!_isPolicyActiveFor(today)) {
        final configuredStart = V3AppSettingsState.instance.pazarPolicyStartDateValue;
        final effectiveStart = configuredStart ?? _defaultPazarPolicyStartDate;
        debugPrint(
          '[V3PazarListener] politika nije aktivna za ${V3BelgradeTime.toIsoDate(today)} (start=${V3BelgradeTime.toIsoDate(effectiveStart)})',
        );
        return;
      }

      debugPrint('[V3PazarListener] proveravam vozacId=$vozacId za ${today.day}.${today.month}.${today.year}');

      final cacheMap = V3MasterRealtimeManager.instance.uplataPazaraCache;
      debugPrint('[V3PazarListener] cache veličina=${cacheMap.length}');

      Map<String, dynamic>? targetRow;
      for (final row in cacheMap.values) {
        if (row['vozac_id'] == vozacId && row['mesec'] == today.month && row['godina'] == today.year) {
          targetRow = row;
          break;
        }
      }

      // Ako nema u cache-u i ovo nije realtime event, proveri bazu kao fallback
      if (targetRow == null && !fromRealtime) {
        debugPrint('[V3PazarListener] nema u cache-u, proveravam bazu...');
        try {
          final uplata = await V3UplataPazaraService.getZaVozacaIMesec(
            vozacId: vozacId,
            datum: today,
          );
          if (uplata != null) {
            targetRow = uplata.toJson();
            debugPrint('[V3PazarListener] pronađeno u bazi');
          } else {
            debugPrint('[V3PazarListener] nema zapisa u bazi');
          }
        } catch (e) {
          debugPrint('[V3PazarListener] greška pri čitanju baze: $e');
        }
      } else if (targetRow != null) {
        debugPrint('[V3PazarListener] pronađeno u cache-u');
      }

      V3DnevnaUplataPazara? dnevna;
      if (targetRow != null) {
        final uplata = V3UplataPazara.fromJson(targetRow);
        dnevna = uplata.uplataZaDan(today.day);
      }

      await _autoRequestIfDue(
        nowBelgrade: today,
        vozacId: vozacId,
        dnevna: dnevna,
      );

      // Posle auto-upisa osveži iz baze kako bi zahtevanUnos odmah bio vidljiv.
      final afterAuto = await V3UplataPazaraService.getZaVozacaIMesec(
        vozacId: vozacId,
        datum: today,
      );
      final dnevnaAfterAuto = afterAuto?.uplataZaDan(today.day) ?? dnevna;

      if (dnevnaAfterAuto == null) {
        debugPrint('[V3PazarListener] nema dnevne uplate za dan ${today.day}');
        return;
      }

      debugPrint(
        '[V3PazarListener] dnevna uplata: predao=${dnevnaAfterAuto.predao}, zahtevanUnos=${dnevnaAfterAuto.zahtevanUnos}',
      );

      if (dnevnaAfterAuto.zahtevanUnos == true) {
        debugPrint('[V3PazarListener] POKREĆEM popup!');
        _dialogOpen = true;

        final navContext = navigatorKey.currentContext;
        if (navContext == null) {
          debugPrint('[V3PazarListener] navigatorKey.currentContext je null, ne mogu otvoriti popup');
          _dialogOpen = false;
          return;
        }

        await showDialog(
          context: navContext,
          barrierDismissible: false,
          builder: (_) => V3VozacPazarPopup(
            datum: today,
            ukupno: dnevnaAfterAuto.ukupno,
            onSaved: () {
              navigatorKey.currentState?.pop();
            },
          ),
        );
        _dialogOpen = false;
        debugPrint('[V3PazarListener] popup zatvoren');
      }
    } finally {
      _checkInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
