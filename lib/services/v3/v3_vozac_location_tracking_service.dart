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
/// Tick: FG u foregroundu, BG isolate kad je app paused.
/// Stop: polazak+55min, svi putnici gotovi, ili ručni stop.
/// `activateSlotWithRetry` → `tracking_started_at` → DB trigger putnicima.
class V3VozacLocationTrackingService with WidgetsBindingObserver {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  static const _tag = '[V3VozacLocationTrackingService]';

  String _vozacId = '';
  String _datumIso = '';
  String _grad = '';
  String _vreme = '';
  bool _isRunning = false;
  bool _startInProgress = false;
  DateTime? _startedAt;
  DateTime? _polazakAt;
  V3SelfReschedulingTicker? _fgTicker;

  final List<String> _optimizedPutnikIds = [];

  bool get isRunning => _isRunning;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> start({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final id = vozacId.trim();
    final datum = V3BelgradeTime.parseIsoDatePart(datumIso);
    final g = grad.trim().toUpperCase();
    final v = V3BelgradeTime.normalizeToHHmm(vreme);

    debugPrint('$_tag start vozac=$id $g $v');

    if (id.isEmpty || datum.isEmpty || g.isEmpty || v.isEmpty) {
      debugPrint('$_tag start prekinut: nedostaju podaci');
      return;
    }
    if (_startInProgress) {
      debugPrint('$_tag start u toku, preskačem');
      return;
    }
    _startInProgress = true;

    try {
      if (_isRunning) await stop();

      _vozacId = id;
      _datumIso = datum;
      _grad = g;
      _vreme = v;
      _polazakAt = v3PolazakDateTime(datumIso: datum, vreme: v);
      _startedAt = V3BelgradeTime.now();
      _optimizedPutnikIds.clear();

      if (!await v3CheckLocationPrerequisites()) {
        await stop();
        return;
      }

      // Slot aktivacija SAMO ovde (main isolate) — BG ne radi activate.
      unawaited(activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: id,
        datumIso: datum,
        grad: g,
        vreme: v,
        logTag: _tag,
        log: debugPrint,
      ));

      _isRunning = true;
      _startFgTicker();
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    debugPrint('$_tag stop()');
    _startInProgress = false;
    final vozacIdToClean = _vozacId;
    _vozacId = '';
    _datumIso = '';
    _grad = '';
    _vreme = '';
    _polazakAt = null;
    _startedAt = null;
    _isRunning = false;
    _optimizedPutnikIds.clear();

    _fgTicker?.cancel();
    _fgTicker = null;
    unawaited(_stopBg());

    if (vozacIdToClean.isNotEmpty) {
      await v3ClearEtaForVozac(client: Supabase.instance.client, vozacId: vozacIdToClean);
    }
  }

  /// Jednokratni GPS+ETA (UI resume / reoptimizacija).
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_vozacId.isEmpty) return (etaMap: <String, int>{}, order: <String>[]);
    try {
      return await _runTick();
    } catch (e) {
      debugPrint('$_tag fetchPositionAndComputeEta error: $e');
      _optimizedPutnikIds.clear();
      return (etaMap: <String, int>{}, order: <String>[]);
    }
  }

  void _startFgTicker() {
    _fgTicker?.cancel();
    _fgTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _fgTick)..start();
  }

  Future<({Map<String, int> etaMap, List<String> order})> _runTick() async {
    final result = await v3RunTrackingTick(
      client: Supabase.instance.client,
      vozacId: _vozacId,
      grad: _grad,
      vreme: _vreme,
      datumIso: _datumIso,
      logTag: _tag,
    );
    _optimizedPutnikIds
      ..clear()
      ..addAll(result.order);
    return result;
  }

  Future<void> _fgTick() async {
    if (!_isRunning) return;
    if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
      debugPrint('$_tag stop reason=timeout polazak=$_polazakAt');
      await stop();
      return;
    }
    if (_vozacId.isEmpty) return;

    try {
      await _runTick();
      final allDone = await v3AllPassengersCompleted(
        client: Supabase.instance.client,
        datumIso: _datumIso,
        grad: _grad,
        vreme: _vreme,
      );
      if (allDone) {
        debugPrint('$_tag stop reason=all_passengers_completed');
        await stop();
      }
    } catch (e) {
      debugPrint('$_tag tick error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRunning) {
      if (state == AppLifecycleState.detached) stop();
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
        // Kratki prekid (control center) — pauza FG, bez BG.
        _fgTicker?.cancel();
        _fgTicker = null;
      case AppLifecycleState.paused:
        _fgTicker?.cancel();
        _fgTicker = null;
        unawaited(_startBg());
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
      case AppLifecycleState.detached:
        stop();
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _onResumed() async {
    await _stopBg();
    if (!_isRunning) return;
    if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
      debugPrint('$_tag stop reason=timeout_on_resume');
      await stop();
      return;
    }
    if (_fgTicker == null) _startFgTicker();
  }

  Future<void> _startBg() async {
    if (_vozacId.isEmpty) return;
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
      service.invoke('startTracking', <String, dynamic>{
        'vozac_id': _vozacId,
        'datum_iso': _datumIso,
        'grad': _grad,
        'vreme': _vreme,
        'started_at': _startedAt?.toUtc().toIso8601String(),
        'polazak_at': _polazakAt?.toUtc().toIso8601String(),
      });
      debugPrint('$_tag BG startovan');
    } catch (e) {
      debugPrint('$_tag BG start greška: $e');
    }
  }

  Future<void> _stopBg() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopTracking');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      service.invoke('stopService');
    } catch (e) {
      debugPrint('$_tag BG stop greška: $e');
    }
  }
}