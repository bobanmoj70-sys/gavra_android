import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_time_utils.dart';

enum V3LocationPrereqStatus {
  ok,
  serviceDisabled,
  denied,
  deniedForever,
  needsAlwaysPermission,
}

class V3VozacLocationTrackingService with WidgetsBindingObserver {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  String _activeVozacId = '';
  String _activeDatumIso = '';
  String _activeGrad = '';
  String _activeVreme = '';
  Position? _lastSentPosition;
  bool _isRunning = false;

  /// Tracking se automatski gasi ako traje duže od ovog vremena
  /// (safety net ako se ne detektuje da su svi putnici pokupljeni).
  static const Duration _maxTrackingDuration = Duration(minutes: 55);

  DateTime? _trackingStartedAt;

  /// iOS nema pravi background isolate (flutter_background_service na iOS-u
  /// se oslanja na retke/negarantovane background fetch pozive). Zato na iOS-u
  /// koristimo Geolocator position stream sa allowsBackgroundLocationUpdates,
  /// koji iOS budi na promenu lokacije čak i kad je app suspendovana.
  StreamSubscription<Position>? _iosPositionSub;
  bool _iosInFlight = false;
  Timer? _iosWatchdogTimer;

  /// Vreme poslednjeg ETA obračuna na iOS-u. Koristi se da se ETA prisilno
  /// osveži i kad vozač stoji (distanceFilter od 20m ne bi inače emitovao
  /// update), tako da iOS ima isto ponašanje kao Android-ov fiksni 20s tajmer.
  DateTime? _iosLastEtaComputedAt;
  static const Duration _iosForcedRefreshInterval = Duration(seconds: 20);

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _kStorageStartedAt = 'vozac_tracking_started_at';
  static const String _kStorageVozacId = 'vozac_tracking_vozac_id';
  static const String _kStorageDatumIso = 'vozac_tracking_datum_iso';
  static const String _kStorageGrad = 'vozac_tracking_grad';
  static const String _kStorageVreme = 'vozac_tracking_vreme';

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
  Position? get lastKnownPosition => _lastSentPosition;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  String _normalizeDateIso(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return value.split('T').first;
  }

  Future<void> _syncBackgroundSupabaseConfig(FlutterBackgroundService service) async {
    try {
      if (!configService.isInitialized) {
        await configService.initializeBasic();
      }
      final url = configService.getSupabaseUrl().trim();
      final anonKey = configService.getSupabaseAnonKey().trim();
      if (url.isEmpty || anonKey.isEmpty) {
        debugPrint('[V3VozacLocationTrackingService] Supabase config empty, cannot sync to background');
        return;
      }
      service.invoke('set_supabase_config', {'url': url, 'anon_key': anonKey});
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Failed to sync Supabase config to background: $e');
    }
  }

  void setActiveTermin({required String datumIso, required String grad, required String vreme}) {
    _activeDatumIso = _normalizeDateIso(datumIso);
    _activeGrad = grad.trim().toUpperCase();
    _activeVreme = V3TimeUtils.normalizeToHHmm(vreme);

    // Očisti deljene ETA/redosled keševe jer je termin promenjen
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    // Prosledi background servisu da i on šalje pravilne vrednosti
    final service = FlutterBackgroundService();
    service.invoke('set_termin', {'datum_iso': _activeDatumIso, 'grad': _activeGrad, 'vreme': _activeVreme});

    if (_isRunning && _activeVozacId.isNotEmpty) {
      service.invoke('set_vozac_id', {
        'vozac_id': _activeVozacId,
        'datum_iso': _activeDatumIso,
        'grad': _activeGrad,
        'vreme': _activeVreme,
      });
    }
  }

