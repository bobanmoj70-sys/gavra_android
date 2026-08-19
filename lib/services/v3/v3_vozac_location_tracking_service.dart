import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

/// Ishod [V3VozacLocationTrackingService.start].
enum V3TrackingStartResult {
  started,
  alreadyRunning,
  missingData,
  inProgress,
  gpsDisabled,
  permissionDenied,
  permissionDeniedForever,
  permissionAlwaysRequired,
  failed,
}

extension V3TrackingStartResultX on V3TrackingStartResult {
  bool get isSuccess => this == V3TrackingStartResult.started || this == V3TrackingStartResult.alreadyRunning;

  /// l10n ključ za grešku; `null` ako je uspeh.
  String? get errorL10nKey => switch (this) {
        V3TrackingStartResult.started || V3TrackingStartResult.alreadyRunning => null,
        V3TrackingStartResult.gpsDisabled => 'gpsIskljucen',
        V3TrackingStartResult.permissionDenied => 'dozvolaOdbijena',
        V3TrackingStartResult.permissionDeniedForever => 'dozvolaTrajnoOdbijena',
        V3TrackingStartResult.permissionAlwaysRequired => 'dozvolaPotrebnaUvek',
        V3TrackingStartResult.missingData ||
        V3TrackingStartResult.inProgress ||
        V3TrackingStartResult.failed =>
          'nemogucIdentifikovatiVozaca',
      };
}

/// GPS/ETA tracking vozača — jedan izvor istine za FG i BG.
///
/// Start: V3VozacScreen auto-start (T-15). Zahteva GPS + **Always**.
/// Tick (20s): live GPS → `v3_vozac_location` → `v3-compute-eta`.
/// Stop: polazak+40, svi putnici gotovi, ili ručni stop.
///
/// Platforme (dok traje vožnja):
/// - **Android** — FGS notifikacija živi dok je tracking aktivan
/// - **Android FG** — main ticker; FGS ticker pauziran
/// - **Android BG** — FGS isolate ticker; main ticker ugašen
/// - **iOS** — uvek main ticker + location keep-alive (nema pouzdanog FGS)
/// - cold start — [tryRestoreFromSession] iz prefs / FGS
class V3VozacLocationTrackingService with WidgetsBindingObserver {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  static const _tag = '[V3VozacLocationTrackingService]';
  static const _bgNotificationId = 888;

  String _vozacId = '';
  String _datumIso = '';
  String _grad = '';
  String _vreme = '';
  bool _isRunning = false;
  bool _startInProgress = false;
  bool _stopInProgress = false;
  bool _restoreInProgress = false;
  DateTime? _startedAt;
  DateTime? _polazakAt;
  DateTime? _lastTickAt;
  V3SelfReschedulingTicker? _fgTicker;
  StreamSubscription<Map<String, dynamic>?>? _bgEndedSub;
  StreamSubscription<Position>? _iosKeepAliveSub;
  bool _tickInFlight = false;

  final List<String> _optimizedPutnikIds = [];

  final StreamController<({Map<String, int> etaMap, List<String> order})> _etaTickController =
      StreamController<({Map<String, int> etaMap, List<String> order})>.broadcast();

  final StreamController<bool> _runningController = StreamController<bool>.broadcast();

