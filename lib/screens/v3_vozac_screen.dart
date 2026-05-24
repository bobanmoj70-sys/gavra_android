import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_address_coordinate_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_driver_push_notification_service.dart';
import '../services/v3/v3_navigation_app_launcher_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_putnik_adresa_resolver_service.dart';
import '../services/v3/v3_route_models.dart';
import '../services/v3/v3_route_waypoint_resolver_service.dart';
import '../services/v3/v3_trenutna_dodela_service.dart';
import '../services/v3/v3_trenutna_dodela_slot_service.dart';
import '../services/v3/v3_vozac_location_tracking_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_geo_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_time_utils.dart';
import '../widgets/v3_bottom_nav_bar_slotovi.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_neradni_dani_banner.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_welcome_screen.dart';

/// V3 Vozač Screen - prikazuje dodjeljene termine i putnike
/// iz cache-a građenog iz v3_operativna_nedelja.
class V3VozacScreen extends StatefulWidget {
  const V3VozacScreen({super.key});

  @override
  State<V3VozacScreen> createState() => _V3VozacScreenState();
}

class _V3VozacScreenState extends State<V3VozacScreen> with WidgetsBindingObserver {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _biometricPromptChoicePrefix = 'v3_biometric_prompt_choice_';

  DateTime _selectedDate = V3DanHelper.dateOnly(DateTime.now());
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  bool _isLoading = true;
  bool _loadingDodela = false;
  StreamSubscription<int>? _trenutnaDodelaRevisionSub;
  final V3RouteWaypointResolverService _routeWaypointResolverService = V3RouteWaypointResolverService();
  int? _lastRealtimeTick;

  /// Efektivni vozač
  dynamic get _efektivniVozac => V3VozacService.currentVozac;

  // Moji termini (izvor: v3_operativna_nedelja)
  List<Map<String, dynamic>> _mojiTermini = [];

  // Moji putnici (izvor: v3_operativna_nedelja)
  List<_PutnikEntry> _mojiPutnici = [];
  Set<String> _assignedOperativnaIds = <String>{};
  List<Map<String, String>> _assignedSlotRows = <Map<String, String>>[];
  bool _autoStopInProgress = false;
  bool _isNavigating = false;
  final List<String> _optimizedPutnikIds = [];
  final Map<String, int> _etaSecondsCache = {};
  bool _hasSentRouteToMap = false;
  bool _mapResyncInFlight = false;
  String _lastSentRouteSignature = '';

  void _resetMapSyncState() {
    _hasSentRouteToMap = false;
    _mapResyncInFlight = false;
    _lastSentRouteSignature = '';
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  bool _isRowEligible(Map<String, dynamic> row) {
    return V3StatusPolicy.canAssign(
      status: row['status']?.toString(),
      otkazanoAt: row['otkazano_at'],
      pokupljenAt: row['pokupljen_at'],
    );
  }

  Future<void> _reloadTrenutnaDodelaForVozac() async {
    final vozac = _efektivniVozac;
    if (vozac == null) {
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      return;
    }

    final vozacAuthId = (vozac.id?.toString() ?? '').trim();
    if (vozacAuthId.isEmpty) {
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      return;
    }

    _loadingDodela = true;
    try {
      _assignedOperativnaIds = await V3TrenutnaDodelaService.loadActiveTerminIds(vozacId: vozacAuthId);
      _assignedSlotRows = await V3TrenutnaDodelaSlotService.loadActiveSlotsForVozac(vozacId: vozacAuthId);
    } catch (e) {
      debugPrint('[V3VozacScreen] _reloadTrenutnaDodelaForVozac error: $e');
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
    } finally {
      _loadingDodela = false;
    }
  }

  void _startTrenutnaDodelaRealtime() {
    final vozac = _efektivniVozac;
    final vozacAuthId = (vozac?.id?.toString() ?? '').trim();
    if (vozacAuthId.isEmpty) return;

    _trenutnaDodelaRevisionSub?.cancel();
    _trenutnaDodelaRevisionSub = V3MasterRealtimeManager.instance.tablesRevisionStream(const [
      V3TrenutnaDodelaService.tableName,
      V3TrenutnaDodelaSlotService.tableName,
    ]).listen((_) {
      unawaited(_refreshDodelaFromRealtime());
    });
  }

  Future<void> _refreshDodelaFromRealtime() async {
    if (!mounted) return;
    await _reloadTrenutnaDodelaForVozac();
    if (!mounted) return;
    _rebuild();
  }

  List<Map<String, dynamic>> _assignedOperativnaRows({
    String? datumIso,
    String? grad,
    String? vreme,
    bool onlyEligible = false,
  }) {
    final rm = V3MasterRealtimeManager.instance;
    final trazeniDatum = datumIso?.trim() ?? '';
    final trazeniGrad = grad?.trim().toUpperCase() ?? '';
    final trazenoVreme = V3TimeUtils.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final operativnaId in _assignedOperativnaIds) {
      final raw = rm.operativnaNedeljaCache[operativnaId] ?? rm.operativnaAssignedCache[operativnaId];
      if (raw == null) continue;

      final row = Map<String, dynamic>.from(raw);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];

      if (trazeniDatum.isNotEmpty) {
        final rowDatum = V3DateUtils.parseIsoDatePart(row['datum'] as String? ?? '');
        if (rowDatum != trazeniDatum) continue;
      }

      if (trazeniGrad.isNotEmpty) {
        final rowGrad = row['grad']?.toString().toUpperCase() ?? '';
        if (rowGrad != trazeniGrad) continue;
      }

      if (trazenoVreme.isNotEmpty) {
        final rowVreme = V3TimeUtils.normalizeToHHmm(row['vreme']?.toString());
        if (rowVreme != trazenoVreme) continue;
      }

      if (onlyEligible && !_isRowEligible(row)) continue;
      rows.add(row);
    }

