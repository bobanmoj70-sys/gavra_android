import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_foreground_gps_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_smart_navigation_service.dart';
import '../services/v3/v3_trip_stops_service.dart';
import '../services/v3/v3_vozac_lokacija_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_filters.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_telefon_helper.dart';
import '../widgets/v3_bottom_nav_bar_letnji.dart';
import '../widgets/v3_bottom_nav_bar_praznici.dart';
import '../widgets/v3_bottom_nav_bar_zimski.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_promena_sifre_screen.dart';
import 'v3_welcome_screen.dart';

/// V3VozacScreen — ekran za vozača (Voja).
/// V3 Vozač Screen - prikazuje dodjeljene termine i putnike
/// iz cache-a građenog iz v3_operativna_nedelja (legacy naziv: v3GpsRasporedCache).
///
/// 🎯 KLJUČNE OPTIMIZACIJE SA FIKSNIM ADRESAMA PUTNIKA:
/// ✅ Primarno bez Geocoding API poziva (Photon fallback samo za adrese bez koordinata)
/// ✅ ETA kalkulacija je trenutna (Haversine formula direktno)
/// ✅ Pametni GPS filtering na osnovu blizine putnika
/// ✅ OSRM optimizacija rute na ručni zahtev vozača
/// ✅ Bolji UX - brže odzivi, manja potrošnja baterije
class V3VozacScreen extends StatefulWidget {
  const V3VozacScreen({super.key});

  @override
  State<V3VozacScreen> createState() => _V3VozacScreenState();
}

class _V3VozacScreenState extends State<V3VozacScreen> {
  // 🎯 SISTEM OPTIMIZOVAN ZA FIKSNE ADRESE PUTNIKA:
  //
  // 1. GPS OPTIMIZACIJA:
  //    • GPS stream umesto Timer-a (real-time pozicije)
  //    • Vozač ručno pokreće optimizaciju kada želi
  //    • Dinamički distance filter na osnovu putnika
  //
  // 2. FIKSNE ADRESE = BRZINA I ŠTEDNJA:
  //    • Primarno bez Geocoding API poziva (Photon fallback samo kada fale koordinate)
  //    • ETA kalkulacija je trenutna (Haversine direktno)
  //    • Optimizacija rute bez external API-ja
  //    • Štedi API quota i novac
  //
  // 3. REZULTAT:
  //    • 80% manje DB poziva (120 → 20/sat po vozaču)
  //    • Brži odziv sistema, manja potrošnja baterije
  //    • Enterprise-level performanse (kao Uber/Tesla)

  DateTime _selectedDate = V3DanHelper.dateOnly(DateTime.now());
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  bool _isLoading = true;
  bool _isTracking = false;
  bool _isOptimizingRoute = false;

  Map<String, dynamic> _lastOptimizationMeta = const {};

  int? _lastRealtimeTick;

  /// Efektivni vozač
  dynamic get _efektivniVozac => V3VozacService.currentVozac;

  // Moji termini iz legacy v3GpsRasporedCache (izvor: v3_operativna_nedelja)
  List<Map<String, dynamic>> _mojiTermini = [];

  // Moji putnici iz legacy v3GpsRasporedCache (izvor: v3_operativna_nedelja)
  List<_PutnikEntry> _mojiPutnici = [];

  List<String> get _bcVremena =>
      getRasporedVremena('bc', navBarTypeNotifier.value, day: V3DanHelper.fullName(_selectedDate));
  List<String> get _vsVremena =>
      getRasporedVremena('vs', navBarTypeNotifier.value, day: V3DanHelper.fullName(_selectedDate));

  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  String _normV(String? v) {
    if (v == null || v.isEmpty) return '';
    final parts = v.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      return V3DanHelper.formatVreme(hour, minute);
    }
    return v;
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  void _updateLastOptimizationMeta({
    required String reason,
    required String engine,
    required int optimizedCount,
    required int eligibleCount,
    Map<String, double>? currentPosition,
    int skippedCount = 0,
  }) {
    final now = DateTime.now();
    _lastOptimizationMeta = {
      'reason': reason,
      'engine': engine,
      'optimized_count': optimizedCount,
      'eligible_count': eligibleCount,
      'skipped_count': skippedCount,
      'at': now.toIso8601String(),
      if (currentPosition != null) 'position': currentPosition,
    };
    debugPrint('[V3VozacScreen] Route meta: $_lastOptimizationMeta');
  }

  bool _isGpsRowEligible(Map<String, dynamic> row) {
    final status = (row['status_final'] as String?) ?? (row['status'] as String?);
    return row['aktivno'] != false && !V3StatusFilters.isRejected(status);
  }

  bool _isGpsRowActiveForCount(Map<String, dynamic> row) {
    final status = (row['status_final'] as String?) ?? (row['status'] as String?);
    final pokupljen = row['pokupljen'] == true;
    return V3StatusFilters.isActiveForDisplay(
      aktivno: _isGpsRowEligible(row),
      status: status,
      pokupljen: pokupljen,
    );
  }

