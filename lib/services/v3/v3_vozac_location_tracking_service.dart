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
/// Tick (svakih 20s, bez dodatnih uslova): live GPS → `v3_vozac_location`
/// (jedini izvor istine) → `v3-compute-eta` (OSRM reoptimizacija).
/// Stop: polazak+55min, svi putnici gotovi, ili ručni stop.
/// Na stop: FG ticker + BG foreground service (GPS + persistent notif) se gase.
/// `activateSlotWithRetry` → `tracking_started_at` → DB trigger putnicima.
///
/// Lifecycle:
/// - paused/hidden → BG FGS (isti tickovi)
/// - resumed → ugasi BG, nastavi FG
/// - detached dok traje vožnja → NE gasi tracking (FGS ostaje)
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
  bool _stopInProgress = false;
  DateTime? _startedAt;
  DateTime? _polazakAt;
  V3SelfReschedulingTicker? _fgTicker;
  StreamSubscription<Map<String, dynamic>?>? _bgEndedSub;

  final List<String> _optimizedPutnikIds = [];

  /// Emituje se posle svakog uspešnog GPS+ETA tick-a (FG i jednokratni fetch).
  final StreamController<({Map<String, int> etaMap, List<String> order})> _etaTickController =
      StreamController<({Map<String, int> etaMap, List<String> order})>.broadcast();

  bool get isRunning => _isRunning;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);

  /// Stream rezultata svakog tick-a — UI sluša radi re-sort kartica/rute.
  Stream<({Map<String, int> etaMap, List<String> order})> get onEtaTick => _etaTickController.stream;

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    // BG isolate (timeout / svi putnici) → main mora da spusti _isRunning,
    // inače bi na resume ponovo digao FG ticker / BG servis.
    _bgEndedSub?.cancel();
    _bgEndedSub = FlutterBackgroundService().on('trackingEnded').listen((event) {
      final reason = event?['reason']?.toString() ?? 'bg';
      debugPrint('$_tag BG trackingEnded reason=$reason');
      if (_isRunning || _vozacId.isNotEmpty) {
        unawaited(stop());
      }
    });
  }

  Map<String, dynamic> _sessionPayload() => <String, dynamic>{
        'vozac_id': _vozacId,
        'datum_iso': _datumIso,
        'grad': _grad,
        'vreme': _vreme,
        'started_at': _startedAt?.toUtc().toIso8601String(),
        'polazak_at': _polazakAt?.toUtc().toIso8601String(),
      };

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
      // Prefs pre prvog BG starta — isolate može da se digne i bez uspešnog invoke-a.
      await v3SaveBgTrackingSession(_sessionPayload());
      _startFgTicker();
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    if (_stopInProgress) return;
    _stopInProgress = true;
    debugPrint('$_tag stop()');
    try {
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
      await v3ClearBgTrackingSession();
      // Sačekaj da BG foreground service + notifikacija stvarno nestanu.
      await _stopBg();

      if (vozacIdToClean.isNotEmpty) {
        await v3ClearEtaForVozac(client: Supabase.instance.client, vozacId: vozacIdToClean);
      }
    } finally {
      _stopInProgress = false;
    }
  }

  /// Jednokratni GPS+ETA (UI resume / reoptimizacija).
  /// UI refresh ide preko [onEtaTick] — ne duplicirati u caller-ima.
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_vozacId.isEmpty) return (etaMap: <String, int>{}, order: List<String>.from(_optimizedPutnikIds));
    try {
      return await _runTick();
    } catch (e) {
      debugPrint('$_tag fetchPositionAndComputeEta error: $e');
      // Zadrži poslednji dobar redosled — ne briši zbog prolazne greške.
      return (etaMap: <String, int>{}, order: List<String>.from(_optimizedPutnikIds));
    }
  }

  void _startFgTicker() {
    _fgTicker?.cancel();
    _fgTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _fgTick)..start();
  }

  /// Svaki tick: live GPS → upsert lokacije → OSRM ETA/reopt. Bez distance/speed gate-ova.
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
    if (!_etaTickController.isClosed) {
      _etaTickController.add(result);
    }
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
    if (!_isRunning) return;

    switch (state) {
      case AppLifecycleState.inactive:
        // Ne gasimo FG ovde — kratki UI prekidi (shade/dialog). BG digne paused.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _fgTicker?.cancel();
        _fgTicker = null;
        unawaited(_startBg());
        break;
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
        break;
      case AppLifecycleState.detached:
        // App engine nestaje, ali FGS mora da nastavi vožnju.
        _fgTicker?.cancel();
        _fgTicker = null;
        unawaited(_startBg());
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
    // Ako je BG završio vožnju dok je app bio u pozadini, a event nije stigao.
    if (_vozacId.isNotEmpty && _datumIso.isNotEmpty && _grad.isNotEmpty && _vreme.isNotEmpty) {
      try {
        final allDone = await v3AllPassengersCompleted(
          client: Supabase.instance.client,
          datumIso: _datumIso,
          grad: _grad,
          vreme: _vreme,
        );
        if (allDone) {
          debugPrint('$_tag stop reason=all_passengers_completed_on_resume');
          await stop();
          return;
        }
      } catch (e) {
        debugPrint('$_tag resume allDone check greška: $e');
      }
    }
    // Odmah jedan tick sa live GPS (ne čekaj interval) + nastavi FG ticker.
    if (_fgTicker == null) _startFgTicker();
  }

  Future<void> _startBg() async {
    if (_vozacId.isEmpty || !_isRunning) return;
    try {
      final payload = _sessionPayload();
      // Prvo prefs — BG onStart čita ovo ako invoke stigne pre listener-a.
      await v3SaveBgTrackingSession(payload);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }

      // Android servicePipe dropuje event dok isolate nema listener — retry.
      for (var i = 0; i < 8; i++) {
        service.invoke('startTracking', payload);
        await Future<void>.delayed(Duration(milliseconds: 150 + (i * 50)));
        if (await service.isRunning()) {
          // Jedan uspešan invoke posle što je servis up je dovoljan u praksi;
          // prefs je ionako fallback u onStart.
          if (i >= 2) break;
        }
      }
      debugPrint('$_tag BG startovan');
    } catch (e) {
      debugPrint('$_tag BG start greška: $e');
    }
  }

  /// Gasi BG foreground service → nestaje persistent notifikacija i GPS tickovi.
  Future<void> _stopBg() async {
    try {
      final service = FlutterBackgroundService();
      final running = await service.isRunning();
      if (!running) return;

      service.invoke('stopService');
      // Sačekaj da Android stvarno ugasi FGS (notifikacija 888).
      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!await service.isRunning()) {
          debugPrint('$_tag BG zaustavljen');
          return;
        }
      }
      debugPrint('$_tag BG još radi posle stopService — ponavljam');
      service.invoke('stopService');
    } catch (e) {
      debugPrint('$_tag BG stop greška: $e');
    }
  }
}
