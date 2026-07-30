import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

/// GPS/ETA tracking vozača.
///
/// Start: V3VozacScreen auto-start (foreground).
/// Tick izvor (međusobno isključivi):
///   - app u foreground → main isolate ticker
///   - app u background → FlutterBackgroundService isolate
///
/// `activateSlotWithRetry` upisuje `tracking_started_at` (samo prvi put) →
/// DB trigger obaveštava putnike.
class V3VozacLocationTrackingService with WidgetsBindingObserver {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  String _activeVozacId = '';
  String _activeDatumIso = '';
  String _activeGrad = '';
  String _activeVreme = '';
  bool _isRunning = false;
  bool _startInProgress = false;
  DateTime? _trackingStartedAt;
  V3SelfReschedulingTicker? _foregroundTicker;

  final List<String> _optimizedPutnikIds = [];
  final Map<String, int> _etaSecondsCache = {};

  bool get isRunning => _isRunning;
  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
  String get activeDatumIso => _activeDatumIso;
  String get activeGrad => _activeGrad;
  String get activeVreme => _activeVreme;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Pokreće tracking za termin. Termin se postavlja ovde (jedan API).
  Future<void> start({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final normalizedVozacId = vozacId.trim();
    final normalizedDatum = V3BelgradeTime.parseIsoDatePart(datumIso);
    final normalizedGrad = grad.trim().toUpperCase();
    final normalizedVreme = V3BelgradeTime.normalizeToHHmm(vreme);

    debugPrint(
        '[V3VozacLocationTrackingService] start vozac=$normalizedVozacId $normalizedGrad $normalizedVreme');

    if (normalizedVozacId.isEmpty ||
        normalizedDatum.isEmpty ||
        normalizedGrad.isEmpty ||
        normalizedVreme.isEmpty) {
      debugPrint('[V3VozacLocationTrackingService] start prekinut: nedostaju podaci');
      return;
    }
    if (_startInProgress) {
      debugPrint('[V3VozacLocationTrackingService] start u toku, preskačem');
      return;
    }
    _startInProgress = true;

    try {
      if (_isRunning) await stop();

      _activeVozacId = normalizedVozacId;
      _activeDatumIso = normalizedDatum;
      _activeGrad = normalizedGrad;
      _activeVreme = normalizedVreme;
      _trackingStartedAt = V3BelgradeTime.now();
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();

      if (!await v3CheckLocationPrerequisites(logTag: '[V3VozacLocationTrackingService]')) {
        await stop();
        return;
      }

      // Slot aktivacija SAMO ovde (main isolate) — BG ne radi activate.
      unawaited(activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: normalizedVozacId,
        datumIso: _activeDatumIso,
        grad: _activeGrad,
        vreme: _activeVreme,
        logTag: '[V3VozacLocationTrackingService]',
        log: debugPrint,
      ));

      _isRunning = true;
      _startForegroundTicker();
      // BG se diže tek kad app ode u background (vidi lifecycle).
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    debugPrint('[V3VozacLocationTrackingService] stop()');
    _startInProgress = false;
    final vozacIdToClean = _activeVozacId;
    _activeVozacId = '';
    _activeDatumIso = '';
    _activeGrad = '';
    _activeVreme = '';
    _isRunning = false;
    _trackingStartedAt = null;
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    _foregroundTicker?.cancel();
    _foregroundTicker = null;
    unawaited(_stopBackgroundTracking());

    if (vozacIdToClean.isNotEmpty) {
      await v3ClearEtaForVozac(
        client: Supabase.instance.client,
        vozacId: vozacIdToClean,
        logTag: '[V3VozacLocationTrackingService]',
      );
    }
  }

  /// Jednokratni GPS+ETA (UI resume / odmah reoptimizacija).
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      return (etaMap: <String, int>{}, order: <String>[]);
    }
    try {
      final result = await v3RunTrackingTick(
        client: Supabase.instance.client,
        vozacId: _activeVozacId,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
        logTag: '[V3VozacLocationTrackingService]',
        log: debugPrint,
      );
      _applyEtaCache(result.etaMap, result.order);
      return (etaMap: result.etaMap, order: result.order);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] fetchPositionAndComputeEta error: $e');
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();
      return (etaMap: <String, int>{}, order: <String>[]);
    }
  }

  void _applyEtaCache(Map<String, int> etaMap, List<String> order) {
    _optimizedPutnikIds
      ..clear()
      ..addAll(order);
    _etaSecondsCache
      ..clear()
      ..addAll(etaMap);
  }

  void _startForegroundTicker() {
    _foregroundTicker?.cancel();
    _foregroundTicker = V3SelfReschedulingTicker(
      interval: v3TrackingTickInterval,
      onTick: _foregroundTick,
    )..start();
  }

  Future<void> _foregroundTick() async {
    if (!_isRunning) return;
    if (v3TrackingTimedOut(_trackingStartedAt)) {
      debugPrint('[V3VozacLocationTrackingService] stop reason=timeout');
      await stop();
      return;
    }
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      return;
    }

    try {
      final result = await v3RunTrackingTick(
        client: Supabase.instance.client,
        vozacId: _activeVozacId,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
        logTag: '[V3VozacLocationTrackingService]',
        log: debugPrint,
      );
      _applyEtaCache(result.etaMap, result.order);

      final allDone = await v3AllPassengersCompleted(
        client: Supabase.instance.client,
        datumIso: _activeDatumIso,
        grad: _activeGrad,
        vreme: _activeVreme,
        logTag: '[V3VozacLocationTrackingService]',
      );
      if (allDone) {
        debugPrint('[V3VozacLocationTrackingService] stop reason=all_passengers_completed');
        await stop();
      }
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] tick error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRunning) {
      if (state == AppLifecycleState.detached) {
        stop();
      }
      return;
    }

    // Jedan izvor tick-ova: FG u foregroundu, BG samo kad je app stvarno u pozadini.
    if (state == AppLifecycleState.inactive) {
      // Kratki prekid (npr. control center) — samo pauziraj FG, ne diži BG.
      _foregroundTicker?.cancel();
      _foregroundTicker = null;
      return;
    }
    if (state == AppLifecycleState.paused) {
      _foregroundTicker?.cancel();
      _foregroundTicker = null;
      unawaited(_startBackgroundTracking());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_stopBackgroundTracking());
      if (_foregroundTicker == null) _startForegroundTicker();
      return;
    }

    if (state == AppLifecycleState.detached) {
      stop();
    }
  }

  Future<void> _startBackgroundTracking() async {
    if (_activeVozacId.isEmpty) return;
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
      service.invoke('startTracking', <String, dynamic>{
        'vozac_id': _activeVozacId,
        'datum_iso': _activeDatumIso,
        'grad': _activeGrad,
        'vreme': _activeVreme,
        'started_at': _trackingStartedAt?.toUtc().toIso8601String(),
      });
      debugPrint('[V3VozacLocationTrackingService] BG tracking startovan');
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] BG start greška: $e');
    }
  }

  Future<void> _stopBackgroundTracking() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopTracking');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      service.invoke('stopService');
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] BG stop greška: $e');
    }
  }
}