  String _terminKeyFromGpsRow(Map<String, dynamic> row) {
    final datum = V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '');
    final grad = row['grad']?.toString().toUpperCase() ?? '';
    final vreme = _normV(row['vreme']?.toString());
    return '$datum|$grad|$vreme';
  }

  Map<String, String> _buildInheritedVozacByTermin() {
    final rm = V3MasterRealtimeManager.instance;
    final inherited = <String, String>{};
    final passengerVozacIdsByTermin = <String, Set<String>>{};

    for (final row in rm.v3GpsRasporedCache.values) {
      if (!_isGpsRowEligible(row)) continue;
      final vozacId = (row['vozac_id']?.toString() ?? '').trim();
      if (vozacId.isEmpty) continue;

      final key = _terminKeyFromGpsRow(row);
      final isMasterTerminRow = row['putnik_id'] == null;

      if (isMasterTerminRow) {
        inherited.putIfAbsent(key, () => vozacId);
        continue;
      }

      passengerVozacIdsByTermin.putIfAbsent(key, () => <String>{}).add(vozacId);
    }

    for (final entry in passengerVozacIdsByTermin.entries) {
      if (inherited.containsKey(entry.key)) continue;
      if (entry.value.length == 1) {
        inherited[entry.key] = entry.value.first;
      }
    }

    return inherited;
  }

  String _effectiveVozacIdForRow(Map<String, dynamic> row, Map<String, String> inheritedVozacByTermin) {
    final explicit = (row['vozac_id']?.toString() ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return inheritedVozacByTermin[_terminKeyFromGpsRow(row)] ?? '';
  }

  bool _isExcludedFromOptimization(_PutnikEntry entry) {
    final status = entry.entry?.statusFinal;
    final isPokupljen = entry.entry?.pokupljen ?? false;
    return V3StatusFilters.isExcludedFromOptimization(
      status: status,
      pokupljen: isPokupljen,
    );
  }

  List<_PutnikEntry> _sortPutniciForDisplay(List<_PutnikEntry> putnici) {
    final sorted = List<_PutnikEntry>.from(putnici);
    sorted.sort((a, b) {
      int sortRank(_PutnikEntry entry) {
        final status = entry.entry?.statusFinal;
        if (V3StatusFilters.isCanceledOrRejected(status)) return 3;
        if (entry.entry?.pokupljen == true) return 2;
        return 1;
      }

      final aRank = sortRank(a);
      final bRank = sortRank(b);

      if (aRank != bRank) {
        return aRank.compareTo(bRank);
      }

      if (aRank == 1 && _isTracking) {
        final aOrder = a.routeOrder ?? 999999;
        final bOrder = b.routeOrder ?? 999999;
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      }

      return a.putnik.imePrezime.compareTo(b.putnik.imePrezime);
    });
    return sorted;
  }

  List<_PutnikEntry> _optimizacijaPutnici() {
    return _mojiPutnici.where((entry) => !_isExcludedFromOptimization(entry)).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = V3DanHelper.defaultWorkdayDate();
    _initData();
  }

  @override
  void dispose() {
    V3StreamUtils.cancelSubscription('vozac_screen_realtime');
    V3StreamUtils.cancelSubscription('vozac_screen_gps');
    super.dispose();
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        V3NavigationUtils.pushAndRemoveUntil(context, const V3WelcomeScreen());
      }
      return;
    }

    final rm = V3MasterRealtimeManager.instance;
    if (rm.v3GpsRasporedCache.isEmpty || rm.putniciCache.isEmpty) {
      try {
        await rm.initV3();
      } catch (_) {
        // Realtime manager već loguje detalje; ekran će prikazati šta je dostupno
      }
    }

    if (mounted) {
      _rebuild();
      V3StateUtils.safeSetState(this, () => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuild();
      });
    }
  }

  void _rebuild() {
    final vozac = _efektivniVozac;
    if (vozac == null) return;
    final rm = V3MasterRealtimeManager.instance;

    String operativnaVreme(Map<String, dynamic> row) {
      return ((row['dodeljeno_vreme'] as String?) ?? (row['zeljeno_vreme'] as String?) ?? '');
    }

    String rowGrad(Map<String, dynamic> row) => (row['grad']?.toString().toUpperCase() ?? '');

    String rowDatum(Map<String, dynamic> row) => V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '');

    final inheritedVozacByTermin = _buildInheritedVozacByTermin();
    final selectedVNorm = _normV(_selectedVreme);

    // 1. Moji termini za ovaj datum (iz v3_gps_raspored)
    _mojiTermini = rm.v3GpsRasporedCache.values
        .where(
          (r) =>
              _effectiveVozacIdForRow(r, inheritedVozacByTermin) == vozac.id &&
              rowDatum(r) == _selectedDatumIso &&
              _isGpsRowEligible(r),
        )
        .toList();

    // Ako selektovani grad/vreme ne odgovara nijednom terminu, auto-select i ponovi rebuild
    final terminPostoji = _mojiTermini.any(
        (t) => t['grad']?.toString().toUpperCase() == _selectedGrad && _normV(t['vreme']?.toString()) == selectedVNorm);

    if (!terminPostoji) {
      final stariGrad = _selectedGrad;
      final staroVreme = _selectedVreme;
      _selectClosestTermin();
      final terminPromenjen = _selectedGrad != stariGrad || _selectedVreme != staroVreme;
      if (terminPromenjen && _selectedVreme.isNotEmpty) {
        // Pronašao bliži termin — odmah ponovi rebuild sa novim vrednostima
        _rebuild();
        return;
      }
      // Nema termina za ovaj dan — prikaži prazno
      V3StateUtils.safeSetState(this, () => _mojiPutnici = []);
      return;
    }

    // 2. Putnici za ovaj dan/grad/vreme:
    //    NOVA LOGIKA: Direktno iz v3_gps_raspored unified tabele

    // Putnici iz v3_gps_raspored za ovog vozača i ovaj termin
    final terminPutnici = rm.v3GpsRasporedCache.values.where((r) =>
        _effectiveVozacIdForRow(r, inheritedVozacByTermin) == vozac.id &&
        rowDatum(r) == _selectedDatumIso &&
        rowGrad(r) == _selectedGrad &&
        _normV(r['vreme']?.toString()) == selectedVNorm &&
        r['putnik_id'] != null &&
        _isGpsRowEligible(r));

    // Putnici individualno dodijeljeni OVOM vozaču (v3_gps_raspored) - override
    final individualniOvajVozac = rm.v3GpsRasporedCache.values.where((r) =>
        (r['vozac_id']?.toString() ?? '').trim() == vozac.id &&
        rowDatum(r) == _selectedDatumIso &&
        rowGrad(r) == _selectedGrad &&
        _normV(r['vreme']?.toString()) == selectedVNorm &&
        _isGpsRowEligible(r));

    // Unija putnik_id-eva (prioritet: individualni override > termin)
    final individualniSet = individualniOvajVozac.map((r) => r['putnik_id']?.toString()).whereType<String>().toSet();
    final svePutnikIds = <String>{
      ...individualniSet,
      ...terminPutnici
          .map((r) => r['putnik_id']?.toString())
          .whereType<String>()
          .where((id) => !individualniSet.contains(id)),
    };

    int? extractRouteOrder(Map<String, dynamic> row) {
      final value = row['route_order'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final routeOrderByPutnik = <String, int?>{};
    final entryIdByPutnik = <String, String>{};
    for (final row in terminPutnici) {
      final putnikId = row['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) continue;
      routeOrderByPutnik[putnikId] ??= extractRouteOrder(row);
      final entryId = row['id']?.toString();
      if (entryId != null && entryId.isNotEmpty) {
        entryIdByPutnik.putIfAbsent(putnikId, () => entryId);
      }
    }
    for (final row in individualniOvajVozac) {
      final putnikId = row['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) continue;
      routeOrderByPutnik[putnikId] = extractRouteOrder(row) ?? routeOrderByPutnik[putnikId];
      final entryId = row['id']?.toString();
      if (entryId != null && entryId.isNotEmpty) {
        entryIdByPutnik[putnikId] = entryId;
      }
    }

    // 3. Za svakog putnika izgradimo _PutnikEntry iz operativna_nedelja
    final putnici = <_PutnikEntry>[];
    for (final putnikId in svePutnikIds) {
      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;
      final putnik = V3Putnik.fromJson(putnikData);

      // Pronađi entry iz operativna_nedelja za ovog putnika
      V3OperativnaNedeljaEntry? entry;
      Map<String, dynamic>? matchedEntryData;
      final exactEntryId = entryIdByPutnik[putnikId];
      if (exactEntryId != null && exactEntryId.isNotEmpty) {
        matchedEntryData = rm.operativnaNedeljaCache[exactEntryId];
      }

      if (matchedEntryData == null) {
        DateTime? bestUpdatedAt;
        for (final r in rm.operativnaNedeljaCache.values) {
          if (r['aktivno'] != true) continue;
          if (r['putnik_id']?.toString() != putnikId) continue;
          if (V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') != _selectedDatumIso) continue;
          if (r['grad']?.toString().toUpperCase() != _selectedGrad) continue;
          if (_normV(operativnaVreme(r)) != selectedVNorm) continue;

          final updatedAtRaw = r['updated_at']?.toString();
          final updatedAt = updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
          if (matchedEntryData == null) {
            matchedEntryData = r;
            bestUpdatedAt = updatedAt;
            continue;
          }
          if (updatedAt != null && (bestUpdatedAt == null || updatedAt.isAfter(bestUpdatedAt))) {
            matchedEntryData = r;
            bestUpdatedAt = updatedAt;
          }
        }
      }

      if (matchedEntryData != null) {
        entry = V3OperativnaNedeljaEntry.fromJson(matchedEntryData);
      }

      putnici.add(
        _PutnikEntry(
          putnik: putnik,
          entry: entry,
          routeOrder: routeOrderByPutnik[putnikId],
        ),
      );
    }

    V3StateUtils.safeSetState(this, () => _mojiPutnici = _sortPutniciForDisplay(putnici));
  }

  void _selectClosestTermin() {
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    String? bestVreme;
    String? bestGrad;
    int minDiff = 9999;

    // Kandidati: samo termini (putnici se izvlače automatski iz operativna_nedelja)
    final kandidati = <Map<String, dynamic>>[
      ..._mojiTermini,
    ];

    for (final t in kandidati) {
      final grad = t['grad']?.toString().toUpperCase() ?? '';
      final vreme = t['vreme']?.toString() ?? '';
      if (vreme.isEmpty) continue;
      final tp = vreme.split(':');
      if (tp.length < 2) continue;
      final mins = (int.tryParse(tp[0]) ?? 0) * 60 + (int.tryParse(tp[1]) ?? 0);
      final diff = (mins - current).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestVreme = V3DanHelper.formatVreme(int.tryParse(tp[0]) ?? 0, int.tryParse(tp[1]) ?? 0);
        bestGrad = grad;
      }
    }
    if (bestVreme != null && bestGrad != null) {
      _selectedVreme = bestVreme;
      _selectedGrad = bestGrad;
    }
  }

  String get _selectedDay => V3DanHelper.fullName(_selectedDate);

  String get _selectedDatumIso {
    return V3DanHelper.toIsoDate(_selectedDate);
  }

  void _onPolazakChanged(String grad, String vreme) {
    setState(() {
      _selectedGrad = grad;
      _selectedVreme = vreme;
    });
    _rebuild();
  }

  void _onDaySelected(String day) {
    final vozac = _efektivniVozac;
    if (vozac == null) return;

    final dayAbbr = V3DanHelper.normalizeToWorkdayAbbr(V3DanHelper.dayAbbrFromFullName(day));
    final dayIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(
      dayAbbr,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );
    final parsedDayDate = DateTime.tryParse(dayIso);
    if (parsedDayDate == null) return;
    final selectedDayDate = V3DanHelper.dateOnly(parsedDayDate);
    final rm = V3MasterRealtimeManager.instance;
    final inheritedVozacByTermin = _buildInheritedVozacByTermin();

    final dayTerms = rm.v3GpsRasporedCache.values
        .where((row) =>
            _effectiveVozacIdForRow(row, inheritedVozacByTermin) == vozac.id &&
            V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') == dayIso &&
            _isGpsRowEligible(row))
        .toList();

    final currentVremeNorm = _normV(_selectedVreme);
    final hasCurrentSelection = dayTerms.any(
      (row) =>
          (row['grad']?.toString().toUpperCase() ?? '') == _selectedGrad &&
          _normV(row['vreme']?.toString()) == currentVremeNorm,
    );

    Map<String, dynamic>? bestTerm;
    if (dayTerms.isNotEmpty && !hasCurrentSelection) {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      dayTerms.sort((a, b) {
        final aTime = _normV(a['vreme']?.toString());
        final bTime = _normV(b['vreme']?.toString());
        final aDiff = _timeToMinutes(aTime) < 0 ? 99999 : (_timeToMinutes(aTime) - nowMinutes).abs();
        final bDiff = _timeToMinutes(bTime) < 0 ? 99999 : (_timeToMinutes(bTime) - nowMinutes).abs();
        if (aDiff != bDiff) return aDiff.compareTo(bDiff);
        final ga = a['grad']?.toString().toUpperCase() ?? '';
        final gb = b['grad']?.toString().toUpperCase() ?? '';
        final byGrad = ga.compareTo(gb);
        if (byGrad != 0) return byGrad;
        return aTime.compareTo(bTime);
      });
      bestTerm = dayTerms.first;
    }

    if (!mounted) return;
    setState(() {
      _selectedDate = selectedDayDate;

      if (bestTerm != null) {
        _selectedGrad = bestTerm['grad']?.toString().toUpperCase() ?? _selectedGrad;
        _selectedVreme = _normV(bestTerm['vreme']?.toString());
      } else if (dayTerms.isEmpty) {
        _selectedVreme = '';
      }

      if (dayTerms.isNotEmpty && _selectedVreme.isEmpty) {
        final fallback = dayTerms.first;
        _selectedGrad = fallback['grad']?.toString().toUpperCase() ?? _selectedGrad;
        _selectedVreme = _normV(fallback['vreme']?.toString());
      }
    });

    _rebuild();
  }

  Future<void> _openMapa() async {
    await V3TelefonHelper.otvoriHereWeGoAppOnly(this, context);
  }

  Future<void> _logout() async {
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Logout',
      message: 'Da li ste sigurni da želite da se odjavite?',
      confirmText: 'Logout',
      cancelText: 'Otkaži',
      isDangerous: true,
    );
    if (ok == true && mounted) {
      V3VozacService.currentVozac = null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
        (r) => false,
      );
    }
  }

  int _getPutnikCount(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return 0;

    final inheritedVozacByTermin = _buildInheritedVozacByTermin();
    final vremeNorm = _normV(vreme);
    final gradUp = grad.toUpperCase();

    int parseBrojMesta(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 1;
    }

    // Broji sva mesta za redove koji efektivno pripadaju ovom vozaču
    return rm.v3GpsRasporedCache.values
        .where((r) =>
            _effectiveVozacIdForRow(r, inheritedVozacByTermin) == vozac.id &&
            V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') == _selectedDatumIso &&
            r['grad']?.toString().toUpperCase() == gradUp &&
            _normV(r['vreme']?.toString()) == vremeNorm &&
            r['putnik_id'] != null &&
            _isGpsRowActiveForCount(r))
        .fold<int>(0, (sum, r) => sum + parseBrojMesta(r['broj_mesta']));
  }

  Future<void> _toggleTracking() async {
    final vozac = _efektivniVozac;
    if (vozac == null) return;

    if (!_isTracking) {
      final canContinue = await _ensureDriverLocationDisclosure();
      if (!canContinue) return;

      // 1. START FOREGROUND GPS TRACKING SA PERSISTENT NOTIFICATION
      V3StateUtils.safeSetState(this, () => _isTracking = true);

      try {
        // Pokreni foreground GPS service sa notification
        final success = await V3ForegroundGpsService.startTracking(
          vozacId: vozac.id,
          vozacIme: vozac.imePrezime ?? 'Vozač',
          polazakVreme: '$_selectedGrad $_selectedVreme',
          putnici: _optimizacijaPutnici().map((entry) => entry.putnik).toList(),
          grad: _selectedGrad,
        );

        if (success) {
          await V3VozacLokacijaService.postaviAktivnost(vozac.id, true);
          await V3ForegroundGpsService.syncTrackingStatus(
            vozacId: vozac.id,
            grad: _selectedGrad,
            polazakVreme: _selectedVreme,
            gpsStatus: 'tracking',
            datumIso: _selectedDatumIso,
          );

          if (_mojiPutnici.isNotEmpty) {
            await _optimizujRutu(reason: 'tracking_start');
          }

          if (mounted) {
            V3AppSnackBar.success(
                context, '📍 GPS tracking pokrenut sa persistent notification! Putnici dobijaju realtime lokaciju.');
          }
        } else {
          V3StateUtils.safeSetState(this, () => _isTracking = false);
          if (mounted) {
            V3AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga. Provjerite dozvole u Settings.');
          }
        }
      } catch (e) {
        V3StateUtils.safeSetState(this, () => _isTracking = false);
        if (mounted) {
          V3AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga: $e');
        }
      }
    } else {
      // 2. STOP FOREGROUND GPS TRACKING
      V3StateUtils.safeSetState(this, () => _isTracking = false);

      // Zaustavi foreground service i notification
      await V3ForegroundGpsService.stopTracking();
      await V3ForegroundGpsService.syncTrackingStatus(
        vozacId: vozac.id,
        grad: _selectedGrad,
        polazakVreme: _selectedVreme,
        gpsStatus: 'pending',
        datumIso: _selectedDatumIso,
      );

      _lastOptimizationMeta = const {};

      if (mounted) {
        V3AppSnackBar.warning(context, '⚠️ GPS tracking zaustavljen - notification uklonjena');
      }
    }
  }

  Future<bool> _ensureDriverLocationDisclosure() async {
    final locationWhenInUse = await Permission.location.status;

    if (locationWhenInUse.isGranted) {
      return true;
    }

    if (mounted) {
      V3AppSnackBar.warning(
        context,
        '⚠️ GPS dozvola nije odobrena. Ulogujte se ponovo kao vozač ili uključite dozvolu u Settings.',
      );
    }
    return false;
  }

  Future<void> _optimizujRutu({
    bool silent = false,
    String reason = 'manual',
  }) async {
    final putniciZaOptimizaciju = _optimizacijaPutnici();
    if (putniciZaOptimizaciju.isEmpty) return;

    if (_isOptimizingRoute) return;

    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return;

    _isOptimizingRoute = true;

    try {
      final data = _buildOptimizationData(putniciZaOptimizaciju);

      final driverPosition = await _resolveDriverPositionForOptimization(
        vozacId: vozac.id,
        silent: silent,
      );
      if (driverPosition == null) return;

      final res = await _optimizeRouteWithOsrm(
        data: data,
        driverLat: driverPosition['lat']!,
        driverLng: driverPosition['lng']!,
      );

      if (res.success && res.optimizedData != null) {
        await _persistRouteOrderToOperativna(res.optimizedData!);

        final orderByEntryId = _buildRouteOrderMapByEntryId(res.optimizedData!);
        _applyOptimizedRouteOrderToState(orderByEntryId);

        final skippedCount = _countSkippedRouteOrders(res.optimizedData!);

        _updateLastOptimizationMeta(
          reason: reason,
          engine: (res.metadata?['engine']?.toString() ?? 'osrm'),
          optimizedCount: orderByEntryId.values.whereType<int>().length,
          eligibleCount: putniciZaOptimizaciju.length,
          skippedCount: skippedCount,
          currentPosition: driverPosition,
        );

        if (!silent && mounted) {
          V3AppSnackBar.success(context, res.message);
        }
      } else if (!silent && mounted) {
        V3AppSnackBar.warning(context, res.message);
      }
    } finally {
      _isOptimizingRoute = false;
    }
  }

  List<Map<String, dynamic>> _buildOptimizationData(List<_PutnikEntry> putnici) {
    return putnici.map((entry) => {'putnik': entry.putnik, 'entry': entry.entry}).toList();
  }

  Future<Map<String, double>?> _resolveDriverPositionForOptimization({
    required String vozacId,
    required bool silent,
  }) async {
    final gpsPosition = await _getCurrentDriverPosition(vozacId);
    final driverLat = gpsPosition?['lat'] as double?;
    final driverLng = gpsPosition?['lng'] as double?;

    if (driverLat == null || driverLng == null) {
      if (!silent && mounted) {
        V3AppSnackBar.warning(context, 'OSRM optimizacija zahteva aktivan GPS vozača.');
      }
      return null;
    }

    return {
      'lat': driverLat,
      'lng': driverLng,
    };
  }

  Future<V3NavigationResult> _optimizeRouteWithOsrm({
    required List<Map<String, dynamic>> data,
    required double driverLat,
    required double driverLng,
  }) {
    return V3SmartNavigationService.optimizeV3Route(
      data: data,
      fromCity: _selectedGrad,
      driverLat: driverLat,
      driverLng: driverLng,
    );
  }

  Map<String, int?> _buildRouteOrderMapByEntryId(List<Map<String, dynamic>> optimizedData) {
    final orderByEntryId = <String, int?>{};

    for (final item in optimizedData) {
      final entry = item['entry'] as V3OperativnaNedeljaEntry?;
      if (entry == null || entry.id.isEmpty) continue;
      orderByEntryId[entry.id] = _parseRouteOrder(item['route_order']);
    }

    return orderByEntryId;
  }

  void _applyOptimizedRouteOrderToState(Map<String, int?> orderByEntryId) {
    setState(() {
      final merged = _mojiPutnici.map((entry) {
        if (_isExcludedFromOptimization(entry)) {
          return _PutnikEntry(putnik: entry.putnik, entry: entry.entry, routeOrder: null);
        }

        final entryId = entry.entry?.id ?? '';
        return _PutnikEntry(
          putnik: entry.putnik,
          entry: entry.entry,
          routeOrder: entryId.isNotEmpty ? orderByEntryId[entryId] : null,
        );
      }).toList();

      _mojiPutnici = _sortPutniciForDisplay(merged);
    });
  }

  int _countSkippedRouteOrders(List<Map<String, dynamic>> optimizedData) {
    return optimizedData.where((item) => _parseRouteOrder(item['route_order']) == null).length;
  }

  int? _parseRouteOrder(dynamic rawOrder) {
    if (rawOrder is int) return rawOrder;
    if (rawOrder is num) return rawOrder.toInt();
    return int.tryParse(rawOrder?.toString() ?? '');
  }

  Future<void> _persistRouteOrderToOperativna(List<Map<String, dynamic>> optimizedData) async {
    try {
      final vozac = V3VozacService.currentVozac;
      if (vozac != null) {
        await V3TripStopsService.upsertStopsForTermin(
          vozacId: vozac.id,
          datumIso: _selectedDatumIso,
          grad: _selectedGrad,
          polazakVreme: _selectedVreme,
          optimizedData: optimizedData,
          source: 'osrm',
        );
      }
    } catch (e) {
      debugPrint('[V3VozacScreen] _persistRouteOrderToOperativna error: $e');
    }
  }

  /// Dobija trenutnu GPS poziciju vozača iz baze podataka
  Future<Map<String, dynamic>?> _getCurrentDriverPosition(String vozacId) async {
    try {
      final response = V3VozacLokacijaService.getVozacLokacijaSync(vozacId, onlyActive: true);

      final lat = (response?['lat'] as num?)?.toDouble() ?? double.tryParse(response?['lat']?.toString() ?? '');
      final lng = (response?['lng'] as num?)?.toDouble() ?? double.tryParse(response?['lng']?.toString() ?? '');

      if (response != null && lat != null && lng != null) {
        return {
          'lat': lat,
          'lng': lng,
          'updated_at': response['updated_at'],
        };
      }
    } catch (e) {
      debugPrint('[V3VozacScreen] _getCurrentDriverPosition error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vozac = V3VozacService.currentVozac;

    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: V3ContainerUtils.backgroundContainer(
            gradient: V3ThemeManager().currentGradient,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }

    // Termini za BottomNavBar — iz v3_gps_raspored
    final vozacId = _efektivniVozac?.id ?? '';
    final rm = V3MasterRealtimeManager.instance;
    final inheritedVozacByTermin = _buildInheritedVozacByTermin();
    String normV(String? v) {
      if (v == null || v.isEmpty) return '';
      final p = v.split(':');
      if (p.length >= 2) {
        final hour = int.tryParse(p[0]) ?? 0;
        final minute = int.tryParse(p[1]) ?? 0;
        return V3DanHelper.formatVreme(hour, minute);
      }
      return v;
    }

    final bcVremenaSet = <String>{};
    final vsVremenaSet = <String>{};
    for (final t in _mojiTermini) {
      final g = t['grad']?.toString().toUpperCase() ?? '';
      final v = normV(t['vreme']?.toString());
      if (v.isEmpty) continue;
      if (g == 'BC') bcVremenaSet.add(v);
      if (g == 'VS') vsVremenaSet.add(v);
    }
    for (final r in rm.v3GpsRasporedCache.values) {
      if (_effectiveVozacIdForRow(r, inheritedVozacByTermin) != vozacId) continue;
      if (V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') != _selectedDatumIso) continue;
      if (!_isGpsRowEligible(r)) continue;
      final g = r['grad']?.toString().toUpperCase() ?? '';
      final v = normV(r['vreme']?.toString());
      if (v.isEmpty) continue;
      if (g == 'BC') bcVremenaSet.add(v);
      if (g == 'VS') vsVremenaSet.add(v);
    }
    final bcVremenaToShow = bcVremenaSet.toList()..sort();
    final vsVremenaToShow = vsVremenaSet.toList()..sort();
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final headerScaleExtra = (textScaleFactor - 1.0).clamp(0.0, 0.7).toDouble();
    final appBarHeight = 104 + (headerScaleExtra * 18);
    final appBarButtonHeight = 30 + (headerScaleExtra * 6);
    final aktivnaSedmicaAnchor = V3DanHelper.schedulingWeekAnchor();
    final ponedeljak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pon', anchor: aktivnaSedmicaAnchor);
    final petak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pet', anchor: aktivnaSedmicaAnchor);
    final aktivnaSedmica =
        'Aktivna sedmica: ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

    return StreamBuilder<int>(
      stream: rm.v3StreamFromCache<int>(
        tables: const ['v3_operativna_nedelja', 'v3_putnici', 'v3_vozaci', 'v3_adrese', 'v3_kapacitet_slots'],
        build: () => DateTime.now().microsecondsSinceEpoch,
      ),
      builder: (context, snapshot) {
        final tick = snapshot.data;
        if (tick != null && tick != _lastRealtimeTick) {
          _lastRealtimeTick = tick;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _rebuild();
          });
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: V3ContainerUtils.backgroundContainer(
            gradient: V3ThemeManager().currentGradient,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(appBarHeight),
                child: V3ContainerUtils.styledContainer(
                  backgroundColor: Theme.of(context).glassContainer,
                  border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                  padding: EdgeInsets.zero,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            aktivnaSedmica,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          // ── Red 1: Datum | Dan (V2 digitalni prikaz) ──
                          _buildDigitalDateDisplay(context, vozac),
                          const SizedBox(height: 6),
                          // ── Red 2: Kompaktni gumbi (V2 stil h=30) ──
                          Row(
                            children: [
                              // START / STOP
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: _isTracking ? 'STOP' : 'START',
                                  color: _isTracking ? Colors.red : Colors.green,
                                  height: appBarButtonHeight,
                                  onTap: _toggleTracking,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // MAPA
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: 'MAPA',
                                  color: Colors.blue,
                                  height: appBarButtonHeight,
                                  onTap: _openMapa,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Dan picker
                              Expanded(
                                flex: 2,
                                child: _buildDanPickerBtn(context, height: appBarButtonHeight),
                              ),
                              const SizedBox(width: 4),
                              // ⚙️ Popup meni — šifra + logout
                              PopupMenuButton<String>(
                                onSelected: (val) async {
                                  if (val == 'tema') {
                                    await V3ThemeManager().nextTheme();
                                    V3StateUtils.safeSetState(this, () {});
                                    if (!mounted) return;
                                    V3AppSnackBar.info(context, '🎨 Tema promenjena');
                                  } else if (val == 'sifra') {
                                    if (!mounted || vozac == null) return;
                                    V3NavigationUtils.pushScreen<void>(
                                      context,
                                      V3PromenaSifreScreen(vozacIme: vozac.imePrezime),
                                    );
                                  } else if (val == 'logout') {
                                    _logout();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'tema',
                                    child: Row(children: [
                                      Icon(Icons.palette, color: Colors.purpleAccent),
                                      SizedBox(width: 8),
                                      Text('Promeni temu'),
                                    ]),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'sifra',
                                    child: Row(children: [
                                      Icon(Icons.lock_reset, color: Colors.blueAccent),
                                      SizedBox(width: 8),
                                      Text('Promeni šifru'),
                                    ]),
                                  ),
                                  PopupMenuItem(
                                    value: 'logout',
                                    child: Row(children: [
                                      Icon(Icons.logout, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Logout'),
                                    ]),
                                  ),
                                ],
                                padding: EdgeInsets.zero,
                                child: V3ContainerUtils.iconContainer(
                                  width: V3ContainerUtils.responsiveHeight(context, 30),
                                  height: V3ContainerUtils.responsiveHeight(context, 30),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  borderRadiusGeometry: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: ValueListenableBuilder<String>(
                valueListenable: navBarTypeNotifier,
                builder: (context, navType, _) {
                  int? getKapacitet(String grad, String vreme) {
                    final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
                    return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
                  }

                  if (navType == 'zimski') {
                    return V3BottomNavBarZimski(
                      sviPolasci: _sviPolasci,
                      selectedGrad: _selectedGrad,
                      selectedVreme: _selectedVreme,
                      onPolazakChanged: _onPolazakChanged,
                      getPutnikCount: _getPutnikCount,
                      getKapacitet: getKapacitet,
                      bcVremena: bcVremenaToShow,
                      vsVremena: vsVremenaToShow,
                    );
                  } else if (navType == 'praznici') {
                    return V3BottomNavBarPraznici(
                      sviPolasci: _sviPolasci,
                      selectedGrad: _selectedGrad,
                      selectedVreme: _selectedVreme,
                      onPolazakChanged: _onPolazakChanged,
                      getPutnikCount: _getPutnikCount,
                      getKapacitet: getKapacitet,
                      bcVremena: bcVremenaToShow,
                      vsVremena: vsVremenaToShow,
                    );
                  }
                  return V3BottomNavBarLetnji(
                    sviPolasci: _sviPolasci,
                    selectedGrad: _selectedGrad,
                    selectedVreme: _selectedVreme,
                    onPolazakChanged: _onPolazakChanged,
                    getPutnikCount: _getPutnikCount,
                    getKapacitet: getKapacitet,
                    bcVremena: bcVremenaToShow,
                    vsVremena: vsVremenaToShow,
                  );
                },
              ),
              body: _buildBody(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final redniBrojevi = <int>[];
    var tekuciRedniBroj = 1;
    for (final putnikEntry in _mojiPutnici) {
      redniBrojevi.add(tekuciRedniBroj);
      tekuciRedniBroj += putnikEntry.entry?.brojMesta ?? 1;
    }

    return Column(
      children: [
        // Forced update gate
        const V3UpdateBanner(),
        // Lista putnika
        Expanded(
          child: _mojiPutnici.isEmpty
              ? Center(
                  child: V3ContainerUtils.styledContainer(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Theme.of(context).glassContainer,
                    border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox, color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Nema putnika za $_selectedGrad $_selectedVreme',
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  itemCount: _mojiPutnici.length,
                  itemBuilder: (context, index) {
                    final pz = _mojiPutnici[index];
                    return V3PutnikCard(
                      putnik: pz.putnik,
                      entry: pz.entry,
                      redniBroj: redniBrojevi[index],
                      onChanged: _rebuild,
                      isExcludedFromOptimization: _isExcludedFromOptimization(pz),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── V2 stil: digitalni datum prikaz ──
  Widget _buildDigitalDateDisplay(BuildContext context, dynamic vozac) {
    final selectedDate = _selectedDate;
    final dayName = _selectedDay.trim().toUpperCase();
    final dateStr = DateFormat('dd.MM.yy').format(selectedDate);
    final vozacBoja = _getVozacBojaRaw(vozac);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        Text(
          dayName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: vozacBoja,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        V3LiveClockText(
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ],
    );
  }

  // ── Kompaktni AppBar dugme (label, h=30) ──
  Widget _buildAppBarBtn({
    required BuildContext context,
    required String label,
    required Color color,
    required double height,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: V3ContainerUtils.styledContainer(
        height: height,
        backgroundColor: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        padding: EdgeInsets.zero,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ── Dan picker dugme (AppBar stil) ──
  Widget _buildDanPickerBtn(BuildContext context, {required double height}) {
    return InkWell(
      onTap: _showDanDialog,
      borderRadius: BorderRadius.circular(8),
      child: V3ContainerUtils.styledContainer(
        height: height,
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        padding: EdgeInsets.zero,
        child: Center(
          child: Text(
            _selectedDay.substring(0, 3).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _showDanDialog() {
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Izaberi dan'),
        children: V3DanHelper.workdayNames.map((dan) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, dan),
            child: Text(dan, style: TextStyle(fontWeight: dan == _selectedDay ? FontWeight.bold : FontWeight.normal)),
          );
        }).toList(),
      ),
    ).then((dan) {
      if (dan != null && mounted) {
        _onDaySelected(dan);
      }
    });
  }

  // Puna boja vozača (bez alpha skaliranja) — za tekst/border
  Color _getVozacBojaRaw(dynamic v3Vozac) {
    if (v3Vozac == null) return Colors.white;
    final hex = v3Vozac.boja?.toString();
    if (hex == null || hex.isEmpty) return Colors.white;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  // Timer funkcionalnost uklonjena - koriste se database trigger-i i CRON job-ovi
  // za automatsku optimizaciju na server strani
}

/// Helper klasa — putnik + njegov operativni entry
class _PutnikEntry {
  final V3Putnik putnik;
  final V3OperativnaNedeljaEntry? entry;
  final int? routeOrder;
  const _PutnikEntry({required this.putnik, this.entry, this.routeOrder});
}
