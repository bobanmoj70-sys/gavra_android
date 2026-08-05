import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../l10n/app_translations.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_address_coordinate_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_device_identity_service.dart';
import '../services/v3/v3_navigation_app_launcher_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_push_token_edge_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3/v3_route_models.dart';
import '../services/v3/v3_route_waypoint_resolver_service.dart';
import '../services/v3/v3_tracking_config.dart';
import '../services/v3/v3_trenutna_dodela_service.dart';
import '../services/v3/v3_trenutna_dodela_slot_service.dart';
import '../services/v3/v3_vozac_location_tracking_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_geo_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_policy.dart';
import '../widgets/v3_bottom_nav_bar_slotovi.dart';
import '../widgets/v3_info_banner.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_neradni_dani_banner.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_welcome_screen.dart';

/// V3 Vozač Screen - prikazuje dodeljene termine i putnike
/// iz cache-a građenog iz v3_operativna_nedelja.
class V3VozacScreen extends StatefulWidget {
  final String? vozacId;

  const V3VozacScreen({
    super.key,
    this.vozacId,
  });

  @override
  State<V3VozacScreen> createState() => _V3VozacScreenState();
}

class _V3VozacScreenState extends State<V3VozacScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Prevodi za vozački ekran (SR/EN/RU/DE).
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vozacScreen');

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  DateTime _selectedDate = V3DanHelper.dateOnly(V3BelgradeTime.now());
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  bool _isLoading = true;
  bool _loadingDodela = false;
  StreamSubscription<int>? _trenutnaDodelaRevisionSub;
  StreamSubscription<({Map<String, int> etaMap, List<String> order})>? _etaTickSub;
  StreamSubscription<bool>? _runningSub;
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
  Map<String, String> _allTerminToVozac = <String, String>{};
  bool _isNavigating = false;
  String _lastSyncedPassengersSignature = '';
  bool _hasSentRouteToMap = false;
  bool _mapResyncInFlight = false;
  String _lastSentRouteSignature = '';
  bool _osrmUnavailableShown = false;
  bool _etaReoptimizeInFlight = false;

  /// Tajmer za automatsko pokretanje trackinga tačno na T-15min pre polaska.
  Timer? _autoStartTimer;
  bool _autoStartInProgress = false;

  /// UI selekcija ≠ tracking sesija. Live ETA/mapa/sort samo kad se poklapaju.
  bool get _isViewingTrackedTermin {
    final t = V3VozacLocationTrackingService.instance;
    if (!t.isRunning) return false;
    final selectedV = V3BelgradeTime.normalizeToHHmm(_selectedVreme);
    return _selectedDatumIso == t.activeDatumIso && _selectedGrad == t.activeGrad && selectedV == t.activeVreme;
  }

  /// Opciono skok na aktivan tracking termin — UI se ne zaključava.
  void _jumpToTrackingTermin() {
    final t = V3VozacLocationTrackingService.instance;
    if (!t.isRunning) return;
    final parsed = V3BelgradeTime.parseDatum(t.activeDatumIso);
    if (!mounted) return;
    setState(() {
      if (parsed != null) _selectedDate = V3DanHelper.dateOnly(parsed);
      _selectedGrad = t.activeGrad;
      _selectedVreme = t.activeVreme;
      _resetMapSyncState();
    });
    _rebuild();
  }

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
      _allTerminToVozac = <String, String>{};
      return;
    }

    final vozacAuthId = (vozac.id.toString()).trim();
    if (vozacAuthId.isEmpty) {
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      _allTerminToVozac = <String, String>{};
      return;
    }

    _loadingDodela = true;
    try {
      _assignedOperativnaIds = await V3TrenutnaDodelaService.loadActiveTerminIds(vozacId: vozacAuthId);
      _assignedSlotRows = await V3TrenutnaDodelaSlotService.loadAllSlotsForVozac(vozacId: vozacAuthId);
      _allTerminToVozac = await V3TrenutnaDodelaService.loadActiveVozacByTerminId();
    } catch (e) {
      debugPrint('[V3VozacScreen] _reloadTrenutnaDodelaForVozac error: $e');
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      _allTerminToVozac = <String, String>{};
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
      'v3_eta_results',
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
    final trazenoVreme = V3BelgradeTime.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final operativnaId in _assignedOperativnaIds) {
      final raw = rm.operativnaNedeljaCache[operativnaId] ?? rm.operativnaAssignedCache[operativnaId];
      if (raw == null) continue;

      final row = Map<String, dynamic>.from(raw);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];

      if (trazeniDatum.isNotEmpty) {
        final rowDatum = V3BelgradeTime.parseIsoDatePart(row['datum'] as String? ?? '');
        if (rowDatum != trazeniDatum) continue;
      }

      if (trazeniGrad.isNotEmpty) {
        final rowGrad = row['grad']?.toString().toUpperCase() ?? '';
        if (rowGrad != trazeniGrad) continue;
      }

      if (trazenoVreme.isNotEmpty) {
        final rowVreme = V3BelgradeTime.normalizeToHHmm(row['vreme']?.toString());
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
    final trazenoVreme = V3BelgradeTime.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final slot in _assignedSlotRows) {
      final slotDatum = (slot[V3TrenutnaDodelaSlotService.colDatum] ?? '').trim();
      final slotGrad = (slot[V3TrenutnaDodelaSlotService.colGrad] ?? '').trim().toUpperCase();
      final slotVreme = V3BelgradeTime.normalizeToHHmm(slot[V3TrenutnaDodelaSlotService.colVreme]);

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
    final sorted = List<_PutnikEntry>.from(putnici);
    final osrmOrder = _resolveOptimizedOrder();

    sorted.sort((a, b) {
      // Završeni (pokupljeni/otkazani) idu na kraj
      final isCompletedA = _isPutnikEntryCompleted(a);
      final isCompletedB = _isPutnikEntryCompleted(b);
      if (isCompletedA != isCompletedB) {
        return isCompletedA ? 1 : -1;
      }

      if (osrmOrder.isNotEmpty) {
        final indexA = osrmOrder.indexOf(a.putnik.id);
        final indexB = osrmOrder.indexOf(b.putnik.id);
        return (indexA == -1 ? 999 : indexA).compareTo(indexB == -1 ? 999 : indexB);
      }

      return 0;
    });

    // Log sortirani redosled
    final buf = StringBuffer('[SORT] order:');
    for (final p in sorted) {
      final osrmIdx = osrmOrder.indexOf(p.putnik.id);
      buf.write(' ${p.putnik.imePrezime}(OsrmIdx=$osrmIdx)');
    }
    debugPrint(buf.toString());

    return sorted;
  }

  /// Lanac istine za redosled:
  /// 1) live tick (`optimizedPutnikIds`) — samo dok gledaš tracking termin
  /// 2) `v3_eta_results.optimized_order` — poslednji uspešan compute-eta
  /// 3) slot `optimized_order` — samo pre navigacije / na drugom terminu
  List<String> _resolveOptimizedOrder() {
    final live = V3VozacLocationTrackingService.instance.optimizedPutnikIds;
    // Live order važi isključivo za aktivan tracking termin — ne mešaj u drugi slot.
    if (_isViewingTrackedTermin && live.isNotEmpty) return live;

    final fromEta = _getOsrmOrderFromEtaResults();
    if (fromEta.isNotEmpty) return fromEta;

    // Tokom live navigacije na tracking terminu ne koristi cron/slot order.
    if (_isViewingTrackedTermin) return const [];
    return _getOsrmOrderFromSlot();
  }

  void _refreshPutniciOrderFromEtaCache() {
    final osrmOrder = _resolveOptimizedOrder();
    if (osrmOrder.isEmpty) {
      if (_isViewingTrackedTermin && !_osrmUnavailableShown) {
        _osrmUnavailableShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            V3AppSnackBar.warning(
              context,
              'OSRM trenutno nije dostupan — redosled kartica neće biti promenjen.',
            );
          }
        });
      }
      return;
    }
    _osrmUnavailableShown = false;
    if (_mojiPutnici.isEmpty) return;
    final sorted = _sortPutniciForDisplay(List<_PutnikEntry>.from(_mojiPutnici));
    if (mounted) {
      setState(() {
        _mojiPutnici = sorted;
      });
    }
  }

  /// Poslednji redosled iz v3_eta_results za ovog vozača + prikazane putnike.
  List<String> _getOsrmOrderFromEtaResults() {
    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isEmpty) return const [];

    final shownIds = _mojiPutnici.map((p) => p.putnik.id).toSet();
    List<String>? bestOrder;
    DateTime? bestAt;

    for (final row in V3MasterRealtimeManager.instance.etaResultsCache.values) {
      if ((row['vozac_id']?.toString() ?? '') != vozacId) continue;
      final order = row['optimized_order'];
      if (order is! List || order.isEmpty) continue;
      final asStrings = order.whereType<String>().toList();
      if (asStrings.isEmpty) continue;
      if (shownIds.isNotEmpty && !asStrings.any(shownIds.contains)) continue;

      final raw = row['computed_at'];
      DateTime? at;
      if (raw is DateTime) {
        at = raw;
      } else if (raw is String) {
        at = V3BelgradeTime.parseTs(raw);
      }
      if (bestOrder == null || (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        bestOrder = asStrings;
        bestAt = at;
      }
    }
    return bestOrder ?? const [];
  }

  List<String> _getOsrmOrderFromSlot() {
    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    final cache = V3MasterRealtimeManager.instance.trenutnaDodelaSlotCache;
    debugPrint('[OSRM_SLOT] efektivniVozacId=$vozacId cacheRows=${cache.length}');
    // Slot je zajednički (datum,grad,vreme) — NE filtriraj po slot.vozac_v3_auth_id.
    // Redosled filtriraj na putnike ovog vozača (individualna dodela → _mojiPutnici).
    final myIds = _mojiPutnici.map((p) => p.putnik.id).where((id) => id.isNotEmpty).toSet();

    for (final row in cache.values) {
      final rowDatum = V3BelgradeTime.parseIsoDatePart(row['datum']?.toString() ?? '');
      final rowGrad = (row['grad']?.toString() ?? '').trim().toUpperCase();
      final rowVreme = V3BelgradeTime.normalizeToHHmm(row['vreme']?.toString());
      final order = row['optimized_order'];
      final hasOrder = order is List && order.isNotEmpty;
      debugPrint('[OSRM_SLOT]   datum=$rowDatum grad=$rowGrad vreme=$rowVreme hasOrder=$hasOrder');
      if (rowDatum != _selectedDatumIso || rowGrad != _selectedGrad || rowVreme != _selectedVreme) {
        continue;
      }
      if (order is! List || order.isEmpty) continue;
      final all = order.whereType<String>().where((s) => s.isNotEmpty).toList();
      if (all.isEmpty) continue;
      if (myIds.isEmpty) return all;
      final mine = all.where(myIds.contains).toList();
      return mine.isNotEmpty ? mine : all;
    }
    return const [];
  }

  /// Jedan GPS+ETA tick (init sa aktivnim trackingom). UI ide preko onEtaTick.
  Future<void> _recomputeEtaFromCurrentPosition() async {
    // Servis koristi svoju sesiju (ne UI selekciju) — uvek OK.
    if (!V3VozacLocationTrackingService.instance.isRunning) return;
    final vid = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vid.isEmpty) return;

    try {
      final etaResult = await V3VozacLocationTrackingService.instance.fetchPositionAndComputeEta();
      debugPrint('[RESUME_ETA] ETA map: ${etaResult.etaMap}');
      debugPrint('[RESUME_ETA] optimized order: ${etaResult.order}');
    } catch (e) {
      debugPrint('[RESUME_ETA] ETA recompute error: $e');
    }
  }

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDate = V3DanHelper.defaultWorkdayDate();
    // Ako je tracking već aktivan (npr. vozač se vratio back), obnovi state
    _isNavigating = V3VozacLocationTrackingService.instance.isRunning;
    _startTrenutnaDodelaRealtime();
    _etaTickSub = V3VozacLocationTrackingService.instance.onEtaTick.listen((result) {
      if (!mounted || !_isNavigating) return;
      // Sort/mapa samo kad vozač gleda isti termin kao tracking sesija.
      if (!_isViewingTrackedTermin) return;
      debugPrint('[ETA_TICK] order=${result.order} etaKeys=${result.etaMap.length}');
      _refreshPutniciOrderFromEtaCache();
      unawaited(_syncMapRouteIfNeeded(reason: 'eta_tick_20s'));
    });
    _runningSub = V3VozacLocationTrackingService.instance.onRunningChanged.listen((running) {
      if (!mounted) return;
      V3StateUtils.safeSetState(this, () => _isNavigating = running);
      // Posle stop-a (timeout / svi gotovi) odmah zakazi sledeci termin.
      if (!running) unawaited(_scheduleAutoStart());
    });
    unawaited(_initData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_trenutnaDodelaRevisionSub?.cancel());
    _trenutnaDodelaRevisionSub = null;
    unawaited(_etaTickSub?.cancel());
    _etaTickSub = null;
    unawaited(_runningSub?.cancel());
    _runningSub = null;
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop na detached radi V3VozacLocationTrackingService (jedan izvor).
    // Timer se može pauzirati u backgroundu — na resume ponovo zakazati.
    if (state == AppLifecycleState.resumed) {
      _scheduleAutoStart();
    }
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

    if (!mounted) return;
    await _reloadTrenutnaDodelaForVozac();
    _rebuild();
    V3StateUtils.safeSetState(this, () => _isLoading = false);

    // Ako je navigacija aktivna (app ubijena pa ponovo otvorena),
    // ponovo izračunaj ETA-e sa TRENUTNOM (live) GPS pozicijom.
    if (_isNavigating) {
      unawaited(_recomputeEtaFromCurrentPosition());
    }
  }

  /// Jedan ulaz za auto-start: zakazuje timer na T-15min ili startuje odmah.
  /// Radi samo dok je V3VozacScreen mounted (foreground).
  Future<void> _scheduleAutoStart() async {
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    if (!mounted || _autoStartInProgress) return;
    if (V3VozacLocationTrackingService.instance.isRunning) {
      if (!_isNavigating) {
        V3StateUtils.safeSetState(this, () => _isNavigating = true);
      }
      return;
    }

    final termin = _findAutoStartTermin();
    if (termin == null) return;

    final delay = termin.polazak.subtract(v3AutoStartLeadTime).difference(V3BelgradeTime.now());
    if (delay > Duration.zero) {
      debugPrint('[V3VozacScreen] auto-start za ${delay.inSeconds}s (${termin.grad} ${termin.vreme})');
      _autoStartTimer = Timer(delay, () => unawaited(_scheduleAutoStart()));
      return;
    }

    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isEmpty) {
      if (mounted) V3AppSnackBar.error(context, _tr('nemogucIdentifikovatiVozaca'));
      return;
    }

    _autoStartInProgress = true;
    try {
      debugPrint('[V3VozacScreen] auto-start → ${termin.grad} ${termin.vreme}');
      var result = await V3VozacLocationTrackingService.instance.start(
        vozacId: vozacId,
        datumIso: termin.datumIso,
        grad: termin.grad,
        vreme: termin.vreme,
      );

      // Always / Settings (Huawei/Android/iOS) — vodi u podešavanja pa retry.
      final needsLocationSettings = result == V3TrackingStartResult.permissionAlwaysRequired ||
          result == V3TrackingStartResult.permissionDenied ||
          result == V3TrackingStartResult.permissionDeniedForever;
      if (!result.isSuccess && needsLocationSettings && mounted) {
        final granted = await V3RolePermissionService.promptAlwaysLocationIfNeeded(context);
        if (granted && mounted) {
          result = await V3VozacLocationTrackingService.instance.start(
            vozacId: vozacId,
            datumIso: termin.datumIso,
            grad: termin.grad,
            vreme: termin.vreme,
          );
        }
      }

      if (!mounted) return;
      final running = result.isSuccess;
      V3StateUtils.safeSetState(this, () => _isNavigating = running);
      if (running) {
        final label = '${termin.grad} ${termin.vreme}';
        V3AppSnackBar.success(
          context,
          _tr('trackingAktivanZaTermin').replaceAll('%GRAD%', termin.grad).replaceAll('%VREME%', termin.vreme),
        );
        debugPrint('[V3VozacScreen] auto-start OK $label (UI ostaje na $_selectedGrad $_selectedVreme)');
      } else {
        V3AppSnackBar.error(context, _tr(result.errorL10nKey ?? 'nemogucIdentifikovatiVozaca'));
      }
    } finally {
      _autoStartInProgress = false;
    }
  }

  bool _isPutnikEntryCompleted(_PutnikEntry item) {
    final entry = item.entry;
    if (entry == null) return false;
    final pokupljen = V3StatusPolicy.isTimestampSet(entry.pokupljenAt);
    final otkazan = V3StatusPolicy.isTimestampSet(entry.otkazanoAt);
    return pokupljen || otkazan;
  }

  void _rebuild() {
    final vozac = _efektivniVozac;
    if (vozac == null) return;
    final rm = V3MasterRealtimeManager.instance;

    final selectedVNorm = V3BelgradeTime.normalizeToHHmm(_selectedVreme);

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
        V3BelgradeTime.normalizeToHHmm(t['vreme']?.toString()) == selectedVNorm);

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
    //    Individualna dodela + slot dodela (ostali putnici iz termina
    //    koji nisu individualno dodeljeni drugom vozaču)

    final vozacAuthId = vozac.id.toString().trim();

    // Najpre individualno dodeljeni putnici
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

    // Uključi i ostale putnike iz tog termina koji nemaju individualnu dodelu drugom vozaču
    for (final raw in rm.operativnaNedeljaCache.values) {
      final rowDatum = V3BelgradeTime.parseIsoDatePart(raw['datum'] as String? ?? '');
      final rowGrad = raw['grad']?.toString().toUpperCase() ?? '';
      final rowVreme = V3BelgradeTime.normalizeToHHmm(raw['polazak_at']?.toString());
      if (rowDatum != _selectedDatumIso || rowGrad != _selectedGrad || rowVreme != _selectedVreme) continue;
      if (raw['created_by'] == null) continue;

      final entryId = raw['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;

      // Ako je već individualno dodeljen ovom vozaču, preskoči (već dodat)
      if (_assignedOperativnaIds.contains(entryId)) continue;

      // Ako je individualno dodeljen drugom vozaču, preskoči
      final assignedVozac = _allTerminToVozac[entryId];
      if (assignedVozac != null && assignedVozac != vozacAuthId) continue;

      // Inače dodaj iz slota
      final row = Map<String, dynamic>.from(raw);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];
      allSelectedRowsById.putIfAbsent(entryId, () => row);
    }

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

    final putniciZaPrikaz = _sortPutniciForDisplay(putnici);

    V3StateUtils.safeSetState(this, () {
      _mojiPutnici = putniciZaPrikaz;
    });

    // Sigurnosna mreža: ETA redosled samo na tracking terminu.
    // Drugi termini ostaju slobodni za pregled/akcije.
    if (_isViewingTrackedTermin) {
      _refreshPutniciOrderFromEtaCache();
      unawaited(_syncPassengersToSlotIfNeeded());
      unawaited(_syncMapRouteIfNeeded(reason: 'realtime_refresh'));
    }

    _scheduleAutoStart();
  }

  void _selectFirstTermin() {
    if (_mojiTermini.isEmpty) return;

    final first = _mojiTermini.first;
    final grad = first['grad']?.toString().toUpperCase() ?? '';
    final vreme = first['vreme']?.toString() ?? '';
    if (grad.isEmpty || vreme.isEmpty) return;

    final normalized = V3BelgradeTime.normalizeToHHmm(vreme);
    if (normalized.isEmpty) return;

    _selectedGrad = grad;
    _selectedVreme = normalized;
  }

  String get _selectedDay => V3DanHelper.fullName(_selectedDate);

  String get _selectedDatumIso {
    return V3DanHelper.toIsoDate(_selectedDate);
  }

  String? get _neradanRazlog => getNeradanDanRazlog(datumIso: _selectedDatumIso, grad: _selectedGrad);

  void _onPolazakChanged(String grad, String vreme) {
    final normalizedGrad = grad.toUpperCase();
    final normalizedVreme = V3BelgradeTime.normalizeToHHmm(vreme);
    setState(() {
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
    final previousVreme = V3BelgradeTime.normalizeToHHmm(_selectedVreme);

    final dayAbbr = V3DanHelper.workdayAbbrFromFullName(day);
    final dayIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(
      dayAbbr,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );
    final parsedDayDate = V3BelgradeTime.parseDatum(dayIso);
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

    final currentVremeNorm = V3BelgradeTime.normalizeToHHmm(_selectedVreme);
    final hasCurrentSelection = dayTerms.any(
      (row) =>
          (row['grad']?.toString().toUpperCase() ?? '') == _selectedGrad &&
          V3BelgradeTime.normalizeToHHmm(row['vreme']?.toString()) == currentVremeNorm,
    );

    Map<String, dynamic>? bestTerm;
    if (dayTerms.isNotEmpty && !hasCurrentSelection) {
      final now = V3BelgradeTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      dayTerms.sort((a, b) {
        final aTime = V3BelgradeTime.normalizeToHHmm(a['vreme']?.toString());
        final bTime = V3BelgradeTime.normalizeToHHmm(b['vreme']?.toString());
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
        _selectedVreme = V3BelgradeTime.normalizeToHHmm(bestTerm['vreme']?.toString());
      } else if (dayTerms.isEmpty) {
        _selectedVreme = '';
      }

      if (dayTerms.isNotEmpty && _selectedVreme.isEmpty) {
        final firstTerm = dayTerms.first;
        _selectedGrad = firstTerm['grad'].toString().toUpperCase();
        _selectedVreme = V3BelgradeTime.normalizeToHHmm(firstTerm['vreme'].toString());
      }
      _resetMapSyncState();
    });

    _rebuild();
  }

  Future<void> _logout() async {
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: _tr('logout'),
      message: _tr('logoutPitanje'),
      confirmText: _tr('logout'),
      cancelText: _tr('otkazi'),
      isDangerous: true,
    );
    if (ok == true && mounted) {
      debugPrint('[V3VozacScreen] stop reason=logout');
      V3VozacLocationTrackingService.instance.stop();

      // Oslobodi uređaj slot u bazi pre brisanja lokalne sesije
      final vozacId = V3VozacService.currentVozac?.id ?? '';
      if (vozacId.isNotEmpty) {
        final deviceId = await V3DeviceIdentityService.getStableDeviceId();
        await V3PushTokenEdgeService.releaseDeviceSlot(
          v3AuthId: vozacId,
          installationId: deviceId,
        );
      }

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
    final vozacAuthId = vozac.id.toString().trim();

    final vremeNorm = V3BelgradeTime.normalizeToHHmm(vreme);
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

    for (final raw in rm.operativnaNedeljaCache.values) {
      final rowDatum = V3BelgradeTime.parseIsoDatePart(raw['datum'] as String? ?? '');
      final rowGrad = raw['grad']?.toString().toUpperCase() ?? '';
      final rowVreme = V3BelgradeTime.normalizeToHHmm(raw['polazak_at']?.toString());
      if (rowDatum != _selectedDatumIso || rowGrad != gradUp || rowVreme != vremeNorm) continue;
      if (raw['created_by'] == null) continue;

      final entryId = raw['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      if (rowsById.containsKey(entryId)) continue;

      final assignedVozac = _allTerminToVozac[entryId];
      if (assignedVozac != null && assignedVozac != vozacAuthId) continue;

      final row = Map<String, dynamic>.from(raw);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];
      if (!hasActivePutnik(row)) continue;
      rowsById[entryId] = row;
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
        label: _tr('ciljGrad').replaceAll('%GRAD%', opposite),
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
      label: _tr('ciljGrad').replaceAll('%GRAD%', opposite),
      coordinate: coordinate,
    );
  }

  // _resolveAdresaIdForEntry() je uklonjena jer se koristi samo u ručnom START-u koji je onemogućen

  String _passengersSignature() {
    final preostali = _mojiPutnici.where((p) => !_isPutnikEntryCompleted(p));
    return preostali
        .map((p) =>
            '${p.putnik.id}|${p.entry?.id ?? ""}|${p.entry?.koristiSekundarnu ?? false}|${p.entry?.adresaIdOverride ?? ""}')
        .join(',');
  }

  Future<void> _syncPassengersToSlotIfNeeded() async {
    // Sync koordinata samo za aktivni tracking termin — ne diraj drugi slot.
    if (!_isViewingTrackedTermin) return;
    final sig = _passengersSignature();
    if (sig == _lastSyncedPassengersSignature) return;
    _lastSyncedPassengersSignature = sig;
    unawaited(_syncPassengersToSlot());
  }

  Future<void> _syncPassengersToSlot() async {
    final vozacId = (_efektivniVozac?.id?.toString() ?? '').trim();
    if (vozacId.isEmpty || _selectedGrad.isEmpty || _selectedVreme.isEmpty) return;

    // NAPOMENA: šaljemo SVE putnike (uključujući pokupljene/otkazane), ne samo
    // preostale. Koordinate se upisuju u v3_trenutna_dodela po termin_id —
    // jedini izvor istine za "da li je putnik završen" je
    // v3_operativna_nedelja.pokupljen_at/otkazano_at.
    final passengerData = <Map<String, dynamic>>[];
    for (final item in _mojiPutnici) {
      final terminId = (item.entry?.id ?? '').trim();
      if (terminId.isEmpty) continue;

      final grad = (item.entry?.grad ?? _selectedGrad).trim().toUpperCase();
      final waypoint = await _routeWaypointResolverService.resolveWaypointForPutnikModel(
        putnik: item.putnik,
        grad: grad,
        koristiSekundarnu: item.entry?.koristiSekundarnu ?? false,
        adresaIdOverride: (item.entry?.adresaIdOverride ?? '').trim(),
        waypointId: item.putnik.id,
        waypointLabel: item.putnik.imePrezime,
      );
      if (waypoint == null) {
        debugPrint(
            '[SYNC] waypoint nije razrešen za putnika ${item.putnik.imePrezime} (${item.putnik.id}), preskačem iz ETA');
        continue;
      }

      passengerData.add(<String, dynamic>{
        'putnik_id': item.putnik.id,
        'termin_id': terminId,
        'lat': waypoint.coordinate.latitude,
        'lng': waypoint.coordinate.longitude,
      });
    }

    try {
      await V3TrenutnaDodelaSlotService.syncPassengerCoordinates(passengerData);
      debugPrint('[SYNC] passengers synced to slot: ${passengerData.length}');
    } catch (e) {
      debugPrint('[SYNC] syncPassengerCoordinates error: $e');
      return;
    }

    // Odmah GPS+ETA tick — UI (sort/mapa) ide preko onEtaTick stream-a.
    if (_etaReoptimizeInFlight || !_isNavigating) return;
    _etaReoptimizeInFlight = true;
    try {
      final etaResult = await V3VozacLocationTrackingService.instance.fetchPositionAndComputeEta();
      debugPrint('[SYNC] immediate re-optimize order: ${etaResult.order}');
    } catch (e) {
      debugPrint('[SYNC] immediate re-optimize error: $e');
    } finally {
      _etaReoptimizeInFlight = false;
    }
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
        V3AppSnackBar.error(context, _tr('rutaNemaKoordinate'));
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
    // HERE resync samo dok gledaš isti termin kao tracking sesija.
    if (!_isViewingTrackedTermin || !_hasSentRouteToMap || _mapResyncInFlight) return;

    final preparedRoute = await _buildHereRouteWaypoints();
    if (preparedRoute == null) return;

    final signature = _routeSignatureFromWaypoints(preparedRoute.waypointsToOpen);
    if (signature == _lastSentRouteSignature) return;

    _mapResyncInFlight = true;
    try {
      final result = await V3NavigationAppLauncherService.launchHereWeGo(
        waypoints: preparedRoute.waypointsToOpen,
      );
      if (result == V3HereWeGoLaunchResult.opened) {
        _lastSentRouteSignature = signature;
        debugPrint('[V3VozacScreen] map route synced ($reason)');
      } else {
        debugPrint('[V3VozacScreen] map route sync skipped ($reason): $result');
      }
    } catch (e) {
      debugPrint('[V3VozacScreen] map route sync error ($reason): $e');
    } finally {
      _mapResyncInFlight = false;
    }
  }

  Future<void> _handleOpenMap() async {
    if (!_isNavigating) {
      if (mounted) V3AppSnackBar.warning(context, _tr('zapocniVoznjuPrviPuta'));
      return;
    }

    // Mapa prati tracking sesiju, ne UI pregled drugog termina.
    if (!_isViewingTrackedTermin) {
      final t = V3VozacLocationTrackingService.instance;
      if (mounted) {
        V3AppSnackBar.warning(
          context,
          _tr('mapaSamoZaAktivniTermin').replaceAll('%GRAD%', t.activeGrad).replaceAll('%VREME%', t.activeVreme),
        );
      }
      return;
    }

    if (_mojiPutnici.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, _tr('nemaPutnikaZaTermin'));
      return;
    }

    final preparedRoute = await _buildHereRouteWaypoints();
    if (preparedRoute == null) return;
    final waypointsToOpen = preparedRoute.waypointsToOpen;

    final result = await V3NavigationAppLauncherService.launchHereWeGo(
      waypoints: waypointsToOpen,
    );
    if (!mounted) return;

    switch (result) {
      case V3HereWeGoLaunchResult.opened:
        _hasSentRouteToMap = true;
        _lastSentRouteSignature = _routeSignatureFromWaypoints(waypointsToOpen);
        V3AppSnackBar.success(context, _tr('hereWeGoOtvoren'));
      case V3HereWeGoLaunchResult.notInstalled:
        V3NavigationAppLauncherService.showInstallPrompt(
          context,
          message: _tr('hereWeGoInstallTitle'),
          actionLabel: _tr('hereWeGoInstallAction'),
        );
      case V3HereWeGoLaunchResult.noWaypoints:
        V3AppSnackBar.error(context, _tr('rutaNemaKoordinate'));
      case V3HereWeGoLaunchResult.failed:
        V3AppSnackBar.error(context, _tr('mapaNijeOtvorena'));
    }
  }

  /// Vraća true ako termin (datum/grad/vreme) ima barem jednog putnika
  /// koji nije pokupljen, otkazan ili odbijen.
  bool _terminHasActivePassengers(String datumIso, String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final vozac = _efektivniVozac;
    if (vozac == null) return false;
    final vozacAuthId = vozac.id.toString().trim();
    final gradUp = grad.toUpperCase();
    final vremeNorm = V3BelgradeTime.normalizeToHHmm(vreme);

    bool isActive(Map<String, dynamic> row) {
      return V3StatusPolicy.canAssign(
        status: row['status']?.toString(),
        otkazanoAt: row['otkazano_at'],
        pokupljenAt: row['pokupljen_at'],
      );
    }

    // 1. Individualno dodeljeni putnici
    for (final row in _assignedOperativnaRows(
      datumIso: datumIso,
      grad: gradUp,
      vreme: vremeNorm,
      onlyEligible: false,
    )) {
      if (row['created_by'] == null) continue;
      if (isActive(row)) return true;
    }

    // 2. Ostali putnici iz istog termina koji nisu dodeljeni drugom vozaču
    for (final raw in rm.operativnaNedeljaCache.values) {
      final rowDatum = V3BelgradeTime.parseIsoDatePart(raw['datum'] as String? ?? '');
      final rowGrad = raw['grad']?.toString().toUpperCase() ?? '';
      final rowVreme = V3BelgradeTime.normalizeToHHmm(raw['polazak_at']?.toString());
      if (rowDatum != datumIso || rowGrad != gradUp || rowVreme != vremeNorm) continue;
      if (raw['created_by'] == null) continue;

      final entryId = raw['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      if (_assignedOperativnaIds.contains(entryId)) continue;

      final assignedVozac = _allTerminToVozac[entryId];
      if (assignedVozac != null && assignedVozac != vozacAuthId) continue;

      if (isActive(raw)) return true;
    }

    return false;
  }

  /// Najbliži termin danas u prozoru T-15 … T+40 (nezavisno od UI selektora).
  ({String datumIso, String grad, String vreme, DateTime polazak})? _findAutoStartTermin() {
    final now = V3BelgradeTime.now();
    final todayIso = V3DanHelper.toIsoDate(now);

    final seen = <String>{};
    final candidates = <({String datumIso, String grad, String vreme, DateTime polazak})>[];

    for (final row in [
      ..._assignedOperativnaRows(datumIso: todayIso),
      ..._assignedSlotTermRows(datumIso: todayIso),
    ]) {
      final datum = V3BelgradeTime.parseIsoDatePart(row['datum']?.toString() ?? '');
      final grad = row['grad']?.toString().toUpperCase() ?? '';
      final vreme = V3BelgradeTime.normalizeToHHmm(row['vreme']?.toString() ?? row['polazak_at']?.toString());
      final key = '$datum|$grad|$vreme';
      if (datum.isEmpty || grad.isEmpty || vreme.isEmpty || !seen.add(key)) continue;

      final polazak = v3PolazakDateTime(datumIso: datum, vreme: vreme);
      if (polazak == null) continue;
      if (now.isAfter(polazak.add(v3TrackingMaxDuration))) continue;
      if (!_terminHasActivePassengers(datum, grad, vreme)) continue;

      candidates.add((datumIso: datum, grad: grad, vreme: vreme, polazak: polazak));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.polazak.compareTo(b.polazak));

    // Prvo aktivan prozor (T-15 prošlo), inače najraniji budući.
    for (final c in candidates) {
      if (!now.isBefore(c.polazak.subtract(v3AutoStartLeadTime))) return c;
    }
    return candidates.first;
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
        '${_tr('operativnaSedmicaPrefix')} ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

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
                          // ── Red 1: Datum | Dan ──
                          _buildDigitalDateDisplay(context, vozac),
                          const SizedBox(height: 6),
                          // ── Red 2: Kompaktni gumbi ──
                          Row(
                            children: [
                              // STATUS: Tracking (samo auto-start, nema ručnog dugmeta)
                              Expanded(
                                flex: 2,
                                child: V3VozacLocationTrackingService.instance.isRunning
                                    ? GestureDetector(
                                        onTap: _isViewingTrackedTermin ? null : _jumpToTrackingTermin,
                                        child: _buildPulsingAktivnoBtn(
                                          context: context,
                                          label: _tr('statusAktivno'),
                                          height: appBarButtonHeight,
                                        ),
                                      )
                                    : _buildAppBarBtn(
                                        context: context,
                                        label: _tr('statusCeka'),
                                        color: Colors.grey,
                                        height: appBarButtonHeight,
                                        onTap: null,
                                      ),
                              ),
                              const SizedBox(width: 4),
                              // MAPA — dostupna kada je tracking aktivan
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: _tr('mapaDugme'),
                                  color: (!_isNavigating)
                                      ? Colors.grey // Inaktivno dok tracking nije aktivan
                                      : Colors.blue,
                                  height: appBarButtonHeight,
                                  onTap: () {
                                    if (!_isNavigating) {
                                      V3AppSnackBar.warning(context, _tr('rutaBiceDostupna'));
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
                                    V3AppSnackBar.info(context, _tr('temaPromenjena'));
                                  } else if (val == 'jezik') {
                                    const codes = ['sr', 'en', 'ru', 'de', 'zh'];
                                    final current = V3LocaleManager().currentLocale.languageCode;
                                    final idx = codes.indexOf(current);
                                    final next = codes[(idx + 1) % codes.length];
                                    await V3LocaleManager().changeLocale(Locale(next));
                                    V3StateUtils.safeSetState(this, () {});
                                    if (!mounted) return;
                                    V3AppSnackBar.info(context, _tr('jezikPromenjen'));
                                  } else if (val == 'promeni_pin') {
                                    final vozac = _efektivniVozac;
                                    final vozacAuthId = (vozac?.id?.toString() ?? '').trim();
                                    if (vozacAuthId.isEmpty) {
                                      V3AppSnackBar.error(context, _tr('nemogucIdentifikovatiVozaca'));
                                      return;
                                    }
                                    await V3DialogHelper.showDialogBuilder<void>(
                                      context: context,
                                      builder: (ctx) => _ChangePinDialog(v3AuthId: vozacAuthId),
                                    );
                                  } else if (val == 'logout') {
                                    _logout();
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'tema',
                                    child: Row(children: [
                                      const Icon(Icons.palette, color: Colors.purpleAccent),
                                      const SizedBox(width: 8),
                                      Text(_tr('promeniTemu')),
                                    ]),
                                  ),
                                  PopupMenuItem(
                                    value: 'jezik',
                                    child: Row(children: [
                                      const Icon(Icons.language, color: Colors.lightBlueAccent),
                                      const SizedBox(width: 8),
                                      Text(_tr('promeniJezik')),
                                    ]),
                                  ),
                                  PopupMenuItem(
                                    value: 'promeni_pin',
                                    child: Row(children: [
                                      const Icon(Icons.lock_reset_outlined, color: Colors.orangeAccent),
                                      const SizedBox(width: 8),
                                      Text(_tr('promeniPin')),
                                    ]),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'logout',
                                    child: Row(children: [
                                      const Icon(Icons.logout, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Text(_tr('logout')),
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
                  final neradanRazlog = _neradanRazlog;
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
                          _tr('slotoviZakljucaniZaRazlog')
                              .replaceAll('%DAN%', V3DanHelper.trFullName(_selectedDay))
                              .replaceAll('%RAZLOG%', neradanRazlog),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  int? getKapacitet(String grad, String vreme) {
                    final datum = V3BelgradeTime.parseDatumOrToday(_selectedDatumIso);
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

    final showTrackingBanner = V3VozacLocationTrackingService.instance.isRunning && !_isViewingTrackedTermin;
    final tTrack = V3VozacLocationTrackingService.instance;

    return Column(
      children: [
        const V3UpdateBanner(),
        Expanded(
          child: ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: neradniDaniNotifier,
            builder: (context, rules, _) {
              final weekRange = V3DanHelper.schedulingWeekRange();
              final today = V3DanHelper.dateOnly(V3BelgradeTime.now());
              final hasNeradan = rules.any((rule) {
                final dateIso = V3BelgradeTime.parseIsoDatePart(rule['date'] ?? '');
                final date = V3BelgradeTime.parseDatum(dateIso);
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
                  if (showTrackingBanner)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _jumpToTrackingTermin,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.75)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.gps_fixed, color: Colors.greenAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tr('trackingAktivanZaTermin')
                                            .replaceAll('%GRAD%', tTrack.activeGrad)
                                            .replaceAll('%VREME%', tTrack.activeVreme),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tr('trackingPrikaziTermin'),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: V3InfoBanner(),
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

  // ── Digitalni datum prikaz ──
  Widget _buildDigitalDateDisplay(BuildContext context, dynamic vozac) {
    final selectedDate = _selectedDate;
    final dayName = V3DanHelper.trFullName(_selectedDay).toUpperCase();
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
    VoidCallback? onTap,
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
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ── Pulsirajuće "Aktivno" dugme sa zelenim gradient prelivom (tracking radi) ──
  Widget _buildPulsingAktivnoBtn({
    required BuildContext context,
    required String label,
    required double height,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = _pulseController.value;
        final sweep = t * 3.0 - 1.0;
        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
        final glow = 0.35 + 0.25 * pulse;

        return Transform.scale(
          scale: 1.0 + 0.03 * pulse,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: glow * 0.6),
                  blurRadius: 10 + 6 * pulse,
                  spreadRadius: 1 + 1.5 * pulse,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.7)),
                  gradient: LinearGradient(
                    begin: Alignment(sweep - 0.6, 0),
                    end: Alignment(sweep + 0.6, 0),
                    colors: [
                      Colors.green.withValues(alpha: 0.25),
                      Colors.greenAccent.withValues(alpha: 0.55),
                      Colors.green.withValues(alpha: 0.25),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.greenAccent.shade100,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.green.withValues(alpha: glow), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
            V3DanHelper.trAbbr(_selectedDay).toUpperCase(),
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        title: Text(_tr('izaberiDan'), style: const TextStyle(color: Colors.white)),
        children: V3DanHelper.workdayNames.map((dan) {
          final isSelected = dan == _selectedDay;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, dan),
            child: Text(
              V3DanHelper.trFullName(dan),
              style: TextStyle(
                color: isSelected ? Colors.amberAccent : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
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

// ─── CHANGE PIN DIALOG ──────────────────────────────────────────────────────
class _ChangePinDialog extends StatefulWidget {
  final String v3AuthId;

  const _ChangePinDialog({required this.v3AuthId});

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _newPinConfirmController = TextEditingController();

  bool _saving = false;
  String? _error;

  // Prevodi za dijalog promene PIN-a (SR/EN/RU/DE).
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vozacScreen2');

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  @override
  dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _newPinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    final oldPin = _oldPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final newPinConfirm = _newPinConfirmController.text.trim();

    if (!V3ClosedAuthService.isValidPin(oldPin)) {
      setState(() => _error = _tr('trenutniPinMora6Cifara'));
      return;
    }
    if (!V3ClosedAuthService.isValidPin(newPin)) {
      setState(() => _error = _tr('noviPinMora6Cifara'));
      return;
    }

    if (newPin != newPinConfirm) {
      setState(() => _error = _tr('noviPinoviSeNePoklapaju'));
      return;
    }
    if (newPin == oldPin) {
      setState(() => _error = _tr('noviPinMoraBitiRazlicit'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await V3ClosedAuthService.changePin(
      v3AuthId: widget.v3AuthId,
      oldPin: oldPin,
      newPin: newPin,
    );

    if (!mounted) return;

    if (!result.ok) {
      final message = switch (result.reason) {
        'old_pin_mismatch' => _tr('trenutniPinNijeIspravan'),
        'pin_not_set' => _tr('nalogNemaPin'),
        _ => _tr('greskaPromenaPin'),
      };
      setState(() {
        _saving = false;
        _error = message;
      });
      return;
    }

    V3AppSnackBar.success(context, _tr('pinPromenjen'));
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = theme.backgroundGradient;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_reset_outlined, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr('promeniPin'),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _tr('unesiPinSubtitle'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      V3InputUtils.textField(
                        controller: _oldPinController,
                        label: _tr('trenutniPin'),
                        icon: Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _newPinController,
                        label: _tr('noviPin'),
                        icon: Icons.lock_open_outlined,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _newPinConfirmController,
                        label: _tr('ponoviNoviPin'),
                        icon: Icons.lock_open_outlined,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: V3ButtonUtils.outlinedButton(
                              onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                              text: _tr('otkazi'),
                              borderColor: Colors.white54,
                              foregroundColor: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: V3ButtonUtils.primaryButton(
                              onPressed: _saving ? null : _sacuvaj,
                              text: _tr('sacuvaj'),
                              icon: Icons.check,
                              isLoading: _saving,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