  bool get isRunning => _isRunning;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);

  /// Aktivna tracking sesija (prazno ako ne radi). Nezavisno od UI selekcije termina.
  String get activeDatumIso => _isRunning ? _datumIso : '';
  String get activeGrad => _isRunning ? _grad : '';
  String get activeVreme => _isRunning ? _vreme : '';

  Stream<({Map<String, int> etaMap, List<String> order})> get onEtaTick => _etaTickController.stream;
  Stream<bool> get onRunningChanged => _runningController.stream;

  void _setRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    if (!_runningController.isClosed) {
      _runningController.add(value);
    }
  }

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _bgEndedSub?.cancel();
    _bgEndedSub = FlutterBackgroundService().on('trackingEnded').listen((event) {
      final reason = event?['reason']?.toString() ?? 'bg';
      debugPrint('$_tag BG trackingEnded reason=$reason');
      if (_isRunning || _vozacId.isNotEmpty) {
        unawaited(stop());
      } else {
        unawaited(v3ClearBgTrackingSession());
      }
    });
    unawaited(tryRestoreFromSession());
  }

  Map<String, dynamic> _sessionPayload({bool ticksPaused = false}) => <String, dynamic>{
        'vozac_id': _vozacId,
        'datum_iso': _datumIso,
        'grad': _grad,
        'vreme': _vreme,
        'started_at': _startedAt?.toUtc().toIso8601String(),
        'polazak_at': _polazakAt?.toUtc().toIso8601String(),
        'ticks_paused': ticksPaused,
      };

  bool _isSameSession({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) {
    return _isRunning && _vozacId == vozacId && _datumIso == datumIso && _grad == grad && _vreme == vreme;
  }

  bool get _isAppInForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  V3TrackingStartResult _prereqToStartResult(V3LocationPrereqResult prereq) => switch (prereq) {
        V3LocationPrereqResult.ok => V3TrackingStartResult.failed,
        V3LocationPrereqResult.gpsDisabled => V3TrackingStartResult.gpsDisabled,
        V3LocationPrereqResult.denied => V3TrackingStartResult.permissionDenied,
        V3LocationPrereqResult.deniedForever => V3TrackingStartResult.permissionDeniedForever,
        V3LocationPrereqResult.alwaysRequired => V3TrackingStartResult.permissionAlwaysRequired,
      };

  /// Jedno mesto: koji engine radi (main ticker / Android FGS / iOS keep-alive).
  Future<void> _syncEngines({bool immediateTick = true}) async {
    if (!_isRunning || _vozacId.isEmpty) return;

    await v3SaveBgTrackingSession(
      _sessionPayload(ticksPaused: !Platform.isIOS && _isAppInForeground),
    );

    if (Platform.isIOS) {
      // iOS: main isolate mora da ostane živ — ticker + continuous location.
      _startIosLocationKeepAlive();
      if (_fgTicker == null) _startFgTicker();
      if (immediateTick) unawaited(_fgTick());
      return;
    }

    // Android: notifikacija ostaje dok je tracking aktivan.
    // FG = main ticker (FGS ticker pauziran); BG = FGS ticker.
    await _ensureBgServiceRunning();
    if (_isAppInForeground) {
      await _pauseBgTicks();
      if (_fgTicker == null) _startFgTicker();
      if (immediateTick) unawaited(_fgTick());
    } else {
      _fgTicker?.cancel();
      _fgTicker = null;
      await _startBg();
    }
  }

  /// Reattach posle process death / cold start. Ne zove activate (već urađeno).
  Future<bool> tryRestoreFromSession() async {
    if (_isRunning) return true;
    if (_startInProgress || _stopInProgress || _restoreInProgress) return _isRunning;
    _restoreInProgress = true;

    try {
      final saved = await v3LoadBgTrackingSession();
      var bgRunning = false;
      if (!Platform.isIOS) {
        try {
          bgRunning = await FlutterBackgroundService().isRunning();
        } catch (e) {
          debugPrint('$_tag restore isRunning greška: $e');
        }
      }

      if (saved == null) {
        if (bgRunning) {
          debugPrint('$_tag restore: orphan BG bez sesije — gasim');
          await _stopBg();
        }
        return false;
      }

      final id = (saved['vozac_id']?.toString() ?? '').trim();
      final datum = V3BelgradeTime.parseIsoDatePart(saved['datum_iso']?.toString() ?? '');
      final g = (saved['grad']?.toString() ?? '').trim().toUpperCase();
      final v = V3BelgradeTime.normalizeToHHmm(saved['vreme']?.toString() ?? '');
      if (id.isEmpty || datum.isEmpty || g.isEmpty || v.isEmpty) {
        debugPrint('$_tag restore: neispravna sesija');
        await v3ClearBgTrackingSession();
        if (bgRunning) await _stopBg();
        return false;
      }

      final startedAt = V3BelgradeTime.parseTs(saved['started_at']?.toString());
      final polazakAt =
          V3BelgradeTime.parseTs(saved['polazak_at']?.toString()) ?? v3PolazakDateTime(datumIso: datum, vreme: v);

      if (v3TrackingTimedOut(startedAt: startedAt, polazakAt: polazakAt)) {
        debugPrint('$_tag restore: sesija istekla');
        await v3ClearBgTrackingSession();
        if (bgRunning) await _stopBg();
        return false;
      }

      final prereq = await v3CheckLocationPrerequisites();
      if (prereq != V3LocationPrereqResult.ok) {
        debugPrint('$_tag restore: nema Always GPS ($prereq) — stop');
        await v3ClearBgTrackingSession();
        if (bgRunning) await _stopBg();
        return false;
      }

      _vozacId = id;
      _datumIso = datum;
      _grad = g;
      _vreme = v;
      _startedAt = startedAt ?? V3BelgradeTime.now();
      _polazakAt = polazakAt;
      _lastTickAt = null;
      _optimizedPutnikIds.clear();
      _setRunning(true);

      debugPrint('$_tag restore OK $g $v bgRunning=$bgRunning fg=$_isAppInForeground');
      // Jednom po T-15..T+40 prozoru — RPC je no-op ako je već poslato.
      await activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: id,
        datumIso: datum,
        grad: g,
        vreme: v,
        logTag: _tag,
        log: debugPrint,
      );
      await _syncEngines(immediateTick: true);
      return true;
    } catch (e) {
      debugPrint('$_tag restore greška: $e');
      return false;
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<V3TrackingStartResult> start({
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
      return V3TrackingStartResult.missingData;
    }
    if (_startInProgress || _restoreInProgress) {
      debugPrint('$_tag start u toku, preskačem');
      return V3TrackingStartResult.inProgress;
    }

    if (_isSameSession(vozacId: id, datumIso: datum, grad: g, vreme: v)) {
      debugPrint('$_tag start: ista sesija već radi');
      if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
        await stop();
        return V3TrackingStartResult.failed;
      }
      // Garantuj push jednom po prozoru ako prvi put nije prošao.
      await activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: id,
        datumIso: datum,
        grad: g,
        vreme: v,
        logTag: _tag,
        log: debugPrint,
      );
      await _syncEngines(immediateTick: true);
      return V3TrackingStartResult.alreadyRunning;
    }

    _startInProgress = true;

    try {
      if (_isRunning) {
        await stop();
      } else {
        await _stopBg();
      }

      _vozacId = id;
      _datumIso = datum;
      _grad = g;
      _vreme = v;
      _polazakAt = v3PolazakDateTime(datumIso: datum, vreme: v);
      _startedAt = V3BelgradeTime.now();
      _lastTickAt = null;
      _optimizedPutnikIds.clear();

      if (_polazakAt == null || !v3IsTrackingWindowOpen(polazakAt: _polazakAt!)) {
        debugPrint('$_tag start prekinut: van T-15..T+40');
        await _resetLocalSessionFields();
        return V3TrackingStartResult.failed;
      }

      final prereq = await v3CheckLocationPrerequisites();
      if (prereq != V3LocationPrereqResult.ok) {
        debugPrint('$_tag start prekinut: $prereq');
        await _resetLocalSessionFields();
        return _prereqToStartResult(prereq);
      }

      // Slot aktivacija SAMO ovde (main) — BG ne radi activate.
      await activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: id,
        datumIso: datum,
        grad: g,
        vreme: v,
        logTag: _tag,
        log: debugPrint,
      );

      _setRunning(true);
      await _syncEngines(immediateTick: true);
      return V3TrackingStartResult.started;
    } catch (e) {
      debugPrint('$_tag start greška: $e');
      await stop();
      return V3TrackingStartResult.failed;
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> _resetLocalSessionFields() async {
    _vozacId = '';
    _datumIso = '';
    _grad = '';
    _vreme = '';
    _polazakAt = null;
    _startedAt = null;
    _lastTickAt = null;
    _optimizedPutnikIds.clear();
    _setRunning(false);
    await v3ClearBgTrackingSession();
  }

  Future<void> stop() async {
    if (_stopInProgress) return;
    _stopInProgress = true;
    debugPrint('$_tag stop()');
    try {
      _startInProgress = false;
      _vozacId = '';
      _datumIso = '';
      _grad = '';
      _vreme = '';
      _polazakAt = null;
      _startedAt = null;
      _lastTickAt = null;
      _optimizedPutnikIds.clear();
      _setRunning(false);

      _fgTicker?.cancel();
      _fgTicker = null;
      await _stopIosLocationKeepAlive();
      await v3ClearBgTrackingSession();
      await _stopBg();

      // ETA se NE briše ovde. Poslednji red ostaje putniku do:
      // T+40 prozora / pokupljen / otkazan / retention 55min (sve u edge-u).
    } finally {
      _stopInProgress = false;
    }
  }

  /// Jednokratni GPS+ETA (UI resume / reoptimizacija).
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_vozacId.isEmpty) return (etaMap: <String, int>{}, order: List<String>.from(_optimizedPutnikIds));
    try {
      return await _runTick();
    } catch (e) {
      debugPrint('$_tag fetchPositionAndComputeEta error: $e');
      return (etaMap: <String, int>{}, order: List<String>.from(_optimizedPutnikIds));
    }
  }

  void _startFgTicker() {
    _fgTicker?.cancel();
    _fgTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _fgTick)..start();
  }

  /// iOS: continuous CLLocationManager — sprečava suspend tokom vožnje.
  void _startIosLocationKeepAlive() {
    if (!Platform.isIOS || !_isRunning) return;
    if (_iosKeepAliveSub != null) return;

    debugPrint('$_tag iOS location keep-alive start');
    _iosKeepAliveSub = Geolocator.getPositionStream(
      locationSettings: v3IosBackgroundStreamSettings,
    ).listen(
      (position) {
        if (!_isRunning) return;
        final last = _lastTickAt;
        if (last != null && DateTime.now().difference(last) < v3TrackingTickInterval) {
          return;
        }
        unawaited(_fgTick());
      },
      onError: (Object e) {
        debugPrint('$_tag iOS location stream error: $e');
      },
      cancelOnError: false,
    );
  }

  Future<void> _stopIosLocationKeepAlive() async {
    if (_iosKeepAliveSub == null) return;
    await _iosKeepAliveSub!.cancel();
    _iosKeepAliveSub = null;
    debugPrint('$_tag iOS location keep-alive stop');
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
    _lastTickAt = DateTime.now();
    // Prazan odgovor (OSRM greška / no location) ne briše poslednji dobar redosled.
    if (result.order.isNotEmpty) {
      _optimizedPutnikIds
        ..clear()
        ..addAll(result.order);
    }
    if (!_etaTickController.isClosed) {
      _etaTickController.add(result);
    }
    return result;
  }

  Future<void> _fgTick() async {
    if (!_isRunning || _tickInFlight || _vozacId.isEmpty) return;
    if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
      debugPrint('$_tag stop reason=timeout polazak=$_polazakAt');
      await stop();
      return;
    }

    _tickInFlight = true;
    try {
      await _runTick();
      final allDone = await v3AllPassengersCompleted(
        client: Supabase.instance.client,
        vozacId: _vozacId,
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
    } finally {
      _tickInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
      return;
    }
    if (!_isRunning) return;

    switch (state) {
      case AppLifecycleState.inactive:
        // Kratki UI prekidi — ne diraj engine.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_syncEngines(immediateTick: false));
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> _onResumed() async {
    if (!_isRunning) {
      final restored = await tryRestoreFromSession();
      if (!restored) return;
    }
    if (!_isRunning) return;

    if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
      debugPrint('$_tag stop reason=timeout_on_resume');
      await stop();
      return;
    }

    if (_vozacId.isNotEmpty && _datumIso.isNotEmpty && _grad.isNotEmpty && _vreme.isNotEmpty) {
      try {
        final allDone = await v3AllPassengersCompleted(
          client: Supabase.instance.client,
          vozacId: _vozacId,
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

    await _syncEngines(immediateTick: true);
  }

  Future<void> _startBg() async {
    if (_vozacId.isEmpty || !_isRunning || Platform.isIOS) return;
    try {
      final payload = _sessionPayload(ticksPaused: false);
      await v3SaveBgTrackingSession(payload);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }

      // servicePipe može dropovati event pre listenera — prefs je fallback.
      for (var i = 0; i < 4; i++) {
        service.invoke('startTracking', payload);
        await Future<void>.delayed(Duration(milliseconds: 200 + (i * 100)));
        if (await service.isRunning() && i >= 1) break;
      }
      debugPrint('$_tag BG startovan');
    } catch (e) {
      debugPrint('$_tag BG start greška: $e');
    }
  }

  Future<void> _ensureBgServiceRunning() async {
    if (_vozacId.isEmpty || !_isRunning || Platform.isIOS) return;
    try {
      await v3SaveBgTrackingSession(_sessionPayload(ticksPaused: _isAppInForeground));
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
    } catch (e) {
      debugPrint('$_tag BG ensure greška: $e');
    }
  }

  Future<void> _pauseBgTicks() async {
    if (Platform.isIOS) return;
    try {
      await v3SaveBgTrackingSession(_sessionPayload(ticksPaused: true));
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) return;
      service.invoke('pauseTicks');
    } catch (e) {
      debugPrint('$_tag BG pause greška: $e');
    }
  }

  Future<void> _cancelBgNotification() async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(_bgNotificationId);
    } catch (e) {
      debugPrint('$_tag cancel BG notifikacije greška: $e');
    }
  }

  Future<void> _stopBg() async {
    if (Platform.isIOS) return;
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
        for (var i = 0; i < 15; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!await service.isRunning()) {
            debugPrint('$_tag BG zaustavljen');
            break;
          }
        }
        if (await service.isRunning()) {
          debugPrint('$_tag BG još radi posle stopService — ponavljam');
          service.invoke('stopService');
        }
      }
    } catch (e) {
      debugPrint('$_tag BG stop greška: $e');
    }
    await _cancelBgNotification();
  }
}
