import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

/// GPS/ETA tracking servis za vozača.
///
/// Tracking počinje iz foreground-a (V3VozacScreen), ali nakon starta se
/// istovremeno pokreće i foreground foreground servis
/// ([FlutterBackgroundService]) koji nastavlja da šalje lokaciju i računa
/// ETA dok je app u pozadini, dok je telefon zaključan, ili dok vozač koristi
/// druge aplikacije. Foreground ticker se pauzira u pozadini da ne bi
/// duplirao rad, a nastavlja kada se app vrati u foreground.
///
/// Kada tracking stvarno krene, `activateSlotWithRetry` upisuje
/// `tracking_started_at` u slot, što okida DB trigger koji obaveštava
/// putnike push-om "Vozač je krenuo".
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

  /// Foreground ticker — jedini izvor tick-ova na obe platforme. Radi samo
  /// dok je app u foreground-u; lifecycle observer ga zaustavlja pri
  /// background-u.
  V3SelfReschedulingTicker? _foregroundTicker;

  /// Optimizovani redosled putnika (deljen između ekrana)
  final List<String> _optimizedPutnikIds = [];

  /// ETA vrednosti (deljene između ekrana)
  final Map<String, int> _etaSecondsCache = {};

  /// Poziva se nakon svakog uspešnog slanja GPS pozicije (foreground).
  void Function(Position position)? onLocationSent;

  bool get isRunning => _isRunning;

  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
  String get activeDatumIso => _activeDatumIso;
  String get activeGrad => _activeGrad;
  String get activeVreme => _activeVreme;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  /// Delegira na deljeni `V3BelgradeTime.parseIsoDatePart`.
  String _normalizeDateIso(String raw) => V3BelgradeTime.parseIsoDatePart(raw);

  void setActiveTermin({required String datumIso, required String grad, required String vreme}) {
    _activeDatumIso = _normalizeDateIso(datumIso);
    _activeGrad = grad.trim().toUpperCase();
    _activeVreme = V3BelgradeTime.normalizeToHHmm(vreme);

    // Očisti deljene ETA/redosled keševe jer je termin promenjen
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();
  }

  Future<void> clearEtaForVozac({required String vozacId}) {
    return v3ClearEtaForVozac(
      client: Supabase.instance.client,
      vozacId: vozacId,
      logTag: '[V3VozacLocationTrackingService]',
    );
  }

  /// Proverava da li su svi putnici u aktivnom slotu završeni.
  Future<bool> _allPassengersCompleted() {
    return v3AllPassengersCompleted(
      client: Supabase.instance.client,
      datumIso: _activeDatumIso,
      grad: _activeGrad,
      vreme: _activeVreme,
      logTag: '[V3VozacLocationTrackingService]',
    );
  }

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    debugPrint('[V3VozacLocationTrackingService] start() pozvan za vozac=$normalizedVozacId');
    if (normalizedVozacId.isEmpty) {
      debugPrint('[V3VozacLocationTrackingService] start() prekinut: prazan vozacId');
      return;
    }

    if (_startInProgress) {
      debugPrint('[V3VozacLocationTrackingService] start() u toku, preskačem duplikat');
      return;
    }
    _startInProgress = true;

    try {
      if (_isRunning || _activeVozacId.isNotEmpty) {
        debugPrint('[V3VozacLocationTrackingService] Zaustavljam prethodni tracking pre starta');
        await stop();
      }

      _activeVozacId = normalizedVozacId;
      _trackingStartedAt = V3BelgradeTime.now();
      debugPrint('[V3VozacLocationTrackingService] Novi tracking startedAt=$_trackingStartedAt');

      if (!await _checkLocationPrerequisites()) {
        debugPrint('[V3VozacLocationTrackingService] start() prekinut: lokacijski preduslovi nisu zadovoljeni');
        await stop();
        return;
      }

      // Aktiviraj slot red (idempotentan upsert).
      debugPrint(
          '[V3VozacLocationTrackingService] Aktiviram slot: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
      unawaited(activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: normalizedVozacId,
        datumIso: _activeDatumIso,
        grad: _activeGrad,
        vreme: _activeVreme,
        logTag: '[V3VozacLocationTrackingService]',
        log: debugPrint,
      ));

      _startForegroundTicker();
      _isRunning = true;
      debugPrint('[V3VozacLocationTrackingService] Tracking označen kao aktivan (_isRunning=true)');

      // Pokreni isti tracking u background servisu kako bi radio dok je app
      // u pozadini ili telefon zaključan.
      unawaited(_startBackgroundTracking(normalizedVozacId));
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    debugPrint('[V3VozacLocationTrackingService] stop() pozvan');
    _startInProgress = false;
    final vozacIdToClean = _activeVozacId;
    _activeVozacId = '';
    _activeDatumIso = '';
    _activeGrad = '';
    _activeVreme = '';
    _isRunning = false;
    _trackingStartedAt = null;
    onLocationSent = null;
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    _foregroundTicker?.cancel();
    _foregroundTicker = null;

    // Zaustavi background tracking servis.
    unawaited(_stopBackgroundTracking());

    if (vozacIdToClean.isNotEmpty) {
      debugPrint('[V3VozacLocationTrackingService] Brišem ETA za vozača=$vozacIdToClean');
      await clearEtaForVozac(vozacId: vozacIdToClean);
    }
    debugPrint('[V3VozacLocationTrackingService] stop() završen');
  }

  /// Zaustavlja background foreground servis.
  Future<void> _stopBackgroundTracking() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopTracking');
      // Sačekaj kratko da background servis završi cleanup, zatim ga ugasi.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      service.invoke('stopService');
      debugPrint('[V3VozacLocationTrackingService] Background servis zaustavljen');
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Background stop greška: $e');
    }
  }

  /// Dobavi trenutnu GPS poziciju i odmah izračunaj ETA.
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      return (etaMap: <String, int>{}, order: <String>[]);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] fetchPositionAndComputeEta error: $e');
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();
      return (etaMap: <String, int>{}, order: <String>[]);
    }
  }

  Future<bool> _checkLocationPrerequisites() async {
    return v3CheckLocationPrerequisites(
      logTag: '[V3VozacLocationTrackingService]',
    );
  }

  Future<({Map<String, int> etaMap, List<String> order})> computeEta({
    required String vozacId,
    required double lat,
    required double lng,
    required String grad,
    required String vreme,
    String? datumIso,
  }) async {
    final supabase = Supabase.instance.client;

    await v3UpdateVozacLocation(
      client: supabase,
      vozacId: vozacId,
      lat: lat,
      lng: lng,
      logTag: '[V3VozacLocationTrackingService]',
      log: debugPrint,
    );

    final requestBody = <String, dynamic>{
      'vozac_id': vozacId,
      'grad': grad,
      'vreme': vreme,
      if (datumIso != null && datumIso.isNotEmpty) 'datum_iso': datumIso,
    };
    debugPrint('[V3VozacLocationTrackingService] computeEta request body: $requestBody');

    final response = await supabase.functions
        .invoke(
          'v3-compute-eta',
          body: requestBody,
        )
        .timeout(v3ComputeEtaNetworkTimeout);
    debugPrint('[V3VozacLocationTrackingService] computeEta response: ${response.data}');

    final etaMap = <String, int>{};
    final order = <String>[];
    final data = response.data;
    if (data is Map && data['ok'] == true) {
      final etaList = data['eta_results'];
      if (etaList is List) {
        for (final item in etaList) {
          if (item is Map) {
            final pid = item['putnik_id']?.toString();
            final sec = (item['eta_seconds'] as num?)?.toInt();
            if (pid != null && pid.isNotEmpty && sec != null) {
              etaMap[pid] = sec;
            }
          }
        }
      }
      final optimizedOrder = data['optimized_order'];
      if (optimizedOrder is List) {
        for (final pid in optimizedOrder) {
          if (pid is String && pid.isNotEmpty) {
            order.add(pid);
          }
        }
      }

      _optimizedPutnikIds
        ..clear()
        ..addAll(order);
      _etaSecondsCache
        ..clear()
        ..addAll(etaMap);
    } else {
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();
    }
    return (etaMap: etaMap, order: order);
  }

  /// Pokreće foreground ticker na obe platforme.
  void _startForegroundTicker() {
    _foregroundTicker?.cancel();
    _foregroundTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _foregroundTick)..start();
  }

  Future<void> _foregroundTick() async {
    debugPrint('[V3VozacLocationTrackingService] _foregroundTick() početak');
    final startedAt = _trackingStartedAt;
    if (v3TrackingTimedOut(startedAt)) {
      debugPrint(
          '[V3VozacLocationTrackingService] stop reason=timeout source=foreground_timer duration_minutes=${v3TrackingMaxDuration.inMinutes}');
      await stop();
      return;
    }

    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      debugPrint(
          '[V3VozacLocationTrackingService] _foregroundTick prekinut: nedostaju podaci vozac=$_activeVozacId grad=$_activeGrad vreme=$_activeVreme datum=$_activeDatumIso');
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final etaResult = await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
      debugPrint(
          '[V3VozacLocationTrackingService] computeEta završen: order=${etaResult.order.length} etaMap=${etaResult.etaMap.length}');
      onLocationSent?.call(position);

      if (await _allPassengersCompleted()) {
        debugPrint('[V3VozacLocationTrackingService] stop reason=all_passengers_completed source=foreground_timer');
        await stop();
      }
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] computeEta error: $e');
    }
    debugPrint('[V3VozacLocationTrackingService] _foregroundTick() kraj');

    // Pokreni background servis ako već nije pokrenut
    if (_activeVozacId.isNotEmpty) {
      try {
        final isBackgroundServiceRunning = await FlutterBackgroundService().isRunning();
        if (!isBackgroundServiceRunning) {
          debugPrint('[V3VozacLocationTrackingService] Pokrećem background servis');
          await FlutterBackgroundService().startService();
        }
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] Greška pri pokretanju background servisa: $e');
      }
    }
  }

  /// Registruje lifecycle observer. U foreground-only režimu ne vršimo
  /// restore sesije — ako je app ubijena, tracking se ne nastavlja.
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Za foreground-only režim restore nije potreban.
  Future<void> restoreAndResumeIfNeeded() async {
    debugPrint('[V3VozacLocationTrackingService] restoreAndResumeIfNeeded(): foreground-only, ništa se ne restore-uje');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground ticker radi samo dok je app vidljiva. Kada app ode u
    // pozadinu ili se telefon zaključa, pauziramo foreground tick (štedi
    // bateriju i izbegava dupliranje sa background servisom), ali NE
    // zaustavljamo ceo tracking — background foreground servis nastavlja
    // da šalje lokaciju i računa ETA.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_foregroundTicker != null) {
        debugPrint('[V3VozacLocationTrackingService] lifecycle=$state — pauziram foreground ticker');
        _foregroundTicker?.cancel();
        _foregroundTicker = null;
      }
      return;
    }

    // Kada se app vrati u foreground, nastavi foreground tick ako tracking
    // još uvek treba da radi.
    if (state == AppLifecycleState.resumed) {
      if (_isRunning && _foregroundTicker == null) {
        debugPrint('[V3VozacLocationTrackingService] lifecycle=resumed — nastavljam foreground ticker');
        _startForegroundTicker();
      }
      return;
    }

    // Ako je app stvarno ubijena (detached), tek tada zaustavi sve.
    if (state == AppLifecycleState.detached) {
      debugPrint('[V3VozacLocationTrackingService] lifecycle=detached — zaustavljam tracking');
      stop();
    }
  }

  /// Pokreće background foreground servis sa istim aktivnim podacima.
  Future<void> _startBackgroundTracking(String vozacId) async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        debugPrint('[V3VozacLocationTrackingService] Pokrećem background servis');
        await service.startService();
      }
      service.invoke(
        'startTracking',
        <String, dynamic>{
          'vozac_id': vozacId,
          'datum_iso': _activeDatumIso,
          'grad': _activeGrad,
          'vreme': _activeVreme,
        },
      );
      debugPrint('[V3VozacLocationTrackingService] Background tracking startovan');
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Background start greška: $e');
    }
  }
}