  Future<void> clearEtaForVozac({required String vozacId}) async {
    final normalized = vozacId.trim();
    if (normalized.isEmpty) return;

    try {
      await Supabase.instance.client.from('v3_eta_results').delete().eq('vozac_id', normalized);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] eta cleanup error: $e');
    }
  }

  /// Proverava da li je vrednost timestamp setovana.
  bool _isTimestampSet(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  /// Proverava da li su svi putnici za aktivni slot završeni
  /// (pokupljeni ili otkazani). Vraća false ako nema putnika.
  Future<bool> _allPassengersCompleted() async {
    if (_activeVozacId.isEmpty || _activeDatumIso.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty) {
      return false;
    }

    try {
      // Učitaj aktivni slot da znamo tačno koje putnike ovaj vozač treba da pokupi.
      final slotRows = await Supabase.instance.client
          .from('v3_trenutna_dodela_slot')
          .select('id, waypoints_json')
          .eq('vozac_v3_auth_id', _activeVozacId)
          .eq('datum', _activeDatumIso)
          .eq('grad', _activeGrad)
          .eq('vreme', _activeVreme);

      final activeSlot = (slotRows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
      if (activeSlot == null) return false;

      final waypointsJson = activeSlot['waypoints_json'] as Map<String, dynamic>?;
      final passengers = waypointsJson?['passengers'] as List<dynamic>?;
      if (passengers == null || passengers.isEmpty) return false;

      final slotTerminIds = passengers
          .whereType<Map<String, dynamic>>()
          .map((p) => p['termin_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet();

      if (slotTerminIds.isEmpty) return false;

      final rows = await Supabase.instance.client
          .from('v3_operativna_nedelja')
          .select('id, pokupljen_at, otkazano_at')
          .inFilter('id', slotTerminIds.toList());

      if (rows.isEmpty) return false;

      for (final row in rows) {
        final pokupljen = _isTimestampSet(row['pokupljen_at']);
        final otkazan = _isTimestampSet(row['otkazano_at']);
        if (!pokupljen && !otkazan) return false;
      }
      return true;
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Greška pri proveri putnika: $e');
      return false;
    }
  }

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    if (normalizedVozacId.isEmpty) return;

    if (_activeVozacId == normalizedVozacId && _isRunning) {
      // Servis je već aktivan za ovog vozača — ipak ponovo pošalji svež
      // termin background isolate-u, jer je prethodni invoke mogao propasti
      // (npr. poslat pre nego što je isolate registrovao listener).
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        debugPrint(
            '[V3VozacLocationTrackingService] Već aktivno — ponovo šaljem termin: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
        service.invoke('set_termin', {'datum_iso': _activeDatumIso, 'grad': _activeGrad, 'vreme': _activeVreme});
        service.invoke('set_vozac_id', {
          'vozac_id': normalizedVozacId,
          'datum_iso': _activeDatumIso,
          'grad': _activeGrad,
          'vreme': _activeVreme,
        });
      }
      return;
    }

    // Ako je drugi vozač — stop pre nego što pokrenemo novi.
    // NAPOMENA: stop() briše _activeDatumIso/_activeGrad/_activeVreme, pa moramo
    // sačuvati termin postavljen kroz setActiveTermin() i vratiti ga posle stop()-a,
    // inače background servis i computeEta() dobijaju prazan termin.
    if (_activeVozacId != normalizedVozacId) {
      final preservedDatumIso = _activeDatumIso;
      final preservedGrad = _activeGrad;
      final preservedVreme = _activeVreme;
      await stop();
      _activeDatumIso = preservedDatumIso;
      _activeGrad = preservedGrad;
      _activeVreme = preservedVreme;
    }
    _activeVozacId = normalizedVozacId;
    _trackingStartedAt ??= DateTime.now();
    unawaited(_secureStorage.write(key: _kStorageStartedAt, value: _trackingStartedAt!.toIso8601String()));
    unawaited(_secureStorage.write(key: _kStorageVozacId, value: normalizedVozacId));
    unawaited(_secureStorage.write(key: _kStorageDatumIso, value: _activeDatumIso));
    unawaited(_secureStorage.write(key: _kStorageGrad, value: _activeGrad));
    unawaited(_secureStorage.write(key: _kStorageVreme, value: _activeVreme));

    final prereqStatus = await checkLocationPrerequisites();
    if (prereqStatus != V3LocationPrereqStatus.ok) {
      debugPrint('[V3VozacLocationTrackingService] start() prekinut, prereq status=$prereqStatus');
      _activeVozacId = '';
      _trackingStartedAt = null;
      unawaited(_secureStorage.delete(key: _kStorageStartedAt));
      unawaited(_secureStorage.delete(key: _kStorageVozacId));
      unawaited(_secureStorage.delete(key: _kStorageDatumIso));
      unawaited(_secureStorage.delete(key: _kStorageGrad));
      unawaited(_secureStorage.delete(key: _kStorageVreme));
      return;
    }

    if (Platform.isIOS) {
      await _startIosTracking();
      return;
    }

    final service = FlutterBackgroundService();
    var isServiceRunning = await service.isRunning();
    if (!isServiceRunning) {
      try {
        await service.startService();
      } catch (e) {
        _activeVozacId = '';
        _isRunning = false;
        debugPrint('[V3VozacLocationTrackingService] Failed to start background service: $e');
        return;
      }
      isServiceRunning = await service.isRunning();
      if (!isServiceRunning) {
        _activeVozacId = '';
        _isRunning = false;
        debugPrint('[V3VozacLocationTrackingService] Background service did not start.');
        return;
      }
    }

    await _syncBackgroundSupabaseConfig(service);

    _isRunning = true;

    // Prosledi termin background servisu ako je setovan
    if (_activeDatumIso.isNotEmpty || _activeGrad.isNotEmpty || _activeVreme.isNotEmpty) {
      debugPrint(
          '[V3VozacLocationTrackingService] Šaljem termin background servisu: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
      service.invoke('set_termin', {'datum_iso': _activeDatumIso, 'grad': _activeGrad, 'vreme': _activeVreme});
    }

    // Prosledi vozac_id background servisu (+ fallback aktivni termin)
    service.invoke('set_vozac_id', {
      'vozac_id': normalizedVozacId,
      'datum_iso': _activeDatumIso,
      'grad': _activeGrad,
      'vreme': _activeVreme,
    });
  }

  Future<void> stop() async {
    final vozacIdToClean = _activeVozacId;
    final datumIsoToClean = _activeDatumIso;
    final gradToClean = _activeGrad;
    final vremeToClean = _activeVreme;
    _activeVozacId = '';
    _activeDatumIso = '';
    _activeGrad = '';
    _activeVreme = '';
    _lastSentPosition = null;
    _isRunning = false;
    _trackingStartedAt = null;
    onLocationSent = null;
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    unawaited(_secureStorage.delete(key: _kStorageStartedAt));
    unawaited(_secureStorage.delete(key: _kStorageVozacId));
    unawaited(_secureStorage.delete(key: _kStorageDatumIso));
    unawaited(_secureStorage.delete(key: _kStorageGrad));
    unawaited(_secureStorage.delete(key: _kStorageVreme));

    await _iosPositionSub?.cancel();
    _iosPositionSub = null;
    _iosWatchdogTimer?.cancel();
    _iosWatchdogTimer = null;
    _iosLastEtaComputedAt = null;

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }

    if (vozacIdToClean.isNotEmpty) {
      await clearEtaForVozac(vozacId: vozacIdToClean);
    }
  }

  /// Dobavi trenutnu GPS poziciju i odmah izračunaj ETA.
  /// Ispravka: _lastSentPosition nije mogao biti setovan iz background isolate-a,
  /// pa se GPS pozicija sada dobavlja direktno.
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
      _lastSentPosition = position;
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

  Future<V3LocationPrereqStatus> checkLocationPrerequisites() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return V3LocationPrereqStatus.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return V3LocationPrereqStatus.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      return V3LocationPrereqStatus.denied;
    }

    // iOS zahteva "Always" autorizaciju za allowsBackgroundLocationUpdates
    // (koje koristimo u _startIosTracking). "While Using" (whileInUse) nije
    // dovoljno — tracking bi prestao čim app ode u pozadinu.
    if (Platform.isIOS && permission == LocationPermission.whileInUse) {
      return V3LocationPrereqStatus.needsAlwaysPermission;
    }

    return V3LocationPrereqStatus.ok;
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
    final response = await supabase.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': lat,
        'lng': lng,
        'grad': grad,
        'vreme': vreme,
        if (datumIso != null && datumIso.isNotEmpty) 'datum_iso': datumIso,
      },
    );
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
      // Koristi eksplicitni optimizovani redosled iz OSRM
      final optimizedOrder = data['optimized_order'];
      if (optimizedOrder is List) {
        for (final pid in optimizedOrder) {
          if (pid is String && pid.isNotEmpty) {
            order.add(pid);
          }
        }
      }

      // Čuvaj u zajednički cache za sve ekrane
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

  /// Registruje lifecycle observer za background tracking servis.
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAndResumeIfNeeded());
  }

  /// Ako je app na iOS-u bio prisilno ugašen dok je tracking bio aktivan,
  /// ovde pokušavamo da automatski nastavimo tracking na osnovu sačuvane
  /// sesije (vozacId/grad/vreme/datum + started_at), bez potrebe da vozač
  /// ručno ponovo klikne "Pokreni vožnju". Android ovo ne treba jer background
  /// isolate tamo nastavlja da radi nezavisno od glavne app.
  Future<void> _restoreAndResumeIfNeeded() async {
    try {
      final startedRaw = await _secureStorage.read(key: _kStorageStartedAt);
      if (startedRaw == null || startedRaw.isEmpty) return;

      final startedAt = DateTime.tryParse(startedRaw);
      if (startedAt == null) return;
      _trackingStartedAt = startedAt;

      if (!Platform.isIOS) return;
      if (_isRunning) return;

      // Ako je vreme trajanja već isteklo, samo očisti sesiju umesto restarta.
      if (DateTime.now().difference(startedAt) >= _maxTrackingDuration) {
        debugPrint('[V3VozacLocationTrackingService][iOS] Sačuvana sesija istekla, ne nastavljam tracking.');
        await stop();
        return;
      }

      final vozacId = (await _secureStorage.read(key: _kStorageVozacId) ?? '').trim();
      final datumIso = (await _secureStorage.read(key: _kStorageDatumIso) ?? '').trim();
      final grad = (await _secureStorage.read(key: _kStorageGrad) ?? '').trim();
      final vreme = (await _secureStorage.read(key: _kStorageVreme) ?? '').trim();

      if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return;

      debugPrint(
          '[V3VozacLocationTrackingService][iOS] Nastavljam sačuvanu sesiju: vozac=$vozacId grad=$grad vreme=$vreme');
      _activeDatumIso = datumIso;
      _activeGrad = grad;
      _activeVreme = vreme;
      await start(vozacId: vozacId);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] restore/resume error: $e');
    }
  }

  /// Pokreće iOS-specifičan tracking preko Geolocator position stream-a sa
  /// allowsBackgroundLocationUpdates. Za razliku od Androida, ovde nema
  /// pravog background isolate-a — GPS updates i ETA se računaju u main isolate-u,
  /// koji iOS budi na promenu lokacije čak i kad je app suspendovana.
  ///
  /// distanceFilter: 0 znači da GPS hardware/OS ne filtrira update-e po
  /// pomaku — stream javlja svaku promenu pozicije koju iOS detektuje.
  /// Throttlovanje ka computeEta()/OSRM pozivu se radi u kodu (vremenski,
  /// najviše jednom na _iosForcedRefreshInterval), a ne preko distanceFilter-a
  /// — tako ETA ostaje sveža i kad vozač stoji, a ne šalje se prekomerno
  /// često kad se kreće.
  Future<void> _startIosTracking() async {
    await _iosPositionSub?.cancel();
    _isRunning = true;

    final locationSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );

    _iosPositionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (position) {
        unawaited(_handleIosPosition(position));
      },
      onError: (Object e) {
        debugPrint('[V3VozacLocationTrackingService][iOS] position stream error: $e');
      },
    );

    // GPS stream sam po sebi ne throttluje po vremenu (može javljati poziciju
    // i svake 1-2s), pa se throttlovanje ka computeEta()/OSRM radi u kodu,
    // u _handleIosPosition, tačno kao Android-ov fiksni Timer.periodic(20s).
    // Watchdog tajmer ovde služi samo za auto-stop nakon _maxTrackingDuration.
    _iosWatchdogTimer?.cancel();
    _iosWatchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final startedAt = _trackingStartedAt;
      if (startedAt == null) return;
      if (DateTime.now().difference(startedAt) < _maxTrackingDuration) return;

      debugPrint(
          '[V3VozacLocationTrackingService][iOS] Auto-stop (watchdog timer): ${_maxTrackingDuration.inMinutes} min trackinga isteklo');
      unawaited(stop());
    });
  }

  Future<void> _handleIosPosition(Position position) async {
    if (_iosInFlight) return;
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) return;

    // Vremenski throttle: ne zovi computeEta()/OSRM češće od jednom na
    // _iosForcedRefreshInterval (20s), bez obzira koliko često GPS stream
    // javlja poziciju. Uvek ažuriramo _lastSentPosition (za UI/druge svrhe),
    // ali stvarni mrežni poziv ide najviše svakih 20s — identično Androidu.
    final lastComputed = _iosLastEtaComputedAt;
    _lastSentPosition = position;
    if (lastComputed != null && DateTime.now().difference(lastComputed) < _iosForcedRefreshInterval) {
      return;
    }

    // 55-min auto-stop watchdog (iOS ekvivalent Android background isolate watchdoga)
    final startedAt = _trackingStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) >= _maxTrackingDuration) {
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] Auto-stop: ${_maxTrackingDuration.inMinutes} min trackinga isteklo');
      await stop();
      return;
    }

    _iosInFlight = true;
    try {
      await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
      _iosLastEtaComputedAt = DateTime.now();
      onLocationSent?.call(position);

      // Auto-stop: ako su svi putnici pokupljeni/otkazani, zaustavi tracking.
      if (await _allPassengersCompleted()) {
        debugPrint('[V3VozacLocationTrackingService][iOS] Auto-stop: svi putnici su pokupljeni/otkazani');
        await stop();
      }
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService][iOS] computeEta error: $e');
    } finally {
      _iosInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background servis radi nezavisno od lifecycle stanja.
    // Po potrebi ovde možemo da pauziramo/ponovo pokrećemo foreground taskove.
  }
}