    return rows;
  }

  List<Map<String, dynamic>> _assignedSlotTermRows({
    String? datumIso,
    String? grad,
    String? vreme,
  }) {
    final trazeniDatum = (datumIso ?? '').trim();
    final trazeniGrad = (grad ?? '').trim().toUpperCase();
    final trazenoVreme = V3TimeUtils.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final slot in _assignedSlotRows) {
      final slotDatum = (slot[V3TrenutnaDodelaSlotService.colDatum] ?? '').trim();
      final slotGrad = (slot[V3TrenutnaDodelaSlotService.colGrad] ?? '').trim().toUpperCase();
      final slotVreme = V3TimeUtils.normalizeToHHmm(slot[V3TrenutnaDodelaSlotService.colVreme]);

      if (slotDatum.isEmpty || slotGrad.isEmpty || slotVreme.isEmpty) continue;
      if (trazeniDatum.isNotEmpty && slotDatum != trazeniDatum) continue;
      if (trazeniGrad.isNotEmpty && slotGrad != trazeniGrad) continue;
      if (trazenoVreme.isNotEmpty && slotVreme != trazenoVreme) continue;

      rows.add(<String, dynamic>{
        'id': 'slot|$slotDatum|$slotGrad|$slotVreme',
        'datum': slotDatum,
        'grad': slotGrad,
        'vreme': slotVreme,
        'polazak_at': slotVreme,
      });
    }

    return rows;
  }

  List<_PutnikEntry> _sortPutniciForDisplay(
    List<_PutnikEntry> putnici,
  ) {
    if (_etaSecondsCache.isEmpty) {
      return List<_PutnikEntry>.from(putnici);
    }
    final sorted = List<_PutnikEntry>.from(putnici);
    sorted.sort((a, b) {
      // Završeni (pokupljeni/otkazani) ostaju prepoznati - ali neka prvo ide sveže vreme
      final isCompletedA = _isPutnikEntryCompleted(a);
      final isCompletedB = _isPutnikEntryCompleted(b);
      if (isCompletedA != isCompletedB) {
        return isCompletedA ? 1 : -1;
      }

      final etaA = _etaSecondsCache[a.putnik.id] ?? 999999;
      final etaB = _etaSecondsCache[b.putnik.id] ?? 999999;
      return etaA.compareTo(etaB);
    });
    return sorted;
  }

  void _refreshEtaCacheFromManager() {
    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isEmpty) {
      _etaSecondsCache.clear();
      return;
    }

    final next = <String, int>{};
    final etaRows = V3MasterRealtimeManager.instance.etaResultsCache.values;
    for (final row in etaRows) {
      final rowVozacId = (row['vozac_id']?.toString() ?? '').trim();
      if (rowVozacId != vozacId) continue;

      final putnikId = (row['putnik_id']?.toString() ?? '').trim();
      if (putnikId.isEmpty) continue;

      final etaRaw = row['eta_seconds'];
      int? etaSeconds;
      if (etaRaw is num) {
        etaSeconds = etaRaw.toInt();
      } else if (etaRaw is String) {
        etaSeconds = int.tryParse(etaRaw);
      }
      if (etaSeconds == null || etaSeconds < 0) continue;

      next[putnikId] = etaSeconds;
    }

    _etaSecondsCache
      ..clear()
      ..addAll(next);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDate = V3DanHelper.defaultWorkdayDate();
    // Ako je tracking već aktivan (npr. vozač se vratio back), obnovi state
    _isNavigating = V3VozacLocationTrackingService.instance.isRunning;
    _optimizedPutnikIds.clear(); // Reset optimizacije za novi termin
    _startTrenutnaDodelaRealtime();
    _initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_trenutnaDodelaRevisionSub?.cancel());
    _trenutnaDodelaRevisionSub = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    if (!V3VozacLocationTrackingService.instance.isRunning) return;

    V3VozacLocationTrackingService.instance.stop();
    _isNavigating = false;
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        V3NavigationUtils.pushAndRemoveUntil(context, const V3WelcomeScreen());
      }
      return;
    }

    final rm = V3MasterRealtimeManager.instance;
    if (rm.operativnaAssignedCache.isEmpty || rm.putniciCache.isEmpty) {
      try {
        await rm.initV3();
      } catch (_) {
        // Realtime manager već loguje detalje; ekran će prikazati šta je dostupno
      }
    }

    if (mounted) {
      await _reloadTrenutnaDodelaForVozac();
      _rebuild();
      V3StateUtils.safeSetState(this, () => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuild();
      });
    }
  }

  Future<bool> _ensureGpsPermissionForStart() async {
    final status = await V3VozacLocationTrackingService.instance.checkLocationPrerequisites();
    if (status == V3LocationPrereqStatus.ok) return true;

    if (!mounted) return false;

    switch (status) {
      case V3LocationPrereqStatus.serviceDisabled:
        V3AppSnackBar.warning(context, 'GPS je isključen. Uključi lokaciju na telefonu.');
        break;
      case V3LocationPrereqStatus.denied:
        V3AppSnackBar.warning(context, 'Dozvola za lokaciju je odbijena.');
        break;
      case V3LocationPrereqStatus.deniedForever:
        V3AppSnackBar.warning(context, 'Dozvola za lokaciju je trajno odbijena. Uključi je u Settings.');
        break;
      case V3LocationPrereqStatus.ok:
        break;
    }

    return false;
  }

  Future<void> _startDriverLocationTracking() async {
    final vozacId = (V3VozacService.currentVozac?.id ?? '').toString().trim();
    if (vozacId.isEmpty) return;
    await V3VozacLocationTrackingService.instance.start(vozacId: vozacId);
  }

  bool _isPutnikEntryCompleted(_PutnikEntry item) {
    final entry = item.entry;
    if (entry == null) return false;
    final pokupljen = V3StatusPolicy.isTimestampSet(entry.pokupljenAt);
    final otkazan = V3StatusPolicy.isTimestampSet(entry.otkazanoAt);
    return pokupljen || otkazan;
  }

  bool _shouldAutoStopTracking(List<_PutnikEntry> putnici) {
    if (putnici.isEmpty) return false;
    return putnici.every(_isPutnikEntryCompleted);
  }

  void _maybeAutoStopTrackingForCompletedTermin(List<_PutnikEntry> putnici) {
    if (!V3VozacLocationTrackingService.instance.isRunning) return;
    if (_autoStopInProgress) return;
    if (!_shouldAutoStopTracking(putnici)) return;

    _autoStopInProgress = true;
    unawaited(() async {
      try {
        await _handleStopNavigation();
      } finally {
        _autoStopInProgress = false;
      }
    }());
  }

  void _rebuild() {
    final vozac = _efektivniVozac;
    if (vozac == null) return;
    final rm = V3MasterRealtimeManager.instance;

    final selectedVNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);

    // 1. Moji termini za ovaj datum (izvor dodele: v3_trenutna_dodela)
    final assignedRows = _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      onlyEligible: false,
    );

    final assignedSlotRows = _assignedSlotTermRows(
      datumIso: _selectedDatumIso,
    );

    final termsById = <String, Map<String, dynamic>>{};
    for (final row in assignedRows) {
      final entryId = row['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      termsById[entryId] = row;
    }
    for (final row in assignedSlotRows) {
      final entryId = row['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      termsById.putIfAbsent(entryId, () => row);
    }

    _mojiTermini = termsById.values.toList();

    // Ako selektovani grad/vreme ne odgovara nijednom terminu, izaberi prvi dostupni i ponovi rebuild
    final terminPostoji = _mojiTermini.any((t) =>
        t['grad']?.toString().toUpperCase() == _selectedGrad &&
        V3TimeUtils.normalizeToHHmm(t['vreme']?.toString()) == selectedVNorm);

    if (!terminPostoji) {
      final stariGrad = _selectedGrad;
      final staroVreme = _selectedVreme;
      _selectFirstTermin();
      final terminPromenjen = _selectedGrad != stariGrad || _selectedVreme != staroVreme;
      if (terminPromenjen && _selectedVreme.isNotEmpty) {
        // Izabran prvi dostupan termin — odmah ponovi rebuild sa novim vrednostima
        _rebuild();
        return;
      }
      // Nema termina za ovaj dan — prikaži prazno
      V3StateUtils.safeSetState(this, () => _mojiPutnici = []);
      return;
    }

    // 2. Putnici za ovaj dan/grad/vreme:
    //    Direktno iz izvedenog operativna cache-a, ali dodela isključivo preko v3_trenutna_dodela

    // Putnici iz operativna reda za assigned ID-jeve (putnik-level dodela dolazi iz v3_trenutna_dodela)
    final terminPutnici = _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      grad: _selectedGrad,
      vreme: selectedVNorm,
      onlyEligible: false,
    ).where((r) => r['created_by'] != null);

    // Redovi bez duplikata po operativna ID
    final allSelectedRowsById = <String, Map<String, dynamic>>{};
    for (final row in terminPutnici) {
      final entryId = row['id']?.toString();
      if (entryId == null || entryId.isEmpty) continue;
      allSelectedRowsById.putIfAbsent(entryId, () => row);
    }

    // Isključeno usisavanje svih putnika putem dodeljenog slota da se ne bi
    // mešali putnici ako dva vozača imaju vožnju u isto vreme i grad.
    // Dodeljivanje sada radi strictly preko individualne dodele u _assignedOperativnaIds.

    // 3. Za svaki red izgradimo _PutnikEntry iz operativna_nedelja
    final putnici = <_PutnikEntry>[];
    for (final row in allSelectedRowsById.values) {
      final putnikId = row['created_by']?.toString();
      final putnikData = putnikId != null ? rm.putniciCache[putnikId] : null;
      if (putnikData == null) continue;

      final entryId = row['id']?.toString() ?? '';
      final V3Putnik putnik = V3Putnik.fromJson(putnikData);

      // Pronađi entry iz operativna_nedelja za ovaj red
      V3OperativnaNedeljaEntry? entry;
      Map<String, dynamic>? matchedEntryData;
      if (entryId.isNotEmpty) {
        matchedEntryData = rm.operativnaNedeljaCache[entryId];
      }

      if (matchedEntryData != null) {
        entry = V3OperativnaNedeljaEntry.fromJson(matchedEntryData);
      }

      putnici.add(
        _PutnikEntry(
          putnik: putnik,
          entry: entry,
        ),
      );
    }

    _refreshEtaCacheFromManager();
    final putniciZaPrikaz = _sortPutniciForDisplay(putnici);

    V3StateUtils.safeSetState(this, () {
      _mojiPutnici = putniciZaPrikaz;
      _applyOptimizedOrderToPutnici(); // Zadrzi optimizovan redosled cak i kad stignu realtime podaci
    });

    _maybeAutoStopTrackingForCompletedTermin(putniciZaPrikaz);
  }

  void _selectFirstTermin() {
    if (_mojiTermini.isEmpty) return;

    final first = _mojiTermini.first;
    final grad = first['grad']?.toString().toUpperCase() ?? '';
    final vreme = first['vreme']?.toString() ?? '';
    if (grad.isEmpty || vreme.isEmpty) return;

    final normalized = V3TimeUtils.normalizeToHHmm(vreme);
    if (normalized.isEmpty) return;

    _selectedGrad = grad;
    _selectedVreme = normalized;
  }

  String get _selectedDay => V3DanHelper.fullName(_selectedDate);

  String get _selectedDatumIso {
    return V3DanHelper.toIsoDate(_selectedDate);
  }

  String? get _neradanDanRazlog => getNeradanDanRazlog(datumIso: _selectedDatumIso, grad: _selectedGrad);

  void _onPolazakChanged(String grad, String vreme) {
    setState(() {
      final normalizedGrad = grad.toUpperCase();
      final normalizedVreme = V3TimeUtils.normalizeToHHmm(vreme);
      _selectedGrad = normalizedGrad;
      _selectedVreme = normalizedVreme;
      _resetMapSyncState();
    });
    _rebuild();
  }

  void _onDaySelected(String day) {
    final vozac = _efektivniVozac;
    if (vozac == null) return;
    final previousDate = V3DanHelper.dateOnly(_selectedDate);
    final previousGrad = _selectedGrad;
    final previousVreme = V3TimeUtils.normalizeToHHmm(_selectedVreme);

    final dayAbbr = V3DanHelper.workdayAbbrFromFullName(day);
    final dayIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(
      dayAbbr,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );
    final parsedDayDate = DateTime.tryParse(dayIso);
    if (parsedDayDate == null) return;
    final selectedDayDate = V3DanHelper.dateOnly(parsedDayDate);
    final dayTerms = [
      ..._assignedOperativnaRows(
        datumIso: dayIso,
        onlyEligible: true,
      ),
      ..._assignedSlotTermRows(
        datumIso: dayIso,
      ),
    ];

    final currentVremeNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);
    final hasCurrentSelection = dayTerms.any(
      (row) =>
          (row['grad']?.toString().toUpperCase() ?? '') == _selectedGrad &&
          V3TimeUtils.normalizeToHHmm(row['vreme']?.toString()) == currentVremeNorm,
    );

    Map<String, dynamic>? bestTerm;
    if (dayTerms.isNotEmpty && !hasCurrentSelection) {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      dayTerms.sort((a, b) {
        final aTime = V3TimeUtils.normalizeToHHmm(a['vreme']?.toString());
        final bTime = V3TimeUtils.normalizeToHHmm(b['vreme']?.toString());
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
        _selectedVreme = V3TimeUtils.normalizeToHHmm(bestTerm['vreme']?.toString());
      } else if (dayTerms.isEmpty) {
        _selectedVreme = '';
      }

      if (dayTerms.isNotEmpty && _selectedVreme.isEmpty) {
        final firstTerm = dayTerms.first;
        _selectedGrad = firstTerm['grad']?.toString().toUpperCase() ?? _selectedGrad;
        _selectedVreme = V3TimeUtils.normalizeToHHmm(firstTerm['vreme']?.toString());
      }
      _resetMapSyncState();
    });

    _rebuild();
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
      V3VozacLocationTrackingService.instance.stop();
      final phoneRaw = V3VozacService.currentVozac?.telefon1 ?? '';
      final normalizedPhone = V3ClosedAuthService.normalizePhone(phoneRaw);
      if (normalizedPhone.isNotEmpty) {
        await _secureStorage.delete(key: '$_biometricPromptChoicePrefix$normalizedPhone');
      }

      await V3BiometricService().clearCredentials();
      V3VozacService.currentVozac = null;
      await V3ClosedAuthService.clearManualSmsVozacPhone();
      await V3ClosedAuthService.clearManualSmsPutnikPhone();
      if (!mounted) return;
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

    final vremeNorm = V3TimeUtils.normalizeToHHmm(vreme);
    final gradUp = grad.toUpperCase();

    bool hasActivePutnik(Map<String, dynamic> row) {
      final putnikId = row['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      final putnik = rm.putniciCache[putnikId];
      return putnik != null;
    }

    // Merge: putnik-level dodela + slot putnici (naknadno dodani)
    final rowsById = <String, Map<String, dynamic>>{};

    for (final row in _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      grad: gradUp,
      vreme: vremeNorm,
    ).where(hasActivePutnik)) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) rowsById.putIfAbsent(id, () => row);
    }

    return V3StatusPolicy.countOccupiedSeatsForSlot<Map<String, dynamic>>(
      items: rowsById.values,
      grad: gradUp,
      vreme: vremeNorm,
      includeItem: (row) {
        final putnikId = row['created_by']?.toString() ?? '';
        final tip = (rm.putniciCache[putnikId]?['tip_putnika'] as String?)?.toLowerCase().trim();
        return tip != 'posiljka';
      },
      gradOf: (row) => row['grad']?.toString(),
      vremeOf: (row) => row['vreme']?.toString() ?? row['polazak_at']?.toString(),
      statusOf: (row) => row['status']?.toString(),
      otkazanoAtOf: (row) => row['otkazano_at'],
    );
  }

  String _oppositeGrad(String grad) {
    switch (grad.trim().toUpperCase()) {
      case 'BC':
        return 'VS';
      case 'VS':
        return 'BC';
      default:
        return '';
    }
  }

  Future<V3RouteWaypoint?> _resolveFixedOppositeDestination() async {
    final opposite = _oppositeGrad(_selectedGrad);
    if (opposite.isEmpty) return null;

    // Hardcoded koordinate centara gradova — pouzdanije od Nominatim geocodinga
    final center = V3GeoUtils.gradCenterCoord(opposite);
    if (center != null) {
      return V3RouteWaypoint(
        id: '__fixed_destination_$opposite',
        label: 'Cilj $opposite',
        coordinate: V3RouteCoordinate(latitude: center.lat, longitude: center.lng),
      );
    }

    // Fallback na Nominatim ako grad nije hardcoded
    final cityLabel = V3GeoUtils.gradLabelForGeocoding(opposite);
    final coordinate = await V3AddressCoordinateService.instance.resolveCoordinate(
      adresaId: null,
      fallbackQuery: '$cityLabel, Srbija',
    );
    if (coordinate == null) return null;

    return V3RouteWaypoint(
      id: '__fixed_destination_$opposite',
      label: 'Cilj $opposite',
      coordinate: coordinate,
    );
  }

  String? _resolveAdresaIdForEntry(_PutnikEntry item) {
    final entry = item.entry;
    final grad = (entry?.grad ?? _selectedGrad).trim().toUpperCase();
    final koristiSekundarnu = entry?.koristiSekundarnu ?? false;
    final override = (entry?.adresaIdOverride ?? '').trim();
    return V3PutnikAdresaResolverService.resolveAdresaIdFromPutnikModel(
      putnik: item.putnik,
      grad: grad,
      koristiSekundarnu: koristiSekundarnu,
      adresaIdOverride: override,
    );
  }

  Future<({List<V3RouteWaypoint> waypoints, int unresolvedCount})> _resolveWaypointsForCurrentOrder() async {
    final preostali = _mojiPutnici.where((item) => !_isPutnikEntryCompleted(item)).toList(growable: false);
    debugPrint('[WAYPOINTS] resolving ${preostali.length} preostalih (od ${_mojiPutnici.length} ukupno)...');
    final waypointTasks = preostali.map((item) async {
      final grad = (item.entry?.grad ?? _selectedGrad).trim().toUpperCase();
      final waypoint = await _routeWaypointResolverService.resolveWaypointForPutnikModel(
        putnik: item.putnik,
        grad: grad,
        koristiSekundarnu: item.entry?.koristiSekundarnu ?? false,
        adresaIdOverride: (item.entry?.adresaIdOverride ?? '').trim(),
        waypointId: item.putnik.id,
        waypointLabel: item.putnik.imePrezime,
      );
      debugPrint('[WAYPOINTS] ${item.putnik.imePrezime}: waypoint=${waypoint != null}');

      return waypoint;
    }).toList(growable: false);

    final resolvedOrNull = await Future.wait(waypointTasks);
    final resolved = resolvedOrNull.whereType<V3RouteWaypoint>().toList(growable: false);
    debugPrint('[WAYPOINTS] resolved=${resolved.length} unresolved=${resolvedOrNull.length - resolved.length}');
    return (waypoints: resolved, unresolvedCount: resolvedOrNull.length - resolved.length);
  }

  void _applyOptimizedOrderToPutnici() {
    if (_optimizedPutnikIds.isEmpty) return;

    // Kad je aktivna navigacija nakon klika, zadržavamo strogi optimizovani redosled
    _mojiPutnici.sort((a, b) {
      // Završeni svakako idu na dno
      final isCompletedA = _isPutnikEntryCompleted(a);
      final isCompletedB = _isPutnikEntryCompleted(b);
      if (isCompletedA != isCompletedB) {
        return isCompletedA ? 1 : -1;
      }

      int indexA = _optimizedPutnikIds.indexOf(a.putnik.id);
      int indexB = _optimizedPutnikIds.indexOf(b.putnik.id);

      if (indexA == -1) indexA = 999;
      if (indexB == -1) indexB = 999;

      return indexA.compareTo(indexB);
    });
  }

  Future<
      ({
        List<V3RouteWaypoint> waypointsToOpen,
        int unresolvedCount,
      })?> _buildHereRouteWaypoints() async {
    final resolveResult = await _resolveWaypointsForCurrentOrder();
    var resolved = resolveResult.waypoints;
    final unresolvedCount = resolveResult.unresolvedCount;

    if (resolved.isEmpty) {
      if (mounted) {
        V3AppSnackBar.error(context, 'Nije moguće formirati rutu: nema validnih koordinata adresa.');
      }
      return null;
    }

    final fixedDestination = await _resolveFixedOppositeDestination();
    final waypointsToOpen = <V3RouteWaypoint>[
      ...resolved,
      if (fixedDestination != null) fixedDestination,
    ];

    return (
      waypointsToOpen: waypointsToOpen,
      unresolvedCount: unresolvedCount,
    );
  }

  String _routeSignatureFromWaypoints(List<V3RouteWaypoint> waypoints) {
    return waypoints
        .map((w) => '${w.id}|${w.coordinate.latitude.toStringAsFixed(6)}|${w.coordinate.longitude.toStringAsFixed(6)}')
        .join('>');
  }

  Future<void> _syncMapRouteIfNeeded({required String reason}) async {
    if (!_isNavigating || !_hasSentRouteToMap || _mapResyncInFlight) return;

    final preparedRoute = await _buildHereRouteWaypoints();
    if (preparedRoute == null) return;

    final signature = _routeSignatureFromWaypoints(preparedRoute.waypointsToOpen);
    if (signature == _lastSentRouteSignature) return;

    _mapResyncInFlight = true;
    try {
      await V3NavigationAppLauncherService.launchHereWeGoAppOnly(
        waypoints: preparedRoute.waypointsToOpen,
      );
      _lastSentRouteSignature = signature;
      debugPrint('[V3VozacScreen] map route synced ($reason)');
    } catch (e) {
      debugPrint('[V3VozacScreen] map route sync error ($reason): $e');
    } finally {
      _mapResyncInFlight = false;
    }
  }

  Future<void> _handleOpenMap() async {
    if (!_isNavigating) {
      if (mounted) V3AppSnackBar.warning(context, 'Prvo započnite vožnju (START) da bi se ruta prosledila na mapu.');
      return;
    }

    if (_mojiPutnici.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, 'Nema putnika za izabrani termin.');
      return;
    }

    final preparedRoute = await _buildHereRouteWaypoints();
    if (preparedRoute == null) return;
    final waypointsToOpen = preparedRoute.waypointsToOpen;

    try {
      await V3NavigationAppLauncherService.launchHereWeGoAppOnly(
        waypoints: waypointsToOpen,
      );
      _hasSentRouteToMap = true;
      _lastSentRouteSignature = _routeSignatureFromWaypoints(waypointsToOpen);
      if (!mounted) return;
      V3AppSnackBar.success(context, 'HERE WeGo otvoren sa trenutnim redosledom stanica.');
    } catch (e) {
      if (mounted) {
        V3AppSnackBar.error(context, 'MAPA nije otvorena: $e');
      }
    }
  }

  Future<void> _handleStartNavigation() async {
    debugPrint('[START] _handleStartNavigation called');
    debugPrint('[START] _mojiPutnici.length = ${_mojiPutnici.length}');
    debugPrint('[START] _selectedGrad=$_selectedGrad _selectedVreme=$_selectedVreme _selectedDay=$_selectedDay');

    if (_mojiPutnici.isEmpty) {
      debugPrint('[START] => early return: nema putnika');
      if (mounted) V3AppSnackBar.warning(context, 'Nema putnika za izabrani termin.');
      return;
    }

    for (final p in _mojiPutnici) {
      final adresaId = _resolveAdresaIdForEntry(p);
      debugPrint('[START] putnik=${p.putnik.imePrezime} adresaId=$adresaId');
    }

    final gpsReady = await _ensureGpsPermissionForStart();
    if (!gpsReady) return;

    final preparedRoute = await _buildHereRouteWaypoints();
    debugPrint('[START] prepared route result: $preparedRoute');
    if (preparedRoute == null || !mounted) {
      debugPrint('[START] => prepared route null or not mounted, returning');
      return;
    }

    await _startDriverLocationTracking();

    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isNotEmpty && _selectedGrad.trim().isNotEmpty && _selectedVreme.trim().isNotEmpty) {
      try {
        await V3TrenutnaDodelaSlotService.upsertActiveSlotDodela(
          datumIso: _selectedDatumIso,
          grad: _selectedGrad,
          vreme: _selectedVreme,
          vozacId: vozacId,
          updatedBy: vozacId,
        );

        await V3DriverPushNotificationService.notifyPassengersDriverStarted(
          vozacId: vozacId,
          datumIso: _selectedDatumIso,
          grad: _selectedGrad,
          vreme: _selectedVreme,
        );
      } catch (e) {
        debugPrint('[START] notify passengers / upsert slot error: $e');
      }
    }

    debugPrint(
        '[START] waypoints.length=${preparedRoute.waypointsToOpen.length} unresolvedCount=${preparedRoute.unresolvedCount}');
    V3AppSnackBar.success(context, 'Ruta pripremljena za HERE WeGo.');
    _isNavigating = true;
    _resetMapSyncState();
    unawaited(_syncMapRouteIfNeeded(reason: 'start_navigation'));

    if (preparedRoute.unresolvedCount > 0) {
      V3AppSnackBar.warning(
        context,
        'Preskočeno adresa bez koordinata: ${preparedRoute.unresolvedCount}.',
      );
    }
  }

  Future<void> _handleStopNavigation() async {
    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isNotEmpty && _selectedGrad.trim().isNotEmpty && _selectedVreme.trim().isNotEmpty) {
      try {
        await V3TrenutnaDodelaSlotService.deactivateSlot(
          datumIso: _selectedDatumIso,
          grad: _selectedGrad,
          vreme: _selectedVreme,
          updatedBy: vozacId,
        );
      } catch (e) {
        debugPrint('[STOP] deactivate slot failed: $e');
      }
    }

    V3VozacLocationTrackingService.instance.stop();
    _isNavigating = false;
    _resetMapSyncState();
    if (mounted) {
      V3AppSnackBar.info(context, 'Tracking zaustavljen.');
      V3StateUtils.safeSetState(this, () {});
    }
  }

  void _handleStartStopTap() {
    if (V3VozacLocationTrackingService.instance.isRunning) {
      unawaited(_handleStopNavigation());
      return;
    }

    _handleStartNavigation();
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

    // Termini za BottomNavBar — iz assigned ID-jeva + slot rezervacija
    final rm = V3MasterRealtimeManager.instance;
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
    for (final r in _assignedOperativnaRows(datumIso: _selectedDatumIso, onlyEligible: true)) {
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
    final weekRange = V3DanHelper.schedulingWeekRange();
    final ponedeljak = weekRange.start;
    final petak = weekRange.end;
    final aktivnaSedmica =
        'Operativna sedmica: ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

    return StreamBuilder<int>(
      stream: rm.tablesRevisionStream(
        const [
          'v3_operativna_nedelja',
          'v3_auth',
          'v3_adrese',
          'v3_kapacitet_slots',
          'v3_app_settings',
          'v3_eta_results',
          'v3_finansije',
        ],
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
                              // START
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: V3VozacLocationTrackingService.instance.isRunning ? 'STOP' : 'START',
                                  color: V3VozacLocationTrackingService.instance.isRunning ? Colors.red : Colors.green,
                                  height: appBarButtonHeight,
                                  onTap: () {
                                    _handleStartStopTap();
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              // MAPA
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: 'MAPA',
                                  color: (!_isNavigating)
                                      ? Colors.grey // Inaktivno dok se ne klikne START
                                      : Colors.blue,
                                  height: appBarButtonHeight,
                                  onTap: () {
                                    if (!_isNavigating) {
                                      V3AppSnackBar.warning(context,
                                          'Prvo kliknite START za izabrani termin da ruta bude prosleđena na mapu.');
                                      return;
                                    }
                                    _handleOpenMap();
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Dan picker
                              Expanded(
                                flex: 2,
                                child: _buildDanPickerBtn(context, height: appBarButtonHeight),
                              ),
                              const SizedBox(width: 4),
                              // ⚙️ Popup meni — tema + logout
                              PopupMenuButton<String>(
                                onSelected: (val) async {
                                  if (val == 'tema') {
                                    await V3ThemeManager().nextTheme();
                                    V3StateUtils.safeSetState(this, () {});
                                    if (!mounted) return;
                                    V3AppSnackBar.info(context, '🎨 Tema promenjena');
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
                  final neradanRazlog = _neradanDanRazlog;
                  if (neradanRazlog != null) {
                    return SafeArea(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          '⛔ Slotovi zaključani za $_selectedDay. Razlog: $neradanRazlog',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  int? getKapacitet(String grad, String vreme) {
                    final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
                    return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
                  }

                  return V3BottomNavBarSlotovi(
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
    final vozacBoja = _getVozacBojaRaw(_efektivniVozac);
    int redniCounter = 0;
    final redniBrojevi = _mojiPutnici.map<int?>((pz) {
      final tip = pz.putnik.tipPutnika.toLowerCase().trim();
      if (tip == 'posiljka') return null;
      redniCounter += 1;
      return redniCounter;
    }).toList(growable: false);

    return Column(
      children: [
        const V3UpdateBanner(),
        Expanded(
          child: ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: neradniDaniNotifier,
            builder: (context, rules, _) {
              final weekRange = V3DanHelper.schedulingWeekRange();
              final today = V3DanHelper.dateOnly(DateTime.now());
              final hasNeradan = rules.any((rule) {
                final dateIso = V3DateUtils.parseIsoDatePart(rule['date'] ?? '');
                final date = DateTime.tryParse(dateIso);
                if (date == null) return false;
                final onlyDate = V3DanHelper.dateOnly(date);
                if (onlyDate.isBefore(today)) return false;
                return !onlyDate.isBefore(weekRange.start) && !onlyDate.isAfter(weekRange.end);
              });

              return Column(
                children: [
                  if (hasNeradan)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: V3NeradniDaniBanner(),
                    ),
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
                                key: ValueKey(pz.putnik.id),
                                putnik: pz.putnik,
                                entry: pz.entry,
                                redniBroj: redniBrojevi[index],
                                vozacBoja: vozacBoja,
                                onChanged: _rebuild,
                              );
                            },
                          ),
                  ),
                ],
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
    V3DialogHelper.showDialogBuilder<String>(
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
    final hex = v3Vozac?.boja?.toString();
    return V3CardColorPolicy.parseHexColor(hex, fallback: Colors.white);
  }
}

/// Helper klasa — putnik + njegov operativni entry
class _PutnikEntry {
  final V3Putnik putnik;
  final V3OperativnaNedeljaEntry? entry;
  const _PutnikEntry({required this.putnik, this.entry});
}
