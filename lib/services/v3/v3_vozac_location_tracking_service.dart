import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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
/// - **Android** paused/hidden → ugasi FG ticker, digne BG FGS (isti tickovi)
/// - **iOS** paused/hidden → zadrži FG ticker + location stream keep-alive
///   (nema pravog FGS; UIBackgroundModes=location + Always drži proces)
/// - resumed → ugasi BG (Android), nastavi FG
/// - detached dok traje vožnja → NE gasi tracking (FGS / iOS stream ostaje)
/// - cold start → [tryRestoreFromSession] reattach na prefs / orphan FGS
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
  bool _restoreInProgress = false;
  DateTime? _startedAt;
  DateTime? _polazakAt;
  DateTime? _lastTickAt;
  V3SelfReschedulingTicker? _fgTicker;
  StreamSubscription<Map<String, dynamic>?>? _bgEndedSub;
  StreamSubscription<Position>? _iosKeepAliveSub;
  bool _tickInFlight = false;

  final List<String> _optimizedPutnikIds = [];

  /// Emituje se posle svakog uspešnog GPS+ETA tick-a (FG i jednokratni fetch).
  final StreamController<({Map<String, int> etaMap, List<String> order})> _etaTickController =
      StreamController<({Map<String, int> etaMap, List<String> order})>.broadcast();

  /// UI sluša da sinkronizuje `_isNavigating` (start / stop / BG ended / restore).
  final StreamController<bool> _runningController = StreamController<bool>.broadcast();

  bool get isRunning => _isRunning;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);

  /// Stream rezultata svakog tick-a — UI sluša radi re-sort kartica/rute.
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
    // BG isolate (timeout / svi putnici) → main mora da spusti _isRunning,
    // inače bi na resume ponovo digao FG ticker / BG servis.
    _bgEndedSub?.cancel();
    _bgEndedSub = FlutterBackgroundService().on('trackingEnded').listen((event) {
      final reason = event?['reason']?.toString() ?? 'bg';
      debugPrint('$_tag BG trackingEnded reason=$reason');
      if (_isRunning || _vozacId.isNotEmpty) {
        unawaited(stop());
      } else {
        // Main već mrtav, a FGS je sam završio — očisti orphan prefs.
        unawaited(v3ClearBgTrackingSession());
      }
    });
    // Cold start: FGS / prefs sesija može biti živa dok je _isRunning false.
    unawaited(tryRestoreFromSession());
  }

  Map<String, dynamic> _sessionPayload() => <String, dynamic>{
        'vozac_id': _vozacId,
        'datum_iso': _datumIso,
        'grad': _grad,
        'vreme': _vreme,
        'started_at': _startedAt?.toUtc().toIso8601String(),
        'polazak_at': _polazakAt?.toUtc().toIso8601String(),
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

  /// Reattach posle process death / cold start.
  ///
  /// Čita prefs sesiju i/ili Android FGS. Ne zove [activateSlotWithRetry]
  /// (slot je već aktiviran pri originalnom startu).
  /// Vraća `true` ako je tracking ponovo označen kao aktivan.
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

      if (_isAppInForeground) {
        // Preuzmi sa BG FGS-a — spreči dual tick.
        if (!Platform.isIOS) {
          await _stopBg();
        }

        final prereq = await v3CheckLocationPrerequisites();
        if (prereq != V3LocationPrereqResult.ok) {
          debugPrint('$_tag restore: nema Always GPS ($prereq) — stop');
          await stop();
          return false;
        }

        await v3SaveBgTrackingSession(_sessionPayload());
        if (Platform.isIOS) {
          _startIosLocationKeepAlive();
        }
        if (_fgTicker == null) _startFgTicker();
        unawaited(_fgTick());
      } else {
        // App još u pozadini — ostavi / digni FGS, bez FG tickera.
        await v3SaveBgTrackingSession(_sessionPayload());
        if (!Platform.isIOS && !bgRunning) {
          unawaited(_startBg());
        }
      }

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

    // Ista sesija već aktivna — reattach FG bez novog activate/stop.
    if (_isSameSession(vozacId: id, datumIso: datum, grad: g, vreme: v)) {
      debugPrint('$_tag start: ista sesija već radi');
      if (_isAppInForeground) {
        if (!Platform.isIOS) await _stopBg();
        if (Platform.isIOS) _startIosLocationKeepAlive();
        if (_fgTicker == null) _startFgTicker();
        unawaited(_fgTick());
      }
      return V3TrackingStartResult.alreadyRunning;
    }

    _startInProgress = true;

    try {
      if (_isRunning) {
        await stop();
      } else {
        // Cold start: orphan FGS iz prethodnog procesa — ugasi pre novog starta.
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

      final prereq = await v3CheckLocationPrerequisites();
      if (prereq != V3LocationPrereqResult.ok) {
        debugPrint('$_tag start prekinut: $prereq');
        await _resetLocalSessionFields();
        return switch (prereq) {
          V3LocationPrereqResult.gpsDisabled => V3TrackingStartResult.gpsDisabled,
          V3LocationPrereqResult.denied => V3TrackingStartResult.permissionDenied,
          V3LocationPrereqResult.deniedForever => V3TrackingStartResult.permissionDeniedForever,
          V3LocationPrereqResult.alwaysRequired => V3TrackingStartResult.permissionAlwaysRequired,
          V3LocationPrereqResult.ok => V3TrackingStartResult.failed,
        };
      }

      // Slot aktivacija SAMO ovde (main isolate) — BG ne radi activate.
      // await: putnički trigger i prvi tick posle stvarnog tracking_started_at.
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
      // Prefs pre prvog BG starta — isolate može da se digne i bez uspešnog invoke-a.
      await v3SaveBgTrackingSession(_sessionPayload());
      _startFgTicker();
      // iOS: location stream odmah — keep-alive i u foreground-u prelazi u BG bez rupe.
      if (Platform.isIOS) {
        _startIosLocationKeepAlive();
      }
      // Odmah prvi tick — ne čekaj prvi 20s interval.
      unawaited(_fgTick());
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
      final vozacIdToClean = _vozacId;
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
      // Sačekaj da BG foreground service + notifikacija stvarno nestanu.
      await _stopBg();

      if (vozacIdToClean.isNotEmpty) {
        try {
          await v3ClearEtaForVozac(client: Supabase.instance.client, vozacId: vozacIdToClean);
        } catch (e) {
          debugPrint('$_tag clearEta greška: $e');
        }
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
      // Zadrži posledji dobar redosled — ne briši zbog prolazne greške.
      return (etaMap: <String, int>{}, order: List<String>.from(_optimizedPutnikIds));
    }
  }

  void _startFgTicker() {
    _fgTicker?.cancel();
    _fgTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _fgTick)..start();
  }

  /// iOS keep-alive: continuous CLLocationManager updates sprečavaju suspend
  /// dok traje vožnja. Kretanje (distanceFilter) može i da ubrza tick.
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
        // Throttle: ne češće od ~tick intervala (stream je keep-alive + backup tick).
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
    _lastTickAt = DateTime.now();
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
    if (_tickInFlight) return;
    if (v3TrackingTimedOut(startedAt: _startedAt, polazakAt: _polazakAt)) {
      debugPrint('$_tag stop reason=timeout polazak=$_polazakAt');
      await stop();
      return;
    }
    if (_vozacId.isEmpty) return;

    _tickInFlight = true;
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
    } finally {
      _tickInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume uvek — i kad _isRunning=false posle cold start (restore iz prefs/FGS).
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
      return;
    }
    if (!_isRunning) return;

    switch (state) {
      case AppLifecycleState.inactive:
        // Ne gasimo FG ovde — kratki UI prekidi (shade/dialog).
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (Platform.isIOS) {
          // iOS nema ekvivalent Android FGS: zadrži FG ticker + location stream.
          // Gasenje ticker-a bi ostavilo samo slab BG fetch → ETA stale posle ~130s.
          _startIosLocationKeepAlive();
          unawaited(v3SaveBgTrackingSession(_sessionPayload()));
        } else {
          _fgTicker?.cancel();
          _fgTicker = null;
          unawaited(_startBg());
        }
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        if (Platform.isIOS) {
          _startIosLocationKeepAlive();
          unawaited(v3SaveBgTrackingSession(_sessionPayload()));
        } else {
          // App engine nestaje, ali FGS mora da nastavi vožnju.
          _fgTicker?.cancel();
          _fgTicker = null;
          unawaited(_startBg());
        }
        break;
    }
  }

  Future<void> _onResumed() async {
    // Ako je process death skinuo _isRunning a sesija/FGS žive — reattach.
    if (!_isRunning) {
      final restored = await tryRestoreFromSession();
      if (!restored) return;
    }

    if (!Platform.isIOS) {
      await _stopBg();
    }
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
    if (Platform.isIOS) {
      _startIosLocationKeepAlive();
    }
    // Nastavi FG ticker + odmah jedan tick (iOS može ostati sa starim timerom
    // posle BG — ne čekaj sledeći interval).
    if (_fgTicker == null) _startFgTicker();
    unawaited(_fgTick());
  }

  Future<void> _startBg() async {
    if (_vozacId.isEmpty || !_isRunning) return;
    // iOS BG path je nepouzdan za 20s ETA — koristi se main-isolate keep-alive.
    if (Platform.isIOS) return;
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
